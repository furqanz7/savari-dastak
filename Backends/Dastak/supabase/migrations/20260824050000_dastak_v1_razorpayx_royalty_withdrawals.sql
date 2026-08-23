-- RazorpayX is an external payout rail only. Dastak's append-only Royalty
-- journal remains the sole balance authority.

create table dastak_v1.royalty_payout_provider_contacts (
  subject_type dastak_v1.settlement_subject_type not null,
  subject_id uuid not null,
  provider text not null default 'RAZORPAYX' check (provider = 'RAZORPAYX'),
  provider_contact_reference text not null unique check (
    provider_contact_reference ~ '^cont_[A-Za-z0-9]+$'
  ),
  provider_reference_id text not null check (
    pg_catalog.char_length(provider_reference_id) between 4 and 40
  ),
  contact_name_snapshot text not null check (
    pg_catalog.char_length(pg_catalog.btrim(contact_name_snapshot)) between 3 and 50
  ),
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  primary key (subject_type, subject_id, provider)
);
create index royalty_payout_provider_contacts_created_by_idx
  on dastak_v1.royalty_payout_provider_contacts(created_by);

create table dastak_v1.razorpayx_payouts (
  withdrawal_id uuid primary key references dastak_v1.royalty_withdrawals(id),
  attempt_id uuid not null unique references dastak_v1.royalty_withdrawal_attempts(id),
  provider_payout_reference text unique check (
    provider_payout_reference is null
    or provider_payout_reference ~ '^pout_[A-Za-z0-9]+$'
  ),
  fund_account_reference text not null check (
    fund_account_reference ~ '^fa_[A-Za-z0-9]+$'
  ),
  payout_idempotency_key text not null unique check (
    pg_catalog.char_length(payout_idempotency_key) between 4 and 36
    and payout_idempotency_key ~ '^[A-Za-z0-9_ -]+$'
  ),
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  amount_paise bigint not null check (amount_paise >= 100),
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  payout_mode text not null check (payout_mode in ('IMPS', 'UPI')),
  provider_status text not null default 'CREATING' check (provider_status in (
    'CREATING', 'SUBMISSION_RETRYABLE', 'QUEUED', 'PENDING', 'PROCESSING',
    'PROCESSED', 'FAILED', 'REVERSED', 'REJECTED', 'CANCELLED'
  )),
  reconciliation_state text not null default 'PENDING' check (
    reconciliation_state in ('PENDING', 'IN_SYNC', 'RETRYABLE', 'REVIEW_REQUIRED')
  ),
  provider_status_occurred_at timestamptz,
  provider_created_at timestamptz,
  utr text check (utr is null or pg_catalog.char_length(utr) between 1 and 120),
  status_details jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(status_details) = 'object'
  ),
  last_provider_event_id text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (payout_idempotency_key = withdrawal_id::text)
);

create table dastak_v1.razorpayx_provider_requests (
  id uuid primary key,
  withdrawal_id uuid not null references dastak_v1.royalty_withdrawals(id),
  attempt_id uuid not null references dastak_v1.royalty_withdrawal_attempts(id),
  operation text not null check (operation in ('PAYOUT_CREATE', 'PAYOUT_FETCH')),
  provider_request_key text not null check (
    pg_catalog.char_length(provider_request_key) between 4 and 36
  ),
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  outcome text not null check (outcome in ('ACCEPTED', 'REJECTED', 'UNKNOWN')),
  http_status integer check (http_status is null or http_status between 100 and 599),
  provider_payout_reference text check (
    provider_payout_reference is null
    or provider_payout_reference ~ '^pout_[A-Za-z0-9]+$'
  ),
  response_metadata jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(response_metadata) = 'object'
  ),
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default pg_catalog.now()
);
create index razorpayx_provider_requests_withdrawal_idx
  on dastak_v1.razorpayx_provider_requests(withdrawal_id, occurred_at desc, id);
create index razorpayx_provider_requests_attempt_idx
  on dastak_v1.razorpayx_provider_requests(attempt_id);

create table dastak_v1.razorpayx_provider_events (
  provider_event_id text primary key check (
    pg_catalog.char_length(provider_event_id) between 1 and 200
  ),
  source text not null check (source in ('WEBHOOK', 'API_RESPONSE', 'API_FETCH')),
  withdrawal_id uuid not null references dastak_v1.royalty_withdrawals(id),
  attempt_id uuid not null references dastak_v1.royalty_withdrawal_attempts(id),
  provider_payout_reference text not null check (
    provider_payout_reference ~ '^pout_[A-Za-z0-9]+$'
  ),
  provider_event_type text not null check (
    pg_catalog.char_length(provider_event_type) between 3 and 80
  ),
  provider_status text not null check (provider_status in (
    'QUEUED', 'PENDING', 'PROCESSING', 'PROCESSED',
    'FAILED', 'REVERSED', 'REJECTED', 'CANCELLED'
  )),
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  payload_metadata jsonb not null check (
    pg_catalog.jsonb_typeof(payload_metadata) = 'object'
  ),
  occurred_at timestamptz not null,
  processed_at timestamptz not null default pg_catalog.now(),
  application_result text not null check (application_result in (
    'APPLIED', 'METADATA_UPDATED', 'IGNORED_STALE', 'IGNORED_TERMINAL',
    'RECONCILIATION_REQUIRED'
  ))
);
create index razorpayx_provider_events_withdrawal_idx
  on dastak_v1.razorpayx_provider_events(withdrawal_id, occurred_at desc, provider_event_id);
create index razorpayx_provider_events_attempt_idx
  on dastak_v1.razorpayx_provider_events(attempt_id);

alter table dastak_v1.royalty_payout_provider_contacts enable row level security;
alter table dastak_v1.razorpayx_payouts enable row level security;
alter table dastak_v1.razorpayx_provider_requests enable row level security;
alter table dastak_v1.razorpayx_provider_events enable row level security;

revoke all on table
  dastak_v1.royalty_payout_provider_contacts,
  dastak_v1.razorpayx_payouts,
  dastak_v1.razorpayx_provider_requests,
  dastak_v1.razorpayx_provider_events
from public, anon, authenticated;
grant select on table
  dastak_v1.royalty_payout_provider_contacts,
  dastak_v1.razorpayx_payouts,
  dastak_v1.razorpayx_provider_requests,
  dastak_v1.razorpayx_provider_events
to service_role;

create trigger royalty_payout_provider_contacts_immutable
before update or delete on dastak_v1.royalty_payout_provider_contacts
for each row execute function dastak_v1.reject_financial_mutation();
create trigger razorpayx_provider_requests_immutable
before update or delete on dastak_v1.razorpayx_provider_requests
for each row execute function dastak_v1.reject_financial_mutation();
create trigger razorpayx_provider_events_immutable
before update or delete on dastak_v1.razorpayx_provider_events
for each row execute function dastak_v1.reject_financial_mutation();

create function dastak_v1.guard_razorpayx_payout()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.withdrawal_id is distinct from old.withdrawal_id
    or new.attempt_id is distinct from old.attempt_id
    or new.fund_account_reference is distinct from old.fund_account_reference
    or new.payout_idempotency_key is distinct from old.payout_idempotency_key
    or new.request_digest is distinct from old.request_digest
    or new.amount_paise is distinct from old.amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.payout_mode is distinct from old.payout_mode
    or new.created_at is distinct from old.created_at then
    raise exception 'RazorpayX payout identity cannot change';
  end if;
  if old.provider_payout_reference is not null
    and new.provider_payout_reference is distinct from old.provider_payout_reference then
    raise exception 'RazorpayX payout reference cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'RazorpayX payout version must increment exactly once';
  end if;
  if old.provider_status in ('FAILED', 'REVERSED', 'REJECTED', 'CANCELLED')
    and new.provider_status <> old.provider_status then
    raise exception 'terminal RazorpayX payout state cannot regress';
  end if;
  if old.provider_status = 'PROCESSED'
    and new.provider_status not in ('PROCESSED', 'REVERSED') then
    raise exception 'processed RazorpayX payout cannot regress';
  end if;
  if old.provider_status = 'SUBMISSION_RETRYABLE'
    and new.provider_status not in ('SUBMISSION_RETRYABLE', 'CREATING') then
    raise exception 'invalid RazorpayX submission retry transition';
  end if;
  new.updated_at := pg_catalog.clock_timestamp();
  return new;
end;
$$;
create trigger razorpayx_payouts_guard
before update on dastak_v1.razorpayx_payouts
for each row execute function dastak_v1.guard_razorpayx_payout();
create trigger razorpayx_payouts_no_delete
before delete on dastak_v1.razorpayx_payouts
for each row execute function dastak_v1.reject_financial_mutation();

create function dastak_v1.ensure_razorpayx_withdrawal_minimum()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.amount_paise < 100 and exists (
    select 1 from dastak_v1.royalty_payout_destinations destination
    where destination.id = new.payout_destination_id
      and destination.provider = 'RAZORPAYX'
  ) then
    raise exception using errcode = '23514',
      message = 'RAZORPAYX_MINIMUM_WITHDRAWAL_REQUIRED';
  end if;
  return new;
end;
$$;
create trigger royalty_withdrawals_razorpayx_minimum
before insert on dastak_v1.royalty_withdrawals
for each row execute function dastak_v1.ensure_razorpayx_withdrawal_minimum();

create unique index royalty_withdrawal_attempts_one_razorpayx_uidx
  on dastak_v1.royalty_withdrawal_attempts(withdrawal_id)
  where provider = 'RAZORPAYX';

create function dastak_v1.guard_razorpayx_attempt_creation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider = 'RAZORPAYX' and (
    new.provider_request_key <> new.withdrawal_id::text
    or pg_catalog.current_setting('dastak_v1.razorpayx_claim', true)
      is distinct from new.withdrawal_id::text
  ) then
    raise exception using errcode = '42501',
      message = 'RazorpayX attempts must use the provider adapter';
  end if;
  return new;
end;
$$;
create trigger royalty_withdrawal_attempts_razorpayx_creation_guard
before insert on dastak_v1.royalty_withdrawal_attempts
for each row execute function dastak_v1.guard_razorpayx_attempt_creation();

create function dastak_v1_api.razorpayx_destination_context(
  p_actor_id uuid,
  p_subject_type text,
  p_subject_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_subject_type dastak_v1.settlement_subject_type;
  v_contact_name text;
  v_contact dastak_v1.royalty_payout_provider_contacts%rowtype;
begin
  begin
    v_subject_type := p_subject_type::dastak_v1.settlement_subject_type;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid Royalty subject';
  end;
  if not dastak_v1_api.actor_can_manage_royalty_subject(
    p_actor_id, v_subject_type, p_subject_id, true
  ) then
    raise exception using errcode = '42501', message = 'Royalty withdrawal permission required';
  end if;
  if v_subject_type = 'MERCHANT_ORGANIZATION' then
    select organization.display_name into v_contact_name
    from dastak_v1.merchant_organizations organization
    where organization.id = p_subject_id;
  else
    select account.display_name into v_contact_name
    from public.accounts account where account.id = p_subject_id;
  end if;
  if v_contact_name is null then
    raise exception using errcode = 'P0002', message = 'Royalty subject not found';
  end if;
  v_contact_name := pg_catalog.left(
    pg_catalog.regexp_replace(pg_catalog.btrim(v_contact_name), '[^A-Za-z0-9 ._()/-]', '', 'g'),
    50
  );
  if pg_catalog.char_length(v_contact_name) < 3 then
    v_contact_name := 'Dastak Partner ' || pg_catalog.left(p_subject_id::text, 8);
  end if;
  select contact.* into v_contact
  from dastak_v1.royalty_payout_provider_contacts contact
  where contact.subject_type = v_subject_type
    and contact.subject_id = p_subject_id
    and contact.provider = 'RAZORPAYX';
  return pg_catalog.jsonb_build_object(
    'subjectType', v_subject_type,
    'subjectId', p_subject_id,
    'contactName', v_contact_name,
    'providerReferenceId', p_subject_id::text,
    'providerContactReference', v_contact.provider_contact_reference
  );
end;
$$;

create function public.dastak_v1_razorpayx_destination_context(
  p_account_id uuid,
  p_subject_type text,
  p_subject_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.razorpayx_destination_context(
    p_account_id, p_subject_type, p_subject_id
  );
$$;

create function dastak_v1_api.finalize_razorpayx_payout_destination(
  p_actor_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_destination_type text,
  p_provider_contact_reference text,
  p_provider_fund_account_reference text,
  p_provider_reference_id text,
  p_contact_name text,
  p_display_label text,
  p_destination_fingerprint text,
  p_safe_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_type dastak_v1.settlement_subject_type;
  v_existing dastak_v1.royalty_payout_provider_contacts%rowtype;
  v_result jsonb;
begin
  begin
    v_subject_type := p_subject_type::dastak_v1.settlement_subject_type;
  exception when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid Royalty subject';
  end;
  if not dastak_v1_api.actor_can_manage_royalty_subject(
    p_actor_id, v_subject_type, p_subject_id, true
  ) then
    raise exception using errcode = '42501', message = 'Royalty withdrawal permission required';
  end if;
  if p_destination_type not in ('BANK_ACCOUNT', 'UPI')
    or p_provider_contact_reference !~ '^cont_[A-Za-z0-9]+$'
    or p_provider_fund_account_reference !~ '^fa_[A-Za-z0-9]+$'
    or pg_catalog.char_length(p_provider_reference_id) not between 4 and 40
    or pg_catalog.char_length(pg_catalog.btrim(p_contact_name)) not between 3 and 50
    or p_destination_fingerprint !~ '^[0-9a-f]{64}$'
    or pg_catalog.jsonb_typeof(p_safe_metadata) <> 'object'
    or p_safe_metadata ?| array[
      'accountNumber', 'account_number', 'vpa', 'upiVpa', 'raw', 'secret'
    ] then
    raise exception using errcode = '22023', message = 'invalid RazorpayX destination';
  end if;
  if p_destination_type = 'BANK_ACCOUNT' and not (
    p_safe_metadata ? 'last4' and p_safe_metadata ? 'ifsc'
    and p_safe_metadata ->> 'last4' ~ '^[0-9]{4}$'
    and p_safe_metadata ->> 'ifsc' ~ '^[A-Z]{4}0[A-Z0-9]{6}$'
  ) then
    raise exception using errcode = '22023', message = 'invalid bank destination metadata';
  end if;
  if p_destination_type = 'UPI' and not (
    p_safe_metadata ? 'maskedAddress'
    and pg_catalog.char_length(p_safe_metadata ->> 'maskedAddress') between 3 and 120
  ) then
    raise exception using errcode = '22023', message = 'invalid UPI destination metadata';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-razorpayx-contact:' || v_subject_type::text || ':' || p_subject_id::text, 0
  ));
  select contact.* into v_existing
  from dastak_v1.royalty_payout_provider_contacts contact
  where contact.subject_type = v_subject_type
    and contact.subject_id = p_subject_id and contact.provider = 'RAZORPAYX';
  if found and (
    v_existing.provider_contact_reference <> p_provider_contact_reference
    or v_existing.provider_reference_id <> p_provider_reference_id
  ) then
    raise exception using errcode = '22023', message = 'RazorpayX contact collision';
  end if;
  if not found then
    insert into dastak_v1.royalty_payout_provider_contacts (
      subject_type, subject_id, provider, provider_contact_reference,
      provider_reference_id, contact_name_snapshot, created_by
    ) values (
      v_subject_type, p_subject_id, 'RAZORPAYX', p_provider_contact_reference,
      p_provider_reference_id, pg_catalog.btrim(p_contact_name), p_actor_id
    );
  end if;
  v_result := dastak_v1_api.register_royalty_payout_destination(
    p_actor_id, v_subject_type::text, p_subject_id, p_destination_type,
    'RAZORPAYX', p_provider_fund_account_reference,
    pg_catalog.btrim(p_display_label),
    pg_catalog.jsonb_build_object(
      'providerContactReference', p_provider_contact_reference,
      'providerFundAccountReference', p_provider_fund_account_reference,
      'destinationFingerprint', p_destination_fingerprint,
      'safeMetadata', p_safe_metadata,
      'rawBankOrVpaStored', false
    )
  );
  return v_result || pg_catalog.jsonb_build_object(
    'type', p_destination_type,
    'displayLabel', pg_catalog.btrim(p_display_label)
  );
end;
$$;

create function public.dastak_v1_finalize_razorpayx_payout_destination(
  p_account_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_destination_type text,
  p_provider_contact_reference text,
  p_provider_fund_account_reference text,
  p_provider_reference_id text,
  p_contact_name text,
  p_display_label text,
  p_destination_fingerprint text,
  p_safe_metadata jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.finalize_razorpayx_payout_destination(
    p_account_id, p_subject_type, p_subject_id, p_destination_type,
    p_provider_contact_reference, p_provider_fund_account_reference,
    p_provider_reference_id, p_contact_name, p_display_label,
    p_destination_fingerprint, p_safe_metadata
  );
$$;

create function dastak_v1_api.claim_razorpayx_withdrawal(
  p_actor_id uuid,
  p_withdrawal_id uuid,
  p_expected_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_attempt dastak_v1.royalty_withdrawal_attempts%rowtype;
  v_payout dastak_v1.razorpayx_payouts%rowtype;
  v_balance bigint;
  v_mode text;
  v_digest text;
begin
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.id = p_withdrawal_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'withdrawal not found';
  end if;
  if not (
    dastak_v1_api.actor_can_manage_royalty_subject(
      p_actor_id, v_withdrawal.subject_type, v_withdrawal.subject_id, true
    ) or dastak_v1_api.actor_has_platform_permission(
      p_actor_id, 'platform.withdrawals.manage'
    )
  ) then
    raise exception using errcode = '42501', message = 'Royalty withdrawal permission required';
  end if;
  if v_withdrawal.destination_snapshot ->> 'provider' <> 'RAZORPAYX'
    or v_withdrawal.destination_snapshot ->> 'providerDestinationReference'
      !~ '^fa_[A-Za-z0-9]+$' then
    raise exception using errcode = '55000', message = 'RAZORPAYX_DESTINATION_REQUIRED';
  end if;
  if v_withdrawal.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'STALE_WITHDRAWAL_VERSION';
  end if;
  if v_withdrawal.status not in ('REQUESTED', 'PROCESSING', 'FAILED_RETRYABLE') then
    raise exception using errcode = '55000', message = 'PAYOUT_ATTEMPT_ALREADY_FINAL';
  end if;
  select payout.* into v_payout
  from dastak_v1.razorpayx_payouts payout
  where payout.withdrawal_id = v_withdrawal.id
  for update;
  if found and (
    v_payout.provider_payout_reference is not null
    and v_payout.provider_status in ('PROCESSED','FAILED','REVERSED','REJECTED','CANCELLED')
  ) then
    raise exception using errcode = '55000', message = 'RAZORPAYX_PAYOUT_TERMINAL';
  end if;
  if v_withdrawal.status = 'REQUESTED' then
    update dastak_v1.royalty_withdrawals withdrawal
    set status = 'PROCESSING', processing_at = pg_catalog.clock_timestamp(),
        version = withdrawal.version + 1
    where withdrawal.id = v_withdrawal.id
    returning * into v_withdrawal;
    perform pg_catalog.set_config(
      'dastak_v1.razorpayx_claim', v_withdrawal.id::text, true
    );
    insert into dastak_v1.royalty_withdrawal_attempts (
      withdrawal_id, attempt_number, provider, provider_request_key, started_by
    ) values (
      v_withdrawal.id, 1, 'RAZORPAYX', v_withdrawal.id::text,
      v_withdrawal.requested_by
    ) returning * into v_attempt;
    v_mode := case v_withdrawal.destination_snapshot ->> 'type'
      when 'UPI' then 'UPI' else 'IMPS' end;
    v_digest := pg_catalog.encode(extensions.digest(
      pg_catalog.convert_to(pg_catalog.jsonb_build_object(
        'withdrawalId', v_withdrawal.id,
        'fundAccountReference',
          v_withdrawal.destination_snapshot ->> 'providerDestinationReference',
        'amountPaise', v_withdrawal.amount_paise,
        'currency', v_withdrawal.currency_code,
        'mode', v_mode,
        'purpose', 'payout'
      )::text, 'UTF8'), 'sha256'
    ), 'hex');
    insert into dastak_v1.razorpayx_payouts (
      withdrawal_id, attempt_id, fund_account_reference,
      payout_idempotency_key, request_digest, amount_paise,
      currency_code, payout_mode
    ) values (
      v_withdrawal.id, v_attempt.id,
      v_withdrawal.destination_snapshot ->> 'providerDestinationReference',
      v_withdrawal.id::text, v_digest, v_withdrawal.amount_paise,
      v_withdrawal.currency_code, v_mode
    ) returning * into v_payout;
  elsif not found then
    raise exception using errcode = '55000', message = 'RAZORPAYX_PAYOUT_STATE_MISSING';
  elsif v_withdrawal.status = 'FAILED_RETRYABLE' then
    if v_payout.provider_payout_reference is not null
      or v_payout.provider_status <> 'SUBMISSION_RETRYABLE' then
      raise exception using errcode = '55000', message = 'RAZORPAYX_PAYOUT_TERMINAL';
    end if;
    v_balance := dastak_v1_api.royalty_balance_paise(
      v_withdrawal.subject_type, v_withdrawal.subject_id
    );
    if v_balance < v_withdrawal.amount_paise then
      raise exception using errcode = '23514',
        message = 'WITHDRAWAL_RETRY_EXCEEDS_AVAILABLE_ROYALTY';
    end if;
    perform dastak_v1_api.post_balanced_financial_transaction(
      v_withdrawal.id::text || ':RAZORPAYX_RETRY_RESERVATION:'
        || (v_payout.version + 1)::text,
      'WITHDRAWAL_RESERVATION', v_withdrawal.amount_paise,
      dastak_v1_api.royalty_account_code(v_withdrawal.subject_type),
      v_withdrawal.subject_type, v_withdrawal.subject_id,
      'PAYOUT_CLEARING', null, null,
      null, null, null, null, null, null, v_withdrawal.id, p_actor_id,
      'Royalty re-reserved for the same idempotent RazorpayX payout.',
      pg_catalog.jsonb_build_object(
        'withdrawalId', v_withdrawal.id,
        'sameExternalPayout', true,
        'payoutIdempotencyKey', v_withdrawal.id::text
      )
    );
    update dastak_v1.royalty_withdrawals withdrawal
    set status = 'PROCESSING', failed_at = null, latest_failure_code = null,
        version = withdrawal.version + 1
    where withdrawal.id = v_withdrawal.id
    returning * into v_withdrawal;
    update dastak_v1.razorpayx_payouts payout
    set provider_status = 'CREATING', reconciliation_state = 'PENDING',
        version = payout.version + 1
    where payout.withdrawal_id = v_withdrawal.id
    returning * into v_payout;
  else
    select attempt.* into strict v_attempt
    from dastak_v1.royalty_withdrawal_attempts attempt
    where attempt.id = v_payout.attempt_id;
  end if;
  if v_attempt.id is null then
    select attempt.* into strict v_attempt
    from dastak_v1.royalty_withdrawal_attempts attempt
    where attempt.id = v_payout.attempt_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'withdrawalId', v_withdrawal.id,
    'attemptId', v_attempt.id,
    'subjectType', v_withdrawal.subject_type,
    'subjectId', v_withdrawal.subject_id,
    'amountPaise', v_withdrawal.amount_paise,
    'currency', v_withdrawal.currency_code,
    'fundAccountReference', v_payout.fund_account_reference,
    'payoutMode', v_payout.payout_mode,
    'payoutIdempotencyKey', v_payout.payout_idempotency_key,
    'requestDigest', v_payout.request_digest,
    'providerPayoutReference', v_payout.provider_payout_reference,
    'providerStatus', v_payout.provider_status,
    'status', v_withdrawal.status,
    'version', v_withdrawal.version
  );
end;
$$;

create function public.dastak_v1_claim_razorpayx_withdrawal(
  p_account_id uuid,
  p_withdrawal_id uuid,
  p_expected_version bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.claim_razorpayx_withdrawal(
    p_account_id, p_withdrawal_id, p_expected_version
  );
$$;

create function dastak_v1_api.record_razorpayx_provider_request(
  p_request_id uuid,
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_operation text,
  p_request_key text,
  p_request_digest text,
  p_outcome text,
  p_http_status integer,
  p_provider_payout_reference text,
  p_response_metadata jsonb,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing dastak_v1.razorpayx_provider_requests%rowtype;
begin
  if p_operation not in ('PAYOUT_CREATE', 'PAYOUT_FETCH')
    or p_outcome not in ('ACCEPTED', 'REJECTED', 'UNKNOWN')
    or p_request_digest !~ '^[0-9a-f]{64}$'
    or pg_catalog.jsonb_typeof(p_response_metadata) <> 'object'
    or p_occurred_at is null then
    raise exception using errcode = '22023', message = 'invalid RazorpayX request result';
  end if;
  insert into dastak_v1.razorpayx_provider_requests (
    id, withdrawal_id, attempt_id, operation, provider_request_key,
    request_digest, outcome, http_status, provider_payout_reference,
    response_metadata, occurred_at
  ) values (
    p_request_id, p_withdrawal_id, p_attempt_id, p_operation, p_request_key,
    p_request_digest, p_outcome, p_http_status, p_provider_payout_reference,
    p_response_metadata, p_occurred_at
  ) on conflict (id) do nothing;
  if not found then
    select request.* into strict v_existing
    from dastak_v1.razorpayx_provider_requests request
    where request.id = p_request_id;
    if v_existing.withdrawal_id <> p_withdrawal_id
      or (p_attempt_id is not null and v_existing.attempt_id <> p_attempt_id)
      or v_existing.operation <> p_operation
      or v_existing.provider_request_key <> p_request_key
      or v_existing.request_digest <> p_request_digest
      or v_existing.outcome <> p_outcome
      or v_existing.http_status is distinct from p_http_status
      or v_existing.provider_payout_reference is distinct from p_provider_payout_reference
      or v_existing.response_metadata <> p_response_metadata then
      raise exception using errcode = '22023', message = 'RazorpayX request collision';
    end if;
    return pg_catalog.jsonb_build_object('requestId', p_request_id, 'replayed', true);
  end if;
  return pg_catalog.jsonb_build_object('requestId', p_request_id, 'replayed', false);
end;
$$;

create function public.dastak_v1_record_razorpayx_provider_request(
  p_request_id uuid,
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_operation text,
  p_request_key text,
  p_request_digest text,
  p_outcome text,
  p_http_status integer,
  p_provider_payout_reference text,
  p_response_metadata jsonb,
  p_occurred_at timestamptz
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.record_razorpayx_provider_request(
    p_request_id, p_withdrawal_id, p_attempt_id, p_operation,
    p_request_key, p_request_digest, p_outcome, p_http_status,
    p_provider_payout_reference, p_response_metadata, p_occurred_at
  );
$$;

create function dastak_v1_api.mark_razorpayx_submission_retryable(
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_request_id uuid,
  p_failure_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_payout dastak_v1.razorpayx_payouts%rowtype;
begin
  if nullif(pg_catalog.btrim(p_failure_code), '') is null then
    raise exception using errcode = '22023', message = 'invalid RazorpayX failure';
  end if;
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.id = p_withdrawal_id for update;
  select payout.* into v_payout
  from dastak_v1.razorpayx_payouts payout
  where payout.withdrawal_id = p_withdrawal_id
    and payout.attempt_id = p_attempt_id for update;
  if v_withdrawal.id is null or v_payout.withdrawal_id is null then
    raise exception using errcode = 'P0002', message = 'RazorpayX payout not found';
  end if;
  if v_withdrawal.status = 'FAILED_RETRYABLE'
    and v_payout.provider_status = 'SUBMISSION_RETRYABLE' then
    return pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id, 'status', v_withdrawal.status,
      'providerStatus', v_payout.provider_status, 'replayed', true
    );
  end if;
  if v_withdrawal.status <> 'PROCESSING'
    or v_payout.provider_payout_reference is not null
    or v_payout.provider_status not in ('CREATING', 'SUBMISSION_RETRYABLE') then
    raise exception using errcode = '55000', message = 'RAZORPAYX_PAYOUT_NOT_RETRYABLE';
  end if;
  update dastak_v1.royalty_withdrawals withdrawal
  set status = 'FAILED_RETRYABLE', failed_at = pg_catalog.clock_timestamp(),
      latest_failure_code = pg_catalog.btrim(p_failure_code),
      version = withdrawal.version + 1
  where withdrawal.id = v_withdrawal.id
  returning * into v_withdrawal;
  update dastak_v1.razorpayx_payouts payout
  set provider_status = 'SUBMISSION_RETRYABLE',
      reconciliation_state = 'RETRYABLE', version = payout.version + 1
  where payout.withdrawal_id = v_withdrawal.id
  returning * into v_payout;
  perform dastak_v1_api.post_balanced_financial_transaction(
    p_request_id::text || ':RAZORPAYX_SUBMISSION_RELEASE',
    'WITHDRAWAL_RELEASE', v_withdrawal.amount_paise,
    'PAYOUT_CLEARING', null, null,
    dastak_v1_api.royalty_account_code(v_withdrawal.subject_type),
    v_withdrawal.subject_type, v_withdrawal.subject_id,
    null, null, null, null, null, null, v_withdrawal.id, null,
    'RazorpayX submission failed before a provider payout reference was established.',
    pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id,
      'requestId', p_request_id,
      'failureCode', p_failure_code,
      'sameIdempotencyKeyRequiredOnRetry', true
    )
  );
  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    'RAZORPAYX_SUBMISSION_RETRYABLE', 'royalty_withdrawal', v_withdrawal.id,
    pg_catalog.jsonb_build_object(
      'requestId', p_request_id, 'failureCode', p_failure_code,
      'RoyaltyReleased', true
    )
  );
  return pg_catalog.jsonb_build_object(
    'withdrawalId', v_withdrawal.id, 'status', v_withdrawal.status,
    'providerStatus', v_payout.provider_status,
    'version', v_withdrawal.version, 'replayed', false
  );
end;
$$;

create function public.dastak_v1_mark_razorpayx_submission_retryable(
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_request_id uuid,
  p_failure_code text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.mark_razorpayx_submission_retryable(
    p_withdrawal_id, p_attempt_id, p_request_id, p_failure_code
  );
$$;

create function dastak_v1_api.mark_razorpayx_reconciliation_required(
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_payout dastak_v1.razorpayx_payouts%rowtype;
begin
  if nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(p_reason) > 120 then
    raise exception using errcode = '22023', message = 'invalid reconciliation reason';
  end if;
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.id = p_withdrawal_id for update;
  select payout.* into v_payout
  from dastak_v1.razorpayx_payouts payout
  where payout.withdrawal_id = p_withdrawal_id
    and payout.attempt_id = p_attempt_id for update;
  if v_withdrawal.id is null or v_payout.withdrawal_id is null then
    raise exception using errcode = 'P0002', message = 'RazorpayX payout not found';
  end if;
  if v_payout.reconciliation_state = 'REVIEW_REQUIRED' then
    return pg_catalog.jsonb_build_object(
      'withdrawalId', v_withdrawal.id,
      'status', v_withdrawal.status,
      'providerStatus', v_payout.provider_status,
      'reconciliationState', v_payout.reconciliation_state,
      'retryable', false,
      'replayed', true
    );
  end if;
  update dastak_v1.razorpayx_payouts payout
  set reconciliation_state = 'REVIEW_REQUIRED',
      status_details = payout.status_details || pg_catalog.jsonb_build_object(
        'reconciliationReason', pg_catalog.btrim(p_reason),
        'providerRequestId', p_request_id
      ),
      version = payout.version + 1
  where payout.withdrawal_id = p_withdrawal_id
  returning * into v_payout;
  insert into dastak_v1.audit_events (
    action, resource_type, resource_id, metadata
  ) values (
    'RAZORPAYX_RECONCILIATION_REQUIRED', 'royalty_withdrawal', v_withdrawal.id,
    pg_catalog.jsonb_build_object(
      'attemptId', p_attempt_id,
      'providerRequestId', p_request_id,
      'reason', pg_catalog.btrim(p_reason),
      'RoyaltyRemainsReserved', v_withdrawal.status = 'PROCESSING'
    )
  );
  return pg_catalog.jsonb_build_object(
    'withdrawalId', v_withdrawal.id,
    'status', v_withdrawal.status,
    'providerStatus', v_payout.provider_status,
    'reconciliationState', v_payout.reconciliation_state,
    'retryable', false,
    'replayed', false
  );
end;
$$;

create function public.dastak_v1_mark_razorpayx_reconciliation_required(
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_request_id uuid,
  p_reason text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.mark_razorpayx_reconciliation_required(
    p_withdrawal_id, p_attempt_id, p_request_id, p_reason
  );
$$;

create function dastak_v1_api.apply_razorpayx_payout_status(
  p_provider_event_id text,
  p_source text,
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_provider_payout_reference text,
  p_provider_event_type text,
  p_provider_status text,
  p_amount_paise bigint,
  p_currency_code text,
  p_fund_account_reference text,
  p_request_digest text,
  p_payload_metadata jsonb,
  p_occurred_at timestamptz,
  p_provider_created_at timestamptz,
  p_utr text,
  p_status_details jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := pg_catalog.upper(p_provider_status);
  v_withdrawal dastak_v1.royalty_withdrawals%rowtype;
  v_attempt dastak_v1.royalty_withdrawal_attempts%rowtype;
  v_payout dastak_v1.razorpayx_payouts%rowtype;
  v_existing dastak_v1.razorpayx_provider_events%rowtype;
  v_result text := 'APPLIED';
  v_conflict boolean := false;
begin
  if p_source not in ('WEBHOOK', 'API_RESPONSE', 'API_FETCH')
    or v_status not in (
      'QUEUED','PENDING','PROCESSING','PROCESSED',
      'FAILED','REVERSED','REJECTED','CANCELLED'
    )
    or p_provider_payout_reference !~ '^pout_[A-Za-z0-9]+$'
    or nullif(pg_catalog.btrim(p_provider_event_id), '') is null
    or pg_catalog.char_length(p_provider_event_id) > 200
    or p_request_digest !~ '^[0-9a-f]{64}$'
    or pg_catalog.jsonb_typeof(p_payload_metadata) <> 'object'
    or pg_catalog.jsonb_typeof(p_status_details) <> 'object'
    or p_occurred_at is null then
    raise exception using errcode = '22023', message = 'invalid RazorpayX payout event';
  end if;
  select event.* into v_existing
  from dastak_v1.razorpayx_provider_events event
  where event.provider_event_id = p_provider_event_id;
  if found then
    if v_existing.withdrawal_id <> p_withdrawal_id
      or (p_attempt_id is not null and v_existing.attempt_id <> p_attempt_id)
      or v_existing.provider_payout_reference <> p_provider_payout_reference
      or v_existing.provider_status <> v_status
      or v_existing.request_digest <> p_request_digest then
      raise exception using errcode = '22023', message = 'RazorpayX event collision';
    end if;
    return pg_catalog.jsonb_build_object(
      'withdrawalId', p_withdrawal_id,
      'status', v_existing.provider_status,
      'applicationResult', v_existing.application_result,
      'replayed', true
    );
  end if;
  select withdrawal.* into v_withdrawal
  from dastak_v1.royalty_withdrawals withdrawal
  where withdrawal.id = p_withdrawal_id for update;
  select payout.* into v_payout
  from dastak_v1.razorpayx_payouts payout
  where payout.withdrawal_id = p_withdrawal_id
    and (p_attempt_id is null or payout.attempt_id = p_attempt_id) for update;
  if v_payout.withdrawal_id is not null then
    select attempt.* into v_attempt
    from dastak_v1.royalty_withdrawal_attempts attempt
    where attempt.id = v_payout.attempt_id
      and attempt.withdrawal_id = p_withdrawal_id
      and attempt.provider = 'RAZORPAYX' for update;
  end if;
  if v_withdrawal.id is null or v_attempt.id is null or v_payout.withdrawal_id is null then
    raise exception using errcode = 'P0002', message = 'RazorpayX withdrawal not found';
  end if;
  -- A duplicate can arrive while the first transaction is waiting on the same
  -- withdrawal lock. Recheck after locking so concurrent delivery is replay-safe.
  select event.* into v_existing
  from dastak_v1.razorpayx_provider_events event
  where event.provider_event_id = p_provider_event_id;
  if found then
    if v_existing.withdrawal_id <> p_withdrawal_id
      or (p_attempt_id is not null and v_existing.attempt_id <> p_attempt_id)
      or v_existing.provider_payout_reference <> p_provider_payout_reference
      or v_existing.provider_status <> v_status
      or v_existing.request_digest <> p_request_digest then
      raise exception using errcode = '22023', message = 'RazorpayX event collision';
    end if;
    return pg_catalog.jsonb_build_object(
      'withdrawalId', p_withdrawal_id,
      'status', v_existing.provider_status,
      'applicationResult', v_existing.application_result,
      'replayed', true
    );
  end if;
  if p_amount_paise <> v_payout.amount_paise
    or p_currency_code <> v_payout.currency_code
    or p_fund_account_reference <> v_payout.fund_account_reference
    or (v_payout.provider_payout_reference is not null
      and v_payout.provider_payout_reference <> p_provider_payout_reference) then
    raise exception using errcode = '22023', message = 'RAZORPAYX_PAYOUT_OWNERSHIP_MISMATCH';
  end if;
  if v_payout.provider_status in ('FAILED','REVERSED','REJECTED','CANCELLED') then
    if v_status = v_payout.provider_status then
      v_result := 'METADATA_UPDATED';
    elsif v_status in ('QUEUED','PENDING','PROCESSING') then
      v_result := 'IGNORED_TERMINAL';
    else
      v_result := 'RECONCILIATION_REQUIRED'; v_conflict := true;
    end if;
  elsif v_payout.provider_status = 'PROCESSED' then
    if v_status = 'REVERSED' then
      v_result := 'APPLIED';
    elsif v_status = 'PROCESSED' then
      v_result := 'METADATA_UPDATED';
    elsif v_status in ('QUEUED','PENDING','PROCESSING') then
      v_result := 'IGNORED_TERMINAL';
    else
      v_result := 'RECONCILIATION_REQUIRED'; v_conflict := true;
    end if;
  elsif v_status in ('QUEUED','PENDING','PROCESSING')
    and v_payout.provider_status_occurred_at is not null
    and p_occurred_at < v_payout.provider_status_occurred_at then
    v_result := 'IGNORED_STALE';
  end if;

  if v_result in ('APPLIED', 'METADATA_UPDATED') then
    if v_status = 'PROCESSED' and v_withdrawal.status = 'PROCESSING' then
      perform dastak_v1_api.record_royalty_withdrawal_result(
        v_withdrawal.id, v_attempt.id, 'RAZORPAYX',
        'rzpx:' || pg_catalog.left(p_provider_event_id, 150) || ':'
          || pg_catalog.left(p_request_digest, 32), 'PAID',
        p_provider_payout_reference, null, p_request_digest,
        p_payload_metadata, p_occurred_at
      );
      select withdrawal.* into strict v_withdrawal
      from dastak_v1.royalty_withdrawals withdrawal
      where withdrawal.id = p_withdrawal_id;
    elsif v_status in ('FAILED','REVERSED','REJECTED','CANCELLED')
      and v_withdrawal.status = 'PROCESSING' then
      perform dastak_v1_api.record_royalty_withdrawal_result(
        v_withdrawal.id, v_attempt.id, 'RAZORPAYX',
        'rzpx:' || pg_catalog.left(p_provider_event_id, 150) || ':'
          || pg_catalog.left(p_request_digest, 32), 'FAILED', null,
        'RAZORPAYX_' || v_status, p_request_digest,
        p_payload_metadata, p_occurred_at
      );
      select withdrawal.* into strict v_withdrawal
      from dastak_v1.royalty_withdrawals withdrawal
      where withdrawal.id = p_withdrawal_id;
    elsif v_status = 'REVERSED' and v_withdrawal.status = 'PAID' then
      perform dastak_v1_api.post_balanced_financial_transaction(
        v_withdrawal.id::text || ':RAZORPAYX_REVERSAL:'
          || p_provider_payout_reference,
        'WITHDRAWAL_RELEASE', v_withdrawal.amount_paise,
        'PAYOUT_CASH', null, null,
        dastak_v1_api.royalty_account_code(v_withdrawal.subject_type),
        v_withdrawal.subject_type, v_withdrawal.subject_id,
        null, null, null, null, null, null, v_withdrawal.id, null,
        'RazorpayX reversal restored Royalty through an append-only entry.',
        pg_catalog.jsonb_build_object(
          'withdrawalId', v_withdrawal.id,
          'providerPayoutReference', p_provider_payout_reference,
          'providerEventId', p_provider_event_id,
          'originalPaidEntryPreserved', true
        )
      );
      insert into dastak_v1.audit_events (
        action, resource_type, resource_id, metadata
      ) values (
        'ROYALTY_WITHDRAWAL_REVERSED', 'royalty_withdrawal', v_withdrawal.id,
        pg_catalog.jsonb_build_object(
          'providerPayoutReference', p_provider_payout_reference,
          'providerEventId', p_provider_event_id,
          'RoyaltyRestoredExactlyOnce', true
        )
      );
      insert into dastak_v1.domain_events_outbox (
        event_key, aggregate_type, aggregate_id, aggregate_version,
        event_type, payload
      ) values (
        v_withdrawal.id::text || ':ROYALTY_WITHDRAWAL_REVERSED:'
          || p_provider_payout_reference,
        'ROYALTY_WITHDRAWAL', v_withdrawal.id, v_withdrawal.version,
        'ROYALTY_WITHDRAWAL_REVERSED',
        pg_catalog.jsonb_build_object(
          'withdrawalId', v_withdrawal.id,
          'providerPayoutReference', p_provider_payout_reference,
          'RoyaltyRestored', true
        )
      ) on conflict (event_key) do nothing;
    end if;
    update dastak_v1.razorpayx_payouts payout
    set provider_payout_reference = coalesce(
          payout.provider_payout_reference, p_provider_payout_reference
        ),
        provider_status = v_status,
        reconciliation_state = case when v_conflict then 'REVIEW_REQUIRED'
          when v_status in ('QUEUED','PENDING','PROCESSING') then 'PENDING'
          else 'IN_SYNC' end,
        provider_status_occurred_at = case
          when payout.provider_status_occurred_at is null
            or p_occurred_at >= payout.provider_status_occurred_at
          then p_occurred_at else payout.provider_status_occurred_at end,
        provider_created_at = coalesce(payout.provider_created_at, p_provider_created_at),
        utr = coalesce(nullif(pg_catalog.btrim(p_utr), ''), payout.utr),
        status_details = p_status_details,
        last_provider_event_id = p_provider_event_id,
        version = payout.version + 1
    where payout.withdrawal_id = p_withdrawal_id
    returning * into v_payout;
  elsif v_conflict then
    update dastak_v1.razorpayx_payouts payout
    set reconciliation_state = 'REVIEW_REQUIRED',
        last_provider_event_id = p_provider_event_id,
        version = payout.version + 1
    where payout.withdrawal_id = p_withdrawal_id
    returning * into v_payout;
  end if;

  insert into dastak_v1.razorpayx_provider_events (
    provider_event_id, source, withdrawal_id, attempt_id,
    provider_payout_reference, provider_event_type, provider_status,
    request_digest, payload_metadata, occurred_at, application_result
  ) values (
    p_provider_event_id, p_source, p_withdrawal_id, v_attempt.id,
    p_provider_payout_reference, p_provider_event_type, v_status,
    p_request_digest, p_payload_metadata, p_occurred_at, v_result
  );
  return pg_catalog.jsonb_build_object(
    'withdrawalId', p_withdrawal_id,
    'domainStatus', v_withdrawal.status,
    'status', case
      when v_payout.provider_status = 'REVERSED' then 'REVERSED'
      when v_payout.provider_status in ('FAILED','REJECTED','CANCELLED') then 'FAILED'
      else v_withdrawal.status::text
    end,
    'providerStatus', v_payout.provider_status,
    'reconciliationState', v_payout.reconciliation_state,
    'applicationResult', v_result,
    'replayed', false
  );
end;
$$;

create function public.dastak_v1_apply_razorpayx_payout_status(
  p_provider_event_id text,
  p_source text,
  p_withdrawal_id uuid,
  p_attempt_id uuid,
  p_provider_payout_reference text,
  p_provider_event_type text,
  p_provider_status text,
  p_amount_paise bigint,
  p_currency_code text,
  p_fund_account_reference text,
  p_request_digest text,
  p_payload_metadata jsonb,
  p_occurred_at timestamptz,
  p_provider_created_at timestamptz,
  p_utr text,
  p_status_details jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.apply_razorpayx_payout_status(
    p_provider_event_id, p_source, p_withdrawal_id, p_attempt_id,
    p_provider_payout_reference, p_provider_event_type, p_provider_status,
    p_amount_paise, p_currency_code, p_fund_account_reference,
    p_request_digest, p_payload_metadata, p_occurred_at,
    p_provider_created_at, p_utr, p_status_details
  );
$$;

alter function dastak_v1_api.royalty_subject_snapshot(
  uuid, dastak_v1.settlement_subject_type, uuid
) rename to royalty_subject_snapshot_pre_razorpayx;

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
  v_snapshot jsonb;
  v_destination jsonb;
  v_withdrawals jsonb;
begin
  v_snapshot := dastak_v1_api.royalty_subject_snapshot_pre_razorpayx(
    p_actor_id, p_subject_type, p_subject_id
  );
  v_destination := v_snapshot -> 'payoutDestination';
  if v_destination is not null and v_destination <> 'null'::jsonb then
    v_snapshot := pg_catalog.jsonb_set(
      v_snapshot, '{payoutDestination}', v_destination - 'provider', true
    );
  end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', withdrawal.id,
    'amountPaise', withdrawal.amount_paise,
    'currency', withdrawal.currency_code,
    'status', case
      when payout.provider_status = 'REVERSED' then 'REVERSED'
      when payout.provider_status in ('FAILED','REJECTED','CANCELLED') then 'FAILED'
      else withdrawal.status::text
    end,
    'destination', pg_catalog.jsonb_build_object(
      'type', withdrawal.destination_snapshot ->> 'type',
      'displayLabel', withdrawal.destination_snapshot ->> 'displayLabel'
    ),
    'providerStatus', payout.provider_status,
    'reconciliationState', payout.reconciliation_state,
    'requestedAt', withdrawal.requested_at,
    'processingAt', withdrawal.processing_at,
    'paidAt', withdrawal.paid_at,
    'failedAt', withdrawal.failed_at,
    'failureCode', withdrawal.latest_failure_code,
    'version', withdrawal.version
  ) order by withdrawal.requested_at desc, withdrawal.id desc), '[]'::jsonb)
  into v_withdrawals
  from dastak_v1.royalty_withdrawals withdrawal
  left join dastak_v1.razorpayx_payouts payout
    on payout.withdrawal_id = withdrawal.id
  where withdrawal.subject_type = p_subject_type
    and withdrawal.subject_id = p_subject_id;
  return pg_catalog.jsonb_set(v_snapshot, '{withdrawals}', v_withdrawals, true);
end;
$$;

create function dastak_v1_api.razorpayx_admin_snapshot(
  p_actor_id uuid,
  p_limit integer default 100
)
returns table(response_body jsonb, response_status integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not dastak_v1_api.actor_has_platform_permission(
    p_actor_id, 'platform.withdrawals.manage'
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied', 'message', 'Withdrawal access is unavailable.'
      )
    );
    response_status := 403;
    return next; return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_limit', 'message', 'Invalid withdrawal limit.'
      )
    );
    response_status := 400;
    return next; return;
  end if;
  response_body := pg_catalog.jsonb_build_object(
    'withdrawals', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', withdrawal.id,
        'subjectType', withdrawal.subject_type,
        'subjectId', withdrawal.subject_id,
        'amountPaise', withdrawal.amount_paise,
        'currency', withdrawal.currency_code,
        'domainStatus', withdrawal.status,
        'effectiveStatus', case
          when payout.provider_status = 'REVERSED' then 'REVERSED'
          when payout.provider_status in ('FAILED','REJECTED','CANCELLED') then 'FAILED'
          else withdrawal.status::text
        end,
        'destinationSnapshot', pg_catalog.jsonb_build_object(
          'type', withdrawal.destination_snapshot ->> 'type',
          'displayLabel', withdrawal.destination_snapshot ->> 'displayLabel',
          'destinationVersion', withdrawal.destination_snapshot ->> 'destinationVersion',
          'providerFundAccountReference',
            withdrawal.destination_snapshot ->> 'providerDestinationReference'
        ),
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
        'attempts', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'id', attempt.id,
            'attemptNumber', attempt.attempt_number,
            'status', attempt.status,
            'providerRequestKey', attempt.provider_request_key,
            'startedAt', attempt.started_at,
            'completedAt', attempt.completed_at,
            'failureCode', attempt.failure_code
          ) order by attempt.attempt_number, attempt.id)
          from dastak_v1.royalty_withdrawal_attempts attempt
          where attempt.withdrawal_id = withdrawal.id
        ), '[]'::jsonb),
        'providerRequests', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'id', request.id,
            'operation', request.operation,
            'outcome', request.outcome,
            'httpStatus', request.http_status,
            'providerPayoutReference', request.provider_payout_reference,
            'occurredAt', request.occurred_at
          ) order by request.occurred_at, request.id)
          from dastak_v1.razorpayx_provider_requests request
          where request.withdrawal_id = withdrawal.id
        ), '[]'::jsonb),
        'webhookHistory', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'eventId', event.provider_event_id,
            'source', event.source,
            'eventType', event.provider_event_type,
            'providerStatus', event.provider_status,
            'applicationResult', event.application_result,
            'occurredAt', event.occurred_at,
            'processedAt', event.processed_at
          ) order by event.occurred_at, event.provider_event_id)
          from dastak_v1.razorpayx_provider_events event
          where event.withdrawal_id = withdrawal.id
        ), '[]'::jsonb)
      ) order by withdrawal.requested_at desc, withdrawal.id desc)
      from (
        select candidate.*
        from dastak_v1.royalty_withdrawals candidate
        order by candidate.requested_at desc, candidate.id desc
        limit p_limit
      ) withdrawal
      left join dastak_v1.razorpayx_payouts payout
        on payout.withdrawal_id = withdrawal.id
    ), '[]'::jsonb)
  );
  response_status := 200;
  return next;
end;
$$;

create function public.dastak_v1_razorpayx_admin_snapshot(
  p_account_id uuid,
  p_limit integer default 100
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select * from dastak_v1_api.razorpayx_admin_snapshot(p_account_id, p_limit);
$$;

revoke all on function dastak_v1.guard_razorpayx_payout()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.ensure_razorpayx_withdrawal_minimum()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1.guard_razorpayx_attempt_creation()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.razorpayx_destination_context(uuid,text,uuid)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.finalize_razorpayx_payout_destination(
  uuid,text,uuid,text,text,text,text,text,text,text,jsonb
) from public, anon, authenticated;
revoke all on function dastak_v1_api.claim_razorpayx_withdrawal(uuid,uuid,bigint)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.record_razorpayx_provider_request(
  uuid,uuid,uuid,text,text,text,text,integer,text,jsonb,timestamptz
) from public, anon, authenticated;
revoke all on function dastak_v1_api.mark_razorpayx_submission_retryable(
  uuid,uuid,uuid,text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.mark_razorpayx_reconciliation_required(
  uuid,uuid,uuid,text
) from public, anon, authenticated;
revoke all on function dastak_v1_api.apply_razorpayx_payout_status(
  text,text,uuid,uuid,text,text,text,bigint,text,text,text,jsonb,
  timestamptz,timestamptz,text,jsonb
) from public, anon, authenticated;
revoke all on function dastak_v1_api.royalty_subject_snapshot_pre_razorpayx(
  uuid,dastak_v1.settlement_subject_type,uuid
) from public, anon, authenticated;
revoke all on function dastak_v1_api.royalty_subject_snapshot(
  uuid,dastak_v1.settlement_subject_type,uuid
) from public, anon, authenticated;
revoke all on function dastak_v1_api.razorpayx_admin_snapshot(uuid,integer)
  from public, anon, authenticated;

revoke all on function public.dastak_v1_razorpayx_destination_context(uuid,text,uuid)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_finalize_razorpayx_payout_destination(
  uuid,text,uuid,text,text,text,text,text,text,text,jsonb
) from public, anon, authenticated;
revoke all on function public.dastak_v1_claim_razorpayx_withdrawal(uuid,uuid,bigint)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_record_razorpayx_provider_request(
  uuid,uuid,uuid,text,text,text,text,integer,text,jsonb,timestamptz
) from public, anon, authenticated;
revoke all on function public.dastak_v1_mark_razorpayx_submission_retryable(
  uuid,uuid,uuid,text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_mark_razorpayx_reconciliation_required(
  uuid,uuid,uuid,text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_apply_razorpayx_payout_status(
  text,text,uuid,uuid,text,text,text,bigint,text,text,text,jsonb,
  timestamptz,timestamptz,text,jsonb
) from public, anon, authenticated;
revoke all on function public.dastak_v1_razorpayx_admin_snapshot(uuid,integer)
  from public, anon, authenticated;

grant execute on function public.dastak_v1_razorpayx_destination_context(uuid,text,uuid)
  to service_role;
grant execute on function public.dastak_v1_finalize_razorpayx_payout_destination(
  uuid,text,uuid,text,text,text,text,text,text,text,jsonb
) to service_role;
grant execute on function public.dastak_v1_claim_razorpayx_withdrawal(uuid,uuid,bigint)
  to service_role;
grant execute on function public.dastak_v1_record_razorpayx_provider_request(
  uuid,uuid,uuid,text,text,text,text,integer,text,jsonb,timestamptz
) to service_role;
grant execute on function public.dastak_v1_mark_razorpayx_submission_retryable(
  uuid,uuid,uuid,text
) to service_role;
grant execute on function public.dastak_v1_mark_razorpayx_reconciliation_required(
  uuid,uuid,uuid,text
) to service_role;
grant execute on function public.dastak_v1_apply_razorpayx_payout_status(
  text,text,uuid,uuid,text,text,text,bigint,text,text,text,jsonb,
  timestamptz,timestamptz,text,jsonb
) to service_role;
grant execute on function public.dastak_v1_razorpayx_admin_snapshot(uuid,integer)
  to service_role;
grant execute on function dastak_v1_api.royalty_subject_snapshot(
  uuid,dastak_v1.settlement_subject_type,uuid
) to service_role;

comment on table dastak_v1.razorpayx_payouts is
  'Provider projection only. Royalty balances never derive from RazorpayX.';
comment on table dastak_v1.razorpayx_provider_events is
  'Verified, deduplicated RazorpayX payout state history with out-of-order application results.';
comment on function dastak_v1_api.claim_razorpayx_withdrawal(uuid,uuid,bigint) is
  'Claims one Dastak withdrawal for one RazorpayX payout keyed by the deterministic withdrawal UUID.';
