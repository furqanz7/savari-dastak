-- Newer locked financial authority: 2% Dastak platform-fee revenue and
-- append-only Merchant/Delivery Partner Royalty accounting.

create type dastak_v1.royalty_withdrawal_status as enum (
  'REQUESTED', 'PROCESSING', 'PAID', 'FAILED_RETRYABLE'
);
create type dastak_v1.royalty_withdrawal_attempt_status as enum (
  'PROCESSING', 'PAID', 'FAILED'
);
create type dastak_v1.royalty_payout_destination_status as enum (
  'ACTIVE', 'INACTIVE'
);
create type dastak_v1.financial_direction as enum ('DEBIT', 'CREDIT');

create table dastak_v1.royalty_payout_destinations (
  id uuid primary key default gen_random_uuid(),
  subject_type dastak_v1.settlement_subject_type not null,
  subject_id uuid not null,
  destination_type text not null check (
    destination_type in ('BANK_ACCOUNT', 'UPI', 'PROVIDER_DESTINATION')
  ),
  provider text not null check (
    provider ~ '^[A-Z][A-Z0-9_]{1,39}$'
  ),
  provider_destination_reference text not null check (
    pg_catalog.char_length(provider_destination_reference) between 1 and 240
  ),
  display_label text not null check (
    pg_catalog.char_length(pg_catalog.btrim(display_label)) between 1 and 120
  ),
  details_snapshot jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(details_snapshot) = 'object'
  ),
  status dastak_v1.royalty_payout_destination_status not null default 'ACTIVE',
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  deactivated_by uuid references public.accounts(id),
  deactivated_at timestamptz,
  version bigint not null default 1 check (version > 0),
  check (
    (status = 'ACTIVE' and deactivated_by is null and deactivated_at is null)
    or (status = 'INACTIVE' and deactivated_by is not null and deactivated_at is not null)
  )
);
create unique index royalty_payout_destinations_active_uidx
  on dastak_v1.royalty_payout_destinations (subject_type, subject_id)
  where status = 'ACTIVE';
create index royalty_payout_destinations_subject_idx
  on dastak_v1.royalty_payout_destinations (subject_type, subject_id, created_at desc);
create index royalty_payout_destinations_created_by_idx
  on dastak_v1.royalty_payout_destinations (created_by, created_at desc);
create index royalty_payout_destinations_deactivated_by_idx
  on dastak_v1.royalty_payout_destinations (deactivated_by, deactivated_at desc);

create table dastak_v1.royalty_withdrawals (
  id uuid primary key default gen_random_uuid(),
  subject_type dastak_v1.settlement_subject_type not null,
  subject_id uuid not null,
  payout_destination_id uuid not null
    references dastak_v1.royalty_payout_destinations(id),
  destination_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(destination_snapshot) = 'object'
  ),
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  status dastak_v1.royalty_withdrawal_status not null default 'REQUESTED',
  idempotency_key text not null check (
    pg_catalog.char_length(idempotency_key) between 1 and 200
  ),
  requested_by uuid not null references public.accounts(id),
  requested_at timestamptz not null default pg_catalog.now(),
  processing_at timestamptz,
  paid_at timestamptz,
  failed_at timestamptz,
  provider_payout_reference text,
  latest_failure_code text,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (subject_type, subject_id, idempotency_key),
  check (
    (status = 'REQUESTED' and processing_at is null and paid_at is null
      and failed_at is null and provider_payout_reference is null)
    or (status = 'PROCESSING' and processing_at is not null and paid_at is null
      and failed_at is null and provider_payout_reference is null)
    or (status = 'PAID' and processing_at is not null and paid_at is not null
      and failed_at is null and provider_payout_reference is not null)
    or (status = 'FAILED_RETRYABLE' and processing_at is not null
      and paid_at is null and failed_at is not null
      and provider_payout_reference is null and latest_failure_code is not null)
  )
);
create index royalty_withdrawals_subject_idx
  on dastak_v1.royalty_withdrawals (subject_type, subject_id, requested_at desc, id desc);
create index royalty_withdrawals_status_idx
  on dastak_v1.royalty_withdrawals (status, requested_at, id);
create index royalty_withdrawals_destination_idx
  on dastak_v1.royalty_withdrawals (payout_destination_id, requested_at desc);
create index royalty_withdrawals_requested_by_idx
  on dastak_v1.royalty_withdrawals (requested_by, requested_at desc);

create table dastak_v1.royalty_withdrawal_attempts (
  id uuid primary key default gen_random_uuid(),
  withdrawal_id uuid not null references dastak_v1.royalty_withdrawals(id),
  attempt_number integer not null check (attempt_number > 0),
  provider text not null check (provider ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  provider_request_key text not null unique check (
    pg_catalog.char_length(provider_request_key) between 1 and 200
  ),
  status dastak_v1.royalty_withdrawal_attempt_status not null default 'PROCESSING',
  provider_payout_reference text,
  failure_code text,
  started_by uuid not null references public.accounts(id),
  started_at timestamptz not null default pg_catalog.now(),
  completed_at timestamptz,
  unique (withdrawal_id, attempt_number),
  check (
    (status = 'PROCESSING' and provider_payout_reference is null
      and failure_code is null and completed_at is null)
    or (status = 'PAID' and provider_payout_reference is not null
      and failure_code is null and completed_at is not null)
    or (status = 'FAILED' and provider_payout_reference is null
      and failure_code is not null and completed_at is not null)
  )
);
create index royalty_withdrawal_attempts_withdrawal_idx
  on dastak_v1.royalty_withdrawal_attempts (withdrawal_id, attempt_number desc);
create index royalty_withdrawal_attempts_started_by_idx
  on dastak_v1.royalty_withdrawal_attempts (started_by, started_at desc);

create table dastak_v1.royalty_withdrawal_provider_events (
  provider text not null check (provider ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  provider_event_id text not null check (
    pg_catalog.char_length(provider_event_id) between 1 and 200
  ),
  withdrawal_id uuid not null references dastak_v1.royalty_withdrawals(id),
  attempt_id uuid not null references dastak_v1.royalty_withdrawal_attempts(id),
  outcome dastak_v1.royalty_withdrawal_attempt_status not null check (
    outcome in ('PAID', 'FAILED')
  ),
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  response_body jsonb not null check (
    pg_catalog.jsonb_typeof(response_body) = 'object'
  ),
  occurred_at timestamptz not null,
  processed_at timestamptz not null default pg_catalog.now(),
  primary key (provider, provider_event_id)
);
create index royalty_withdrawal_events_withdrawal_idx
  on dastak_v1.royalty_withdrawal_provider_events (withdrawal_id, processed_at desc);
create index royalty_withdrawal_events_attempt_idx
  on dastak_v1.royalty_withdrawal_provider_events (attempt_id, processed_at desc);

create table dastak_v1.financial_journal_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_key text not null unique check (
    pg_catalog.char_length(transaction_key) between 1 and 300
  ),
  transaction_type text not null check (transaction_type in (
    'PLATFORM_FEE_RECOGNITION', 'PLATFORM_FEE_REFUND_ADJUSTMENT',
    'MERCHANT_ROYALTY_EARNING', 'RIDER_ROYALTY_EARNING',
    'ROYALTY_FAULT_ADJUSTMENT', 'ROYALTY_CREDIT_ADJUSTMENT',
    'WITHDRAWAL_RESERVATION', 'WITHDRAWAL_RELEASE', 'WITHDRAWAL_PAID'
  )),
  amount_paise bigint not null check (amount_paise >= 0),
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  order_id uuid references dastak_v1.orders(id),
  fulfilment_id uuid references dastak_v1.fulfilments(id),
  delivery_mission_id uuid references dastak_v1.delivery_missions(id),
  payment_id uuid references dastak_v1.payments(id),
  refund_id uuid references dastak_v1.refunds(id),
  settlement_entry_id uuid references dastak_v1.settlement_entries(id),
  withdrawal_id uuid references dastak_v1.royalty_withdrawals(id),
  actor_id uuid references public.accounts(id),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500
  ),
  metadata jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(metadata) = 'object'
  ),
  created_at timestamptz not null default pg_catalog.now()
);
create index financial_journal_transactions_order_idx
  on dastak_v1.financial_journal_transactions (order_id, created_at, id);
create index financial_journal_transactions_fulfilment_idx
  on dastak_v1.financial_journal_transactions (fulfilment_id, created_at, id);
create index financial_journal_transactions_mission_idx
  on dastak_v1.financial_journal_transactions (delivery_mission_id, created_at, id);
create index financial_journal_transactions_payment_idx
  on dastak_v1.financial_journal_transactions (payment_id, created_at, id);
create index financial_journal_transactions_refund_idx
  on dastak_v1.financial_journal_transactions (refund_id, created_at, id);
create index financial_journal_transactions_settlement_idx
  on dastak_v1.financial_journal_transactions (settlement_entry_id, created_at, id);
create index financial_journal_transactions_withdrawal_idx
  on dastak_v1.financial_journal_transactions (withdrawal_id, created_at, id);
create index financial_journal_transactions_actor_idx
  on dastak_v1.financial_journal_transactions (actor_id, created_at desc);

create table dastak_v1.financial_journal_lines (
  id bigint generated always as identity primary key,
  transaction_id uuid not null
    references dastak_v1.financial_journal_transactions(id),
  line_number smallint not null check (line_number in (1, 2)),
  account_code text not null check (account_code in (
    'PAYMENT_CLEARING_ALLOCATION', 'PLATFORM_FEE_REVENUE',
    'PLATFORM_FEE_REFUND_CLEARING',
    'MERCHANT_FULFILMENT_COST', 'RIDER_DELIVERY_COST',
    'MERCHANT_ROYALTY_PAYABLE', 'RIDER_ROYALTY_PAYABLE',
    'FAULT_RECOVERY', 'PAYOUT_CLEARING', 'PAYOUT_CASH'
  )),
  subject_type dastak_v1.settlement_subject_type,
  subject_id uuid,
  direction dastak_v1.financial_direction not null,
  amount_paise bigint not null check (amount_paise >= 0),
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (transaction_id, line_number),
  check (
    (account_code = 'MERCHANT_ROYALTY_PAYABLE'
      and subject_type = 'MERCHANT_ORGANIZATION' and subject_id is not null)
    or (account_code = 'RIDER_ROYALTY_PAYABLE'
      and subject_type = 'RIDER' and subject_id is not null)
    or (account_code not in ('MERCHANT_ROYALTY_PAYABLE', 'RIDER_ROYALTY_PAYABLE')
      and subject_type is null and subject_id is null)
  )
);
create index financial_journal_lines_subject_idx
  on dastak_v1.financial_journal_lines (
    subject_type, subject_id, account_code, transaction_id
  );

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values
  ('merchant.royalty.withdraw', 'Request withdrawal of positive Merchant Royalty.', 'HIGHLY_SENSITIVE'),
  ('platform.royalty.adjust', 'Create named audited Royalty adjustments.', 'HIGHLY_SENSITIVE'),
  ('platform.withdrawals.manage', 'Process Royalty withdrawals through an authorized payout rail.', 'HIGHLY_SENSITIVE');

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values
  ('10000000-0000-4000-8000-000000000001', 'merchant.royalty.withdraw'),
  ('10000000-0000-4000-8000-000000000009', 'platform.royalty.adjust'),
  ('10000000-0000-4000-8000-000000000009', 'platform.withdrawals.manage');

alter table dastak_v1.royalty_payout_destinations enable row level security;
alter table dastak_v1.royalty_withdrawals enable row level security;
alter table dastak_v1.royalty_withdrawal_attempts enable row level security;
alter table dastak_v1.royalty_withdrawal_provider_events enable row level security;
alter table dastak_v1.financial_journal_transactions enable row level security;
alter table dastak_v1.financial_journal_lines enable row level security;

revoke all on table
  dastak_v1.royalty_payout_destinations,
  dastak_v1.royalty_withdrawals,
  dastak_v1.royalty_withdrawal_attempts,
  dastak_v1.royalty_withdrawal_provider_events,
  dastak_v1.financial_journal_transactions,
  dastak_v1.financial_journal_lines
from public, anon, authenticated;
grant select on table
  dastak_v1.royalty_payout_destinations,
  dastak_v1.royalty_withdrawals,
  dastak_v1.royalty_withdrawal_attempts,
  dastak_v1.royalty_withdrawal_provider_events,
  dastak_v1.financial_journal_transactions,
  dastak_v1.financial_journal_lines
to service_role;

create function dastak_v1.guard_royalty_payout_destination()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.subject_type is distinct from old.subject_type
    or new.subject_id is distinct from old.subject_id
    or new.destination_type is distinct from old.destination_type
    or new.provider is distinct from old.provider
    or new.provider_destination_reference is distinct from old.provider_destination_reference
    or new.display_label is distinct from old.display_label
    or new.details_snapshot is distinct from old.details_snapshot
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'payout destination snapshot cannot change';
  end if;
  if old.status <> 'ACTIVE' or new.status <> 'INACTIVE'
    or new.version <> old.version + 1 then
    raise exception 'invalid payout destination transition';
  end if;
  return new;
end;
$$;

create function dastak_v1.guard_royalty_withdrawal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.subject_type is distinct from old.subject_type
    or new.subject_id is distinct from old.subject_id
    or new.payout_destination_id is distinct from old.payout_destination_id
    or new.destination_snapshot is distinct from old.destination_snapshot
    or new.amount_paise is distinct from old.amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.idempotency_key is distinct from old.idempotency_key
    or new.requested_by is distinct from old.requested_by
    or new.requested_at is distinct from old.requested_at then
    raise exception 'withdrawal financial identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'withdrawal version must increment exactly once';
  end if;
  if new.status is not distinct from old.status or not (
    (old.status = 'REQUESTED' and new.status = 'PROCESSING')
    or (old.status = 'PROCESSING' and new.status in ('PAID', 'FAILED_RETRYABLE'))
    or (old.status = 'FAILED_RETRYABLE' and new.status = 'PROCESSING')
  ) then
    raise exception 'invalid withdrawal transition: % -> %', old.status, new.status;
  end if;
  if old.paid_at is not null and new.paid_at is distinct from old.paid_at then
    raise exception 'paid withdrawal timestamp cannot change';
  end if;
  if old.provider_payout_reference is not null
    and new.provider_payout_reference is distinct from old.provider_payout_reference then
    raise exception 'withdrawal provider reference cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.reject_financial_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'append-only financial history cannot be changed';
end;
$$;

create function dastak_v1.assert_financial_transaction_balanced()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Both constraint triggers are INSERT-only, but their row types differ. Read
  -- through jsonb so PostgreSQL never resolves a field absent from one row type.
  v_transaction_id uuid := coalesce(
    (pg_catalog.to_jsonb(new) ->> 'transaction_id')::uuid,
    (pg_catalog.to_jsonb(new) ->> 'id')::uuid
  );
  v_amount bigint;
  v_line_count bigint;
  v_debits bigint;
  v_credits bigint;
begin
  select transaction.amount_paise into v_amount
  from dastak_v1.financial_journal_transactions transaction
  where transaction.id = v_transaction_id;
  if not found then return null; end if;
  select count(*),
    coalesce(sum(line.amount_paise) filter (where line.direction = 'DEBIT'), 0),
    coalesce(sum(line.amount_paise) filter (where line.direction = 'CREDIT'), 0)
  into v_line_count, v_debits, v_credits
  from dastak_v1.financial_journal_lines line
  where line.transaction_id = v_transaction_id;
  if v_line_count <> 2 or v_debits <> v_amount or v_credits <> v_amount then
    raise exception 'UNBALANCED_FINANCIAL_TRANSACTION';
  end if;
  return null;
end;
$$;

create trigger royalty_payout_destinations_guard
before update on dastak_v1.royalty_payout_destinations
for each row execute function dastak_v1.guard_royalty_payout_destination();
create trigger royalty_payout_destinations_no_delete
before delete on dastak_v1.royalty_payout_destinations
for each row execute function dastak_v1.reject_financial_mutation();
create trigger royalty_withdrawals_guard
before update on dastak_v1.royalty_withdrawals
for each row execute function dastak_v1.guard_royalty_withdrawal();
create trigger royalty_withdrawals_no_delete
before delete on dastak_v1.royalty_withdrawals
for each row execute function dastak_v1.reject_financial_mutation();
create trigger royalty_withdrawal_attempts_immutable
before update or delete on dastak_v1.royalty_withdrawal_attempts
for each row execute function dastak_v1.reject_financial_mutation();
create trigger royalty_withdrawal_provider_events_immutable
before update or delete on dastak_v1.royalty_withdrawal_provider_events
for each row execute function dastak_v1.reject_financial_mutation();
create trigger financial_journal_transactions_immutable
before update or delete on dastak_v1.financial_journal_transactions
for each row execute function dastak_v1.reject_financial_mutation();
create trigger financial_journal_lines_immutable
before update or delete on dastak_v1.financial_journal_lines
for each row execute function dastak_v1.reject_financial_mutation();
create constraint trigger financial_transactions_balanced
after insert on dastak_v1.financial_journal_transactions
deferrable initially deferred
for each row execute function dastak_v1.assert_financial_transaction_balanced();
create constraint trigger financial_lines_balanced
after insert on dastak_v1.financial_journal_lines
deferrable initially deferred
for each row execute function dastak_v1.assert_financial_transaction_balanced();

create function dastak_v1_api.calculate_platform_fee(p_paid_total_paise bigint)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  if p_paid_total_paise is null or p_paid_total_paise <= 0 then
    raise exception using errcode = '22023', message = 'invalid paid total';
  end if;
  -- Locked 200 bps, rounded half-up to the nearest whole paise.
  return pg_catalog.floor(
    (p_paid_total_paise::numeric * 200::numeric + 5000::numeric) / 10000::numeric
  )::bigint;
end;
$$;

create function dastak_v1_api.post_balanced_financial_transaction(
  p_transaction_key text,
  p_transaction_type text,
  p_amount_paise bigint,
  p_debit_account text,
  p_debit_subject_type dastak_v1.settlement_subject_type,
  p_debit_subject_id uuid,
  p_credit_account text,
  p_credit_subject_type dastak_v1.settlement_subject_type,
  p_credit_subject_id uuid,
  p_order_id uuid default null,
  p_fulfilment_id uuid default null,
  p_delivery_mission_id uuid default null,
  p_payment_id uuid default null,
  p_refund_id uuid default null,
  p_settlement_entry_id uuid default null,
  p_withdrawal_id uuid default null,
  p_actor_id uuid default null,
  p_reason text default 'Authoritative financial event.',
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_amount_paise is null or p_amount_paise < 0
    or nullif(pg_catalog.btrim(p_transaction_key), '') is null
    or pg_catalog.jsonb_typeof(p_metadata) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid financial transaction';
  end if;
  insert into dastak_v1.financial_journal_transactions (
    transaction_key, transaction_type, amount_paise,
    order_id, fulfilment_id, delivery_mission_id, payment_id, refund_id,
    settlement_entry_id, withdrawal_id, actor_id, reason, metadata
  ) values (
    p_transaction_key, p_transaction_type, p_amount_paise,
    p_order_id, p_fulfilment_id, p_delivery_mission_id, p_payment_id, p_refund_id,
    p_settlement_entry_id, p_withdrawal_id, p_actor_id,
    pg_catalog.btrim(p_reason), p_metadata
  ) on conflict (transaction_key) do nothing
  returning id into v_id;
  if v_id is null then
    select transaction.id into v_id
    from dastak_v1.financial_journal_transactions transaction
    where transaction.transaction_key = p_transaction_key
      and transaction.transaction_type = p_transaction_type
      and transaction.amount_paise = p_amount_paise
      and transaction.order_id is not distinct from p_order_id
      and transaction.fulfilment_id is not distinct from p_fulfilment_id
      and transaction.delivery_mission_id is not distinct from p_delivery_mission_id
      and transaction.payment_id is not distinct from p_payment_id
      and transaction.refund_id is not distinct from p_refund_id
      and transaction.settlement_entry_id is not distinct from p_settlement_entry_id
      and transaction.withdrawal_id is not distinct from p_withdrawal_id
      and transaction.actor_id is not distinct from p_actor_id
      and transaction.reason = pg_catalog.btrim(p_reason)
      and transaction.metadata = p_metadata
      and exists (
        select 1 from dastak_v1.financial_journal_lines line
        where line.transaction_id = transaction.id
          and line.line_number = 1
          and line.account_code = p_debit_account
          and line.subject_type is not distinct from p_debit_subject_type
          and line.subject_id is not distinct from p_debit_subject_id
          and line.direction = 'DEBIT'
          and line.amount_paise = p_amount_paise
      )
      and exists (
        select 1 from dastak_v1.financial_journal_lines line
        where line.transaction_id = transaction.id
          and line.line_number = 2
          and line.account_code = p_credit_account
          and line.subject_type is not distinct from p_credit_subject_type
          and line.subject_id is not distinct from p_credit_subject_id
          and line.direction = 'CREDIT'
          and line.amount_paise = p_amount_paise
      )
      and 2 = (
        select pg_catalog.count(*)
        from dastak_v1.financial_journal_lines line
        where line.transaction_id = transaction.id
      );
    if v_id is null then
      raise exception 'financial transaction key collision';
    end if;
    return v_id;
  end if;
  insert into dastak_v1.financial_journal_lines (
    transaction_id, line_number, account_code, subject_type,
    subject_id, direction, amount_paise
  ) values
    (v_id, 1, p_debit_account, p_debit_subject_type,
      p_debit_subject_id, 'DEBIT', p_amount_paise),
    (v_id, 2, p_credit_account, p_credit_subject_type,
      p_credit_subject_id, 'CREDIT', p_amount_paise);
  return v_id;
end;
$$;

create function dastak_v1.record_platform_fee_after_payment_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment dastak_v1.payments%rowtype;
  v_paid_snapshot dastak_v1.order_price_snapshots%rowtype;
  v_fee bigint;
  v_transaction_id uuid;
begin
  if new.outcome <> 'SUCCEEDED' then return new; end if;
  select payment.* into strict v_payment
  from dastak_v1.payments payment
  where payment.id = new.payment_id
    and payment.order_id = new.order_id
    and payment.status = 'SUCCEEDED'
    and payment.amount_paise = new.amount_paise;
  select snapshot.* into strict v_paid_snapshot
  from dastak_v1.order_price_snapshots snapshot
  where snapshot.order_id = new.order_id
    and snapshot.snapshot_kind = 'PAID';
  if v_paid_snapshot.total_paise <> v_payment.amount_paise then
    raise exception 'PAID_PRICE_SNAPSHOT_MISMATCH';
  end if;
  v_fee := dastak_v1_api.calculate_platform_fee(v_payment.amount_paise);
  v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
    new.order_id::text || ':PLATFORM_FEE',
    'PLATFORM_FEE_RECOGNITION', v_fee,
    'PAYMENT_CLEARING_ALLOCATION', null, null,
    'PLATFORM_FEE_REVENUE', null, null,
    new.order_id, null, null, v_payment.id, null, null, null, null,
    'Locked 2% platform-fee revenue recognized from the immutable paid total.',
    pg_catalog.jsonb_build_object(
      'paidTotalPaise', v_payment.amount_paise,
      'platformFeeBps', 200,
      'rounding', 'HALF_UP_TO_PAISE',
      'platformFeePaise', v_fee,
      'paymentSnapshotId', v_paid_snapshot.id,
      'provider', new.provider,
      'providerEventId', new.provider_event_id,
      'providerPaymentReference', new.provider_payment_reference,
      'checkoutPriceUnchanged', true
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_transaction_id::text || ':PLATFORM_FEE_RECORDED',
    'FINANCIAL_TRANSACTION', v_transaction_id, 1,
    'PLATFORM_FEE_RECORDED',
    pg_catalog.jsonb_build_object(
      'orderId', new.order_id, 'paymentId', v_payment.id,
      'platformFeePaise', v_fee, 'currency', 'INR'
    )
  ) on conflict (event_key) do nothing;
  return new;
end;
$$;

create trigger payment_provider_events_record_platform_fee
after insert on dastak_v1.payment_provider_events
for each row when (new.outcome = 'SUCCEEDED')
execute function dastak_v1.record_platform_fee_after_payment_event();

create function dastak_v1.record_platform_fee_refund_adjustment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_original_fee bigint;
  v_completed_refunds bigint;
  v_prior_adjustments bigint;
  v_target_adjustment bigint;
  v_amount bigint;
  v_transaction_id uuid;
begin
  if old.status = 'COMPLETED' or new.status <> 'COMPLETED' then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-platform-fee:' || new.order_id::text, 0)
  );
  select transaction.amount_paise into v_original_fee
  from dastak_v1.financial_journal_transactions transaction
  where transaction.transaction_key = new.order_id::text || ':PLATFORM_FEE';
  if v_original_fee is null then
    raise exception 'PLATFORM_FEE_SOURCE_REQUIRED';
  end if;
  select coalesce(sum(refund.amount_paise), 0) into v_completed_refunds
  from dastak_v1.refunds refund
  where refund.order_id = new.order_id and refund.status = 'COMPLETED';
  select coalesce(sum(transaction.amount_paise), 0) into v_prior_adjustments
  from dastak_v1.financial_journal_transactions transaction
  where transaction.order_id = new.order_id
    and transaction.transaction_type = 'PLATFORM_FEE_REFUND_ADJUSTMENT';
  v_target_adjustment := least(
    v_original_fee,
    dastak_v1_api.calculate_platform_fee(v_completed_refunds)
  );
  v_amount := greatest(0, v_target_adjustment - v_prior_adjustments);
  v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
    new.id::text || ':PLATFORM_FEE_REFUND_ADJUSTMENT',
    'PLATFORM_FEE_REFUND_ADJUSTMENT', v_amount,
    'PLATFORM_FEE_REVENUE', null, null,
    'PLATFORM_FEE_REFUND_CLEARING', null, null,
    new.order_id, null, null, new.payment_id, new.id, null, null, null,
    'Completed original-method refund recorded as an append-only platform-fee correction.',
    pg_catalog.jsonb_build_object(
      'refundId', new.id,
      'refundAmountPaise', new.amount_paise,
      'cumulativeCompletedRefundPaise', v_completed_refunds,
      'originalPlatformFeePaise', v_original_fee,
      'cumulativeFeeAdjustmentPaise', v_target_adjustment,
      'thisAdjustmentPaise', v_amount,
      'platformFeeBps', 200,
      'rounding', 'HALF_UP_TO_PAISE'
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_transaction_id::text || ':PLATFORM_FEE_ADJUSTED',
    'FINANCIAL_TRANSACTION', v_transaction_id, 1,
    'PLATFORM_FEE_REFUND_ADJUSTED',
    pg_catalog.jsonb_build_object(
      'orderId', new.order_id, 'refundId', new.id,
      'adjustmentPaise', v_amount, 'currency', 'INR'
    )
  ) on conflict (event_key) do nothing;
  return new;
end;
$$;

create trigger refunds_record_platform_fee_adjustment
after update of status on dastak_v1.refunds
for each row execute function dastak_v1.record_platform_fee_refund_adjustment();

create function dastak_v1.normalize_royalty_adjustment_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.entry_type in ('DEBIT_ADJUSTMENT', 'REFUND_ADJUSTMENT')
    and new.calculation_status = 'CALCULATED' then
    new.amount_paise := -abs(coalesce(new.gross_amount_paise, new.amount_paise));
    new.status := 'ELIGIBLE';
    new.eligible_at := coalesce(new.eligible_at, pg_catalog.clock_timestamp());
  elsif new.entry_type = 'CREDIT_ADJUSTMENT'
    and new.calculation_status = 'CALCULATED' then
    new.amount_paise := abs(coalesce(new.gross_amount_paise, new.amount_paise));
    new.status := 'ELIGIBLE';
    new.eligible_at := coalesce(new.eligible_at, pg_catalog.clock_timestamp());
  end if;
  return new;
end;
$$;

create trigger settlement_entries_00_normalize_royalty_adjustment
before insert on dastak_v1.settlement_entries
for each row execute function dastak_v1.normalize_royalty_adjustment_entry();

create function dastak_v1_api.royalty_earning_milestone_proven(
  p_settlement_entry_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(case entry.subject_type
    when 'MERCHANT_ORGANIZATION' then exists (
      select 1
      from dastak_v1.fulfilments fulfilment
      where fulfilment.id = entry.fulfilment_id
        and fulfilment.order_id = entry.order_id
        and fulfilment.organization_id = entry.subject_id
        and fulfilment.status in ('PICKED_UP', 'COMPLETED')
        and fulfilment.package_count >= 1
        and fulfilment.actual_ready_at is not null
        and fulfilment.ready_at is not null
        and exists (
          select 1
          from dastak_v1.fulfilment_lines fulfilment_line
          where fulfilment_line.fulfilment_id = fulfilment.id
            and fulfilment_line.order_line_id = entry.order_line_id
        )
        and exists (
          select 1
          from dastak_v1.fulfilment_evidence evidence
          where evidence.order_id = entry.order_id
            and evidence.fulfilment_id = fulfilment.id
            and evidence.evidence_type = 'MERCHANT_READY_PHOTO'
        )
        and exists (
          select 1
          from dastak_v1.verification_handoffs handoff
          join dastak_v1.delivery_missions mission
            on mission.id = handoff.mission_id
           and mission.order_id = entry.order_id
           and mission.assigned_rider_id = handoff.consumed_by
          where handoff.order_id = entry.order_id
            and handoff.fulfilment_id = fulfilment.id
            and handoff.handoff_type = 'MERCHANT_TO_RIDER'
            and handoff.status = 'CONSUMED'
            and handoff.consumed_by is not null
            and (
              select pg_catalog.count(*)
              from dastak_v1.packages package
              where package.fulfilment_id = fulfilment.id
            ) = fulfilment.package_count
            and not exists (
              select 1
              from dastak_v1.packages package
              where package.fulfilment_id = fulfilment.id
                and not exists (
                  select 1
                  from dastak_v1.package_custody_events custody
                  where custody.order_id = entry.order_id
                    and custody.mission_id = mission.id
                    and custody.fulfilment_id = fulfilment.id
                    and custody.package_id = package.id
                    and custody.verification_handoff_id = handoff.id
                    and custody.from_owner_type = 'MERCHANT_BRANCH'
                    and custody.from_owner_id = fulfilment.branch_id
                    and custody.to_owner_type = 'RIDER'
                    and custody.to_owner_id = mission.assigned_rider_id
                    and custody.transferred_by = mission.assigned_rider_id
                )
            )
        )
    )
    when 'RIDER' then exists (
      select 1
      from dastak_v1.delivery_missions mission
      join dastak_v1.orders customer_order
        on customer_order.id = mission.order_id
      where mission.id = entry.delivery_mission_id
        and mission.order_id = entry.order_id
        and mission.assigned_rider_id = entry.subject_id
        and mission.status = 'DELIVERED'
        and mission.delivered_at is not null
        and customer_order.status = 'DELIVERED'
        and customer_order.delivered_at is not null
        and exists (
          select 1
          from dastak_v1.verification_handoffs handoff
          where handoff.order_id = entry.order_id
            and handoff.mission_id = mission.id
            and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
            and handoff.status = 'CONSUMED'
            and handoff.consumed_by = mission.assigned_rider_id
            and exists (
              select 1
              from dastak_v1.delivery_evidence evidence
              where evidence.order_id = entry.order_id
                and evidence.mission_id = mission.id
                and evidence.verification_handoff_id = handoff.id
                and evidence.captured_by = mission.assigned_rider_id
            )
            and exists (
              select 1
              from dastak_v1.packages package
              where package.order_id = entry.order_id
            )
            and not exists (
              select 1
              from dastak_v1.packages package
              where package.order_id = entry.order_id
                and (
                  not exists (
                    select 1
                    from dastak_v1.package_custody_events custody
                    where custody.order_id = entry.order_id
                      and custody.mission_id = mission.id
                      and custody.fulfilment_id = package.fulfilment_id
                      and custody.package_id = package.id
                      and custody.verification_handoff_id = handoff.id
                      and custody.from_owner_type = 'RIDER'
                      and custody.from_owner_id = mission.assigned_rider_id
                      and custody.to_owner_type = 'CUSTOMER'
                      and custody.to_owner_id = customer_order.customer_id
                      and custody.transferred_by = mission.assigned_rider_id
                  )
                  or not exists (
                    select 1
                    from dastak_v1.delivery_evidence evidence
                    join dastak_v1.delivery_evidence_packages evidence_package
                      on evidence_package.evidence_id = evidence.id
                     and evidence_package.package_id = package.id
                     and evidence_package.order_id = entry.order_id
                     and evidence_package.mission_id = mission.id
                    where evidence.order_id = entry.order_id
                      and evidence.mission_id = mission.id
                      and evidence.verification_handoff_id = handoff.id
                      and evidence.captured_by = mission.assigned_rider_id
                  )
                )
            )
        )
    )
    else false
  end, false)
  from dastak_v1.settlement_entries entry
  where entry.id = p_settlement_entry_id
    and entry.entry_type = 'EARNING';
$$;

create function dastak_v1_api.resolve_merchant_refund_fulfilment(
  p_refund_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_refund dastak_v1.refunds%rowtype;
  v_recovery dastak_v1.recovery_cases%rowtype;
  v_line_id uuid;
  v_fulfilment_id uuid;
begin
  select refund.* into v_refund
  from dastak_v1.refunds refund
  where refund.id = p_refund_id;
  if not found or v_refund.fault_source <> 'MERCHANT' then return null; end if;

  if v_refund.recovery_case_id is not null then
    select recovery.* into v_recovery
    from dastak_v1.recovery_cases recovery
    where recovery.id = v_refund.recovery_case_id
      and recovery.order_id = v_refund.order_id;
    if found and v_recovery.case_type = 'EXACT_SKU'
      and v_recovery.source_fulfilment_id is not null then
      return v_recovery.source_fulfilment_id;
    end if;
  end if;

  v_line_id := v_refund.order_line_id;
  if v_line_id is null and v_refund.customer_issue_id is not null then
    select issue.order_line_id into v_line_id
    from dastak_v1.customer_issues issue
    where issue.id = v_refund.customer_issue_id
      and issue.order_id = v_refund.order_id;
  end if;
  if v_line_id is null and v_refund.return_id is not null then
    select case when pg_catalog.count(distinct return_line.order_line_id) = 1
        then pg_catalog.min(return_line.order_line_id::text)::uuid end
    into v_line_id
    from dastak_v1.return_lines return_line
    where return_line.return_id = v_refund.return_id;
  end if;

  if v_line_id is not null then
    select fulfilment.id into v_fulfilment_id
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.fulfilment_lines fulfilment_line
      on fulfilment_line.fulfilment_id = fulfilment.id
     and fulfilment_line.order_line_id = v_line_id
    where fulfilment.order_id = v_refund.order_id
      and fulfilment.status in ('PICKED_UP', 'COMPLETED')
    order by (fulfilment.fulfilment_type = 'RECOVERY') desc,
      (fulfilment.status = 'COMPLETED') desc,
      fulfilment.committed_at desc nulls last,
      fulfilment.id
    limit 1;
    if v_fulfilment_id is not null then return v_fulfilment_id; end if;
  end if;

  -- An order-level Merchant fault is safe to auto-attribute only when exactly
  -- one picked-up fulfilment exists. Multi-Merchant liability requires the
  -- named, audited Operations adjustment command rather than a heuristic.
  select case when pg_catalog.count(distinct fulfilment.id) = 1
      then pg_catalog.min(fulfilment.id::text)::uuid end
  into v_fulfilment_id
  from dastak_v1.fulfilments fulfilment
  where fulfilment.order_id = v_refund.order_id
    and fulfilment.status in ('PICKED_UP', 'COMPLETED')
    and exists (
      select 1 from dastak_v1.packages package
      where package.fulfilment_id = fulfilment.id
        and package.picked_up_at is not null
    );
  return v_fulfilment_id;
end;
$$;

create function dastak_v1_api.resolve_rider_refund_mission(
  p_refund_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_refund dastak_v1.refunds%rowtype;
  v_mission_id uuid;
begin
  select refund.* into v_refund
  from dastak_v1.refunds refund
  where refund.id = p_refund_id;
  if not found or v_refund.fault_source <> 'RIDER' then return null; end if;

  if v_refund.recovery_case_id is not null then
    select recovery.delivery_mission_id into v_mission_id
    from dastak_v1.recovery_cases recovery
    join dastak_v1.delivery_missions mission
      on mission.id = recovery.delivery_mission_id
     and mission.order_id = v_refund.order_id
     and mission.assigned_rider_id is not null
    where recovery.id = v_refund.recovery_case_id
      and recovery.case_type = 'DELIVERY'
      and recovery.order_id = v_refund.order_id;
    if v_mission_id is not null then return v_mission_id; end if;
  end if;

  select case when pg_catalog.count(distinct mission.id) = 1
      then pg_catalog.min(mission.id::text)::uuid end
  into v_mission_id
  from dastak_v1.delivery_missions mission
  where mission.order_id = v_refund.order_id
    and mission.assigned_rider_id is not null
    and mission.status = 'DELIVERED'
    and mission.delivered_at is not null;
  return v_mission_id;
end;
$$;

create or replace function dastak_v1_api.create_approved_refund(
  p_actor_id uuid,
  p_order_id uuid,
  p_order_line_id uuid,
  p_recovery_case_id uuid,
  p_customer_issue_id uuid,
  p_return_id uuid,
  p_amount_paise bigint,
  p_fault_source dastak_v1.refund_fault_source,
  p_reason text,
  p_approval_kind text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment dastak_v1.payments%rowtype;
  v_existing_total bigint;
  v_refund_id uuid := gen_random_uuid();
  v_responsible_fulfilment_id uuid;
  v_entry dastak_v1.settlement_entries%rowtype;
begin
  select payment.* into v_payment
  from dastak_v1.payments payment where payment.order_id = p_order_id for update;
  if not found or v_payment.status <> 'SUCCEEDED'
    or v_payment.provider_payment_reference is null then
    raise exception using errcode = '55000', message = 'PAID_ORDER_REQUIRED';
  end if;
  if p_amount_paise is null or p_amount_paise <= 0 then
    raise exception using errcode = '22023', message = 'invalid refund amount';
  end if;
  select coalesce(sum(refund.amount_paise), 0) into v_existing_total
  from dastak_v1.refunds refund
  where refund.order_id = p_order_id and refund.status <> 'FAILED';
  if v_existing_total + p_amount_paise > v_payment.amount_paise then
    raise exception using errcode = '23514', message = 'REFUND_EXCEEDS_PAYMENT';
  end if;
  insert into dastak_v1.refunds (
    id, order_id, payment_id, order_line_id, recovery_case_id,
    customer_issue_id, return_id, status, fault_source, amount_paise,
    reason, approval_kind, created_by, approved_by, approved_at,
    provider_payment_reference, provider_receipt
  ) values (
    v_refund_id, p_order_id, v_payment.id, p_order_line_id,
    p_recovery_case_id, p_customer_issue_id, p_return_id,
    'APPROVED', p_fault_source, p_amount_paise, pg_catalog.btrim(p_reason),
    p_approval_kind, p_actor_id, case when p_approval_kind = 'AUTHORIZED_OPERATIONS'
      then p_actor_id else null end, pg_catalog.clock_timestamp(),
    v_payment.provider_payment_reference,
    'd1r-' || pg_catalog.replace(v_refund_id::text, '-', '')
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_refund_id::text || ':REFUND_CREATED:1', 'REFUND', v_refund_id, 1,
    'REFUND_CREATED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', p_order_id, 'refundId', v_refund_id,
      'amountPaise', p_amount_paise, 'currency', 'INR',
      'destination', 'ORIGINAL_PAYMENT_METHOD', 'status', 'APPROVED'
    )
  );
  if p_fault_source = 'MERCHANT' then
    v_responsible_fulfilment_id :=
      dastak_v1_api.resolve_merchant_refund_fulfilment(v_refund_id);
    if v_responsible_fulfilment_id is not null then
      select entry.* into v_entry
      from dastak_v1.settlement_entries entry
      where entry.order_id = p_order_id
        and entry.fulfilment_id = v_responsible_fulfilment_id
        and entry.subject_type = 'MERCHANT_ORGANIZATION'
        and entry.entry_type = 'EARNING'
        and (p_order_line_id is null or entry.order_line_id = p_order_line_id)
      order by entry.created_at, entry.id
      limit 1;
    end if;
    if v_entry.id is not null then
      insert into dastak_v1.settlement_entries (
        entry_key, subject_type, subject_id, order_id, fulfilment_id,
        order_line_id, refund_id, entry_type, status, calculation_status,
        gross_amount_paise, amount_paise, calculation_snapshot
      ) values (
        p_order_id::text || ':REFUND_ADJUSTMENT:' || v_refund_id::text,
        v_entry.subject_type, v_entry.subject_id, p_order_id,
        v_entry.fulfilment_id, p_order_line_id, v_refund_id,
        'REFUND_ADJUSTMENT', 'PENDING', 'CALCULATED',
        p_amount_paise, -p_amount_paise,
        pg_catalog.jsonb_build_object(
          'reason', 'MERCHANT_CAUSED_APPROVED_REFUND',
          'refundId', v_refund_id,
          'orderId', p_order_id,
          'orderLineId', p_order_line_id,
          'recoveryCaseId', p_recovery_case_id,
          'customerIssueId', p_customer_issue_id,
          'returnId', p_return_id,
          'responsibleFulfilmentId', v_entry.fulfilment_id,
          'responsibleOrganizationId', v_entry.subject_id,
          'originalEarningEntryId', v_entry.id,
          'approvalKind', p_approval_kind,
          'authorizedBy', p_actor_id,
          'customerRefundIndependent', true,
          'historicalEarningPreserved', true
        )
      );
    else
      insert into dastak_v1.audit_events (
        actor_id, action, resource_type, resource_id, metadata
      ) values (
        p_actor_id, 'MERCHANT_ROYALTY_LIABILITY_ATTRIBUTION_REQUIRED',
        'refund', v_refund_id,
        pg_catalog.jsonb_build_object(
          'orderId', p_order_id,
          'orderLineId', p_order_line_id,
          'recoveryCaseId', p_recovery_case_id,
          'customerIssueId', p_customer_issue_id,
          'returnId', p_return_id,
          'refundAmountPaise', p_amount_paise,
          'customerRefundContinuesIndependently', true,
          'requiresNamedRoyaltyAdjustment', true
        )
      );
    end if;
  end if;
  return v_refund_id;
end;
$$;

create or replace function dastak_v1_api.mark_order_settlements_eligible(
  p_order_id uuid,
  p_actor_id uuid,
  p_reason text,
  p_include_rider boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  perform pg_catalog.set_config(
    'dastak_v1.settlement_actor_id', coalesce(p_actor_id::text, ''), true
  );
  perform pg_catalog.set_config('dastak_v1.settlement_reason', p_reason, true);
  update dastak_v1.settlement_entries entry
  set status = 'ELIGIBLE', eligible_at = pg_catalog.clock_timestamp(),
      version = entry.version + 1
  where entry.order_id = p_order_id
    and entry.status = 'PENDING'
    and entry.calculation_status = 'CALCULATED'
    and (entry.subject_type = 'MERCHANT_ORGANIZATION' or p_include_rider)
    and (entry.refund_id is null or exists (
      select 1 from dastak_v1.refunds refund
      where refund.id = entry.refund_id and refund.status = 'COMPLETED'
    ))
    and (
      entry.entry_type <> 'EARNING'
      or dastak_v1_api.royalty_earning_milestone_proven(entry.id)
    );
  get diagnostics v_changed = row_count;
  return v_changed;
end;
$$;

create or replace function dastak_v1.mark_refund_adjustment_eligible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status <> 'COMPLETED' and new.status = 'COMPLETED' then
    perform pg_catalog.set_config('dastak_v1.settlement_actor_id', '', true);
    perform pg_catalog.set_config(
      'dastak_v1.settlement_reason',
      'Completed original-method refund made only its append-only adjustment eligible.',
      true
    );
    update dastak_v1.settlement_entries entry
    set status = 'ELIGIBLE', eligible_at = pg_catalog.clock_timestamp(),
        version = entry.version + 1
    where entry.refund_id = new.id
      and entry.entry_type <> 'EARNING'
      and entry.status = 'PENDING'
      and entry.calculation_status = 'CALCULATED';
  end if;
  return new;
end;
$$;

create function dastak_v1_api.post_royalty_from_settlement_entry(
  p_settlement_entry_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry dastak_v1.settlement_entries%rowtype;
  v_transaction_type text;
  v_royalty_account text;
  v_debit_account text;
  v_credit_account text;
  v_debit_subject_type dastak_v1.settlement_subject_type;
  v_credit_subject_type dastak_v1.settlement_subject_type;
  v_debit_subject_id uuid;
  v_credit_subject_id uuid;
  v_transaction_id uuid;
begin
  select entry.* into strict v_entry
  from dastak_v1.settlement_entries entry
  where entry.id = p_settlement_entry_id;
  if v_entry.calculation_status <> 'CALCULATED'
    or v_entry.amount_paise is null
    or v_entry.status not in ('ELIGIBLE', 'SETTLED') then
    raise exception 'ROYALTY_SOURCE_NOT_ELIGIBLE';
  end if;
  if v_entry.entry_type = 'EARNING'
    and not dastak_v1_api.royalty_earning_milestone_proven(v_entry.id) then
    raise exception using
      errcode = '55000', message = 'ROYALTY_EARNING_MILESTONE_NOT_PROVEN',
      detail = 'Immutable verified custody evidence is required before Royalty credit.';
  end if;
  if v_entry.subject_type = 'MERCHANT_ORGANIZATION'
    and v_entry.entry_type = 'EARNING'
    and (
      v_entry.amount_paise <> v_entry.gross_amount_paise
      or v_entry.calculation_snapshot ->> 'commissionBps' is distinct from '0'
    ) then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Locked V1 Merchant commission must be exactly 0 bps.';
  end if;
  v_royalty_account := case v_entry.subject_type
    when 'MERCHANT_ORGANIZATION' then 'MERCHANT_ROYALTY_PAYABLE'
    else 'RIDER_ROYALTY_PAYABLE'
  end;
  if v_entry.entry_type = 'EARNING' then
    v_transaction_type := case v_entry.subject_type
      when 'MERCHANT_ORGANIZATION' then 'MERCHANT_ROYALTY_EARNING'
      else 'RIDER_ROYALTY_EARNING'
    end;
    v_debit_account := case v_entry.subject_type
      when 'MERCHANT_ORGANIZATION' then 'MERCHANT_FULFILMENT_COST'
      else 'RIDER_DELIVERY_COST'
    end;
    v_credit_account := v_royalty_account;
    v_credit_subject_type := v_entry.subject_type;
    v_credit_subject_id := v_entry.subject_id;
  elsif v_entry.amount_paise < 0 then
    v_transaction_type := 'ROYALTY_FAULT_ADJUSTMENT';
    v_debit_account := v_royalty_account;
    v_debit_subject_type := v_entry.subject_type;
    v_debit_subject_id := v_entry.subject_id;
    v_credit_account := 'FAULT_RECOVERY';
  else
    v_transaction_type := 'ROYALTY_CREDIT_ADJUSTMENT';
    v_debit_account := 'FAULT_RECOVERY';
    v_credit_account := v_royalty_account;
    v_credit_subject_type := v_entry.subject_type;
    v_credit_subject_id := v_entry.subject_id;
  end if;
  v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
    v_entry.id::text || ':ROYALTY_POSTING',
    v_transaction_type, abs(v_entry.amount_paise),
    v_debit_account, v_debit_subject_type, v_debit_subject_id,
    v_credit_account, v_credit_subject_type, v_credit_subject_id,
    v_entry.order_id, v_entry.fulfilment_id, v_entry.delivery_mission_id,
    null, v_entry.refund_id, v_entry.id, null, null,
    case when v_entry.entry_type = 'EARNING'
      then 'Verified operational milestone credited Royalty exactly once.'
      else 'Authorized liability adjustment posted without rewriting the original earning.'
    end,
    v_entry.calculation_snapshot || pg_catalog.jsonb_build_object(
      'settlementEntryId', v_entry.id,
      'entryType', v_entry.entry_type,
      'subjectType', v_entry.subject_type,
      'subjectId', v_entry.subject_id,
      'signedRoyaltyDeltaPaise', v_entry.amount_paise,
      'historicalSourcePreserved', true
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_transaction_id::text || ':ROYALTY_POSTED',
    'FINANCIAL_TRANSACTION', v_transaction_id, 1,
    case when v_entry.entry_type = 'EARNING'
      then 'ROYALTY_EARNING_CREDITED' else 'ROYALTY_ADJUSTMENT_POSTED' end,
    pg_catalog.jsonb_build_object(
      'orderId', v_entry.order_id,
      'fulfilmentId', v_entry.fulfilment_id,
      'missionId', v_entry.delivery_mission_id,
      'refundId', v_entry.refund_id,
      'subjectType', v_entry.subject_type,
      'subjectId', v_entry.subject_id,
      'amountPaise', v_entry.amount_paise,
      'currency', v_entry.currency_code
    )
  ) on conflict (event_key) do nothing;
  return v_transaction_id;
end;
$$;

create function dastak_v1.post_royalty_when_settlement_eligible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.calculation_status = 'CALCULATED'
    and new.status in ('ELIGIBLE', 'SETTLED')
    and (tg_op = 'INSERT' or old.status not in ('ELIGIBLE', 'SETTLED')) then
    perform dastak_v1_api.post_royalty_from_settlement_entry(new.id);
  end if;
  return new;
end;
$$;

create trigger settlement_entries_post_royalty
after insert or update of status on dastak_v1.settlement_entries
for each row execute function dastak_v1.post_royalty_when_settlement_eligible();

create function dastak_v1.credit_merchant_royalty_after_pickup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission_id uuid;
  v_rider_id uuid;
  v_package_count bigint;
  v_entry_count bigint;
  v_entry record;
begin
  if old.status = 'PICKED_UP' or new.status <> 'PICKED_UP' then return new; end if;
  select handoff.mission_id, handoff.consumed_by
  into v_mission_id, v_rider_id
  from dastak_v1.verification_handoffs handoff
  join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
  where handoff.fulfilment_id = new.id
    and handoff.handoff_type = 'MERCHANT_TO_RIDER'
    and handoff.status = 'CONSUMED'
    and handoff.consumed_by = mission.assigned_rider_id
  order by handoff.consumed_at desc
  limit 1;
  if v_mission_id is null or v_rider_id is null or new.package_count is null then
    raise exception 'VERIFIED_COMPLETE_PICKUP_REQUIRED_FOR_MERCHANT_ROYALTY';
  end if;
  select count(*) into v_package_count
  from dastak_v1.packages package
  where package.fulfilment_id = new.id
    and package.status = 'PICKED_UP'
    and package.current_custody_owner_type = 'RIDER'
    and package.current_custody_owner_id = v_rider_id;
  if v_package_count <> new.package_count then
    raise exception 'COMPLETE_RIDER_CUSTODY_REQUIRED_FOR_MERCHANT_ROYALTY';
  end if;
  select count(*) into v_entry_count
  from dastak_v1.settlement_entries entry
  where entry.fulfilment_id = new.id
    and entry.subject_type = 'MERCHANT_ORGANIZATION'
    and entry.entry_type = 'EARNING';
  if v_entry_count = 0 or exists (
    select 1 from dastak_v1.settlement_entries entry
    where entry.fulfilment_id = new.id
      and entry.subject_type = 'MERCHANT_ORGANIZATION'
      and entry.entry_type = 'EARNING'
      and entry.calculation_status <> 'CALCULATED'
  ) then
    raise exception using
      errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Merchant Royalty calculation is missing or invalid.';
  end if;
  perform pg_catalog.set_config(
    'dastak_v1.settlement_reason',
    'Complete verified Merchant-to-Rider custody credited Merchant Royalty.', true
  );
  update dastak_v1.settlement_entries entry
  set status = 'ELIGIBLE', eligible_at = pg_catalog.clock_timestamp(),
      version = entry.version + 1
  where entry.fulfilment_id = new.id
    and entry.subject_type = 'MERCHANT_ORGANIZATION'
    and entry.entry_type = 'EARNING'
    and entry.status = 'PENDING';
  for v_entry in
    select entry.id
    from dastak_v1.settlement_entries entry
    where entry.fulfilment_id = new.id
      and entry.subject_type = 'MERCHANT_ORGANIZATION'
      and entry.entry_type = 'EARNING'
      and entry.status in ('ELIGIBLE', 'SETTLED')
  loop
    perform dastak_v1_api.post_royalty_from_settlement_entry(v_entry.id);
  end loop;
  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    'MERCHANT_ROYALTY_CREDITED', 'fulfilment', new.id,
    pg_catalog.jsonb_build_object(
      'orderId', new.order_id, 'missionId', v_mission_id,
      'organizationId', new.organization_id,
      'packageCount', v_package_count,
      'settlementEntryCount', v_entry_count,
      'verifiedHandoff', true
    )
  );
  return new;
end;
$$;

create trigger fulfilments_credit_merchant_royalty
after update of status on dastak_v1.fulfilments
for each row execute function dastak_v1.credit_merchant_royalty_after_pickup();

create or replace function dastak_v1.mark_settlements_after_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_entry_id uuid;
begin
  if old.status = 'DELIVERED' or new.status <> 'DELIVERED' then return new; end if;
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.order_id = new.id
    and mission.status = 'DELIVERED'
    and mission.assigned_rider_id is not null
    and exists (
      select 1 from dastak_v1.verification_handoffs handoff
      where handoff.mission_id = mission.id
        and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
        and handoff.status = 'CONSUMED'
        and handoff.consumed_by = mission.assigned_rider_id
    )
    and exists (
      select 1 from dastak_v1.delivery_evidence evidence
      where evidence.mission_id = mission.id
        and evidence.captured_by = mission.assigned_rider_id
    )
    and not exists (
      select 1 from dastak_v1.packages package
      where package.order_id = new.id
        and package.status <> 'DELIVERED'
    )
  order by mission.delivered_at desc
  limit 1;
  if v_mission.id is null then
    -- Exceptional OVERRIDDEN delivery remains truthful and does not masquerade
    -- as normal recipient verification for Rider Royalty eligibility.
    return new;
  end if;
  if exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.settlement_entries entry on entry.fulfilment_id = fulfilment.id
    where fulfilment.order_id = new.id
      and fulfilment.status <> 'RELEASED'
      and entry.subject_type = 'MERCHANT_ORGANIZATION'
      and entry.entry_type = 'EARNING'
      and entry.status not in ('ELIGIBLE', 'SETTLED')
  ) then
    raise exception 'MERCHANT_ROYALTY_PICKUP_CREDIT_REQUIRED_BEFORE_DELIVERY';
  end if;
  insert into dastak_v1.settlement_entries (
    entry_key, subject_type, subject_id, order_id, delivery_mission_id,
    entry_type, status, calculation_status, gross_amount_paise,
    amount_paise, calculation_snapshot, eligible_at
  ) values (
    new.id::text || ':RIDER:' || v_mission.id::text,
    'RIDER', v_mission.assigned_rider_id, new.id, v_mission.id,
    'EARNING', 'ELIGIBLE', 'CALCULATED',
    v_mission.rider_payout_quote_paise,
    v_mission.rider_payout_quote_paise,
    v_mission.rider_payout_quote_snapshot || pg_catalog.jsonb_build_object(
      'missionId', v_mission.id,
      'verifiedRecipientHandoff', true,
      'completeCustomerCustody', true,
      'missionQuotePreserved', true,
      'configurationRequired', false
    ),
    coalesce(v_mission.delivered_at, pg_catalog.clock_timestamp())
  ) on conflict (entry_key) do nothing returning id into v_entry_id;
  if v_entry_id is null then
    select entry.id into v_entry_id
    from dastak_v1.settlement_entries entry
    where entry.entry_key = new.id::text || ':RIDER:' || v_mission.id::text;
    update dastak_v1.settlement_entries entry
    set status = 'ELIGIBLE', eligible_at = coalesce(
          entry.eligible_at, v_mission.delivered_at, pg_catalog.clock_timestamp()
        ),
        version = entry.version + 1
    where entry.id = v_entry_id and entry.status = 'PENDING';
  end if;
  perform dastak_v1_api.post_royalty_from_settlement_entry(v_entry_id);
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    v_mission.assigned_rider_id, 'RIDER_ROYALTY_CREDITED',
    'delivery_mission', v_mission.id,
    pg_catalog.jsonb_build_object(
      'orderId', new.id,
      'amountPaise', v_mission.rider_payout_quote_paise,
      'verifiedRecipientHandoff', true,
      'completeCustomerCustody', true
    )
  );
  return new;
end;
$$;

create function dastak_v1.seed_rider_fault_adjustment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
begin
  if new.fault_source <> 'RIDER' then return new; end if;
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = dastak_v1_api.resolve_rider_refund_mission(new.id);
  if v_mission.id is null then
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      new.created_by, 'RIDER_ROYALTY_LIABILITY_ATTRIBUTION_REQUIRED',
      'refund', new.id,
      pg_catalog.jsonb_build_object(
        'orderId', new.order_id,
        'recoveryCaseId', new.recovery_case_id,
        'customerIssueId', new.customer_issue_id,
        'returnId', new.return_id,
        'refundAmountPaise', new.amount_paise,
        'customerRefundContinuesIndependently', true,
        'requiresNamedRoyaltyAdjustment', true
      )
    );
    return new;
  end if;
  insert into dastak_v1.settlement_entries (
    entry_key, subject_type, subject_id, order_id, delivery_mission_id,
    refund_id, entry_type, status, calculation_status,
    gross_amount_paise, amount_paise, calculation_snapshot
  ) values (
    new.order_id::text || ':RIDER_REFUND_ADJUSTMENT:' || new.id::text,
    'RIDER', v_mission.assigned_rider_id, new.order_id, v_mission.id,
    new.id, 'REFUND_ADJUSTMENT', 'PENDING', 'CALCULATED',
    new.amount_paise, -new.amount_paise,
    pg_catalog.jsonb_build_object(
      'reason', 'RIDER_CAUSED_APPROVED_REFUND',
      'refundId', new.id,
      'missionId', v_mission.id,
      'responsibleRiderId', v_mission.assigned_rider_id,
      'recoveryCaseId', new.recovery_case_id,
      'customerIssueId', new.customer_issue_id,
      'returnId', new.return_id,
      'authorizedBy', new.created_by,
      'customerRefundIndependent', true,
      'historicalEarningPreserved', true
    )
  ) on conflict (entry_key) do nothing;
  return new;
end;
$$;

create trigger refunds_seed_rider_fault_adjustment
after insert on dastak_v1.refunds
for each row execute function dastak_v1.seed_rider_fault_adjustment();

drop trigger royalty_withdrawal_attempts_immutable
  on dastak_v1.royalty_withdrawal_attempts;
create function dastak_v1.guard_royalty_withdrawal_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.withdrawal_id is distinct from old.withdrawal_id
    or new.attempt_number is distinct from old.attempt_number
    or new.provider is distinct from old.provider
    or new.provider_request_key is distinct from old.provider_request_key
    or new.started_by is distinct from old.started_by
    or new.started_at is distinct from old.started_at then
    raise exception 'withdrawal attempt identity cannot change';
  end if;
  if old.status <> 'PROCESSING' or new.status not in ('PAID', 'FAILED') then
    raise exception 'invalid withdrawal attempt transition';
  end if;
  return new;
end;
$$;
create trigger royalty_withdrawal_attempts_guard
before update on dastak_v1.royalty_withdrawal_attempts
for each row execute function dastak_v1.guard_royalty_withdrawal_attempt();
create trigger royalty_withdrawal_attempts_no_delete
before delete on dastak_v1.royalty_withdrawal_attempts
for each row execute function dastak_v1.reject_financial_mutation();

create function dastak_v1_api.royalty_account_code(
  p_subject_type dastak_v1.settlement_subject_type
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_subject_type
    when 'MERCHANT_ORGANIZATION' then 'MERCHANT_ROYALTY_PAYABLE'
    else 'RIDER_ROYALTY_PAYABLE'
  end;
$$;

create function dastak_v1_api.royalty_balance_paise(
  p_subject_type dastak_v1.settlement_subject_type,
  p_subject_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    case line.direction when 'CREDIT' then line.amount_paise
      else -line.amount_paise end
  ), 0)::bigint
  from dastak_v1.financial_journal_lines line
  where line.subject_type = p_subject_type
    and line.subject_id = p_subject_id
    and line.account_code = dastak_v1_api.royalty_account_code(p_subject_type);
$$;

create function dastak_v1_api.actor_can_manage_royalty_subject(
  p_actor_id uuid,
  p_subject_type dastak_v1.settlement_subject_type,
  p_subject_id uuid,
  p_withdraw boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_subject_type
    when 'MERCHANT_ORGANIZATION' then
      dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, p_subject_id,
        case when p_withdraw then 'merchant.royalty.withdraw'
          else 'merchant.earnings.read' end,
        null
      )
    when 'RIDER' then p_actor_id = p_subject_id and exists (
      select 1 from private.delivery_partner_profiles profile
      join private.account_memberships membership
        on membership.account_id = profile.account_id
       and membership.role = 'dastak_partner'
       and membership.approved_at is not null
       and (membership.suspended_until is null
         or membership.suspended_until <= pg_catalog.now())
      where profile.account_id = p_actor_id
    )
    else false
  end;
$$;

create function dastak_v1_api.royalty_subject_snapshot(
  p_actor_id uuid,
  p_subject_type dastak_v1.settlement_subject_type,
  p_subject_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_balance bigint := dastak_v1_api.royalty_balance_paise(
    p_subject_type, p_subject_id
  );
begin
  return pg_catalog.jsonb_build_object(
    'subjectType', p_subject_type,
    'subjectId', p_subject_id,
    'currency', 'INR',
    'balancePaise', v_balance,
    'availablePaise', greatest(v_balance, 0),
    'negativeBalancePaise', greatest(-v_balance, 0),
    'lifetimeEarnedPaise', coalesce((
      select sum(transaction.amount_paise)
      from dastak_v1.financial_journal_transactions transaction
      join dastak_v1.financial_journal_lines line
        on line.transaction_id = transaction.id
      where line.subject_type = p_subject_type
        and line.subject_id = p_subject_id
        and line.direction = 'CREDIT'
        and transaction.transaction_type in (
          'MERCHANT_ROYALTY_EARNING', 'RIDER_ROYALTY_EARNING'
        )
    ), 0),
    'canWithdraw', v_balance > 0
      and dastak_v1_api.actor_can_manage_royalty_subject(
        p_actor_id, p_subject_type, p_subject_id, true
      ) and exists (
      select 1 from dastak_v1.royalty_payout_destinations destination
      where destination.subject_type = p_subject_type
        and destination.subject_id = p_subject_id
        and destination.status = 'ACTIVE'
    ),
    'payoutDestination', (
      select pg_catalog.jsonb_build_object(
        'id', destination.id,
        'type', destination.destination_type,
        'provider', destination.provider,
        'displayLabel', destination.display_label,
        'status', destination.status,
        'version', destination.version
      )
      from dastak_v1.royalty_payout_destinations destination
      where destination.subject_type = p_subject_type
        and destination.subject_id = p_subject_id
        and destination.status = 'ACTIVE'
    ),
    'entries', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', transaction.id,
        'type', transaction.transaction_type,
        'amountPaise', case line.direction when 'CREDIT'
          then line.amount_paise else -line.amount_paise end,
        'orderId', transaction.order_id,
        'fulfilmentId', transaction.fulfilment_id,
        'missionId', transaction.delivery_mission_id,
        'refundId', transaction.refund_id,
        'withdrawalId', transaction.withdrawal_id,
        'reason', transaction.reason,
        'createdAt', transaction.created_at
      ) order by transaction.created_at desc, transaction.id desc)
      from dastak_v1.financial_journal_lines line
      join dastak_v1.financial_journal_transactions transaction
        on transaction.id = line.transaction_id
      where line.subject_type = p_subject_type
        and line.subject_id = p_subject_id
        and line.account_code = dastak_v1_api.royalty_account_code(p_subject_type)
    ), '[]'::jsonb),
    'adjustments', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', transaction.id,
        'type', transaction.transaction_type,
        'amountPaise', case line.direction when 'CREDIT'
          then line.amount_paise else -line.amount_paise end,
        'orderId', transaction.order_id,
        'refundId', transaction.refund_id,
        'reason', transaction.reason,
        'createdAt', transaction.created_at
      ) order by transaction.created_at desc, transaction.id desc)
      from dastak_v1.financial_journal_lines line
      join dastak_v1.financial_journal_transactions transaction
        on transaction.id = line.transaction_id
      where line.subject_type = p_subject_type
        and line.subject_id = p_subject_id
        and transaction.transaction_type in (
          'ROYALTY_FAULT_ADJUSTMENT', 'ROYALTY_CREDIT_ADJUSTMENT'
        )
    ), '[]'::jsonb),
    'withdrawals', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', withdrawal.id,
        'amountPaise', withdrawal.amount_paise,
        'currency', withdrawal.currency_code,
        'status', withdrawal.status,
        'destination', pg_catalog.jsonb_build_object(
          'type', withdrawal.destination_snapshot ->> 'type',
          'provider', withdrawal.destination_snapshot ->> 'provider',
          'displayLabel', withdrawal.destination_snapshot ->> 'displayLabel'
        ),
        'providerPayoutReference', withdrawal.provider_payout_reference,
        'requestedAt', withdrawal.requested_at,
        'processingAt', withdrawal.processing_at,
        'paidAt', withdrawal.paid_at,
        'failedAt', withdrawal.failed_at,
        'failureCode', withdrawal.latest_failure_code,
        'version', withdrawal.version
      ) order by withdrawal.requested_at desc, withdrawal.id desc)
      from dastak_v1.royalty_withdrawals withdrawal
      where withdrawal.subject_type = p_subject_type
        and withdrawal.subject_id = p_subject_id
    ), '[]'::jsonb)
  );
end;
$$;

create function dastak_v1_api.get_royalty_snapshot(
  p_actor_id uuid,
  p_kind text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_subjects jsonb;
  v_available bigint;
  v_balance bigint;
  v_negative bigint;
  v_lifetime bigint;
begin
  if p_actor_id is null or p_kind not in ('MERCHANT', 'RIDER') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied', 'message', 'Royalty access is unavailable.'
      )
    );
    response_status := 403;
    return next; return;
  end if;
  if p_kind = 'MERCHANT' then
    select coalesce(pg_catalog.jsonb_agg(
      dastak_v1_api.royalty_subject_snapshot(
        p_actor_id, 'MERCHANT_ORGANIZATION', organization.id
      ) order by organization.display_name, organization.id
    ), '[]'::jsonb)
    into v_subjects
    from dastak_v1.merchant_organizations organization
    where dastak_v1_api.actor_can_manage_royalty_subject(
      p_actor_id, 'MERCHANT_ORGANIZATION', organization.id, false
    );
  else
    if not dastak_v1_api.actor_can_manage_royalty_subject(
      p_actor_id, 'RIDER', p_actor_id, false
    ) then
      v_subjects := '[]'::jsonb;
    else
      v_subjects := pg_catalog.jsonb_build_array(
        dastak_v1_api.royalty_subject_snapshot(p_actor_id, 'RIDER', p_actor_id)
      );
    end if;
  end if;
  if pg_catalog.jsonb_array_length(v_subjects) = 0 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied', 'message', 'Royalty access is unavailable.'
      )
    );
    response_status := 403;
    return next; return;
  end if;
  select
    coalesce(sum((subject ->> 'availablePaise')::bigint), 0),
    coalesce(sum((subject ->> 'balancePaise')::bigint), 0),
    coalesce(sum((subject ->> 'negativeBalancePaise')::bigint), 0),
    coalesce(sum((subject ->> 'lifetimeEarnedPaise')::bigint), 0)
  into v_available, v_balance, v_negative, v_lifetime
  from pg_catalog.jsonb_array_elements(v_subjects) as subjects(subject);
  response_body := pg_catalog.jsonb_build_object(
    'currency', 'INR',
    'availablePaise', v_available,
    'balancePaise', v_balance,
    'negativeBalancePaise', v_negative,
    'lifetimeEarnedPaise', v_lifetime,
    'subjects', v_subjects
  );
  response_status := 200;
  return next;
end;
$$;

create function public.dastak_v1_get_royalty_snapshot(
  p_account_id uuid,
  p_kind text
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select * from dastak_v1_api.get_royalty_snapshot(p_account_id, p_kind);
$$;

create function dastak_v1_api.register_royalty_payout_destination(
  p_actor_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_destination_type text,
  p_provider text,
  p_provider_destination_reference text,
  p_display_label text,
  p_details_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_type dastak_v1.settlement_subject_type;
  v_destination dastak_v1.royalty_payout_destinations%rowtype;
begin
  begin v_subject_type := p_subject_type::dastak_v1.settlement_subject_type;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid Royalty subject';
  end;
  if not dastak_v1_api.actor_can_manage_royalty_subject(
    p_actor_id, v_subject_type, p_subject_id, true
  ) then
    raise exception using errcode = '42501', message = 'Royalty withdrawal permission required';
  end if;
  if p_destination_type not in ('BANK_ACCOUNT', 'UPI', 'PROVIDER_DESTINATION')
    or p_provider !~ '^[A-Z][A-Z0-9_]{1,39}$'
    or nullif(pg_catalog.btrim(p_provider_destination_reference), '') is null
    or nullif(pg_catalog.btrim(p_display_label), '') is null
    or pg_catalog.jsonb_typeof(p_details_snapshot) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid payout destination';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-payout-destination:' || v_subject_type::text || ':' || p_subject_id::text, 0
  ));
  select destination.* into v_destination
  from dastak_v1.royalty_payout_destinations destination
  where destination.subject_type = v_subject_type
    and destination.subject_id = p_subject_id
    and destination.status = 'ACTIVE'
  for update;
  if found and v_destination.provider = p_provider
    and v_destination.provider_destination_reference = p_provider_destination_reference
    and v_destination.destination_type = p_destination_type
    and v_destination.display_label = pg_catalog.btrim(p_display_label) then
    return pg_catalog.jsonb_build_object(
      'destinationId', v_destination.id, 'status', v_destination.status,
      'version', v_destination.version, 'unchanged', true
    );
  end if;
  if found then
    update dastak_v1.royalty_payout_destinations destination
    set status = 'INACTIVE', deactivated_by = p_actor_id,
        deactivated_at = pg_catalog.clock_timestamp(),
        version = destination.version + 1
    where destination.id = v_destination.id;
  end if;
  insert into dastak_v1.royalty_payout_destinations (
    subject_type, subject_id, destination_type, provider,
    provider_destination_reference, display_label, details_snapshot, created_by
  ) values (
    v_subject_type, p_subject_id, p_destination_type, p_provider,
    pg_catalog.btrim(p_provider_destination_reference),
    pg_catalog.btrim(p_display_label), p_details_snapshot, p_actor_id
  ) returning * into v_destination;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'ROYALTY_PAYOUT_DESTINATION_REGISTERED',
    'royalty_payout_destination', v_destination.id,
    pg_catalog.jsonb_build_object(
      'subjectType', v_subject_type, 'subjectId', p_subject_id,
      'destinationType', p_destination_type, 'provider', p_provider,
      'displayLabel', v_destination.display_label,
      'providerReferenceStoredPrivately', true
    )
  );
  return pg_catalog.jsonb_build_object(
    'destinationId', v_destination.id, 'status', v_destination.status,
    'version', v_destination.version, 'unchanged', false
  );
end;
$$;

create function public.dastak_v1_register_royalty_payout_destination(
  p_account_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_destination_type text,
  p_provider text,
  p_provider_destination_reference text,
  p_display_label text,
  p_details_snapshot jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.register_royalty_payout_destination(
    p_account_id, p_subject_type, p_subject_id, p_destination_type,
    p_provider, p_provider_destination_reference, p_display_label,
    p_details_snapshot
  );
$$;

create function dastak_v1_api.request_royalty_withdrawal(
  p_actor_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_amount_paise bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_type dastak_v1.settlement_subject_type;
  v_destination dastak_v1.royalty_payout_destinations%rowtype;
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_balance bigint;
  v_transaction_id uuid;
begin
  begin
    v_subject_type := p_subject_type::dastak_v1.settlement_subject_type;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid Royalty subject';
  end;
  if p_amount_paise is null or p_amount_paise <= 0
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid withdrawal request';
  end if;
  if not dastak_v1_api.actor_can_manage_royalty_subject(
    p_actor_id, v_subject_type, p_subject_id, true
  ) then
    raise exception using errcode = '42501', message = 'Royalty withdrawal permission required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-royalty:' || v_subject_type::text || ':' || p_subject_id::text, 0
  ));
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.subject_type = v_subject_type
    and withdrawal.subject_id = p_subject_id
    and withdrawal.idempotency_key = p_idempotency_key;
  if found then
    if v_withdrawal.amount_paise <> p_amount_paise
      or v_withdrawal.requested_by <> p_actor_id then
      raise exception using errcode = '22023',
        message = 'idempotency key was already used with a different request';
    end if;
    return pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id,
      'amountPaise', v_withdrawal.amount_paise,
      'currency', v_withdrawal.currency_code,
      'status', v_withdrawal.status,
      'requestedAt', v_withdrawal.requested_at,
      'version', v_withdrawal.version,
      'replayed', true
    );
  end if;
  v_balance := dastak_v1_api.royalty_balance_paise(v_subject_type, p_subject_id);
  if v_balance <= 0 then
    raise exception using errcode = '23514', message = 'POSITIVE_ROYALTY_BALANCE_REQUIRED';
  end if;
  if p_amount_paise > v_balance then
    raise exception using errcode = '23514', message = 'WITHDRAWAL_EXCEEDS_AVAILABLE_ROYALTY';
  end if;
  select destination.* into v_destination
  from dastak_v1.royalty_payout_destinations destination
  where destination.subject_type = v_subject_type
    and destination.subject_id = p_subject_id
    and destination.status = 'ACTIVE'
  for share;
  if not found then
    raise exception using errcode = '55000', message = 'PAYOUT_DESTINATION_REQUIRED';
  end if;
  insert into dastak_v1.royalty_withdrawals (
    subject_type, subject_id, payout_destination_id, destination_snapshot,
    amount_paise, idempotency_key, requested_by
  ) values (
    v_subject_type, p_subject_id, v_destination.id,
    pg_catalog.jsonb_build_object(
      'id', v_destination.id,
      'type', v_destination.destination_type,
      'provider', v_destination.provider,
      'providerDestinationReference', v_destination.provider_destination_reference,
      'displayLabel', v_destination.display_label,
      'details', v_destination.details_snapshot,
      'destinationVersion', v_destination.version,
      'snapshottedAt', pg_catalog.clock_timestamp()
    ),
    p_amount_paise, p_idempotency_key, p_actor_id
  ) returning * into v_withdrawal;
  v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
    v_withdrawal.id::text || ':WITHDRAWAL_RESERVATION:1',
    'WITHDRAWAL_RESERVATION', v_withdrawal.amount_paise,
    dastak_v1_api.royalty_account_code(v_subject_type),
    v_subject_type, p_subject_id,
    'PAYOUT_CLEARING', null, null,
    null, null, null, null, null, null, v_withdrawal.id, p_actor_id,
    'Positive Royalty reserved transactionally for withdrawal.',
    pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id,
      'destinationSnapshotId', v_destination.id,
      'availableBeforePaise', v_balance,
      'availableAfterPaise', v_balance - p_amount_paise,
      'providerIndependent', true
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'ROYALTY_WITHDRAWAL_REQUESTED', 'royalty_withdrawal',
    v_withdrawal.id, pg_catalog.jsonb_build_object(
      'subjectType', v_subject_type, 'subjectId', p_subject_id,
      'amountPaise', p_amount_paise,
      'destinationId', v_destination.id,
      'financialTransactionId', v_transaction_id,
      'destinationSnapshotted', true
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_withdrawal.id::text || ':ROYALTY_WITHDRAWAL_REQUESTED:1',
    'ROYALTY_WITHDRAWAL', v_withdrawal.id, 1,
    'ROYALTY_WITHDRAWAL_REQUESTED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id,
      'subjectType', v_subject_type, 'subjectId', p_subject_id,
      'amountPaise', p_amount_paise, 'currency', 'INR'
    )
  );
  return pg_catalog.jsonb_build_object(
    'withdrawalId', v_withdrawal.id,
    'amountPaise', v_withdrawal.amount_paise,
    'currency', v_withdrawal.currency_code,
    'status', v_withdrawal.status,
    'requestedAt', v_withdrawal.requested_at,
    'version', v_withdrawal.version,
    'replayed', false
  );
end;
$$;

create function public.dastak_v1_request_royalty_withdrawal(
  p_account_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_amount_paise bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.request_royalty_withdrawal(
    p_account_id, p_subject_type, p_subject_id,
    p_amount_paise, p_idempotency_key
  );
$$;

create function dastak_v1_api.start_royalty_withdrawal(
  p_actor_id uuid,
  p_withdrawal_id uuid,
  p_expected_version bigint,
  p_provider_request_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_attempt dastak_v1.royalty_withdrawal_attempts%rowtype;
  v_attempt_number integer;
  v_provider text;
  v_balance bigint;
  v_transaction_id uuid;
begin
  if p_actor_id is null or not exists (
    select 1 from public.accounts account where account.id = p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if not dastak_v1_api.actor_has_platform_permission(
    p_actor_id, 'platform.withdrawals.manage'
  ) then
    raise exception using errcode = '42501', message = 'platform permission required';
  end if;
  if p_expected_version is null
    or nullif(pg_catalog.btrim(p_provider_request_key), '') is null
    or pg_catalog.char_length(p_provider_request_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid withdrawal processing request';
  end if;
  select attempt.* into v_attempt
  from dastak_v1.royalty_withdrawal_attempts attempt
  where attempt.provider_request_key = p_provider_request_key;
  if found then
    if v_attempt.withdrawal_id <> p_withdrawal_id then
      raise exception using errcode = '22023',
        message = 'provider request key collision';
    end if;
    return pg_catalog.jsonb_build_object(
      'withdrawalId', v_attempt.withdrawal_id,
      'attemptId', v_attempt.id,
      'attemptNumber', v_attempt.attempt_number,
      'provider', v_attempt.provider,
      'status', v_attempt.status,
      'providerRequestKey', v_attempt.provider_request_key,
      'replayed', true
    );
  end if;
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.id = p_withdrawal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'withdrawal not found';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-royalty:' || v_withdrawal.subject_type::text || ':'
      || v_withdrawal.subject_id::text, 0
  ));
  select attempt.* into v_attempt
  from dastak_v1.royalty_withdrawal_attempts attempt
  where attempt.provider_request_key = p_provider_request_key;
  if found then
    if v_attempt.withdrawal_id <> p_withdrawal_id then
      raise exception using errcode = '22023',
        message = 'provider request key collision';
    end if;
    return pg_catalog.jsonb_build_object(
      'withdrawalId', v_attempt.withdrawal_id,
      'attemptId', v_attempt.id,
      'attemptNumber', v_attempt.attempt_number,
      'provider', v_attempt.provider,
      'status', v_attempt.status,
      'providerRequestKey', v_attempt.provider_request_key,
      'replayed', true
    );
  end if;
  if v_withdrawal.version <> p_expected_version
    or v_withdrawal.status not in ('REQUESTED', 'FAILED_RETRYABLE') then
    raise exception using errcode = '40001', message = 'STALE_WITHDRAWAL_VERSION';
  end if;
  v_provider := v_withdrawal.destination_snapshot ->> 'provider';
  if v_provider is null or v_provider !~ '^[A-Z][A-Z0-9_]{1,39}$' then
    raise exception using errcode = '55000', message = 'PAYOUT_PROVIDER_CONFIGURATION_REQUIRED';
  end if;
  select coalesce(max(attempt.attempt_number), 0) + 1
  into v_attempt_number
  from dastak_v1.royalty_withdrawal_attempts attempt
  where attempt.withdrawal_id = v_withdrawal.id;
  if v_withdrawal.status = 'FAILED_RETRYABLE' then
    v_balance := dastak_v1_api.royalty_balance_paise(
      v_withdrawal.subject_type, v_withdrawal.subject_id
    );
    if v_balance < v_withdrawal.amount_paise then
      raise exception using errcode = '23514',
        message = 'WITHDRAWAL_RETRY_EXCEEDS_AVAILABLE_ROYALTY';
    end if;
    v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
      v_withdrawal.id::text || ':WITHDRAWAL_RESERVATION:' || v_attempt_number::text,
      'WITHDRAWAL_RESERVATION', v_withdrawal.amount_paise,
      dastak_v1_api.royalty_account_code(v_withdrawal.subject_type),
      v_withdrawal.subject_type, v_withdrawal.subject_id,
      'PAYOUT_CLEARING', null, null,
      null, null, null, null, null, null, v_withdrawal.id, p_actor_id,
      'Royalty re-reserved transactionally for an authorized payout retry.',
      pg_catalog.jsonb_build_object(
        'withdrawalId', v_withdrawal.id,
        'attemptNumber', v_attempt_number,
        'availableBeforePaise', v_balance,
        'availableAfterPaise', v_balance - v_withdrawal.amount_paise
      )
    );
  end if;
  update dastak_v1.royalty_withdrawals withdrawal
  set status = 'PROCESSING',
      processing_at = coalesce(withdrawal.processing_at, pg_catalog.clock_timestamp()),
      failed_at = null, latest_failure_code = null,
      version = withdrawal.version + 1
  where withdrawal.id = v_withdrawal.id
  returning * into v_withdrawal;
  insert into dastak_v1.royalty_withdrawal_attempts (
    withdrawal_id, attempt_number, provider, provider_request_key, started_by
  ) values (
    v_withdrawal.id, v_attempt_number, v_provider,
    pg_catalog.btrim(p_provider_request_key), p_actor_id
  ) returning * into v_attempt;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'ROYALTY_WITHDRAWAL_PROCESSING', 'royalty_withdrawal',
    v_withdrawal.id, pg_catalog.jsonb_build_object(
      'attemptId', v_attempt.id, 'attemptNumber', v_attempt.attempt_number,
      'provider', v_provider,
      'destinationSnapshotPreserved', true,
      'retryReservationTransactionId', v_transaction_id
    )
  );
  return pg_catalog.jsonb_build_object(
    'withdrawalId', v_withdrawal.id,
    'attemptId', v_attempt.id,
    'attemptNumber', v_attempt.attempt_number,
    'provider', v_attempt.provider,
    'providerRequestKey', v_attempt.provider_request_key,
    'amountPaise', v_withdrawal.amount_paise,
    'currency', v_withdrawal.currency_code,
    'destinationSnapshot', v_withdrawal.destination_snapshot,
    'status', v_withdrawal.status,
    'version', v_withdrawal.version,
    'replayed', false
  );
end;
$$;

create function public.dastak_v1_start_royalty_withdrawal(
  p_account_id uuid,
  p_withdrawal_id uuid,
  p_expected_version bigint,
  p_provider_request_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.start_royalty_withdrawal(
    p_account_id, p_withdrawal_id, p_expected_version, p_provider_request_key
  );
$$;

create function dastak_v1_api.record_royalty_withdrawal_result(
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_provider text,
  p_provider_event_id text,
  p_outcome text,
  p_provider_payout_reference text,
  p_failure_code text,
  p_request_digest text,
  p_response_body jsonb,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_attempt dastak_v1.royalty_withdrawal_attempts%rowtype;
  v_existing dastak_v1.royalty_withdrawal_provider_events%rowtype;
  v_transaction_id uuid;
begin
  if p_outcome not in ('PAID', 'FAILED')
    or p_provider !~ '^[A-Z][A-Z0-9_]{1,39}$'
    or nullif(pg_catalog.btrim(p_provider_event_id), '') is null
    or pg_catalog.char_length(p_provider_event_id) > 200
    or p_request_digest !~ '^[0-9a-f]{64}$'
    or pg_catalog.jsonb_typeof(p_response_body) <> 'object'
    or p_occurred_at is null
    or (p_outcome = 'PAID' and (
      nullif(pg_catalog.btrim(p_provider_payout_reference), '') is null
      or p_failure_code is not null
    ))
    or (p_outcome = 'FAILED' and (
      nullif(pg_catalog.btrim(p_failure_code), '') is null
      or p_provider_payout_reference is not null
    )) then
    raise exception using errcode = '22023', message = 'invalid payout result';
  end if;
  select event.* into v_existing
  from dastak_v1.royalty_withdrawal_provider_events event
  where event.provider = p_provider
    and event.provider_event_id = p_provider_event_id;
  if found then
    if v_existing.withdrawal_id <> p_withdrawal_id
      or v_existing.attempt_id <> p_attempt_id
      or v_existing.outcome::text <> p_outcome
      or v_existing.request_digest <> p_request_digest then
      raise exception using errcode = '22023', message = 'payout event collision';
    end if;
    select withdrawal.* into strict v_withdrawal
    from dastak_v1.royalty_withdrawals withdrawal
    where withdrawal.id = p_withdrawal_id;
    return pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id, 'status', v_withdrawal.status,
      'providerPayoutReference', v_withdrawal.provider_payout_reference,
      'version', v_withdrawal.version, 'replayed', true
    );
  end if;
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.id = p_withdrawal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'withdrawal not found';
  end if;
  select attempt.* into v_attempt
  from dastak_v1.royalty_withdrawal_attempts attempt
  where attempt.id = p_attempt_id
    and attempt.withdrawal_id = v_withdrawal.id
    and attempt.provider = p_provider
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'withdrawal attempt not found';
  end if;
  if v_withdrawal.status <> 'PROCESSING' or v_attempt.status <> 'PROCESSING' then
    select event.* into v_existing
    from dastak_v1.royalty_withdrawal_provider_events event
    where event.provider = p_provider
      and event.provider_event_id = p_provider_event_id;
    if found and v_existing.withdrawal_id = p_withdrawal_id
      and v_existing.attempt_id = p_attempt_id
      and v_existing.outcome::text = p_outcome
      and v_existing.request_digest = p_request_digest then
      return pg_catalog.jsonb_build_object(
        'withdrawalId', v_withdrawal.id, 'status', v_withdrawal.status,
        'providerPayoutReference', v_withdrawal.provider_payout_reference,
        'version', v_withdrawal.version, 'replayed', true
      );
    end if;
    raise exception using errcode = '55000', message = 'PAYOUT_ATTEMPT_ALREADY_FINAL';
  end if;
  insert into dastak_v1.royalty_withdrawal_provider_events (
    provider, provider_event_id, withdrawal_id, attempt_id, outcome,
    request_digest, response_body, occurred_at
  ) values (
    p_provider, pg_catalog.btrim(p_provider_event_id), v_withdrawal.id,
    v_attempt.id, p_outcome::dastak_v1.royalty_withdrawal_attempt_status,
    p_request_digest, p_response_body, p_occurred_at
  );
  if p_outcome = 'PAID' then
    update dastak_v1.royalty_withdrawal_attempts attempt
    set status = 'PAID',
        provider_payout_reference = pg_catalog.btrim(p_provider_payout_reference),
        completed_at = pg_catalog.clock_timestamp()
    where attempt.id = v_attempt.id;
    update dastak_v1.royalty_withdrawals withdrawal
    set status = 'PAID',
        provider_payout_reference = pg_catalog.btrim(p_provider_payout_reference),
        paid_at = pg_catalog.clock_timestamp(),
        version = withdrawal.version + 1
    where withdrawal.id = v_withdrawal.id
    returning * into v_withdrawal;
    v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
      v_attempt.id::text || ':WITHDRAWAL_PAID',
      'WITHDRAWAL_PAID', v_withdrawal.amount_paise,
      'PAYOUT_CLEARING', null, null,
      'PAYOUT_CASH', null, null,
      null, null, null, null, null, null, v_withdrawal.id, null,
      'External payout confirmation completed the immutable withdrawal.',
      pg_catalog.jsonb_build_object(
        'withdrawalId', v_withdrawal.id,
        'attemptId', v_attempt.id,
        'provider', p_provider,
        'providerEventId', p_provider_event_id,
        'providerPayoutReference', p_provider_payout_reference
      )
    );
  else
    update dastak_v1.royalty_withdrawal_attempts attempt
    set status = 'FAILED', failure_code = pg_catalog.btrim(p_failure_code),
        completed_at = pg_catalog.clock_timestamp()
    where attempt.id = v_attempt.id;
    update dastak_v1.royalty_withdrawals withdrawal
    set status = 'FAILED_RETRYABLE', failed_at = pg_catalog.clock_timestamp(),
        latest_failure_code = pg_catalog.btrim(p_failure_code),
        version = withdrawal.version + 1
    where withdrawal.id = v_withdrawal.id
    returning * into v_withdrawal;
    v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
      v_attempt.id::text || ':WITHDRAWAL_RELEASE',
      'WITHDRAWAL_RELEASE', v_withdrawal.amount_paise,
      'PAYOUT_CLEARING', null, null,
      dastak_v1_api.royalty_account_code(v_withdrawal.subject_type),
      v_withdrawal.subject_type, v_withdrawal.subject_id,
      null, null, null, null, null, null, v_withdrawal.id, null,
      'Failed payout attempt released the reserved Royalty without losing funds.',
      pg_catalog.jsonb_build_object(
        'withdrawalId', v_withdrawal.id,
        'attemptId', v_attempt.id,
        'provider', p_provider,
        'providerEventId', p_provider_event_id,
        'failureCode', p_failure_code,
        'retryable', true
      )
    );
  end if;
  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    case when p_outcome = 'PAID' then 'ROYALTY_WITHDRAWAL_PAID'
      else 'ROYALTY_WITHDRAWAL_FAILED_RETRYABLE' end,
    'royalty_withdrawal', v_withdrawal.id,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt.id, 'provider', p_provider,
      'providerEventId', p_provider_event_id,
      'providerPayoutReference', p_provider_payout_reference,
      'failureCode', p_failure_code,
      'financialTransactionId', v_transaction_id
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, payload
  ) values (
    v_withdrawal.id::text || ':ROYALTY_WITHDRAWAL_' || p_outcome || ':'
      || v_withdrawal.version::text,
    'ROYALTY_WITHDRAWAL', v_withdrawal.id, v_withdrawal.version,
    'ROYALTY_WITHDRAWAL_' || p_outcome,
    pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id,
      'amountPaise', v_withdrawal.amount_paise,
      'currency', v_withdrawal.currency_code,
      'provider', p_provider,
      'providerPayoutReference', p_provider_payout_reference,
      'failureCode', p_failure_code,
      'retryable', p_outcome = 'FAILED'
    )
  );
  return pg_catalog.jsonb_build_object(
    'withdrawalId', v_withdrawal.id, 'status', v_withdrawal.status,
    'providerPayoutReference', v_withdrawal.provider_payout_reference,
    'failureCode', v_withdrawal.latest_failure_code,
    'version', v_withdrawal.version, 'replayed', false
  );
end;
$$;

create function public.dastak_v1_record_royalty_withdrawal_result(
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_provider text,
  p_provider_event_id text,
  p_outcome text,
  p_provider_payout_reference text,
  p_failure_code text,
  p_request_digest text,
  p_response_body jsonb,
  p_occurred_at timestamptz
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.record_royalty_withdrawal_result(
    p_withdrawal_id, p_attempt_id, p_provider, p_provider_event_id,
    p_outcome, p_provider_payout_reference, p_failure_code,
    p_request_digest, p_response_body, p_occurred_at
  );
$$;

create function dastak_v1_api.create_royalty_adjustment(
  p_actor_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_order_id uuid,
  p_fulfilment_id uuid,
  p_delivery_mission_id uuid,
  p_refund_id uuid,
  p_signed_amount_paise bigint,
  p_reason text,
  p_authorization_reference text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_type dastak_v1.settlement_subject_type;
  v_entry_type dastak_v1.settlement_entry_type;
  v_entry dastak_v1.settlement_entries%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
begin
  if p_actor_id is null or not exists (
    select 1 from public.accounts account where account.id = p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if not dastak_v1_api.actor_has_platform_permission(
    p_actor_id, 'platform.royalty.adjust'
  ) then
    raise exception using errcode = '42501', message = 'platform permission required';
  end if;
  begin
    v_subject_type := p_subject_type::dastak_v1.settlement_subject_type;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid Royalty subject';
  end;
  if p_order_id is null or p_signed_amount_paise is null
    or p_signed_amount_paise = 0
    or nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_authorization_reference), '') is null
    or pg_catalog.char_length(p_authorization_reference) > 200
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid Royalty adjustment';
  end if;
  if v_subject_type = 'MERCHANT_ORGANIZATION' and not exists (
    select 1 from dastak_v1.fulfilments fulfilment
    where fulfilment.id = p_fulfilment_id
      and fulfilment.order_id = p_order_id
      and fulfilment.organization_id = p_subject_id
  ) then
    raise exception using errcode = '23503', message = 'merchant adjustment source mismatch';
  elsif v_subject_type = 'RIDER' and not exists (
    select 1 from dastak_v1.delivery_missions mission
    where mission.id = p_delivery_mission_id
      and mission.order_id = p_order_id
      and mission.assigned_rider_id = p_subject_id
  ) then
    raise exception using errcode = '23503', message = 'rider adjustment source mismatch';
  end if;
  if p_refund_id is not null and not exists (
    select 1 from dastak_v1.refunds refund
    where refund.id = p_refund_id and refund.order_id = p_order_id
  ) then
    raise exception using errcode = '23503', message = 'refund adjustment source mismatch';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'subjectType', v_subject_type, 'subjectId', p_subject_id,
    'orderId', p_order_id, 'fulfilmentId', p_fulfilment_id,
    'deliveryMissionId', p_delivery_mission_id, 'refundId', p_refund_id,
    'signedAmountPaise', p_signed_amount_paise,
    'reason', pg_catalog.btrim(p_reason),
    'authorizationReference', pg_catalog.btrim(p_authorization_reference)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':createRoyaltyAdjustment:' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = 'createRoyaltyAdjustment'
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  v_entry_type := case when p_signed_amount_paise < 0
    then 'DEBIT_ADJUSTMENT'::dastak_v1.settlement_entry_type
    else 'CREDIT_ADJUSTMENT'::dastak_v1.settlement_entry_type end;
  insert into dastak_v1.settlement_entries (
    entry_key, subject_type, subject_id, order_id, fulfilment_id,
    delivery_mission_id, refund_id, entry_type, status,
    calculation_status, gross_amount_paise, amount_paise,
    calculation_snapshot, eligible_at
  ) values (
    'ROYALTY_ADJUSTMENT:' || gen_random_uuid()::text,
    v_subject_type, p_subject_id, p_order_id, p_fulfilment_id,
    p_delivery_mission_id, p_refund_id, v_entry_type, 'ELIGIBLE',
    'CALCULATED', abs(p_signed_amount_paise), p_signed_amount_paise,
    pg_catalog.jsonb_build_object(
      'reason', pg_catalog.btrim(p_reason),
      'authorizationReference', pg_catalog.btrim(p_authorization_reference),
      'authorizedBy', p_actor_id,
      'orderId', p_order_id,
      'fulfilmentId', p_fulfilment_id,
      'missionId', p_delivery_mission_id,
      'refundId', p_refund_id,
      'historicalEarningsAndWithdrawalsPreserved', true
    ), pg_catalog.clock_timestamp()
  ) returning * into v_entry;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'ROYALTY_ADJUSTMENT_AUTHORIZED', 'settlement_entry', v_entry.id,
    pg_catalog.jsonb_build_object(
      'subjectType', v_subject_type, 'subjectId', p_subject_id,
      'orderId', p_order_id, 'fulfilmentId', p_fulfilment_id,
      'missionId', p_delivery_mission_id, 'refundId', p_refund_id,
      'signedAmountPaise', p_signed_amount_paise,
      'reason', pg_catalog.btrim(p_reason),
      'authorizationReference', pg_catalog.btrim(p_authorization_reference)
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'adjustmentId', v_entry.id,
    'subjectType', v_subject_type, 'subjectId', p_subject_id,
    'amountPaise', v_entry.amount_paise, 'currency', v_entry.currency_code,
    'status', v_entry.status, 'createdAt', v_entry.created_at
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, 'createRoyaltyAdjustment', p_idempotency_key,
    v_hash, v_response, 200, v_entry.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_create_royalty_adjustment(
  p_account_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_order_id uuid,
  p_fulfilment_id uuid,
  p_delivery_mission_id uuid,
  p_refund_id uuid,
  p_signed_amount_paise bigint,
  p_reason text,
  p_authorization_reference text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.create_royalty_adjustment(
    p_account_id, p_subject_type, p_subject_id, p_order_id,
    p_fulfilment_id, p_delivery_mission_id, p_refund_id,
    p_signed_amount_paise, p_reason, p_authorization_reference,
    p_idempotency_key
  );
$$;

create or replace function dastak_v1_api.settle_entry(
  p_actor_id uuid,
  p_settlement_entry_id uuid,
  p_settlement_reference text,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.settlements.manage'
  );
  raise exception using
    errcode = '55000',
    message = 'ROYALTY_WITHDRAWAL_REQUIRED',
    detail = 'Eligible Royalty must be withdrawn through the reserved, idempotent withdrawal domain.';
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_pre_royalty;

create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trace jsonb;
begin
  v_trace := dastak_v1_api.admin_execution_trace_pre_royalty(
    p_actor_id, p_order_id
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace, '{failureAndFinance,platformFees}', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', transaction.id,
        'type', transaction.transaction_type,
        'amountPaise', transaction.amount_paise,
        'paymentId', transaction.payment_id,
        'refundId', transaction.refund_id,
        'reason', transaction.reason,
        'createdAt', transaction.created_at
      ) order by transaction.created_at, transaction.id)
      from dastak_v1.financial_journal_transactions transaction
      where transaction.order_id = p_order_id
        and transaction.transaction_type in (
          'PLATFORM_FEE_RECOGNITION', 'PLATFORM_FEE_REFUND_ADJUSTMENT'
        )
    ), '[]'::jsonb), true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace, '{failureAndFinance,royaltyLedger}', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', transaction.id,
        'type', transaction.transaction_type,
        'subjectType', line.subject_type,
        'subjectId', line.subject_id,
        'amountPaise', case line.direction when 'CREDIT'
          then line.amount_paise else -line.amount_paise end,
        'fulfilmentId', transaction.fulfilment_id,
        'missionId', transaction.delivery_mission_id,
        'refundId', transaction.refund_id,
        'withdrawalId', transaction.withdrawal_id,
        'reason', transaction.reason,
        'createdAt', transaction.created_at
      ) order by transaction.created_at, transaction.id)
      from dastak_v1.financial_journal_transactions transaction
      join dastak_v1.financial_journal_lines line
        on line.transaction_id = transaction.id
       and line.subject_type is not null
      where transaction.order_id = p_order_id
    ), '[]'::jsonb), true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace, '{failureAndFinance,royaltyBalances}', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'subjectType', subject.subject_type,
        'subjectId', subject.subject_id,
        'balancePaise', dastak_v1_api.royalty_balance_paise(
          subject.subject_type, subject.subject_id
        ),
        'availablePaise', greatest(dastak_v1_api.royalty_balance_paise(
          subject.subject_type, subject.subject_id
        ), 0),
        'negativeBalancePaise', greatest(-dastak_v1_api.royalty_balance_paise(
          subject.subject_type, subject.subject_id
        ), 0)
      ) order by subject.subject_type, subject.subject_id)
      from (
        select distinct line.subject_type, line.subject_id
        from dastak_v1.financial_journal_transactions transaction
        join dastak_v1.financial_journal_lines line
          on line.transaction_id = transaction.id
        where transaction.order_id = p_order_id
          and line.subject_type is not null
      ) subject
    ), '[]'::jsonb), true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace, '{failureAndFinance,withdrawals}', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', withdrawal.id,
        'subjectType', withdrawal.subject_type,
        'subjectId', withdrawal.subject_id,
        'amountPaise', withdrawal.amount_paise,
        'status', withdrawal.status,
        'destination', pg_catalog.jsonb_build_object(
          'type', withdrawal.destination_snapshot ->> 'type',
          'provider', withdrawal.destination_snapshot ->> 'provider',
          'displayLabel', withdrawal.destination_snapshot ->> 'displayLabel'
        ),
        'providerPayoutReference', withdrawal.provider_payout_reference,
        'requestedAt', withdrawal.requested_at,
        'processingAt', withdrawal.processing_at,
        'paidAt', withdrawal.paid_at,
        'failedAt', withdrawal.failed_at,
        'failureCode', withdrawal.latest_failure_code,
        'version', withdrawal.version
      ) order by withdrawal.requested_at, withdrawal.id)
      from dastak_v1.royalty_withdrawals withdrawal
      where (
        withdrawal.subject_type = 'MERCHANT_ORGANIZATION' and exists (
          select 1 from dastak_v1.settlement_entries entry
          where entry.order_id = p_order_id
            and entry.subject_type = withdrawal.subject_type
            and entry.subject_id = withdrawal.subject_id
        )
      ) or (
        withdrawal.subject_type = 'RIDER' and exists (
          select 1 from dastak_v1.delivery_missions mission
          where mission.order_id = p_order_id
            and mission.assigned_rider_id = withdrawal.subject_id
        )
      )
    ), '[]'::jsonb), true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace, '{failureAndFinance,permissions,canManageRoyaltyAdjustments}',
    pg_catalog.to_jsonb(dastak_v1_api.actor_has_platform_permission(
      p_actor_id, 'platform.royalty.adjust'
    )), true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace, '{failureAndFinance,permissions,canManageWithdrawals}',
    pg_catalog.to_jsonb(dastak_v1_api.actor_has_platform_permission(
      p_actor_id, 'platform.withdrawals.manage'
    )), true
  );
  return v_trace;
end;
$$;

-- Additive backfill for V1 history already present when this migration is
-- applied. Source milestones remain immutable and transaction keys make the
-- backfill safe to rerun without fabricating duplicate financial facts.
do $$
declare
  v_event record;
  v_entry record;
  v_fee bigint;
  v_transaction_id uuid;
begin
  for v_event in
    select event.*, payment.amount_paise as paid_total_paise,
      payment.id as paid_payment_id, snapshot.id as paid_snapshot_id
    from dastak_v1.payment_provider_events event
    join dastak_v1.payments payment on payment.id = event.payment_id
    join dastak_v1.order_price_snapshots snapshot
      on snapshot.order_id = event.order_id and snapshot.snapshot_kind = 'PAID'
    where event.outcome = 'SUCCEEDED' and payment.status = 'SUCCEEDED'
      and snapshot.total_paise = payment.amount_paise
    order by event.processed_at, event.provider, event.provider_event_id
  loop
    v_fee := dastak_v1_api.calculate_platform_fee(v_event.paid_total_paise);
    v_transaction_id := dastak_v1_api.post_balanced_financial_transaction(
      v_event.order_id::text || ':PLATFORM_FEE',
      'PLATFORM_FEE_RECOGNITION', v_fee,
      'PAYMENT_CLEARING_ALLOCATION', null, null,
      'PLATFORM_FEE_REVENUE', null, null,
      v_event.order_id, null, null, v_event.paid_payment_id,
      null, null, null, null,
      'Locked 2% platform-fee revenue backfilled from immutable V1 payment history.',
      pg_catalog.jsonb_build_object(
        'paidTotalPaise', v_event.paid_total_paise,
        'platformFeeBps', 200,
        'rounding', 'HALF_UP_TO_PAISE',
        'platformFeePaise', v_fee,
        'paymentSnapshotId', v_event.paid_snapshot_id,
        'provider', v_event.provider,
        'providerEventId', v_event.provider_event_id,
        'backfilledFromAuthoritativeHistory', true,
        'checkoutPriceUnchanged', true
      )
    );
  end loop;
  perform pg_catalog.set_config(
    'dastak_v1.settlement_reason',
    'Verified historical Merchant-to-Rider custody credited Merchant Royalty.', true
  );
  update dastak_v1.settlement_entries entry
  set status = 'ELIGIBLE', eligible_at = coalesce(
        entry.eligible_at, handoff.consumed_at, pg_catalog.clock_timestamp()
      ),
      version = entry.version + 1
  from dastak_v1.fulfilments fulfilment,
    lateral (
      select verification.consumed_at
      from dastak_v1.verification_handoffs verification
      where verification.fulfilment_id = fulfilment.id
        and verification.handoff_type = 'MERCHANT_TO_RIDER'
        and verification.status = 'CONSUMED'
      order by verification.consumed_at desc
      limit 1
    ) handoff
  where entry.fulfilment_id = fulfilment.id
    and entry.subject_type = 'MERCHANT_ORGANIZATION'
    and entry.entry_type = 'EARNING'
    and entry.calculation_status = 'CALCULATED'
    and entry.status = 'PENDING'
    and dastak_v1_api.royalty_earning_milestone_proven(entry.id);
  for v_entry in
    select entry.id
    from dastak_v1.settlement_entries entry
    where entry.calculation_status = 'CALCULATED'
      and entry.status in ('ELIGIBLE', 'SETTLED')
      and (
        entry.entry_type <> 'EARNING'
        or dastak_v1_api.royalty_earning_milestone_proven(entry.id)
      )
      and (
        entry.entry_type <> 'REFUND_ADJUSTMENT'
        or entry.refund_id is null
        or (
          entry.subject_type = 'MERCHANT_ORGANIZATION'
          and dastak_v1_api.resolve_merchant_refund_fulfilment(entry.refund_id)
            = entry.fulfilment_id
        )
        or (
          entry.subject_type = 'RIDER'
          and dastak_v1_api.resolve_rider_refund_mission(entry.refund_id)
            = entry.delivery_mission_id
        )
      )
    order by entry.created_at, entry.id
  loop
    perform dastak_v1_api.post_royalty_from_settlement_entry(v_entry.id);
  end loop;
end;
$$;

revoke all on function dastak_v1.guard_royalty_payout_destination()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.guard_royalty_withdrawal()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.guard_royalty_withdrawal_attempt()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.reject_financial_mutation()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.assert_financial_transaction_balanced()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.record_platform_fee_after_payment_event()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.record_platform_fee_refund_adjustment()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.normalize_royalty_adjustment_entry()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.post_royalty_when_settlement_eligible()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.credit_merchant_royalty_after_pickup()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.seed_rider_fault_adjustment()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.mark_settlements_after_delivery()
  from public, anon, authenticated, service_role;

revoke all on function dastak_v1_api.calculate_platform_fee(bigint)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.post_balanced_financial_transaction(
  text,text,bigint,text,dastak_v1.settlement_subject_type,uuid,
  text,dastak_v1.settlement_subject_type,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,jsonb
) from public, anon, authenticated;
revoke all on function dastak_v1_api.post_royalty_from_settlement_entry(uuid)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.royalty_earning_milestone_proven(uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.resolve_merchant_refund_fulfilment(uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.resolve_rider_refund_mission(uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.royalty_account_code(
  dastak_v1.settlement_subject_type
) from public, anon, authenticated;
revoke all on function dastak_v1_api.royalty_balance_paise(
  dastak_v1.settlement_subject_type, uuid
) from public, anon, authenticated;
revoke all on function dastak_v1_api.actor_can_manage_royalty_subject(
  uuid, dastak_v1.settlement_subject_type, uuid, boolean
) from public, anon, authenticated;
revoke all on function dastak_v1_api.royalty_subject_snapshot(
  uuid, dastak_v1.settlement_subject_type, uuid
) from public, anon, authenticated;
revoke all on function dastak_v1_api.get_royalty_snapshot(uuid, text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.register_royalty_payout_destination(
  uuid,text,uuid,text,text,text,text,jsonb
) from public, anon, authenticated;
revoke all on function dastak_v1_api.request_royalty_withdrawal(
  uuid,text,uuid,bigint,text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.start_royalty_withdrawal(
  uuid,uuid,bigint,text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.record_royalty_withdrawal_result(
  uuid,uuid,text,text,text,text,text,text,jsonb,timestamptz
) from public, anon, authenticated;
revoke all on function dastak_v1_api.create_royalty_adjustment(
  uuid,text,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.settle_entry(uuid,uuid,text,bigint,text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_execution_trace_pre_royalty(uuid,uuid)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_execution_trace(uuid,uuid)
  from public, anon, authenticated;

revoke all on function public.dastak_v1_get_royalty_snapshot(uuid,text)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_register_royalty_payout_destination(
  uuid,text,uuid,text,text,text,text,jsonb
) from public, anon, authenticated;
revoke all on function public.dastak_v1_request_royalty_withdrawal(
  uuid,text,uuid,bigint,text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_start_royalty_withdrawal(
  uuid,uuid,bigint,text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_record_royalty_withdrawal_result(
  uuid,uuid,text,text,text,text,text,text,jsonb,timestamptz
) from public, anon, authenticated;
revoke all on function public.dastak_v1_create_royalty_adjustment(
  uuid,text,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text
) from public, anon, authenticated;

grant execute on function public.dastak_v1_get_royalty_snapshot(uuid,text)
  to service_role;
grant execute on function public.dastak_v1_register_royalty_payout_destination(
  uuid,text,uuid,text,text,text,text,jsonb
) to service_role;
grant execute on function public.dastak_v1_request_royalty_withdrawal(
  uuid,text,uuid,bigint,text
) to service_role;
grant execute on function public.dastak_v1_start_royalty_withdrawal(
  uuid,uuid,bigint,text
) to service_role;
grant execute on function public.dastak_v1_record_royalty_withdrawal_result(
  uuid,uuid,text,text,text,text,text,text,jsonb,timestamptz
) to service_role;
grant execute on function public.dastak_v1_create_royalty_adjustment(
  uuid,text,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text
) to service_role;
grant execute on function dastak_v1_api.get_royalty_snapshot(uuid,text)
  to service_role;
grant execute on function dastak_v1_api.register_royalty_payout_destination(
  uuid,text,uuid,text,text,text,text,jsonb
) to service_role;
grant execute on function dastak_v1_api.request_royalty_withdrawal(
  uuid,text,uuid,bigint,text
) to service_role;
grant execute on function dastak_v1_api.start_royalty_withdrawal(
  uuid,uuid,bigint,text
) to service_role;
grant execute on function dastak_v1_api.record_royalty_withdrawal_result(
  uuid,uuid,text,text,text,text,text,text,jsonb,timestamptz
) to service_role;
grant execute on function dastak_v1_api.create_royalty_adjustment(
  uuid,text,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text
) to service_role;
grant execute on function dastak_v1_api.settle_entry(uuid,uuid,text,bigint,text)
  to authenticated, service_role;
grant execute on function dastak_v1_api.admin_execution_trace(uuid,uuid)
  to service_role;

comment on table dastak_v1.financial_journal_transactions is
  'Immutable append-only financial transaction headers. Royalty balances derive only from balanced journal lines.';
comment on table dastak_v1.royalty_withdrawals is
  'Provider-independent Royalty withdrawal domain with immutable amount and payout-destination snapshot.';
comment on function dastak_v1_api.calculate_platform_fee(bigint) is
  'Locked 2% of immutable successfully-paid total, rounded half-up to whole paise; does not alter checkout pricing.';
comment on function dastak_v1_api.request_royalty_withdrawal(uuid,text,uuid,bigint,text) is
  'Transactionally reserves a positive derived Royalty balance; subject advisory locking prevents concurrent overspend.';
comment on function dastak_v1_api.record_royalty_withdrawal_result(uuid,uuid,text,text,text,text,text,text,jsonb,timestamptz) is
  'Idempotently records external payout results. Failure restores availability; success never fabricates a provider confirmation.';
