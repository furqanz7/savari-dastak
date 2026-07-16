alter table private.merchant_orders
  add column pickup_code_version integer not null default 1,
  add column delivery_code_version integer not null default 1,
  add constraint merchant_orders_pickup_code_version_check check (
    pickup_code_version > 0
  ),
  add constraint merchant_orders_delivery_code_version_check check (
    delivery_code_version > 0
  );

create function private.order_handoff_code_for_version(
  p_order_id uuid,
  p_purpose text,
  p_version integer
)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_bytes bytea;
  v_context text;
  v_number bigint;
begin
  if p_order_id is null
    or p_purpose not in ('pickup', 'delivery')
    or p_version is null
    or p_version < 1
  then
    raise exception 'invalid handoff code context';
  end if;

  v_context := p_order_id::text || ':' || p_purpose || case
    when p_version = 1 then ''
    else ':' || p_version::text
  end;
  v_bytes := extensions.hmac(
    v_context,
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

create or replace function private.order_handoff_code(
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
  v_version integer;
begin
  select case p_purpose
    when 'pickup' then merchant_order.pickup_code_version
    when 'delivery' then merchant_order.delivery_code_version
    else null
  end
  into v_version
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id;

  if v_version is null then
    raise exception 'invalid handoff code context';
  end if;

  return private.order_handoff_code_for_version(
    p_order_id,
    p_purpose,
    v_version
  );
end;
$$;

revoke execute on function private.order_handoff_code_for_version(
  uuid, text, integer
) from public, anon, authenticated;
grant execute on function private.order_handoff_code_for_version(
  uuid, text, integer
) to service_role;

create function public.owner_reset_order_handoff_code(
  p_account_id uuid,
  p_order_id uuid,
  p_purpose text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_before_state jsonb;
  v_current_code text;
  v_current_version integer;
  v_existing_dedup private.request_deduplication%rowtype;
  v_expires_at timestamptz;
  v_failed_attempts integer;
  v_function_name constant text := 'owner_reset_order_handoff_code';
  v_locked_at timestamptz;
  v_new_code text;
  v_new_version integer;
  v_order private.merchant_orders%rowtype;
  v_purpose text;
  v_reason text;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
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
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  v_purpose := nullif(pg_catalog.btrim(p_purpose), '');
  v_reason := nullif(
    pg_catalog.regexp_replace(pg_catalog.btrim(p_reason), '\s+', ' ', 'g'),
    ''
  );
  if p_order_id is null
    or v_purpose is null
    or v_purpose not in ('pickup', 'delivery')
    or v_reason is null
    or pg_catalog.char_length(v_reason) > 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The owner handoff recovery request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_order_id::text || ':' || v_function_name, 0)
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

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
  else
    if v_purpose = 'pickup' then
      v_current_version := v_order.pickup_code_version;
      v_expires_at := v_order.pickup_code_expires_at;
      v_failed_attempts := v_order.pickup_code_failed_attempts;
      v_locked_at := v_order.pickup_code_locked_at;
    else
      v_current_version := v_order.delivery_code_version;
      v_expires_at := v_order.delivery_code_expires_at;
      v_failed_attempts := v_order.delivery_code_failed_attempts;
      v_locked_at := v_order.delivery_code_locked_at;
    end if;

    if (v_purpose = 'pickup' and v_order.status not in (
      'assigned', 'en_route_to_pickup', 'at_store'
    )) or (v_purpose = 'delivery' and v_order.status not in (
      'picked_up', 'in_transit'
    )) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_handoff_state',
          'message', 'This handoff code is not active for the order.'
        )
      );
      response_status := 409;
    elsif v_expires_at is null then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'verification_code_unavailable',
          'message', 'The handoff code is not available.'
        )
      );
      response_status := 409;
    elsif v_locked_at is null and v_expires_at > pg_catalog.now() then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'handoff_code_not_recoverable',
          'message', 'Only a locked or expired handoff code can be reset.'
        )
      );
      response_status := 409;
    else
      v_current_code := private.order_handoff_code_for_version(
        v_order.id,
        v_purpose,
        v_current_version
      );
      v_new_version := v_current_version + 1;

      loop
        v_new_code := private.order_handoff_code_for_version(
          v_order.id,
          v_purpose,
          v_new_version
        );
        exit when v_new_code <> v_current_code;
        v_new_version := v_new_version + 1;
        if v_new_version > v_current_version + 100 then
          raise exception 'could not rotate handoff code';
        end if;
      end loop;

      v_before_state := pg_catalog.jsonb_build_object(
        'purpose', v_purpose,
        'version', v_current_version,
        'failedAttempts', v_failed_attempts,
        'locked', v_locked_at is not null,
        'expired', v_expires_at <= pg_catalog.now()
      );

      if v_purpose = 'pickup' then
        update private.merchant_orders as merchant_order
        set pickup_code_version = v_new_version,
            pickup_code_digest = private.order_handoff_digest(v_new_code),
            pickup_code_expires_at = pg_catalog.now() + interval '6 hours',
            pickup_code_failed_attempts = 0,
            pickup_code_locked_at = null,
            state_version = merchant_order.state_version + 1,
            updated_at = pg_catalog.now()
        where merchant_order.id = v_order.id
        returning merchant_order.* into v_order;
      else
        update private.merchant_orders as merchant_order
        set delivery_code_version = v_new_version,
            delivery_code_digest = private.order_handoff_digest(v_new_code),
            delivery_code_expires_at = pg_catalog.now() + interval '6 hours',
            delivery_code_failed_attempts = 0,
            delivery_code_locked_at = null,
            state_version = merchant_order.state_version + 1,
            updated_at = pg_catalog.now()
        where merchant_order.id = v_order.id
        returning merchant_order.* into v_order;
      end if;

      response_body := private.merchant_order_json(v_order);
      response_status := 200;

      insert into audit.events (
        actor_id, action, entity_type, entity_id,
        reason, before_state, after_state
      ) values (
        p_account_id,
        'merchant_order_handoff_code_reset',
        'merchant_order',
        v_order.id,
        v_reason,
        v_before_state,
        pg_catalog.jsonb_build_object(
          'purpose', v_purpose,
          'version', v_new_version,
          'failedAttempts', 0,
          'locked', false,
          'expired', false
        )
      );
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

revoke execute on function public.owner_reset_order_handoff_code(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.owner_reset_order_handoff_code(
  uuid, uuid, text, text, text, text
) to service_role;
