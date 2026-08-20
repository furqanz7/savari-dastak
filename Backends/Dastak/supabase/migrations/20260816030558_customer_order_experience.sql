create table private.customer_order_support_cases (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  entity_kind text not null check (entity_kind in ('merchant_order', 'parcel_delivery')),
  entity_id uuid not null,
  requester_account_id uuid not null references public.accounts(id) on delete cascade,
  category text not null check (
    category in (
      'delivery_status', 'merchant_or_items', 'payment', 'refund',
      'cancellation', 'safety', 'other'
    )
  ),
  message text not null check (
    pg_catalog.char_length(pg_catalog.btrim(message)) between 10 and 1000
  ),
  status text not null default 'open' check (
    status in ('open', 'in_review', 'resolved', 'closed')
  ),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create index customer_order_support_cases_requester_idx
  on private.customer_order_support_cases (requester_account_id, created_at desc);
create index customer_order_support_cases_entity_idx
  on private.customer_order_support_cases (entity_kind, entity_id, created_at desc);
create index customer_order_support_cases_open_idx
  on private.customer_order_support_cases (entity_kind, entity_id, requester_account_id)
  where status in ('open', 'in_review');

alter table private.customer_order_support_cases enable row level security;
revoke all on table private.customer_order_support_cases from public, anon, authenticated;
grant select, insert, update on table private.customer_order_support_cases to service_role;

create function private.customer_order_support_case_json(
  support_case private.customer_order_support_cases
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'caseId', (support_case).id,
    'reference', 'DST-' || pg_catalog.upper(
      pg_catalog.substr(pg_catalog.replace((support_case).id::text, '-', ''), 1, 8)
    ),
    'entityKind', (support_case).entity_kind,
    'entityId', (support_case).entity_id,
    'category', (support_case).category,
    'message', (support_case).message,
    'status', (support_case).status,
    'createdAt', (support_case).created_at,
    'updatedAt', (support_case).updated_at
  );
$$;

create function private.customer_order_support_cases_json(
  p_entity_kind text,
  p_entity_id uuid,
  p_account_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      private.customer_order_support_case_json(support_case)
      order by support_case.created_at desc, support_case.id desc
    ),
    '[]'::jsonb
  )
  from private.customer_order_support_cases as support_case
  where support_case.entity_kind = p_entity_kind
    and support_case.entity_id = p_entity_id
    and support_case.requester_account_id = p_account_id;
$$;

create function private.customer_merchant_order_actions(
  order_row private.merchant_orders
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with latest_customer_review as (
    select decision.decision_status
    from private.merchant_order_refund_decisions as decision
    where decision.order_id = (order_row).id
      and decision.source = 'customer'
    order by decision.created_at desc, decision.id desc
    limit 1
  )
  select pg_catalog.jsonb_build_object(
    'canPay',
      (order_row).status = 'payment_pending'
      and (order_row).payment_state = 'payment_pending',
    'cancellationMode', case
      when exists (
        select 1 from latest_customer_review where decision_status = 'review_required'
      ) then 'pending_review'
      when (order_row).status in ('payment_pending', 'paid') then 'cancel'
      when (order_row).status in (
        'merchant_accepted', 'ready', 'assigned', 'en_route_to_pickup',
        'at_store', 'picked_up', 'in_transit', 'returning_to_merchant'
      ) then 'request_review'
      else 'none'
    end,
    'canTrack', (order_row).status in (
      'assigned', 'en_route_to_pickup', 'at_store', 'picked_up', 'in_transit'
    ),
    'canContactStore', (order_row).status in (
      'paid', 'merchant_accepted', 'ready', 'assigned', 'en_route_to_pickup',
      'at_store', 'picked_up', 'in_transit'
    ),
    'canContactCourier', (order_row).status in (
      'assigned', 'en_route_to_pickup', 'at_store', 'picked_up', 'in_transit'
    ),
    'canRequestSupport', true
  );
$$;

create function private.customer_parcel_delivery_actions(
  parcel_row private.parcel_deliveries,
  p_audience text
)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'canPay',
      p_audience = 'customer'
      and (parcel_row).status = 'payment_pending'
      and (parcel_row).payment_status in ('pending', 'failed'),
    'cancellationMode', case
      when p_audience = 'customer'
        and (parcel_row).status in ('payment_pending', 'paid', 'assigned', 'en_route_to_pickup')
      then 'cancel'
      else 'none'
    end,
    'canTrack', (parcel_row).status in (
      'assigned', 'en_route_to_pickup', 'picked_up', 'in_transit'
    ),
    'canContactStore', false,
    'canContactCourier', (parcel_row).status in (
      'assigned', 'en_route_to_pickup', 'picked_up', 'in_transit'
    ),
    'canRequestSupport', true
  );
$$;

create function private.customer_merchant_order_json(
  order_row private.merchant_orders,
  p_account_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.merchant_order_json_with_handoff(order_row, 'customer')
    || pg_catalog.jsonb_build_object(
      'customerActions', private.customer_merchant_order_actions(order_row),
      'supportCases', private.customer_order_support_cases_json(
        'merchant_order', (order_row).id, p_account_id
      )
    );
$$;

create function private.customer_parcel_delivery_json(
  parcel_row private.parcel_deliveries,
  p_audience text,
  p_account_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.parcel_delivery_json(parcel_row, p_audience)
    || pg_catalog.jsonb_build_object(
      'customerActions', private.customer_parcel_delivery_actions(parcel_row, p_audience),
      'supportCases', private.customer_order_support_cases_json(
        'parcel_delivery', (parcel_row).id, p_account_id
      )
    );
$$;

revoke execute on function private.customer_order_support_case_json(
  private.customer_order_support_cases
) from public, anon, authenticated;
revoke execute on function private.customer_order_support_cases_json(text, uuid, uuid)
  from public, anon, authenticated;
revoke execute on function private.customer_merchant_order_actions(private.merchant_orders)
  from public, anon, authenticated;
revoke execute on function private.customer_parcel_delivery_actions(
  private.parcel_deliveries, text
) from public, anon, authenticated;
revoke execute on function private.customer_merchant_order_json(
  private.merchant_orders, uuid
) from public, anon, authenticated;
revoke execute on function private.customer_parcel_delivery_json(
  private.parcel_deliveries, text, uuid
) from public, anon, authenticated;

grant execute on function private.customer_order_support_case_json(
  private.customer_order_support_cases
) to service_role;
grant execute on function private.customer_order_support_cases_json(text, uuid, uuid)
  to service_role;
grant execute on function private.customer_merchant_order_actions(private.merchant_orders)
  to service_role;
grant execute on function private.customer_parcel_delivery_actions(
  private.parcel_deliveries, text
) to service_role;
grant execute on function private.customer_merchant_order_json(
  private.merchant_orders, uuid
) to service_role;
grant execute on function private.customer_parcel_delivery_json(
  private.parcel_deliveries, text, uuid
) to service_role;

create or replace function public.get_customer_orders(p_account_id uuid)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

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

  select pg_catalog.jsonb_build_object(
    'orders', coalesce(
      pg_catalog.jsonb_agg(
        private.customer_merchant_order_json(merchant_order, p_account_id)
        order by merchant_order.created_at desc, merchant_order.id desc
      ),
      '[]'::jsonb
    )
  )
  into response_body
  from private.merchant_orders as merchant_order
  where merchant_order.customer_account_id = p_account_id;

  response_status := 200;
  return next;
end;
$$;

create function public.get_customer_order_snapshot(
  p_account_id uuid,
  p_order_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_order private.merchant_orders%rowtype;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

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

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.customer_account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The order does not exist.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  response_body := private.customer_merchant_order_json(v_order, p_account_id);
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_parcel_delivery_snapshot(
  p_account_id uuid,
  p_parcel_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parcel private.parcel_deliveries%rowtype;
  v_audience text;
begin
  select parcel.* into v_parcel
  from private.parcel_deliveries as parcel
  where parcel.id = p_parcel_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'parcel_not_found', 'message', 'The parcel does not exist.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if v_parcel.customer_account_id = p_account_id then
    v_audience := 'customer';
  elsif v_parcel.recipient_account_id = p_account_id then
    v_audience := 'recipient';
  elsif exists (
    select 1
    from private.parcel_assignment_attempts as assignment
    where assignment.parcel_id = v_parcel.id
      and assignment.partner_account_id = p_account_id
      and assignment.status in ('offered', 'acknowledged', 'completed')
  ) then
    v_audience := 'partner_current';
  else
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'This parcel is not available to the account.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  response_body := case
    when v_audience in ('customer', 'recipient')
      then private.customer_parcel_delivery_json(v_parcel, v_audience, p_account_id)
    else private.parcel_delivery_json(v_parcel, v_audience)
  end;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_customer_parcel_deliveries(
  p_account_id uuid,
  p_limit integer default 50
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The parcel list request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

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
      private.customer_parcel_delivery_json(
        selected.parcel, selected.private_audience, p_account_id
      ) || pg_catalog.jsonb_build_object('audience', selected.public_audience)
      order by selected.sort_created_at desc
    ),
    '[]'::jsonb
  )
  into response_body
  from (
    select
      parcel,
      parcel.created_at as sort_created_at,
      case when parcel.customer_account_id = p_account_id then 'customer' else 'recipient' end
        as private_audience,
      case when parcel.customer_account_id = p_account_id then 'sender' else 'recipient' end
        as public_audience
    from private.parcel_deliveries as parcel
    where parcel.customer_account_id = p_account_id
       or parcel.recipient_account_id = p_account_id
    order by parcel.created_at desc
    limit p_limit
  ) as selected;

  response_status := 200;
  return next;
end;
$$;

create function public.create_customer_order_support_case(
  p_account_id uuid,
  p_entity_kind text,
  p_entity_id uuid,
  p_category text,
  p_message text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'create_customer_order_support_case';
  v_existing private.request_deduplication%rowtype;
  v_support_case private.customer_order_support_cases%rowtype;
  v_response jsonb;
begin
  if p_entity_kind not in ('merchant_order', 'parcel_delivery')
    or p_category not in (
      'delivery_status', 'merchant_or_items', 'payment', 'refund',
      'cancellation', 'safety', 'other'
    )
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_message, ''))) not between 10 and 1000
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 8 and 200
    or coalesce(p_request_digest, '') !~ '^[0-9a-f]{64}$'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed', 'message', 'The support request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select * into v_existing
  from private.request_deduplication
  where account_id = p_account_id
    and function_name = v_function_name
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

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

  if p_entity_kind = 'merchant_order' then
    perform 1
    from private.merchant_orders as merchant_order
    where merchant_order.id = p_entity_id
      and merchant_order.customer_account_id = p_account_id;
  else
    perform 1
    from private.parcel_deliveries as parcel
    where parcel.id = p_entity_id
      and (
        parcel.customer_account_id = p_account_id
        or parcel.recipient_account_id = p_account_id
      );
  end if;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The order does not exist.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  select support_case.* into v_support_case
  from private.customer_order_support_cases as support_case
  where support_case.entity_kind = p_entity_kind
    and support_case.entity_id = p_entity_id
    and support_case.requester_account_id = p_account_id
    and support_case.category = p_category
    and support_case.status in ('open', 'in_review')
  order by support_case.created_at desc, support_case.id desc
  limit 1;

  if not found then
    insert into private.customer_order_support_cases (
      entity_kind, entity_id, requester_account_id, category, message
    )
    values (
      p_entity_kind,
      p_entity_id,
      p_account_id,
      p_category,
      pg_catalog.regexp_replace(pg_catalog.btrim(p_message), '\\s+', ' ', 'g')
    )
    returning * into v_support_case;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason, after_state
    )
    values (
      p_account_id,
      'customer_order_support_requested',
      'customer_order_support_case',
      v_support_case.id,
      v_support_case.category,
      private.customer_order_support_case_json(v_support_case)
    );
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'supportCase', private.customer_order_support_case_json(v_support_case)
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response, 201
  );

  response_body := v_response;
  response_status := 201;
  return next;
end;
$$;

revoke execute on function public.get_customer_orders(uuid) from public, anon, authenticated;
revoke execute on function public.get_customer_order_snapshot(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.get_parcel_delivery_snapshot(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.get_customer_parcel_deliveries(uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.create_customer_order_support_case(
  uuid, text, uuid, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.get_customer_orders(uuid) to service_role;
grant execute on function public.get_customer_order_snapshot(uuid, uuid) to service_role;
grant execute on function public.get_parcel_delivery_snapshot(uuid, uuid) to service_role;
grant execute on function public.get_customer_parcel_deliveries(uuid, integer) to service_role;
grant execute on function public.create_customer_order_support_case(
  uuid, text, uuid, text, text, text, text
) to service_role;

notify pgrst, 'reload schema';
