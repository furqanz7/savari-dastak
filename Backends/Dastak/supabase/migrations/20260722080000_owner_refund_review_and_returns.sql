create or replace function public.get_owner_merchant_orders(
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
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    );

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

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The order limit must be between 1 and 100.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select pg_catalog.jsonb_build_object(
    'orders', coalesce(
      pg_catalog.jsonb_agg(recent.order_json order by recent.created_at desc),
      '[]'::jsonb
    )
  )
  into response_body
  from (
    select
      merchant_order.created_at,
      pg_catalog.jsonb_build_object(
        'orderId', merchant_order.id,
        'store', pg_catalog.jsonb_build_object(
          'storeId', store.id,
          'name', store.name
        ),
        'status', merchant_order.status,
        'paymentState', merchant_order.payment_state,
        'itemSubtotal', pg_catalog.jsonb_build_object(
          'paise', merchant_order.item_subtotal_paise
        ),
        'deliveryFee', pg_catalog.jsonb_build_object(
          'paise', merchant_order.delivery_fee_paise
        ),
        'total', pg_catalog.jsonb_build_object(
          'paise', merchant_order.total_paise
        ),
        'itemCount', coalesce(line_totals.item_count, 0),
        'assignmentStatus', latest_assignment.status,
        'controlledScope', merchant_order.controlled_scope,
        'refundDecision', case
          when latest_refund.id is null then null
          else private.merchant_order_refund_json(latest_refund)
            || pg_catalog.jsonb_build_object(
              'orderStatus', latest_refund.order_status
            )
        end,
        'createdAt', merchant_order.created_at,
        'updatedAt', merchant_order.updated_at
      ) as order_json
    from private.merchant_orders as merchant_order
    join private.merchant_stores as store
      on store.id = merchant_order.store_id
    left join lateral (
      select pg_catalog.sum(line.quantity)::integer as item_count
      from private.merchant_order_lines as line
      where line.order_id = merchant_order.id
    ) as line_totals on true
    left join lateral (
      select assignment.status
      from private.delivery_assignment_attempts as assignment
      where assignment.order_id = merchant_order.id
      order by assignment.attempt_number desc
      limit 1
    ) as latest_assignment on true
    left join lateral (
      select decision.*
      from private.merchant_order_refund_decisions as decision
      where decision.order_id = merchant_order.id
      order by decision.created_at desc, decision.id desc
      limit 1
    ) as latest_refund on true
    order by merchant_order.created_at desc, merchant_order.id desc
    limit p_limit
  ) as recent;

  response_status := 200;
  return next;
end;
$$;

create function public.owner_review_merchant_order_refund(
  p_account_id uuid,
  p_order_id uuid,
  p_outcome text,
  p_fault_source text,
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
  v_function_name constant text := 'owner_review_merchant_order_refund';
  v_existing private.request_deduplication%rowtype;
  v_order private.merchant_orders%rowtype;
  v_review private.merchant_order_refund_decisions%rowtype;
  v_before_state jsonb;
  v_outcome text := nullif(pg_catalog.btrim(p_outcome), '');
  v_fault_source text := nullif(pg_catalog.btrim(p_fault_source), '');
  v_reason text := nullif(pg_catalog.btrim(p_reason), '');
  v_post_pickup boolean;
  v_eligibility text;
  v_delivery_refund integer;
begin
  if p_account_id is null
    or p_order_id is null
    or v_outcome is null
    or v_outcome not in ('approve_full', 'approve_items_only', 'deny')
    or (v_fault_source is not null and v_fault_source not in ('merchant', 'dastak'))
    or v_reason is null
    or pg_catalog.char_length(v_reason) > 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The refund review request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

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
        'message', 'Only an active Dastak owner can review refunds.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
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
    return next;
    return;
  end if;

  select decision.*
  into v_review
  from private.merchant_order_refund_decisions as decision
  where decision.order_id = v_order.id
  order by decision.created_at desc, decision.id desc
  limit 1
  for update;

  if not found or v_review.decision_status <> 'review_required' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'refund_review_not_pending',
        'message', 'This order has no refund request awaiting review.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := private.merchant_order_json(v_order);
  v_post_pickup := v_review.eligibility = 'delivery_fee_retained_unless_fault'
    or v_order.status in ('picked_up', 'in_transit', 'returning_to_merchant');

  if v_outcome = 'approve_items_only' and not v_post_pickup then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_refund_decision',
        'message', 'Items-only refunds apply only after courier pickup.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_outcome = 'approve_full' and v_post_pickup and v_fault_source is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'refund_fault_required',
        'message', 'A merchant or Dastak fault is required to refund delivery after pickup.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_outcome <> 'deny'
    and (
      v_order.payment_state <> 'paid'
      or v_order.status in ('payment_pending', 'paid', 'cancelled', 'delivered')
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order can no longer enter the approved refund flow.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_outcome = 'deny' then
    insert into private.merchant_order_refund_decisions (
      order_id, requested_by_account_id, source, order_status,
      eligibility, decision_status, item_refund_paise,
      delivery_fee_refund_paise, reason
    ) values (
      v_order.id, p_account_id, 'owner', v_order.status,
      v_review.eligibility, 'denied', null, null, v_reason
    );
  else
    v_eligibility := case
      when v_post_pickup and v_outcome = 'approve_full'
        then 'merchant_fault_full_refund'
      else 'full_refund'
    end;
    v_delivery_refund := case
      when v_outcome = 'approve_items_only' then 0
      else v_order.delivery_fee_paise
    end;

    insert into private.merchant_order_refund_decisions (
      order_id, requested_by_account_id, source, order_status,
      eligibility, decision_status, item_refund_paise,
      delivery_fee_refund_paise, reason
    ) values (
      v_order.id, p_account_id, 'owner', v_order.status,
      v_eligibility, 'eligible', v_order.item_subtotal_paise,
      v_delivery_refund,
      case
        when v_fault_source is null then v_reason
        else v_fault_source || ' fault: ' || v_reason
      end
    );

    update private.merchant_orders as merchant_order
    set status = case
          when v_post_pickup then 'returning_to_merchant'
          else 'cancelled'
        end,
        payment_state = 'refund_pending',
        cancelled_at = case
          when v_post_pickup then merchant_order.cancelled_at
          else coalesce(merchant_order.cancelled_at, pg_catalog.now())
        end,
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;
  end if;

  response_body := private.merchant_order_json(v_order);
  response_status := 200;

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason,
    before_state, after_state
  ) values (
    p_account_id,
    case
      when v_outcome = 'deny' then 'merchant_order_refund_denied'
      else 'merchant_order_refund_approved'
    end,
    'merchant_order', v_order.id, v_reason,
    v_before_state, response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

create function public.merchant_confirm_customer_cancellation_return(
  p_account_id uuid,
  p_order_id uuid,
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
  v_function_name constant text := 'merchant_confirm_customer_cancellation_return';
  v_existing private.request_deduplication%rowtype;
  v_order private.merchant_orders%rowtype;
  v_decision private.merchant_order_refund_decisions%rowtype;
  v_assignment private.delivery_assignment_attempts%rowtype;
  v_before_state jsonb;
  v_reason text := nullif(pg_catalog.btrim(p_reason), '');
begin
  if p_account_id is null
    or p_order_id is null
    or v_reason is null
    or pg_catalog.char_length(v_reason) > 300
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The return confirmation is invalid.'
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
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
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

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  join private.merchant_stores as store
    on store.id = merchant_order.store_id
   and store.merchant_account_id = p_account_id
  where merchant_order.id = p_order_id
  for update of merchant_order;

  if not found
    or not private.has_active_membership(p_account_id, 'merchant')
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only the approved merchant can confirm this return.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select decision.*
  into v_decision
  from private.merchant_order_refund_decisions as decision
  where decision.order_id = v_order.id
  order by decision.created_at desc, decision.id desc
  limit 1;

  if not found
    or v_order.status <> 'returning_to_merchant'
    or v_order.payment_state <> 'refund_pending'
    or v_decision.source <> 'owner'
    or v_decision.decision_status <> 'eligible'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order is not awaiting a customer-cancellation return.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select assignment.*
  into v_assignment
  from private.delivery_assignment_attempts as assignment
  where assignment.order_id = v_order.id
    and assignment.status = 'accepted'
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'active_assignment_required',
        'message', 'The assigned delivery partner must return this order.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := private.merchant_order_json(v_order);

  update private.delivery_assignment_attempts as assignment
  set status = 'completed',
      responded_at = coalesce(assignment.responded_at, pg_catalog.now()),
      response_reason = 'customer_cancellation_returned',
      updated_at = pg_catalog.now()
  where assignment.id = v_assignment.id;

  update private.merchant_orders as merchant_order
  set status = 'cancelled',
      cancelled_at = coalesce(merchant_order.cancelled_at, pg_catalog.now()),
      state_version = merchant_order.state_version + 1,
      updated_at = pg_catalog.now()
  where merchant_order.id = v_order.id
  returning merchant_order.* into v_order;

  response_body := private.merchant_order_json(v_order);
  response_status := 200;

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason,
    before_state, after_state
  ) values (
    p_account_id, 'customer_cancellation_return_confirmed',
    'merchant_order', v_order.id, v_reason,
    v_before_state, response_body
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );

  return next;
end;
$$;

revoke execute on function public.get_owner_merchant_orders(uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.owner_review_merchant_order_refund(
  uuid, uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.merchant_confirm_customer_cancellation_return(
  uuid, uuid, text, text, text
) from public, anon, authenticated;

grant execute on function public.get_owner_merchant_orders(uuid, integer)
  to service_role;
grant execute on function public.owner_review_merchant_order_refund(
  uuid, uuid, text, text, text, text, text
) to service_role;
grant execute on function public.merchant_confirm_customer_cancellation_return(
  uuid, uuid, text, text, text
) to service_role;
