-- Admin scale hardening. These additive, permission-checked projections replace
-- complete-looking fixed snapshots with opaque keyset pages. Existing mutation,
-- audit, and authorization contracts remain unchanged.

create function dastak_v1_api.admin_execution_orders_page(
  p_actor_id uuid,
  p_scope text default 'ACTIVE',
  p_query text default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_order_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_scope, 'ACTIVE')));
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_orders jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.orders.trace');
  if v_scope not in ('ACTIVE', 'HISTORY') then
    raise exception using errcode = '22023', message = 'invalid Admin order scope';
  end if;
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'limit must be between 1 and 100';
  end if;
  if (p_after_updated_at is null) <> (p_after_order_id is null) then
    raise exception using errcode = '22023', message = 'complete Admin order cursor required';
  end if;
  if v_query is not null and pg_catalog.char_length(v_query) > 80 then
    raise exception using errcode = '22023', message = 'Admin order query is too long';
  end if;

  insert into dastak_v1.audit_events(actor_id, action, resource_type, metadata)
  values (p_actor_id, 'ADMIN_EXECUTION_ORDERS_READ', 'order_collection',
    pg_catalog.jsonb_build_object('scope', v_scope, 'query', v_query, 'limit', p_limit));

  with eligible as (
    select customer_order.*
    from dastak_v1.orders customer_order
    where (
      (v_scope = 'ACTIVE' and customer_order.status::text not in (
        'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT',
        'CANCELLED', 'DASTAK_FULFILMENT_FAILURE'
      )) or
      (v_scope = 'HISTORY' and customer_order.status::text in (
        'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT',
        'CANCELLED', 'DASTAK_FULFILMENT_FAILURE'
      ))
    )
      and (v_query is null or customer_order.id::text = pg_catalog.lower(v_query)
        or customer_order.display_order_number ilike '%' || v_query || '%')
      and (p_after_updated_at is null or
        (customer_order.updated_at, customer_order.id) < (p_after_updated_at, p_after_order_id))
    order by customer_order.updated_at desc, customer_order.id desc
    limit p_limit + 1
  ), visible as (
    select * from eligible order by updated_at desc, id desc limit p_limit
  )
  select
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', visible.id,
      'displayOrderNumber', visible.display_order_number,
      'orderType', visible.order_type,
      'status', visible.status,
      'version', visible.version,
      'submittedAt', visible.submitted_at,
      'fullySecuredAt', visible.fully_secured_at,
      'paymentExpiresAt', visible.payment_expires_at,
      'paidAt', visible.paid_at,
      'updatedAt', visible.updated_at,
      'deliveredAt', visible.delivered_at
    ) order by visible.updated_at desc, visible.id desc), '[]'::jsonb),
    (select pg_catalog.count(*) > p_limit from eligible),
    case when (select pg_catalog.count(*) > p_limit from eligible) then (
      select pg_catalog.jsonb_build_object('updatedAt', tail.updated_at, 'orderId', tail.id)
      from visible tail order by tail.updated_at, tail.id limit 1
    ) else null end
  into v_orders, v_has_more, v_next_cursor
  from visible;

  return pg_catalog.jsonb_build_object(
    'orders', v_orders, 'hasMore', v_has_more, 'nextCursor', v_next_cursor,
    'scope', v_scope
  );
end;
$$;

create function public.dastak_v1_admin_execution_orders_page(
  p_scope text default 'ACTIVE',
  p_query text default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_order_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_execution_orders_page(
    auth.uid(), p_scope, p_query, p_limit, p_after_updated_at, p_after_order_id
  );
$$;

create function public.get_owner_merchant_orders_page(
  p_account_id uuid,
  p_query text default null,
  p_limit integer default 50,
  p_after_created_at timestamptz default null,
  p_after_order_id uuid default null
)
returns table(response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_orders jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  if p_limit is null or p_limit not between 1 and 100 or
    (p_after_created_at is null) <> (p_after_order_id is null) or
    (v_query is not null and pg_catalog.char_length(v_query) > 80) then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'validation_failed', 'message', 'The history page request is invalid.'));
    response_status := 400; return next; return;
  end if;
  perform 1 from private.account_memberships membership
  where membership.account_id = p_account_id and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active Dastak owner account is required.'));
    response_status := 403; return next; return;
  end if;

  with eligible as (
    select merchant_order.*, store.name as store_name,
      coalesce(line_totals.item_count, 0) as item_count,
      latest_assignment.status as assignment_status,
      latest_refund.id as refund_id,
      latest_refund.order_status as refund_order_status,
      case when latest_refund.id is null then null else
        private.merchant_order_refund_json(latest_refund)
          || pg_catalog.jsonb_build_object('orderStatus', latest_refund.order_status)
      end as refund_decision
    from private.merchant_orders merchant_order
    join private.merchant_stores store on store.id = merchant_order.store_id
    left join lateral (
      select pg_catalog.sum(line.quantity)::integer as item_count
      from private.merchant_order_lines line where line.order_id = merchant_order.id
    ) line_totals on true
    left join lateral (
      select assignment.status from private.delivery_assignment_attempts assignment
      where assignment.order_id = merchant_order.id
      order by assignment.attempt_number desc limit 1
    ) latest_assignment on true
    left join lateral (
      select decision.* from private.merchant_order_refund_decisions decision
      where decision.order_id = merchant_order.id
      order by decision.created_at desc, decision.id desc limit 1
    ) latest_refund on true
    where (v_query is null or merchant_order.id::text = pg_catalog.lower(v_query)
      or store.name ilike '%' || v_query || '%')
      and (p_after_created_at is null or
        (merchant_order.created_at, merchant_order.id) < (p_after_created_at, p_after_order_id))
    order by merchant_order.created_at desc, merchant_order.id desc
    limit p_limit + 1
  ), visible as (
    select * from eligible order by created_at desc, id desc limit p_limit
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'orderId', visible.id,
    'store', pg_catalog.jsonb_build_object('storeId', visible.store_id, 'name', visible.store_name),
    'status', visible.status,
    'paymentState', visible.payment_state,
    'itemSubtotal', pg_catalog.jsonb_build_object('paise', visible.item_subtotal_paise),
    'deliveryFee', pg_catalog.jsonb_build_object('paise', visible.delivery_fee_paise),
    'total', pg_catalog.jsonb_build_object('paise', visible.total_paise),
    'itemCount', visible.item_count,
    'assignmentStatus', visible.assignment_status,
    'controlledScope', visible.controlled_scope,
    'refundDecision', visible.refund_decision,
    'createdAt', visible.created_at,
    'updatedAt', visible.updated_at
  ) order by visible.created_at desc, visible.id desc), '[]'::jsonb),
    (select pg_catalog.count(*) > p_limit from eligible),
    case when (select pg_catalog.count(*) > p_limit from eligible) then (
      select pg_catalog.jsonb_build_object('createdAt', tail.created_at, 'orderId', tail.id)
      from visible tail order by tail.created_at, tail.id limit 1
    ) else null end
  into v_orders, v_has_more, v_next_cursor from visible;

  response_body := pg_catalog.jsonb_build_object(
    'orders', v_orders, 'hasMore', v_has_more, 'nextCursor', v_next_cursor);
  response_status := 200; return next;
end;
$$;

create function public.get_owner_order_exceptions_page(
  p_account_id uuid,
  p_limit integer default 50,
  p_after_occurred_at timestamptz default null,
  p_after_exception_id text default null
)
returns table(response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_exceptions jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  if p_limit is null or p_limit not between 1 and 100 or
    (p_after_occurred_at is null) <> (p_after_exception_id is null) then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'validation_failed', 'message', 'The exception page request is invalid.'));
    response_status := 400; return next; return;
  end if;
  perform 1 from private.account_memberships membership
  where membership.account_id = p_account_id and membership.role = 'owner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active Dastak owner account is required.'));
    response_status := 403; return next; return;
  end if;

  with exception_rows as (
    select 'support:' || support_case.id::text as exception_id, 'support'::text as kind,
      case when support_case.category = 'safety' then 'critical' else 'attention' end as severity,
      support_case.entity_kind, support_case.entity_id, 'Customer support request'::text as title,
      support_case.message as detail, support_case.status, null::text as purpose,
      support_case.created_at as occurred_at
    from private.customer_order_support_cases support_case
    where support_case.status in ('open', 'in_review')
    union all
    select 'refund:' || decision.id::text, 'refund_review', 'attention', 'merchant_order', decision.order_id,
      'Refund decision required', decision.reason, decision.decision_status, null::text, decision.created_at
    from private.merchant_order_refund_decisions decision
    where decision.decision_status = 'review_required'
      and not exists (select 1 from private.merchant_order_refund_decisions later
        where later.order_id = decision.order_id and
          (later.created_at, later.id) > (decision.created_at, decision.id))
    union all
    select 'merchant-code:' || merchant_order.id::text || ':' || code.purpose,
      'handoff_locked', 'critical', 'merchant_order', merchant_order.id,
      case code.purpose when 'pickup' then 'Pickup code locked' else 'Delivery code locked' end,
      'Five unsuccessful code attempts require owner recovery.', 'locked', code.purpose,
      coalesce(code.locked_at, merchant_order.updated_at)
    from private.merchant_orders merchant_order
    cross join lateral (values ('pickup'::text, merchant_order.pickup_code_locked_at),
      ('delivery'::text, merchant_order.delivery_code_locked_at)) code(purpose, locked_at)
    where code.locked_at is not null and merchant_order.status not in ('delivered', 'cancelled')
    union all
    select 'parcel-code:' || parcel.id::text || ':' || code.purpose,
      'handoff_locked', 'critical', 'parcel_delivery', parcel.id,
      case code.purpose when 'pickup' then 'Parcel pickup code locked' else 'Parcel delivery code locked' end,
      'Five unsuccessful code attempts require owner recovery.', 'locked', code.purpose,
      coalesce(code.locked_at, parcel.updated_at)
    from private.parcel_deliveries parcel
    cross join lateral (values ('pickup'::text, parcel.pickup_code_locked_at),
      ('delivery'::text, parcel.delivery_code_locked_at)) code(purpose, locked_at)
    where code.locked_at is not null and parcel.status not in ('delivered', 'cancelled')
    union all
    select 'stalled-merchant:' || merchant_order.id::text, 'stalled_order', 'attention',
      'merchant_order', merchant_order.id, 'Merchant order needs attention',
      'No lifecycle progress has been recorded within the expected window.', merchant_order.status,
      null::text, merchant_order.updated_at
    from private.merchant_orders merchant_order
    where (merchant_order.status in ('merchant_accepted', 'ready', 'at_store') and merchant_order.updated_at < pg_catalog.now() - interval '30 minutes')
      or (merchant_order.status = 'assigned' and merchant_order.updated_at < pg_catalog.now() - interval '15 minutes')
      or (merchant_order.status = 'en_route_to_pickup' and merchant_order.updated_at < pg_catalog.now() - interval '60 minutes')
      or (merchant_order.status in ('picked_up', 'in_transit', 'returning_to_merchant') and merchant_order.updated_at < pg_catalog.now() - interval '2 hours')
    union all
    select 'stalled-parcel:' || parcel.id::text, 'stalled_order', 'attention',
      'parcel_delivery', parcel.id, 'Parcel delivery needs attention',
      'No lifecycle progress has been recorded within the expected window.', parcel.status,
      null::text, parcel.updated_at
    from private.parcel_deliveries parcel
    where (parcel.status in ('paid', 'assigned') and parcel.updated_at < pg_catalog.now() - interval '15 minutes')
      or (parcel.status = 'en_route_to_pickup' and parcel.updated_at < pg_catalog.now() - interval '60 minutes')
      or (parcel.status in ('picked_up', 'in_transit') and parcel.updated_at < pg_catalog.now() - interval '2 hours')
  ), eligible as (
    select * from exception_rows
    where p_after_occurred_at is null or
      (occurred_at, exception_id) < (p_after_occurred_at, p_after_exception_id)
    order by occurred_at desc, exception_id desc limit p_limit + 1
  ), visible as (
    select * from eligible order by occurred_at desc, exception_id desc limit p_limit
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'exceptionId', exception.exception_id, 'kind', exception.kind, 'severity', exception.severity,
    'entityKind', exception.entity_kind, 'entityId', exception.entity_id, 'title', exception.title,
    'detail', exception.detail, 'status', exception.status, 'purpose', exception.purpose,
    'occurredAt', exception.occurred_at
  )) order by exception.occurred_at desc, exception.exception_id desc), '[]'::jsonb),
    (select pg_catalog.count(*) > p_limit from eligible),
    case when (select pg_catalog.count(*) > p_limit from eligible) then (
      select pg_catalog.jsonb_build_object('occurredAt', tail.occurred_at, 'exceptionId', tail.exception_id)
      from visible tail order by tail.occurred_at, tail.exception_id limit 1
    ) else null end
  into v_exceptions, v_has_more, v_next_cursor from visible exception;

  response_body := pg_catalog.jsonb_build_object(
    'exceptions', v_exceptions, 'hasMore', v_has_more, 'nextCursor', v_next_cursor);
  response_status := 200; return next;
end;
$$;

create function dastak_v1_api.razorpayx_admin_page(
  p_actor_id uuid,
  p_limit integer default 50,
  p_after_requested_at timestamptz default null,
  p_after_withdrawal_id uuid default null
)
returns table(response_body jsonb, response_status integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_withdrawals jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  if not dastak_v1_api.actor_has_platform_permission(p_actor_id, 'platform.withdrawals.manage') then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'Withdrawal access is unavailable.'));
    response_status := 403; return next; return;
  end if;
  if p_limit is null or p_limit not between 1 and 100 or
    (p_after_requested_at is null) <> (p_after_withdrawal_id is null) then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'invalid_page', 'message', 'Invalid withdrawal page.'));
    response_status := 400; return next; return;
  end if;

  with eligible as (
    select candidate.* from dastak_v1.royalty_withdrawals candidate
    where p_after_requested_at is null or
      (candidate.requested_at, candidate.id) < (p_after_requested_at, p_after_withdrawal_id)
    order by candidate.requested_at desc, candidate.id desc limit p_limit + 1
  ), visible as (
    select * from eligible order by requested_at desc, id desc limit p_limit
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', withdrawal.id,
    'subjectType', withdrawal.subject_type,
    'subjectId', withdrawal.subject_id,
    'amountPaise', withdrawal.amount_paise,
    'currency', withdrawal.currency_code,
    'domainStatus', withdrawal.status,
    'effectiveStatus', case
      when payout.provider_status = 'REVERSED' then 'REVERSED'
      when payout.provider_status in ('FAILED','REJECTED','CANCELLED') then 'FAILED'
      else withdrawal.status::text end,
    'destinationSnapshot', pg_catalog.jsonb_build_object(
      'type', withdrawal.destination_snapshot ->> 'type',
      'displayLabel', withdrawal.destination_snapshot ->> 'displayLabel',
      'destinationVersion', withdrawal.destination_snapshot ->> 'destinationVersion',
      'providerFundAccountReference', withdrawal.destination_snapshot ->> 'providerDestinationReference'),
    'provider', case when payout.withdrawal_id is null then null else 'RAZORPAYX' end,
    'providerPayoutReference', payout.provider_payout_reference,
    'providerStatus', payout.provider_status,
    'reconciliationState', payout.reconciliation_state,
    'utr', payout.utr,
    'statusDetails', payout.status_details,
    'requestedAt', withdrawal.requested_at,
    'processingAt', withdrawal.processing_at,
    'paidAt', withdrawal.paid_at,
    'failedAt', withdrawal.failed_at,
    'attempts', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', attempt.id, 'attemptNumber', attempt.attempt_number, 'status', attempt.status,
      'providerRequestKey', attempt.provider_request_key, 'startedAt', attempt.started_at,
      'completedAt', attempt.completed_at, 'failureCode', attempt.failure_code)
      order by attempt.attempt_number, attempt.id)
      from dastak_v1.royalty_withdrawal_attempts attempt
      where attempt.withdrawal_id = withdrawal.id), '[]'::jsonb),
    'providerRequests', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', request.id, 'operation', request.operation, 'outcome', request.outcome,
      'httpStatus', request.http_status, 'providerPayoutReference', request.provider_payout_reference,
      'occurredAt', request.occurred_at) order by request.occurred_at, request.id)
      from dastak_v1.razorpayx_provider_requests request
      where request.withdrawal_id = withdrawal.id), '[]'::jsonb),
    'webhookHistory', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'eventId', event.provider_event_id, 'source', event.source,
      'eventType', event.provider_event_type, 'providerStatus', event.provider_status,
      'applicationResult', event.application_result, 'occurredAt', event.occurred_at,
      'processedAt', event.processed_at) order by event.occurred_at, event.provider_event_id)
      from dastak_v1.razorpayx_provider_events event
      where event.withdrawal_id = withdrawal.id), '[]'::jsonb)
  ) order by withdrawal.requested_at desc, withdrawal.id desc), '[]'::jsonb),
    (select pg_catalog.count(*) > p_limit from eligible),
    case when (select pg_catalog.count(*) > p_limit from eligible) then (
      select pg_catalog.jsonb_build_object('requestedAt', tail.requested_at, 'withdrawalId', tail.id)
      from visible tail order by tail.requested_at, tail.id limit 1
    ) else null end
  into v_withdrawals, v_has_more, v_next_cursor
  from visible withdrawal
  left join dastak_v1.razorpayx_payouts payout on payout.withdrawal_id = withdrawal.id;

  response_body := pg_catalog.jsonb_build_object(
    'withdrawals', v_withdrawals, 'hasMore', v_has_more, 'nextCursor', v_next_cursor);
  response_status := 200; return next;
end;
$$;

create function public.dastak_v1_razorpayx_admin_page(
  p_account_id uuid,
  p_limit integer default 50,
  p_after_requested_at timestamptz default null,
  p_after_withdrawal_id uuid default null
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select * from dastak_v1_api.razorpayx_admin_page(
    p_account_id, p_limit, p_after_requested_at, p_after_withdrawal_id);
$$;

revoke all on function dastak_v1_api.admin_execution_orders_page(uuid,text,text,integer,timestamptz,uuid)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_admin_execution_orders_page(text,text,integer,timestamptz,uuid)
  from public, anon;
revoke all on function public.get_owner_merchant_orders_page(uuid,text,integer,timestamptz,uuid)
  from public, anon, authenticated;
revoke all on function public.get_owner_order_exceptions_page(uuid,integer,timestamptz,text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.razorpayx_admin_page(uuid,integer,timestamptz,uuid)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_razorpayx_admin_page(uuid,integer,timestamptz,uuid)
  from public, anon, authenticated;

grant execute on function dastak_v1_api.admin_execution_orders_page(uuid,text,text,integer,timestamptz,uuid)
  to authenticated, service_role;
grant execute on function public.dastak_v1_admin_execution_orders_page(text,text,integer,timestamptz,uuid)
  to authenticated, service_role;
grant execute on function public.get_owner_merchant_orders_page(uuid,text,integer,timestamptz,uuid)
  to service_role;
grant execute on function public.get_owner_order_exceptions_page(uuid,integer,timestamptz,text)
  to service_role;
grant execute on function dastak_v1_api.razorpayx_admin_page(uuid,integer,timestamptz,uuid)
  to service_role;
grant execute on function public.dastak_v1_razorpayx_admin_page(uuid,integer,timestamptz,uuid)
  to service_role;

comment on function public.dastak_v1_admin_execution_orders_page(text,text,integer,timestamptz,uuid) is
  'Permission-checked keyset page for active or terminal Dastak V1 orders.';
comment on function public.get_owner_merchant_orders_page(uuid,text,integer,timestamptz,uuid) is
  'Owner-only keyset page for legacy order history and exact/search lookup.';
comment on function public.get_owner_order_exceptions_page(uuid,integer,timestamptz,text) is
  'Owner-only keyset page for operational exceptions and recovery work.';
comment on function public.dastak_v1_razorpayx_admin_page(uuid,integer,timestamptz,uuid) is
  'Service-role Edge boundary for permission-checked payout keyset pages.';
