create table private.order_handoff_code_keys (
  singleton boolean primary key default true check (singleton),
  secret text not null check (char_length(secret) = 64),
  created_at timestamptz not null default now()
);

alter table private.order_handoff_code_keys enable row level security;
revoke all on table private.order_handoff_code_keys
  from public, anon, authenticated;
grant select on table private.order_handoff_code_keys to service_role;

insert into private.order_handoff_code_keys (singleton, secret)
values (
  true,
  pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')
);

alter table private.merchant_orders
  add column pickup_code_digest bytea,
  add column pickup_code_expires_at timestamptz,
  add column pickup_code_failed_attempts integer not null default 0,
  add column pickup_code_locked_at timestamptz,
  add column delivery_code_digest bytea,
  add column delivery_code_expires_at timestamptz,
  add column delivery_code_failed_attempts integer not null default 0,
  add column delivery_code_locked_at timestamptz,
  add constraint merchant_orders_pickup_code_attempts_check check (
    pickup_code_failed_attempts between 0 and 5
  ),
  add constraint merchant_orders_delivery_code_attempts_check check (
    delivery_code_failed_attempts between 0 and 5
  ),
  add constraint merchant_orders_pickup_code_pair_check check (
    (pickup_code_digest is null) = (pickup_code_expires_at is null)
  ),
  add constraint merchant_orders_delivery_code_pair_check check (
    (delivery_code_digest is null) = (delivery_code_expires_at is null)
  ),
  add constraint merchant_orders_pickup_code_lock_check check (
    pickup_code_locked_at is null or pickup_code_failed_attempts = 5
  ),
  add constraint merchant_orders_delivery_code_lock_check check (
    delivery_code_locked_at is null or delivery_code_failed_attempts = 5
  );

create function private.order_handoff_secret()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select key.secret
  from private.order_handoff_code_keys as key
  where key.singleton;
$$;

create function private.order_handoff_code(
  p_order_id uuid,
  p_purpose text
)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_bytes bytea;
  v_number bigint;
begin
  if p_order_id is null or p_purpose not in ('pickup', 'delivery') then
    raise exception 'invalid handoff code context';
  end if;

  v_bytes := extensions.hmac(
    p_order_id::text || ':' || p_purpose,
    private.order_handoff_secret(),
    'sha256'
  );
  v_number := (
    pg_catalog.get_byte(v_bytes, 0)::bigint * 16777216
    + pg_catalog.get_byte(v_bytes, 1)::bigint * 65536
    + pg_catalog.get_byte(v_bytes, 2)::bigint * 256
    + pg_catalog.get_byte(v_bytes, 3)::bigint
  ) % 10000;

  return pg_catalog.lpad(v_number::text, 4, '0');
end;
$$;

create function private.order_handoff_digest(p_code text)
returns bytea
language sql
stable
security invoker
set search_path = ''
as $$
  select extensions.hmac(
    p_code,
    private.order_handoff_secret(),
    'sha256'
  );
$$;

create function private.merchant_order_json_with_handoff(
  order_row private.merchant_orders,
  p_audience text
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.merchant_order_json(order_row)
    || pg_catalog.jsonb_build_object(
      'handoffCode',
      case
        when p_audience = 'merchant'
          and (order_row).status in (
            'assigned', 'en_route_to_pickup', 'at_store'
          )
          and (order_row).pickup_code_digest is not null
          and (order_row).pickup_code_expires_at > pg_catalog.now()
          and (order_row).pickup_code_locked_at is null
        then pg_catalog.jsonb_build_object(
          'purpose', 'pickup',
          'code', private.order_handoff_code((order_row).id, 'pickup'),
          'expiresAt', (order_row).pickup_code_expires_at
        )
        when p_audience = 'customer'
          and (order_row).status in ('picked_up', 'in_transit')
          and (order_row).delivery_code_digest is not null
          and (order_row).delivery_code_expires_at > pg_catalog.now()
          and (order_row).delivery_code_locked_at is null
        then pg_catalog.jsonb_build_object(
          'purpose', 'delivery',
          'code', private.order_handoff_code((order_row).id, 'delivery'),
          'expiresAt', (order_row).delivery_code_expires_at
        )
        else null
      end
    );
$$;

revoke execute on function private.order_handoff_secret()
  from public, anon, authenticated;
revoke execute on function private.order_handoff_code(uuid, text)
  from public, anon, authenticated;
revoke execute on function private.order_handoff_digest(text)
  from public, anon, authenticated;
revoke execute on function private.merchant_order_json_with_handoff(
  private.merchant_orders, text
) from public, anon, authenticated;
grant execute on function private.order_handoff_secret() to service_role;
grant execute on function private.order_handoff_code(uuid, text) to service_role;
grant execute on function private.order_handoff_digest(text) to service_role;
grant execute on function private.merchant_order_json_with_handoff(
  private.merchant_orders, text
) to service_role;

create or replace function private.stamp_merchant_order_lifecycle()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_code text;
begin
  case new.status
    when 'assigned' then
      new.assigned_at := coalesce(new.assigned_at, pg_catalog.now());
      if new.pickup_code_digest is null then
        v_code := private.order_handoff_code(new.id, 'pickup');
        new.pickup_code_digest := private.order_handoff_digest(v_code);
        new.pickup_code_expires_at := pg_catalog.now() + interval '6 hours';
        new.pickup_code_failed_attempts := 0;
        new.pickup_code_locked_at := null;
      end if;
    when 'en_route_to_pickup' then
      new.en_route_to_pickup_at := coalesce(
        new.en_route_to_pickup_at,
        pg_catalog.now()
      );
    when 'at_store' then
      new.arrived_at_store_at := coalesce(
        new.arrived_at_store_at,
        pg_catalog.now()
      );
    when 'picked_up' then
      new.picked_up_at := coalesce(new.picked_up_at, pg_catalog.now());
      if new.delivery_code_digest is null then
        v_code := private.order_handoff_code(new.id, 'delivery');
        new.delivery_code_digest := private.order_handoff_digest(v_code);
        new.delivery_code_expires_at := pg_catalog.now() + interval '6 hours';
        new.delivery_code_failed_attempts := 0;
        new.delivery_code_locked_at := null;
      end if;
    when 'in_transit' then
      new.in_transit_at := coalesce(new.in_transit_at, pg_catalog.now());
    when 'delivered' then
      new.delivered_at := coalesce(new.delivered_at, pg_catalog.now());
    else
      null;
  end case;

  return new;
end;
$$;

update private.merchant_orders as merchant_order
set pickup_code_digest = private.order_handoff_digest(
      private.order_handoff_code(merchant_order.id, 'pickup')
    ),
    pickup_code_expires_at = pg_catalog.now() + interval '6 hours'
where merchant_order.status in (
  'assigned', 'en_route_to_pickup', 'at_store'
)
  and merchant_order.pickup_code_digest is null;

update private.merchant_orders as merchant_order
set delivery_code_digest = private.order_handoff_digest(
      private.order_handoff_code(merchant_order.id, 'delivery')
    ),
    delivery_code_expires_at = pg_catalog.now() + interval '6 hours'
where merchant_order.status in ('picked_up', 'in_transit')
  and merchant_order.delivery_code_digest is null;

create or replace function public.get_customer_orders(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_orders jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.merchant_order_json_with_handoff(merchant_order, 'customer')
      order by merchant_order.created_at desc, merchant_order.id desc
    ),
    '[]'::jsonb
  )
  into v_orders
  from private.merchant_orders as merchant_order
  where merchant_order.customer_account_id = p_account_id;

  response_body := pg_catalog.jsonb_build_object('orders', v_orders);
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_merchant_orders(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_store_id uuid;
  v_orders jsonb;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select store.id
  into v_store_id
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.merchant_order_json_with_handoff(merchant_order, 'merchant')
      order by merchant_order.created_at desc, merchant_order.id desc
    ),
    '[]'::jsonb
  )
  into v_orders
  from private.merchant_orders as merchant_order
  where merchant_order.store_id = v_store_id
    and merchant_order.status <> 'payment_pending'
    and not (
      merchant_order.status = 'cancelled'
      and merchant_order.payment_state = 'not_collected'
    );

  response_body := pg_catalog.jsonb_build_object('orders', v_orders);
  response_status := 200;
  return next;
end;
$$;

drop function public.advance_delivery_assignment(
  uuid, uuid, text, text, text
);

create function public.advance_delivery_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
  p_action text,
  p_idempotency_key text,
  p_request_digest text,
  p_verification_code text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_action text;
  v_attempt private.delivery_assignment_attempts%rowtype;
  v_audit_action text;
  v_before_state jsonb;
  v_existing_dedup private.request_deduplication%rowtype;
  v_expected_status text;
  v_failed_attempts integer;
  v_function_name constant text := 'advance_delivery_assignment';
  v_order private.merchant_orders%rowtype;
  v_purpose text;
  v_target_status text;
  v_verification_digest bytea;
  v_verification_expires_at timestamptz;
  v_verification_locked_at timestamptz;
begin
  v_action := nullif(pg_catalog.btrim(p_action), '');

  if p_account_id is null
    or p_assignment_id is null
    or v_action is null
    or v_action not in (
      'start_to_store',
      'arrive_at_store',
      'confirm_pickup',
      'start_delivery',
      'complete_delivery'
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The delivery lifecycle request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_account_id::text || ':' || v_function_name,
      0
    )
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing_dedup.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select assignment.*
  into v_attempt
  from private.delivery_assignment_attempts as assignment
  where assignment.id = p_assignment_id
    and assignment.partner_account_id = p_account_id
    and assignment.status in ('accepted', 'completed')
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'assignment_not_found',
        'message', 'The active delivery assignment was not found.'
      )
    );
    response_status := 404;
  else
    select merchant_order.*
    into v_order
    from private.merchant_orders as merchant_order
    where merchant_order.id = v_attempt.order_id
    for update;

    case v_action
      when 'start_to_store' then
        v_expected_status := 'assigned';
        v_target_status := 'en_route_to_pickup';
        v_audit_action := 'delivery_job_started_to_store';
      when 'arrive_at_store' then
        v_expected_status := 'en_route_to_pickup';
        v_target_status := 'at_store';
        v_audit_action := 'delivery_job_arrived_at_store';
      when 'confirm_pickup' then
        v_expected_status := 'at_store';
        v_target_status := 'picked_up';
        v_audit_action := 'delivery_job_pickup_confirmed';
        v_purpose := 'pickup';
      when 'start_delivery' then
        v_expected_status := 'picked_up';
        v_target_status := 'in_transit';
        v_audit_action := 'delivery_job_started_delivery';
      when 'complete_delivery' then
        v_expected_status := 'in_transit';
        v_target_status := 'delivered';
        v_audit_action := 'delivery_job_completed';
        v_purpose := 'delivery';
    end case;

    if v_order.status = v_target_status then
      response_body := private.delivery_partner_dispatch_snapshot_json(
        p_account_id
      );
      response_status := 200;
    elsif v_attempt.status <> 'accepted'
      or v_order.status <> v_expected_status
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_order_transition',
          'message', 'The delivery job cannot perform that action now.'
        )
      );
      response_status := 409;
    else
      if v_purpose = 'pickup' then
        v_verification_digest := v_order.pickup_code_digest;
        v_verification_expires_at := v_order.pickup_code_expires_at;
        v_verification_locked_at := v_order.pickup_code_locked_at;
        v_failed_attempts := v_order.pickup_code_failed_attempts;
      elsif v_purpose = 'delivery' then
        v_verification_digest := v_order.delivery_code_digest;
        v_verification_expires_at := v_order.delivery_code_expires_at;
        v_verification_locked_at := v_order.delivery_code_locked_at;
        v_failed_attempts := v_order.delivery_code_failed_attempts;
      end if;

      if v_purpose is not null
        and (
          p_verification_code is null
          or p_verification_code !~ '^[0-9]{4}$'
        )
      then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'verification_code_required',
            'message', 'A valid four-digit handoff code is required.'
          )
        );
        response_status := 400;
      elsif v_purpose is not null and v_verification_digest is null then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'verification_code_unavailable',
            'message', 'The handoff code is not available.'
          )
        );
        response_status := 409;
      elsif v_purpose is not null and v_verification_locked_at is not null then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'verification_code_locked',
            'message', 'Handoff verification is locked for owner review.'
          )
        );
        response_status := 423;
      elsif v_purpose is not null
        and v_verification_expires_at <= pg_catalog.now()
      then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'verification_code_expired',
            'message', 'The handoff code has expired.'
          )
        );
        response_status := 410;
      elsif v_purpose is not null
        and v_verification_digest <> private.order_handoff_digest(
          p_verification_code
        )
      then
        v_before_state := pg_catalog.jsonb_build_object(
          'purpose', v_purpose,
          'failedAttempts', v_failed_attempts,
          'locked', false
        );
        v_failed_attempts := least(v_failed_attempts + 1, 5);

        if v_purpose = 'pickup' then
          update private.merchant_orders as merchant_order
          set pickup_code_failed_attempts = v_failed_attempts,
              pickup_code_locked_at = case
                when v_failed_attempts = 5 then pg_catalog.now()
                else null
              end,
              updated_at = pg_catalog.now()
          where merchant_order.id = v_order.id
          returning merchant_order.* into v_order;
        else
          update private.merchant_orders as merchant_order
          set delivery_code_failed_attempts = v_failed_attempts,
              delivery_code_locked_at = case
                when v_failed_attempts = 5 then pg_catalog.now()
                else null
              end,
              updated_at = pg_catalog.now()
          where merchant_order.id = v_order.id
          returning merchant_order.* into v_order;
        end if;

        insert into audit.events (
          actor_id, action, entity_type, entity_id,
          reason, before_state, after_state
        ) values (
          p_account_id,
          'delivery_handoff_code_rejected',
          'delivery_assignment',
          v_attempt.id,
          v_purpose,
          v_before_state,
          pg_catalog.jsonb_build_object(
            'purpose', v_purpose,
            'failedAttempts', v_failed_attempts,
            'locked', v_failed_attempts = 5
          )
        );

        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', case
              when v_failed_attempts = 5 then 'verification_code_locked'
              else 'verification_code_invalid'
            end,
            'message', case
              when v_failed_attempts = 5
                then 'Handoff verification is locked for owner review.'
              else 'The handoff code is incorrect.'
            end
          )
        );
        response_status := case when v_failed_attempts = 5 then 423 else 422 end;
      else
        v_before_state := private.delivery_assignment_json(v_attempt);

        update private.merchant_orders as merchant_order
        set status = v_target_status,
            state_version = merchant_order.state_version + 1,
            updated_at = pg_catalog.now()
        where merchant_order.id = v_order.id
        returning merchant_order.* into v_order;

        select assignment.*
        into v_attempt
        from private.delivery_assignment_attempts as assignment
        where assignment.id = p_assignment_id;

        insert into audit.events (
          actor_id, action, entity_type, entity_id,
          before_state, after_state
        ) values (
          p_account_id,
          v_audit_action,
          'delivery_assignment',
          v_attempt.id,
          v_before_state,
          private.delivery_assignment_json(v_attempt)
        );

        response_body := private.delivery_partner_dispatch_snapshot_json(
          p_account_id
        );
        response_status := 200;
      end if;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id,
    v_function_name,
    pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest),
    response_body,
    response_status
  );

  return next;
end;
$$;

revoke execute on function public.advance_delivery_assignment(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.advance_delivery_assignment(
  uuid, uuid, text, text, text, text
) to service_role;
