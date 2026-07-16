alter table private.merchant_orders
drop constraint merchant_orders_status_check;

alter table private.merchant_orders
add constraint merchant_orders_status_check check (
  status in (
    'payment_pending', 'paid', 'merchant_accepted', 'ready', 'assigned',
    'en_route_to_pickup', 'at_store', 'picked_up', 'in_transit', 'delivered',
    'cancelled', 'returning_to_merchant'
  )
);

alter table private.merchant_orders
  add column assigned_at timestamptz,
  add column en_route_to_pickup_at timestamptz,
  add column arrived_at_store_at timestamptz,
  add column picked_up_at timestamptz,
  add column in_transit_at timestamptz,
  add column delivered_at timestamptz;

update private.merchant_orders
set assigned_at = coalesce(assigned_at, updated_at)
where status in (
  'assigned', 'en_route_to_pickup', 'picked_up', 'in_transit',
  'delivered', 'returning_to_merchant'
);

update private.merchant_orders
set en_route_to_pickup_at = coalesce(en_route_to_pickup_at, updated_at)
where status in (
  'en_route_to_pickup', 'picked_up', 'in_transit',
  'delivered', 'returning_to_merchant'
);

update private.merchant_orders
set picked_up_at = coalesce(picked_up_at, updated_at)
where status in ('picked_up', 'in_transit', 'delivered', 'returning_to_merchant');

update private.merchant_orders
set in_transit_at = coalesce(in_transit_at, updated_at)
where status in ('in_transit', 'delivered');

update private.merchant_orders
set delivered_at = coalesce(delivered_at, updated_at)
where status = 'delivered';

create function private.stamp_merchant_order_lifecycle()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  case new.status
    when 'assigned' then
      new.assigned_at := coalesce(new.assigned_at, pg_catalog.now());
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

revoke execute on function private.stamp_merchant_order_lifecycle()
  from public, anon, authenticated;
grant execute on function private.stamp_merchant_order_lifecycle()
  to service_role;

create trigger merchant_order_lifecycle_timestamps
before update of status on private.merchant_orders
for each row
when (old.status is distinct from new.status)
execute function private.stamp_merchant_order_lifecycle();

create function public.advance_delivery_assignment(
  p_account_id uuid,
  p_assignment_id uuid,
  p_action text,
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
  v_action text;
  v_attempt private.delivery_assignment_attempts%rowtype;
  v_audit_action text;
  v_before_state jsonb;
  v_existing_dedup private.request_deduplication%rowtype;
  v_expected_status text;
  v_function_name constant text := 'advance_delivery_assignment';
  v_order private.merchant_orders%rowtype;
  v_target_status text;
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
      when 'start_delivery' then
        v_expected_status := 'picked_up';
        v_target_status := 'in_transit';
        v_audit_action := 'delivery_job_started_delivery';
      when 'complete_delivery' then
        v_expected_status := 'in_transit';
        v_target_status := 'delivered';
        v_audit_action := 'delivery_job_completed';
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
  uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.advance_delivery_assignment(
  uuid, uuid, text, text, text
) to service_role;

create or replace function public.customer_cancel_order(
  p_account_id uuid,
  p_order_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'customer_cancel_order';
  v_existing_dedup private.request_deduplication%rowtype;
  v_order private.merchant_orders%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_response_status integer;
  v_order_status text;
  v_eligibility text;
  v_decision_status text;
  v_item_refund_paise bigint;
  v_delivery_fee_refund_paise integer;
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

  if p_order_id is null
    or p_reason is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 1 and 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The customer cancellation request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_dedup.request_digest = p_request_digest then
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
    and merchant_order.customer_account_id = p_account_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if v_order.status = 'cancelled' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'The merchant order is already cancelled.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_order_status := v_order.status;
  v_before_state := private.merchant_order_json(v_order);

  if v_order.status = 'payment_pending'
    and v_order.payment_state = 'payment_pending'
  then
    update private.merchant_orders as merchant_order
    set status = 'cancelled',
        payment_state = 'not_collected',
        cancelled_at = pg_catalog.now(),
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;

    v_eligibility := 'no_payment';
    v_decision_status := 'not_required';
    v_item_refund_paise := 0;
    v_delivery_fee_refund_paise := 0;
    v_response_status := 200;
  elsif v_order.status = 'paid' and v_order.payment_state = 'paid' then
    update private.merchant_orders as merchant_order
    set status = 'cancelled',
        payment_state = 'refund_pending',
        cancelled_at = pg_catalog.now(),
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;

    v_eligibility := 'full_refund';
    v_decision_status := 'eligible';
    v_item_refund_paise := v_order.item_subtotal_paise;
    v_delivery_fee_refund_paise := v_order.delivery_fee_paise;
    v_response_status := 200;
  elsif v_order.status in (
    'merchant_accepted', 'ready', 'assigned', 'en_route_to_pickup',
    'at_store', 'delivered'
  ) then
    v_eligibility := 'owner_review_required';
    v_decision_status := 'review_required';
    v_item_refund_paise := null;
    v_delivery_fee_refund_paise := null;
    v_response_status := 202;
  elsif v_order.status in ('picked_up', 'in_transit', 'returning_to_merchant') then
    v_eligibility := 'delivery_fee_retained_unless_fault';
    v_decision_status := 'review_required';
    v_item_refund_paise := null;
    v_delivery_fee_refund_paise := null;
    v_response_status := 202;
  else
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order cannot be cancelled in its current state.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into private.merchant_order_refund_decisions (
    order_id, requested_by_account_id, source, order_status,
    eligibility, decision_status, item_refund_paise,
    delivery_fee_refund_paise, reason
  ) values (
    v_order.id,
    p_account_id,
    'customer',
    v_order_status,
    v_eligibility,
    v_decision_status,
    v_item_refund_paise,
    v_delivery_fee_refund_paise,
    pg_catalog.btrim(p_reason)
  );

  v_response_body := private.merchant_order_json(v_order);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason, before_state, after_state
  ) values (
    p_account_id,
    'merchant_order_cancellation_requested',
    'merchant_order',
    v_order.id,
    pg_catalog.btrim(p_reason),
    v_before_state,
    v_response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, v_response_status
  );

  response_body := v_response_body;
  response_status := v_response_status;
  return next;
end;
$$;
