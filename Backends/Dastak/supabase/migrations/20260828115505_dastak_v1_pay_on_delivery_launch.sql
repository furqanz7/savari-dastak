-- Dastak V1 launch payment override.
--
-- The provider payment domain remains intact for historical orders and a future
-- release. New launch orders use one server-owned commitment followed by an
-- assigned-rider collection at the doorstep. No provider row is fabricated.

update dastak_v1.setting_definitions
set default_value = 'true'::jsonb,
    updated_at = pg_catalog.now()
where setting_key = 'commerce.allow_cod';

update dastak_v1.setting_definitions
set default_value = 'false'::jsonb,
    updated_at = pg_catalog.now()
where setting_key = 'commerce.prepaid_only';

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values (
  'payment.launch_option_code',
  'TEXT',
  'The only customer-visible payment option enabled for this launch.',
  '"PAY_VIA_UPI_OR_CASH_ON_DELIVERY"'::jsonb,
  '{"allowedValues":["PAY_VIA_UPI_OR_CASH_ON_DELIVERY"]}'::jsonb,
  true,
  false
) on conflict (setting_key) do update
set value_type = excluded.value_type,
    description = excluded.description,
    default_value = excluded.default_value,
    validation_rules = excluded.validation_rules,
    protected = excluded.protected,
    requires_explicit_value = excluded.requires_explicit_value,
    updated_at = pg_catalog.now();

create table dastak_v1.launch_payment_commitments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references dastak_v1.orders(id),
  customer_id uuid not null references public.accounts(id),
  retired_payment_id uuid not null unique references dastak_v1.payments(id),
  option_code text not null default 'PAY_VIA_UPI_OR_CASH_ON_DELIVERY'
    check (option_code = 'PAY_VIA_UPI_OR_CASH_ON_DELIVERY'),
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null check (currency_code = 'INR'),
  secured_at timestamptz not null,
  reservation_expires_at timestamptz not null,
  committed_at timestamptz not null default pg_catalog.clock_timestamp(),
  version bigint not null default 1 check (version = 1),
  check (reservation_expires_at > secured_at),
  unique (id, order_id),
  unique (id, order_id, amount_paise, currency_code)
);

create table dastak_v1.launch_payment_collection_attempts (
  id uuid primary key default gen_random_uuid(),
  commitment_id uuid not null,
  order_id uuid not null,
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  rider_id uuid not null references public.accounts(id),
  outcome text not null check (outcome in ('COLLECTED', 'FAILED')),
  method text not null check (method in ('CASH', 'UPI')),
  collection_reference text check (
    collection_reference is null or (
      pg_catalog.char_length(collection_reference) between 1 and 200
      and collection_reference ~ '^[A-Za-z0-9][A-Za-z0-9._:/ -]*$'
    )
  ),
  failure_reason text check (
    failure_reason is null
    or pg_catalog.char_length(failure_reason) between 3 and 500
  ),
  attempted_at timestamptz not null default pg_catalog.clock_timestamp(),
  collected_at timestamptz,
  foreign key (commitment_id, order_id)
    references dastak_v1.launch_payment_commitments(id, order_id),
  check (
    (outcome = 'COLLECTED' and collected_at is not null and failure_reason is null)
    or (outcome = 'FAILED' and collected_at is null)
  )
);

create unique index launch_payment_one_collection_uidx
  on dastak_v1.launch_payment_collection_attempts (commitment_id)
  where outcome = 'COLLECTED';
create index launch_payment_commitment_customer_idx
  on dastak_v1.launch_payment_commitments (customer_id);
create index launch_payment_collection_commitment_idx
  on dastak_v1.launch_payment_collection_attempts (commitment_id, order_id);
create index launch_payment_collection_order_idx
  on dastak_v1.launch_payment_collection_attempts (order_id, attempted_at desc, id desc);
create index launch_payment_collection_mission_idx
  on dastak_v1.launch_payment_collection_attempts (mission_id, attempted_at desc, id desc);
create index launch_payment_collection_rider_idx
  on dastak_v1.launch_payment_collection_attempts (rider_id, attempted_at desc, id desc);

create trigger launch_payment_commitments_immutable
before update or delete on dastak_v1.launch_payment_commitments
for each row execute function dastak_v1.reject_mutation();
create trigger launch_payment_collection_attempts_immutable
before update or delete on dastak_v1.launch_payment_collection_attempts
for each row execute function dastak_v1.reject_mutation();

alter table dastak_v1.launch_payment_commitments enable row level security;
alter table dastak_v1.launch_payment_collection_attempts enable row level security;
revoke all on table dastak_v1.launch_payment_commitments,
  dastak_v1.launch_payment_collection_attempts
  from public, anon, authenticated;
grant select on table dastak_v1.launch_payment_commitments,
  dastak_v1.launch_payment_collection_attempts
  to service_role;

create or replace function dastak_v1.is_valid_order_transition(
  p_from dastak_v1.order_status,
  p_to dastak_v1.order_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_from
    when 'CREATED' then p_to in ('MATCHING', 'CANCELLED_PREPAYMENT')
    when 'MATCHING' then p_to in ('FULLY_SECURED', 'UNAVAILABLE', 'CANCELLED_PREPAYMENT')
    when 'FULLY_SECURED' then p_to in ('AWAITING_PAYMENT', 'CANCELLED_PREPAYMENT')
    when 'AWAITING_PAYMENT' then p_to in (
      'PAID', 'PREPARING', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT'
    )
    when 'PAID' then p_to in ('PREPARING', 'DASTAK_FULFILMENT_FAILURE')
    when 'PREPARING' then p_to in ('PICKUP_IN_PROGRESS', 'DASTAK_FULFILMENT_FAILURE')
    when 'PICKUP_IN_PROGRESS' then p_to in ('OUT_FOR_DELIVERY', 'DASTAK_FULFILMENT_FAILURE')
    when 'OUT_FOR_DELIVERY' then p_to in ('DELIVERED', 'DASTAK_FULFILMENT_FAILURE')
    else false
  end;
$$;

create function dastak_v1_api.launch_payment_customer_json(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_commitment dastak_v1.launch_payment_commitments%rowtype;
  v_latest dastak_v1.launch_payment_collection_attempts%rowtype;
  v_state text;
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;
  if v_order.id is null then return null; end if;

  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.order_id = p_order_id;
  select commitment.* into v_commitment
  from dastak_v1.launch_payment_commitments commitment
  where commitment.order_id = p_order_id;
  if v_commitment.id is not null then
    select attempt.* into v_latest
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.commitment_id = v_commitment.id
    order by attempt.attempted_at desc, attempt.id desc
    limit 1;
  end if;

  v_state := case
    when v_commitment.id is null and v_order.status = 'AWAITING_PAYMENT'
      and v_payment.status = 'RESERVED'
      and v_payment.expires_at > pg_catalog.statement_timestamp()
      then 'READY_TO_CONFIRM'
    when v_commitment.id is null and v_order.status in ('PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT')
      then 'RESERVATION_EXPIRED'
    when v_latest.outcome = 'COLLECTED' then 'PAYMENT_COLLECTED'
    when v_latest.outcome = 'FAILED' then 'COLLECTION_RETRY_NEEDED'
    when v_commitment.id is not null then 'PAYMENT_DUE_AT_DELIVERY'
    else 'NOT_APPLICABLE'
  end;

  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'optionLabel', 'Pay via UPI/Cash on Delivery',
    'state', v_state,
    'amountPaise', coalesce(v_commitment.amount_paise, v_payment.amount_paise),
    'currencyCode', coalesce(v_commitment.currency_code, v_payment.currency_code),
    'securedAt', coalesce(v_commitment.secured_at, v_order.fully_secured_at),
    'reservationExpiresAt', coalesce(v_commitment.reservation_expires_at, v_payment.expires_at),
    'reservationSecondsRemaining', case when v_commitment.id is null then
      greatest(0::numeric, pg_catalog.floor(extract(
        epoch from (v_payment.expires_at - pg_catalog.statement_timestamp())
      )))::bigint else 0 end,
    'reservationState', case
      when v_commitment.id is not null then 'COMMITTED'
      when v_payment.status = 'RESERVED' and v_payment.expires_at > pg_catalog.statement_timestamp()
        then 'ACTIVE'
      else 'EXPIRED'
    end,
    'committedAt', v_commitment.committed_at,
    'collectedAt', v_latest.collected_at,
    'collectionMethod', case when v_latest.outcome = 'COLLECTED' then v_latest.method end,
    'canCommit', v_commitment.id is null
      and v_order.status = 'AWAITING_PAYMENT'
      and v_payment.status = 'RESERVED'
      and v_payment.expires_at > pg_catalog.statement_timestamp(),
    'noChargeNow', v_commitment.id is null,
    'payAtDoorstep', true
  ));
end;
$$;

create function dastak_v1_api.launch_collection_mission_json(
  p_mission_id uuid,
  p_rider_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_commitment dastak_v1.launch_payment_commitments%rowtype;
  v_latest dastak_v1.launch_payment_collection_attempts%rowtype;
  v_provider_paid boolean;
begin
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
    and mission.assigned_rider_id = p_rider_id;
  if v_mission.id is null then return null; end if;

  select commitment.* into v_commitment
  from dastak_v1.launch_payment_commitments commitment
  where commitment.order_id = v_mission.order_id;
  select exists (
    select 1 from dastak_v1.payments payment
    where payment.order_id = v_mission.order_id and payment.status = 'SUCCEEDED'
  ) into v_provider_paid;
  if v_commitment.id is not null then
    select attempt.* into v_latest
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.commitment_id = v_commitment.id
    order by attempt.attempted_at desc, attempt.id desc
    limit 1;
  end if;

  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'required', v_commitment.id is not null and v_latest.outcome is distinct from 'COLLECTED',
    'state', case
      when v_provider_paid then 'NOT_REQUIRED'
      when v_latest.outcome = 'COLLECTED' then 'PAYMENT_COLLECTED'
      when v_latest.outcome = 'FAILED' then 'COLLECTION_RETRY_NEEDED'
      when v_commitment.id is not null then 'PAYMENT_DUE_AT_DELIVERY'
      else 'NOT_REQUIRED'
    end,
    'amountPaise', v_commitment.amount_paise,
    'currencyCode', v_commitment.currency_code,
    'methods', case when v_commitment.id is null then '[]'::jsonb
      else '["CASH","UPI"]'::jsonb end,
    'canRecord', v_commitment.id is not null
      and v_latest.outcome is distinct from 'COLLECTED'
      and v_mission.status = 'ARRIVED',
    'lastOutcome', v_latest.outcome,
    'lastMethod', v_latest.method,
    'failureReason', case when v_latest.outcome = 'FAILED' then v_latest.failure_reason end,
    'attemptedAt', v_latest.attempted_at,
    'collectedAt', v_latest.collected_at
  ));
end;
$$;

create function dastak_v1_api.launch_payment_admin_json(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'commitment', case when commitment.id is null then null else
      pg_catalog.jsonb_build_object(
        'id', commitment.id,
        'optionCode', commitment.option_code,
        'customerId', commitment.customer_id,
        'retiredPaymentId', commitment.retired_payment_id,
        'amountPaise', commitment.amount_paise,
        'currencyCode', commitment.currency_code,
        'securedAt', commitment.secured_at,
        'reservationExpiresAt', commitment.reservation_expires_at,
        'committedAt', commitment.committed_at,
        'version', commitment.version
      ) end,
    'collectionStatus', case
      when collected.id is not null then 'COLLECTED'
      when commitment.id is not null and failed.id is not null then 'RETRY_NEEDED'
      when commitment.id is not null then 'DUE'
      else 'NOT_APPLICABLE'
    end,
    'attempts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(
        pg_catalog.jsonb_build_object(
          'id', attempt.id,
          'outcome', attempt.outcome,
          'method', attempt.method,
          'riderId', attempt.rider_id,
          'missionId', attempt.mission_id,
          'reference', attempt.collection_reference,
          'reason', attempt.failure_reason,
          'attemptedAt', attempt.attempted_at,
          'collectedAt', attempt.collected_at
        )
      ) order by attempt.attempted_at, attempt.id)
      from dastak_v1.launch_payment_collection_attempts attempt
      where attempt.order_id = p_order_id
    ), '[]'::jsonb),
    'platformFee', (
      select pg_catalog.jsonb_build_object(
        'transactionId', transaction.id,
        'amountPaise', transaction.amount_paise,
        'currencyCode', transaction.currency_code,
        'postedAt', transaction.created_at,
        'balanced', (
          select pg_catalog.count(*) = 2
            and coalesce(pg_catalog.sum(case when line.direction = 'DEBIT'
              then line.amount_paise else -line.amount_paise end), 0) = 0
          from dastak_v1.financial_journal_lines line
          where line.transaction_id = transaction.id
        )
      )
      from dastak_v1.financial_journal_transactions transaction
      where transaction.transaction_key = p_order_id::text || ':PLATFORM_FEE'
    )
  )
  from (select 1) seed
  left join dastak_v1.launch_payment_commitments commitment
    on commitment.order_id = p_order_id
  left join lateral (
    select attempt.id
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.order_id = p_order_id and attempt.outcome = 'COLLECTED'
    limit 1
  ) collected on true
  left join lateral (
    select attempt.id
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.order_id = p_order_id and attempt.outcome = 'FAILED'
    order by attempt.attempted_at desc, attempt.id desc
    limit 1
  ) failed on true;
$$;

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_pre_launch_payment;
create function dastak_v1_api.order_json(p_order_id uuid, p_customer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when base.snapshot is null then null else
    case when launch.snapshot ->> 'state' <> 'NOT_APPLICABLE'
      then base.snapshot - 'payment'
      else base.snapshot
    end || pg_catalog.jsonb_build_object('launchPayment', launch.snapshot) end
  from (
    select dastak_v1_api.order_json_pre_launch_payment(
      p_order_id, p_customer_id
    ) as snapshot
  ) base
  cross join lateral (
    select dastak_v1_api.launch_payment_customer_json(p_order_id) as snapshot
  ) launch;
$$;

alter function dastak_v1_api.delivery_partner_snapshot(uuid)
  rename to delivery_partner_snapshot_pre_launch_payment;
create function dastak_v1_api.delivery_partner_snapshot(p_rider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_snapshot jsonb;
  v_mission_id uuid;
  v_collection jsonb;
begin
  v_snapshot := dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(p_rider_id);
  begin
    v_mission_id := (v_snapshot #>> '{currentMission,id}')::uuid;
  exception when invalid_text_representation then
    v_mission_id := null;
  end;
  if v_mission_id is not null then
    v_collection := dastak_v1_api.launch_collection_mission_json(
      v_mission_id, p_rider_id
    );
    v_snapshot := pg_catalog.jsonb_set(
      v_snapshot,
      '{currentMission,launchCollection}',
      coalesce(v_collection, 'null'::jsonb),
      true
    );
  end if;
  return v_snapshot;
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_pre_launch_payment;
create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select dastak_v1_api.admin_execution_trace_pre_launch_payment(
    p_actor_id, p_order_id
  ) || pg_catalog.jsonb_build_object(
    'launchPayment', dastak_v1_api.launch_payment_admin_json(p_order_id)
  );
$$;

create function dastak_v1_api.commit_launch_payment(
  p_actor_id uuid,
  p_order_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'commitLaunchPayment';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_price dastak_v1.order_price_snapshots%rowtype;
  v_commitment dastak_v1.launch_payment_commitments%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_required_count integer;
  v_response jsonb;
  v_option text;
  v_settlement_id uuid;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_order_id is null or p_expected_version is null or p_expected_version < 1
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid launch payment commitment';
  end if;

  v_option := dastak_v1_api.effective_setting_json(
    'payment.launch_option_code', null, null, null
  ) #>> '{}';
  if v_option is distinct from 'PAY_VIA_UPI_OR_CASH_ON_DELIVERY' then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'The launch payment option is missing or invalid.';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'orderId', p_order_id,
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
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
    and customer_order.customer_id = p_actor_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  select commitment.* into v_commitment
  from dastak_v1.launch_payment_commitments commitment
  where commitment.order_id = v_order.id;
  if v_commitment.id is not null then
    v_response := dastak_v1_api.order_json(v_order.id, p_actor_id);
    insert into dastak_v1.idempotency_records (
      actor_id, command_name, idempotency_key, request_hash,
      response_body, response_status, resource_id
    ) values (
      p_actor_id, v_command, p_idempotency_key, v_hash,
      v_response, 200, v_order.id
    );
    return v_response;
  end if;

  if v_order.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale order version';
  end if;
  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.order_id = v_order.id
  for update;
  select snapshot.* into v_price
  from dastak_v1.order_price_snapshots snapshot
  where snapshot.order_id = v_order.id
    and snapshot.snapshot_kind = 'FULLY_SECURED';

  if v_order.status <> 'AWAITING_PAYMENT'
    or v_order.fully_secured_at is null
    or v_order.payment_expires_at is null
    or v_order.payment_expires_at <= v_now
    or v_payment.id is null
    or v_payment.customer_id is distinct from p_actor_id
    or v_payment.status <> 'RESERVED'
    or v_payment.expires_at <= v_now
    or v_payment.expires_at is distinct from v_order.payment_expires_at
    or v_price.id is null
    or v_price.total_paise is distinct from v_payment.amount_paise
    or v_price.currency_code is distinct from v_payment.currency_code then
    raise exception using errcode = '55000',
      message = 'launch payment reservation is not active';
  end if;

  perform 1 from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = v_order.id
  order by fulfilment.id for update;
  perform 1 from dastak_v1.order_lines line
  where line.order_id = v_order.id
  order by line.id for update;
  select pg_catalog.count(*) into v_required_count
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = v_order.id;
  if v_required_count < 1 or exists (
    select 1 from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = v_order.id
      and (
        fulfilment.status <> 'RESERVED_PREPAYMENT'
        or fulfilment.prep_started_at is not null
        or fulfilment.estimated_ready_at is not null
      )
  ) or exists (
    select 1
    from dastak_v1.order_lines line
    left join (
      select fulfilment_line.order_line_id,
        pg_catalog.sum(fulfilment_line.confirmed_quantity)::bigint as secured_quantity
      from dastak_v1.fulfilment_lines fulfilment_line
      join dastak_v1.fulfilments fulfilment
        on fulfilment.id = fulfilment_line.fulfilment_id
      where fulfilment.order_id = v_order.id
      group by fulfilment_line.order_line_id
    ) secured on secured.order_line_id = line.id
    where line.order_id = v_order.id
      and (line.status <> 'RESERVED' or coalesce(secured.secured_quantity, 0) <> line.quantity)
  ) then
    raise exception using errcode = '55000',
      message = 'the full secured basket is required before commitment';
  end if;

  insert into dastak_v1.launch_payment_commitments (
    order_id, customer_id, retired_payment_id, option_code,
    amount_paise, currency_code, secured_at,
    reservation_expires_at, committed_at
  ) values (
    v_order.id, p_actor_id, v_payment.id, v_option,
    v_payment.amount_paise, v_payment.currency_code,
    v_order.fully_secured_at, v_payment.expires_at, v_now
  ) returning * into v_commitment;

  update dastak_v1.payment_attempts attempt
  set status = 'EXPIRED', expired_at = v_now,
      version = attempt.version + 1
  where attempt.payment_id = v_payment.id
    and attempt.status in ('CREATED', 'PROVIDER_READY');
  update dastak_v1.payments payment
  set status = 'CANCELLED', cancelled_at = v_now,
      version = payment.version + 1
  where payment.id = v_payment.id;

  for v_fulfilment in
    update dastak_v1.fulfilments fulfilment
    set status = 'PREPARING',
        prep_started_at = v_now,
        estimated_ready_at = v_now + pg_catalog.make_interval(
          mins => fulfilment.promised_prep_minutes
        ),
        version = fulfilment.version + 1
    where fulfilment.order_id = v_order.id
      and fulfilment.status = 'RESERVED_PREPAYMENT'
    returning fulfilment.*
  loop
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_fulfilment.id::text || ':PREPARATION_STARTED:' || v_fulfilment.version::text,
      'FULFILMENT', v_fulfilment.id, v_fulfilment.version,
      'PREPARATION_STARTED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'fulfilmentId', v_fulfilment.id,
        'branchId', v_fulfilment.branch_id,
        'promisedPrepMinutes', v_fulfilment.promised_prep_minutes,
        'prepStartedAt', v_fulfilment.prep_started_at,
        'estimatedReadyAt', v_fulfilment.estimated_ready_at,
        'paymentCollection', 'RIDER_AT_DELIVERY'
      )
    );
  end loop;

  update dastak_v1.order_lines line
  set status = 'FULFILLING', version = line.version + 1
  where line.order_id = v_order.id and line.status = 'RESERVED';

  for v_settlement_id in
    select dastak_v1_api.seed_merchant_settlement_entry(
      v_order.id, fulfilment.id, fulfilment_line.order_line_id, 'ORIGINAL'
    )
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.fulfilment_lines fulfilment_line
      on fulfilment_line.fulfilment_id = fulfilment.id
    where fulfilment.order_id = v_order.id
    order by fulfilment.id, fulfilment_line.order_line_id
  loop
    if exists (
      select 1 from dastak_v1.settlement_entries entry
      where entry.id = v_settlement_id
        and (
          entry.calculation_status <> 'CALCULATED'
          or entry.calculation_snapshot ->> 'commissionBps' <> '0'
        )
    ) then
      raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
        detail = 'Merchant commission must be configured at zero for launch.';
    end if;
  end loop;

  update dastak_v1.orders customer_order
  set status = 'PREPARING', version = customer_order.version + 1
  where customer_order.id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, actor_id, reason, metadata
  ) values (
    v_order.id, 'AWAITING_PAYMENT', 'PREPARING', v_order.version,
    v_command, p_actor_id,
    'Customer confirmed payment by UPI or cash to the assigned rider at delivery.',
    pg_catalog.jsonb_build_object(
      'commitmentId', v_commitment.id,
      'retiredPaymentId', v_payment.id,
      'optionCode', v_commitment.option_code,
      'amountPaise', v_commitment.amount_paise,
      'currencyCode', v_commitment.currency_code,
      'requiredFulfilmentCount', v_required_count,
      'prepStartedAt', v_now,
      'providerInvoked', false
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_order.id::text || ':LAUNCH_PAYMENT_COMMITTED:' || v_order.version::text,
    'ORDER', v_order.id, v_order.version,
    'LAUNCH_PAYMENT_COMMITTED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'commitmentId', v_commitment.id,
      'status', 'PREPARING',
      'amountPaise', v_commitment.amount_paise,
      'currencyCode', v_commitment.currency_code,
      'committedAt', v_commitment.committed_at,
      'collectionAtDelivery', true
    )
  ), (
    v_order.id::text || ':ORDER_PREPARATION_STARTED:' || v_order.version::text,
    'ORDER', v_order.id, v_order.version,
    'PREPARATION_STARTED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'requiredFulfilmentCount', v_required_count,
      'prepStartedAt', v_now,
      'status', 'PREPARING',
      'paymentCollection', 'RIDER_AT_DELIVERY'
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'LAUNCH_PAYMENT_COMMITTED', 'order', v_order.id,
    pg_catalog.jsonb_build_object(
      'commitmentId', v_commitment.id,
      'retiredPaymentId', v_payment.id,
      'amountPaise', v_commitment.amount_paise,
      'currencyCode', v_commitment.currency_code,
      'version', v_order.version,
      'providerInvoked', false
    )
  );

  v_response := dastak_v1_api.order_json(v_order.id, p_actor_id);
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_order.id
  );
  return v_response;
end;
$$;

create function dastak_v1_api.record_launch_payment_collection(
  p_actor_id uuid,
  p_mission_id uuid,
  p_outcome text,
  p_method text,
  p_collection_reference text,
  p_failure_reason text,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'recordLaunchPaymentCollection';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_commitment dastak_v1.launch_payment_commitments%rowtype;
  v_collected dastak_v1.launch_payment_collection_attempts%rowtype;
  v_attempt dastak_v1.launch_payment_collection_attempts%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_package_count integer;
  v_price dastak_v1.order_price_snapshots%rowtype;
  v_fee bigint;
  v_transaction_id uuid;
begin
  if p_actor_id is null or p_mission_id is null
    or p_outcome not in ('COLLECTED', 'FAILED')
    or p_method not in ('CASH', 'UPI')
    or p_expected_mission_version is null or p_expected_mission_version < 1
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or (
      p_collection_reference is not null and (
        pg_catalog.char_length(pg_catalog.btrim(p_collection_reference)) not between 1 and 200
        or pg_catalog.btrim(p_collection_reference) !~ '^[A-Za-z0-9][A-Za-z0-9._:/ -]*$'
      )
    )
    or (
      p_failure_reason is not null
      and pg_catalog.char_length(pg_catalog.btrim(p_failure_reason)) not between 3 and 500
    )
    or (p_outcome = 'COLLECTED' and p_failure_reason is not null) then
    raise exception using errcode = '22023', message = 'invalid launch collection attempt';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'missionId', p_mission_id,
    'outcome', p_outcome,
    'method', p_method,
    'collectionReference', nullif(pg_catalog.btrim(p_collection_reference), ''),
    'failureReason', nullif(pg_catalog.btrim(p_failure_reason), ''),
    'expectedMissionVersion', p_expected_mission_version
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
    if v_existing.request_hash = v_hash then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
      return next;
      return;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-rider:' || p_actor_id::text, 0)
  );
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found or v_mission.assigned_rider_id is distinct from p_actor_id then
    raise exception using errcode = 'P0002', message = 'mission not found';
  end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_mission.order_id
  for update;
  select commitment.* into v_commitment
  from dastak_v1.launch_payment_commitments commitment
  where commitment.order_id = v_order.id
  for update;
  if v_commitment.id is null then
    raise exception using errcode = 'P0002', message = 'launch payment commitment not found';
  end if;
  select attempt.* into v_collected
  from dastak_v1.launch_payment_collection_attempts attempt
  where attempt.commitment_id = v_commitment.id
    and attempt.outcome = 'COLLECTED';

  if v_collected.id is not null then
    if p_outcome <> 'COLLECTED' or p_method is distinct from v_collected.method then
      raise exception using errcode = '55000', message = 'payment was already collected';
    end if;
    response_body := dastak_v1_api.delivery_partner_snapshot(p_actor_id);
    response_status := 200;
    insert into dastak_v1.idempotency_records (
      actor_id, command_name, idempotency_key, request_hash,
      response_body, response_status, resource_id
    ) values (
      p_actor_id, v_command, p_idempotency_key, v_hash,
      response_body, response_status, v_mission.id
    );
    return next;
    return;
  end if;

  if v_mission.version is distinct from p_expected_mission_version then
    raise exception using errcode = '40001', message = 'stale mission version';
  end if;
  select pg_catalog.count(*) into v_package_count
  from dastak_v1.packages package
  where package.order_id = v_order.id;
  if v_mission.status <> 'ARRIVED'
    or v_order.status <> 'OUT_FOR_DELIVERY'
    or v_package_count < 1
    or exists (
      select 1 from dastak_v1.packages package
      where package.order_id = v_order.id
        and (
          package.status <> 'IN_TRANSIT'
          or package.current_custody_owner_type <> 'RIDER'
          or package.current_custody_owner_id is distinct from p_actor_id
        )
    )
    or exists (
      select 1 from dastak_v1.fulfilments fulfilment
      where fulfilment.order_id = v_order.id
        and fulfilment.status <> 'PICKED_UP'
    ) then
    raise exception using errcode = '55000',
      message = 'complete rider custody at the final-delivery stage is required';
  end if;

  insert into dastak_v1.launch_payment_collection_attempts (
    commitment_id, order_id, mission_id, rider_id,
    outcome, method, collection_reference, failure_reason,
    attempted_at, collected_at
  ) values (
    v_commitment.id, v_order.id, v_mission.id, p_actor_id,
    p_outcome, p_method,
    nullif(pg_catalog.btrim(p_collection_reference), ''),
    case when p_outcome = 'FAILED'
      then nullif(pg_catalog.btrim(p_failure_reason), '') end,
    v_now, case when p_outcome = 'COLLECTED' then v_now end
  ) returning * into v_attempt;

  if p_outcome = 'FAILED' then
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_attempt.id::text || ':LAUNCH_PAYMENT_COLLECTION_FAILED',
      'LAUNCH_PAYMENT_COLLECTION_ATTEMPT', v_attempt.id, 1,
      'LAUNCH_PAYMENT_COLLECTION_FAILED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'missionId', v_mission.id,
        'attemptId', v_attempt.id,
        'method', v_attempt.method,
        'retryable', true,
        'attemptedAt', v_attempt.attempted_at
      )
    );
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_actor_id, 'LAUNCH_PAYMENT_COLLECTION_FAILED',
      'launch_payment_collection_attempt', v_attempt.id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'missionId', v_mission.id,
        'method', v_attempt.method,
        'reason', v_attempt.failure_reason,
        'retryable', true
      )
    );
    response_body := dastak_v1_api.delivery_partner_snapshot(p_actor_id);
    response_status := 200;
  else
    if v_order.paid_at is not null or exists (
      select 1 from dastak_v1.payments payment
      where payment.order_id = v_order.id and payment.status = 'SUCCEEDED'
    ) then
      raise exception using errcode = '55000', message = 'order already has paid authority';
    end if;
    select snapshot.* into v_price
    from dastak_v1.order_price_snapshots snapshot
    where snapshot.order_id = v_order.id
      and snapshot.snapshot_kind = 'FULLY_SECURED';
    if v_price.id is null
      or v_price.total_paise is distinct from v_commitment.amount_paise
      or v_price.currency_code is distinct from v_commitment.currency_code then
      raise exception using errcode = '55000', message = 'authoritative collection amount changed';
    end if;

    insert into dastak_v1.order_price_snapshots (
      order_id, snapshot_kind, subtotal_paise, delivery_fee_paise,
      platform_fee_paise, discount_paise, tax_paise, total_paise,
      currency_code, calculation_details
    ) values (
      v_order.id, 'PAID', v_price.subtotal_paise, v_price.delivery_fee_paise,
      v_price.platform_fee_paise, v_price.discount_paise, v_price.tax_paise,
      v_price.total_paise, v_price.currency_code,
      v_price.calculation_details || pg_catalog.jsonb_build_object(
        'paymentAuthority', 'RIDER_DOORSTEP_COLLECTION',
        'launchPaymentCommitmentId', v_commitment.id,
        'collectionAttemptId', v_attempt.id,
        'collectionMethod', v_attempt.method,
        'providerInvoked', false
      )
    );
    update dastak_v1.orders customer_order
    set paid_at = v_attempt.collected_at,
        version = customer_order.version + 1
    where customer_order.id = v_order.id
      and customer_order.paid_at is null
    returning * into v_order;

    v_fee := dastak_v1_api.calculate_platform_fee(v_commitment.amount_paise);
    v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
      v_order.id::text || ':PLATFORM_FEE',
      'PLATFORM_FEE_RECOGNITION', v_fee,
      'PAYMENT_CLEARING_ALLOCATION', null, null,
      'PLATFORM_FEE_REVENUE', null, null,
      v_order.id, null, v_mission.id, null, null, null, null, p_actor_id,
      'Locked 2% platform-fee revenue recognized at successful doorstep collection.',
      pg_catalog.jsonb_build_object(
        'paidTotalPaise', v_commitment.amount_paise,
        'platformFeeBps', 200,
        'rounding', 'HALF_UP_TO_PAISE',
        'platformFeePaise', v_fee,
        'paymentSnapshotKind', 'PAID',
        'launchPaymentCommitmentId', v_commitment.id,
        'collectionAttemptId', v_attempt.id,
        'collectionMethod', v_attempt.method,
        'providerInvoked', false,
        'checkoutPriceUnchanged', true
      )
    );

    insert into dastak_v1.order_state_journal (
      order_id, from_status, to_status, order_version,
      command_name, actor_id, reason, metadata
    ) values (
      v_order.id, 'OUT_FOR_DELIVERY', 'OUT_FOR_DELIVERY', v_order.version,
      v_command, p_actor_id,
      'Assigned rider recorded successful doorstep payment collection.',
      pg_catalog.jsonb_build_object(
        'commitmentId', v_commitment.id,
        'collectionAttemptId', v_attempt.id,
        'missionId', v_mission.id,
        'method', v_attempt.method,
        'amountPaise', v_commitment.amount_paise,
        'currencyCode', v_commitment.currency_code,
        'platformFeeTransactionId', v_transaction_id
      )
    );
    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_attempt.id::text || ':LAUNCH_PAYMENT_COLLECTED',
      'ORDER', v_order.id, v_order.version,
      'LAUNCH_PAYMENT_COLLECTED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'missionId', v_mission.id,
        'collectionAttemptId', v_attempt.id,
        'method', v_attempt.method,
        'amountPaise', v_commitment.amount_paise,
        'currencyCode', v_commitment.currency_code,
        'collectedAt', v_attempt.collected_at,
        'platformFeePaise', v_fee
      )
    ), (
      v_transaction_id::text || ':PLATFORM_FEE_RECORDED',
      'FINANCIAL_TRANSACTION', v_transaction_id, 1,
      'PLATFORM_FEE_RECORDED', p_actor_id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'platformFeePaise', v_fee,
        'currency', v_commitment.currency_code,
        'recognizedAt', v_attempt.collected_at
      )
    ) on conflict (event_key) do nothing;
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_actor_id, 'LAUNCH_PAYMENT_COLLECTED',
      'launch_payment_collection_attempt', v_attempt.id,
      pg_catalog.jsonb_build_object(
        'orderId', v_order.id,
        'missionId', v_mission.id,
        'commitmentId', v_commitment.id,
        'method', v_attempt.method,
        'amountPaise', v_commitment.amount_paise,
        'currencyCode', v_commitment.currency_code,
        'platformFeePaise', v_fee,
        'platformFeeTransactionId', v_transaction_id,
        'providerInvoked', false
      )
    );
    response_body := dastak_v1_api.delivery_partner_snapshot(p_actor_id);
    response_status := 200;
  end if;

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    response_body, response_status, v_mission.id
  );
  return next;
end;
$$;

alter function dastak_v1_api.complete_final_delivery_locked(
  uuid, uuid, uuid, dastak_v1.verification_handoff_status, timestamptz
) rename to complete_final_delivery_locked_pre_launch_payment;
create function dastak_v1_api.complete_final_delivery_locked(
  p_actor_id uuid,
  p_mission_id uuid,
  p_handoff_id uuid,
  p_verification_status dastak_v1.verification_handoff_status,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
begin
  select mission.order_id into v_order_id
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id;
  if v_order_id is null then
    raise exception using errcode = 'P0002', message = 'mission not found';
  end if;
  if not exists (
    select 1
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.order_id = v_order_id
      and attempt.mission_id = p_mission_id
      and attempt.outcome = 'COLLECTED'
  ) and not exists (
    select 1 from dastak_v1.payments payment
    where payment.order_id = v_order_id and payment.status = 'SUCCEEDED'
  ) then
    raise exception using errcode = '55000',
      message = 'LAUNCH_PAYMENT_COLLECTION_REQUIRED';
  end if;
  return dastak_v1_api.complete_final_delivery_locked_pre_launch_payment(
    p_actor_id, p_mission_id, p_handoff_id, p_verification_status, p_now
  );
end;
$$;

create function public.dastak_v1_commit_launch_payment(
  p_order_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.commit_launch_payment(
    auth.uid(), p_order_id, p_expected_version, p_idempotency_key
  );
$$;

create function public.dastak_v1_record_launch_payment_collection(
  p_account_id uuid,
  p_mission_id uuid,
  p_outcome text,
  p_method text,
  p_collection_reference text,
  p_failure_reason text,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select * from dastak_v1_api.record_launch_payment_collection(
    p_account_id, p_mission_id, p_outcome, p_method,
    p_collection_reference, p_failure_reason,
    p_expected_mission_version, p_idempotency_key
  );
$$;

update dastak_v1.notification_routes
set title = 'Order confirmed',
    body = case audience
      when 'MERCHANT' then
        'Start preparing this order now. The Delivery Partner will collect payment at the doorstep.'
      else 'Your order is confirmed and is being prepared.'
    end,
    version = version + 1
where event_type in ('PAYMENT_CONFIRMED', 'PREPARATION_STARTED')
  and (title ilike '%payment%' or body ilike '%payment%');

insert into dastak_v1.notification_routes (
  event_type, audience, notification_type, title, body
) values (
  'LAUNCH_PAYMENT_COLLECTED', 'CUSTOMER', 'customer.payment_collected_at_delivery',
  'Payment collected', 'Your payment was collected at delivery. You can now complete the handoff.'
) on conflict (event_type, audience, notification_type) do update
set title = excluded.title,
    body = excluded.body,
    enabled = true,
    version = dastak_v1.notification_routes.version + 1;

revoke all on function dastak_v1_api.launch_payment_customer_json(uuid),
  dastak_v1_api.launch_collection_mission_json(uuid,uuid),
  dastak_v1_api.launch_payment_admin_json(uuid),
  dastak_v1_api.order_json_pre_launch_payment(uuid,uuid),
  dastak_v1_api.order_json(uuid,uuid),
  dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(uuid),
  dastak_v1_api.delivery_partner_snapshot(uuid),
  dastak_v1_api.admin_execution_trace_pre_launch_payment(uuid,uuid),
  dastak_v1_api.admin_execution_trace(uuid,uuid),
  dastak_v1_api.commit_launch_payment(uuid,uuid,bigint,text),
  dastak_v1_api.record_launch_payment_collection(
    uuid,uuid,text,text,text,text,bigint,text
  ),
  dastak_v1_api.complete_final_delivery_locked_pre_launch_payment(
    uuid,uuid,uuid,dastak_v1.verification_handoff_status,timestamptz
  ),
  dastak_v1_api.complete_final_delivery_locked(
    uuid,uuid,uuid,dastak_v1.verification_handoff_status,timestamptz
  ) from public, anon, authenticated;

revoke all on function public.dastak_v1_commit_launch_payment(uuid,bigint,text),
  public.dastak_v1_record_launch_payment_collection(
    uuid,uuid,text,text,text,text,bigint,text
  ) from public, anon, authenticated;

grant execute on function dastak_v1_api.order_json(uuid,uuid),
  dastak_v1_api.delivery_partner_snapshot(uuid),
  dastak_v1_api.admin_execution_trace(uuid,uuid),
  dastak_v1_api.commit_launch_payment(uuid,uuid,bigint,text),
  dastak_v1_api.complete_final_delivery_locked(
    uuid,uuid,uuid,dastak_v1.verification_handoff_status,timestamptz
  ) to authenticated;
grant execute on function dastak_v1_api.record_launch_payment_collection(
  uuid,uuid,text,text,text,text,bigint,text
) to service_role;
grant execute on function public.dastak_v1_commit_launch_payment(uuid,bigint,text)
  to authenticated;
grant execute on function public.dastak_v1_record_launch_payment_collection(
  uuid,uuid,text,text,text,text,bigint,text
) to service_role;

comment on table dastak_v1.launch_payment_commitments is
  'Immutable customer commitment to the one launch option, tied to the authoritative secured parent-order total and retired provider reservation.';
comment on table dastak_v1.launch_payment_collection_attempts is
  'Append-only assigned-rider doorstep collection attempts. One commitment can have many failures and exactly one success.';
comment on function public.dastak_v1_commit_launch_payment(uuid,bigint,text) is
  'Commits the authenticated customer to Pay via UPI/Cash on Delivery and atomically starts preparation without invoking a provider.';
comment on function public.dastak_v1_record_launch_payment_collection(
  uuid,uuid,text,text,text,text,bigint,text
) is
  'Service-bound authenticated rider command for append-only CASH/UPI collection outcomes; amount, order and rider authority are server-owned.';
