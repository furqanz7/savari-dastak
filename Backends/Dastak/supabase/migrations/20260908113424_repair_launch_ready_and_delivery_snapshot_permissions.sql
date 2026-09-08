-- Launch-payment orders prepare before doorstep collection. Keep the legacy
-- succeeded-payment authority while also accepting the server-side launch
-- commitment that authorizes preparation for pay-at-delivery orders.
create or replace function dastak_v1_api.mark_fulfilment_ready(
  p_actor_id uuid,
  p_fulfilment_id uuid,
  p_idempotency_key text,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'markFulfilmentReady';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_package_count integer;
  v_released_capacity integer;
  v_eligibility jsonb;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'fulfilmentId', p_fulfilment_id,
    'expectedVersion', p_expected_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select fulfilment.order_id into v_order_id
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'fulfilment not found';
  end if;

  -- Preparation commands lock order, fulfilment, packages, evidence, then capacity.
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_fulfilment.organization_id,
    'merchant.fulfilment.manage',
    v_fulfilment.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if v_fulfilment.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale fulfilment version';
  end if;
  if v_order.status <> 'PREPARING'
    or not (
      exists (
        select 1
        from dastak_v1.payments payment
        where payment.order_id = v_order.id
          and payment.status = 'SUCCEEDED'
      )
      or exists (
        select 1
        from dastak_v1.launch_payment_commitments commitment
        where commitment.order_id = v_order.id
          and commitment.option_code = 'PAY_VIA_UPI_OR_CASH_ON_DELIVERY'
      )
    ) then
    raise exception using errcode = '55000',
      message = 'order payment has not started preparation';
  end if;
  if v_fulfilment.status <> 'PREPARING' then
    raise exception using errcode = '55000',
      message = 'only a Preparing fulfilment can become Ready';
  end if;
  if v_fulfilment.package_count is null then
    raise exception using errcode = '55000',
      message = 'declare package count before marking Ready';
  end if;

  perform 1
  from dastak_v1.packages package
  where package.fulfilment_id = v_fulfilment.id
  order by package.id
  for update;
  select count(*) into v_package_count
  from dastak_v1.packages package
  where package.fulfilment_id = v_fulfilment.id
    and package.status = 'DECLARED'
    and package.current_custody_owner_type = 'MERCHANT_BRANCH'
    and package.current_custody_owner_id = v_fulfilment.branch_id;
  if v_package_count <> v_fulfilment.package_count then
    raise exception using errcode = '55000',
      message = 'every declared package must be present before Ready';
  end if;

  perform 1
  from dastak_v1.fulfilment_evidence evidence
  where evidence.fulfilment_id = v_fulfilment.id
  order by evidence.id
  for share;
  if not exists (
    select 1
    from dastak_v1.fulfilment_evidence evidence
    where evidence.fulfilment_id = v_fulfilment.id
      and evidence.evidence_type = 'MERCHANT_READY_PHOTO'
  ) then
    raise exception using errcode = '55000',
      message = 'merchant Ready evidence is required';
  end if;

  perform 1
  from dastak_v1.retail_capacity_slots slot
  where slot.fulfilment_id = v_fulfilment.id
  for update;

  update dastak_v1.packages
  set status = 'READY',
      ready_at = v_now,
      version = version + 1
  where fulfilment_id = v_fulfilment.id
    and status = 'DECLARED';

  update dastak_v1.fulfilments
  set status = 'READY',
      ready_at = v_now,
      actual_ready_at = v_now,
      version = version + 1
  where id = v_fulfilment.id
  returning * into v_fulfilment;

  if v_fulfilment.fulfilment_type = 'RETAIL' then
    update dastak_v1.retail_capacity_slots
    set status = 'RELEASED',
        released_at = v_now,
        release_reason = 'FULFILMENT_READY',
        version = version + 1
    where fulfilment_id = v_fulfilment.id
      and status = 'HELD';
    get diagnostics v_released_capacity = row_count;
    if v_released_capacity <> 1 then
      raise exception 'Ready must release exactly one retail capacity slot';
    end if;
  end if;

  v_eligibility := dastak_v1_api.order_rider_match_eligibility(v_order.id, v_now);
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_fulfilment.id::text || ':FULFILMENT_READY:' || v_fulfilment.version::text,
    'FULFILMENT',
    v_fulfilment.id,
    v_fulfilment.version,
    'FULFILMENT_READY',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'fulfilmentId', v_fulfilment.id,
      'branchId', v_fulfilment.branch_id,
      'actualReadyAt', v_fulfilment.actual_ready_at,
      'packageCount', v_fulfilment.package_count,
      'capacityReleased', v_fulfilment.fulfilment_type = 'RETAIL',
      'orderRiderMatchEligible', (v_eligibility ->> 'eligible')::boolean
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'FULFILMENT_READY',
    'fulfilment',
    v_fulfilment.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'branchId', v_fulfilment.branch_id,
      'packageCount', v_fulfilment.package_count,
      'actualReadyAt', v_fulfilment.actual_ready_at,
      'idempotencyKey', p_idempotency_key,
      'riderMatchEligibility', v_eligibility
    )
  );

  v_response := dastak_v1_api.merchant_fulfilment_json(
    p_actor_id, v_fulfilment.id
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_fulfilment.id
  );
  return v_response;
end;
$$;

-- Edge Functions call the public wrapper with the service role. The launch
-- payment migration accidentally granted this internal projection to
-- authenticated clients instead, which made every V1 rider refresh return 403.
revoke all on function dastak_v1_api.delivery_partner_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function dastak_v1_api.delivery_partner_snapshot(uuid)
  to service_role;

comment on function dastak_v1_api.mark_fulfilment_ready(uuid,uuid,text,bigint) is
  'Marks a prepared fulfilment Ready after either legacy payment success or a server-authoritative launch pay-at-delivery commitment.';

comment on function dastak_v1_api.delivery_partner_snapshot(uuid) is
  'Service-only delivery snapshot projection used by the authenticated courier-dispatch edge function.';
