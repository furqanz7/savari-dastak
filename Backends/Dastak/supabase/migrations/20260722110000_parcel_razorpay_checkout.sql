create table private.parcel_payment_records (
  parcel_id uuid primary key references private.parcel_deliveries(id),
  expected_amount_paise integer not null check (expected_amount_paise > 0),
  currency text not null default 'INR' check (currency = 'INR'),
  state text not null default 'pending' check (
    state in ('pending', 'captured', 'refund_pending', 'refunded', 'failed')
  ),
  provider text check (provider is null or pg_catalog.char_length(provider) between 1 and 40),
  provider_order_reference text check (
    provider_order_reference is null or pg_catalog.char_length(provider_order_reference) between 1 and 200
  ),
  provider_payment_reference text check (
    provider_payment_reference is null or pg_catalog.char_length(provider_payment_reference) between 1 and 200
  ),
  provider_refund_reference text check (
    provider_refund_reference is null or pg_catalog.char_length(provider_refund_reference) between 1 and 200
  ),
  captured_at timestamptz,
  refunded_at timestamptz,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create unique index parcel_payment_provider_order_uidx
  on private.parcel_payment_records(provider, provider_order_reference)
  where provider is not null and provider_order_reference is not null;
create unique index parcel_payment_provider_payment_uidx
  on private.parcel_payment_records(provider, provider_payment_reference)
  where provider is not null and provider_payment_reference is not null;
create unique index parcel_payment_provider_refund_uidx
  on private.parcel_payment_records(provider, provider_refund_reference)
  where provider is not null and provider_refund_reference is not null;

alter table private.parcel_payment_records enable row level security;
revoke all on table private.parcel_payment_records from public, anon, authenticated;
grant select, insert, update on table private.parcel_payment_records to service_role;

insert into private.parcel_payment_records (
  parcel_id, expected_amount_paise, state, captured_at, refunded_at
)
select
  parcel.id,
  parcel.delivery_fee_paise,
  case parcel.payment_status
    when 'paid' then 'captured'
    when 'refund_pending' then 'refund_pending'
    when 'refunded' then 'refunded'
    when 'failed' then 'failed'
    else 'pending'
  end,
  parcel.payment_captured_at,
  case when parcel.payment_status = 'refunded' then parcel.updated_at else null end
from private.parcel_deliveries as parcel
on conflict (parcel_id) do nothing;

create function private.create_parcel_payment_record()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into private.parcel_payment_records (parcel_id, expected_amount_paise)
  values (new.id, new.delivery_fee_paise)
  on conflict (parcel_id) do nothing;
  return new;
end;
$$;

create trigger parcel_payment_record_on_create
after insert on private.parcel_deliveries
for each row execute function private.create_parcel_payment_record();

revoke execute on function private.create_parcel_payment_record()
  from public, anon, authenticated;
grant execute on function private.create_parcel_payment_record() to service_role;

create function public.get_customer_parcel_deliveries(
  p_account_id uuid,
  p_limit integer default 20
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
      'error', pg_catalog.jsonb_build_object('code', 'validation_failed', 'message', 'The parcel list request is invalid.')
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform 1 from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'customer'
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());
  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object('code', 'access_denied', 'message', 'An active Dastak customer account is required.')
    );
    response_status := 403;
    return next;
    return;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.parcel_delivery_json(selected.parcel, selected.private_audience)
        || pg_catalog.jsonb_build_object('audience', selected.public_audience)
      order by selected.sort_created_at desc
    ),
    '[]'::jsonb
  )
  into response_body
  from (
    select
      parcel,
      parcel.created_at as sort_created_at,
      case when parcel.customer_account_id = p_account_id then 'customer' else 'recipient' end as private_audience,
      case when parcel.customer_account_id = p_account_id then 'sender' else 'recipient' end as public_audience
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

create function public.prepare_parcel_razorpay_checkout(
  p_account_id uuid,
  p_parcel_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_parcel private.parcel_deliveries%rowtype;
  v_payment private.parcel_payment_records%rowtype;
begin
  select parcel.* into v_parcel
  from private.parcel_deliveries as parcel
  where parcel.id = p_parcel_id and parcel.customer_account_id = p_account_id;
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'parcel_not_found', 'message', 'The parcel was not found.'));
    response_status := 404;
    return next;
    return;
  end if;

  select payment.* into v_payment
  from private.parcel_payment_records as payment
  where payment.parcel_id = v_parcel.id
  for update;
  if v_parcel.status <> 'payment_pending' or v_parcel.payment_status <> 'pending' or v_payment.state <> 'pending' then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'invalid_parcel_transition', 'message', 'This parcel is not awaiting payment.'));
    response_status := 409;
    return next;
    return;
  end if;
  if v_payment.provider is not null and v_payment.provider <> 'razorpay' then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'provider_reference_conflict', 'message', 'This parcel uses another payment provider.'));
    response_status := 409;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'entityId', v_parcel.id,
    'providerOrderId', v_payment.provider_order_reference,
    'amountPaise', v_payment.expected_amount_paise,
    'currency', v_payment.currency,
    'receipt', 'dst_pr_' || pg_catalog.replace(v_parcel.id::text, '-', '')
  );
  response_status := 200;
  return next;
end;
$$;

create function public.attach_parcel_razorpay_order(
  p_account_id uuid,
  p_parcel_id uuid,
  p_provider_order_reference text,
  p_amount_paise bigint,
  p_currency text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_prepared record;
  v_body jsonb;
  v_reference text := pg_catalog.btrim(p_provider_order_reference);
begin
  if nullif(v_reference, '') is null or v_reference !~ '^order_[A-Za-z0-9]+$'
    or pg_catalog.char_length(v_reference) > 200 or p_amount_paise is null or p_amount_paise <= 0
    or pg_catalog.upper(pg_catalog.btrim(p_currency)) <> 'INR'
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'validation_failed', 'message', 'The Razorpay order is invalid.'));
    response_status := 400;
    return next;
    return;
  end if;

  select prepared.* into v_prepared
  from public.prepare_parcel_razorpay_checkout(p_account_id, p_parcel_id) as prepared;
  if v_prepared.response_status <> 200 then
    response_body := v_prepared.response_body;
    response_status := v_prepared.response_status;
    return next;
    return;
  end if;
  v_body := v_prepared.response_body;
  if (v_body ->> 'amountPaise')::bigint <> p_amount_paise
    or v_body ->> 'currency' <> pg_catalog.upper(pg_catalog.btrim(p_currency))
    or ((v_body ->> 'providerOrderId') is not null and v_body ->> 'providerOrderId' <> v_reference)
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'provider_reference_conflict', 'message', 'The Razorpay order does not match this parcel.'));
    response_status := 409;
    return next;
    return;
  end if;

  update private.parcel_payment_records as payment
  set provider = 'razorpay',
      provider_order_reference = coalesce(payment.provider_order_reference, v_reference),
      version = payment.version + 1,
      updated_at = pg_catalog.now()
  where payment.parcel_id = p_parcel_id;

  response_body := v_body || pg_catalog.jsonb_build_object('providerOrderId', v_reference);
  response_status := 200;
  return next;
end;
$$;

create function public.prepare_parcel_razorpay_refund(
  p_account_id uuid,
  p_parcel_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_parcel private.parcel_deliveries%rowtype;
  v_payment private.parcel_payment_records%rowtype;
  v_authorized boolean;
begin
  select parcel.* into v_parcel from private.parcel_deliveries as parcel where parcel.id = p_parcel_id;
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'parcel_not_found', 'message', 'The parcel was not found.'));
    response_status := 404;
    return next;
    return;
  end if;
  v_authorized := v_parcel.customer_account_id = p_account_id or exists (
    select 1 from private.account_memberships as membership
    where membership.account_id = p_account_id and membership.role = 'owner'
      and membership.approved_at is not null
      and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
  );
  if not v_authorized then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'access_denied', 'message', 'This account cannot process the parcel refund.'));
    response_status := 403;
    return next;
    return;
  end if;

  select payment.* into v_payment
  from private.parcel_payment_records as payment
  where payment.parcel_id = p_parcel_id
  for update;
  if v_payment.provider <> 'razorpay' or v_payment.provider_payment_reference is null
    or v_parcel.status <> 'cancelled' or v_parcel.payment_status not in ('refund_pending', 'refunded')
    or v_parcel.refund_status not in ('pending', 'completed')
    or v_payment.state not in ('captured', 'refund_pending', 'refunded')
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'invalid_parcel_transition', 'message', 'This parcel does not have an eligible Razorpay refund.'));
    response_status := 409;
    return next;
    return;
  end if;

  if v_payment.state = 'captured' then
    update private.parcel_payment_records as payment
    set state = 'refund_pending', version = payment.version + 1, updated_at = pg_catalog.now()
    where payment.parcel_id = p_parcel_id;
  end if;
  response_body := pg_catalog.jsonb_build_object(
    'entityId', p_parcel_id,
    'providerPaymentId', v_payment.provider_payment_reference,
    'providerRefundId', v_payment.provider_refund_reference,
    'amountPaise', v_payment.expected_amount_paise,
    'currency', v_payment.currency,
    'receipt', 'dstprf_' || pg_catalog.replace(p_parcel_id::text, '-', ''),
    'refundState', case when v_payment.state = 'refunded' then 'processed' else 'pending' end
  );
  response_status := 200;
  return next;
end;
$$;

create function public.attach_parcel_razorpay_refund(
  p_account_id uuid,
  p_parcel_id uuid,
  p_provider_refund_reference text,
  p_amount_paise bigint
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_prepared record;
  v_body jsonb;
  v_reference text := pg_catalog.btrim(p_provider_refund_reference);
begin
  if nullif(v_reference, '') is null or v_reference !~ '^rfnd_[A-Za-z0-9]+$'
    or pg_catalog.char_length(v_reference) > 200 or p_amount_paise is null or p_amount_paise <= 0
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'validation_failed', 'message', 'The Razorpay refund is invalid.'));
    response_status := 400;
    return next;
    return;
  end if;
  select prepared.* into v_prepared
  from public.prepare_parcel_razorpay_refund(p_account_id, p_parcel_id) as prepared;
  if v_prepared.response_status <> 200 then
    response_body := v_prepared.response_body;
    response_status := v_prepared.response_status;
    return next;
    return;
  end if;
  v_body := v_prepared.response_body;
  if (v_body ->> 'amountPaise')::bigint <> p_amount_paise
    or ((v_body ->> 'providerRefundId') is not null and v_body ->> 'providerRefundId' <> v_reference)
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'provider_reference_conflict', 'message', 'The Razorpay refund does not match this parcel.'));
    response_status := 409;
    return next;
    return;
  end if;
  update private.parcel_payment_records as payment
  set provider_refund_reference = coalesce(payment.provider_refund_reference, v_reference),
      version = payment.version + 1,
      updated_at = pg_catalog.now()
  where payment.parcel_id = p_parcel_id;
  response_body := pg_catalog.jsonb_build_object('entityId', p_parcel_id, 'providerRefundId', v_reference, 'refundState', v_body ->> 'refundState');
  response_status := case when v_body ->> 'refundState' = 'processed' then 200 else 202 end;
  return next;
end;
$$;

create function public.record_razorpay_parcel_event(
  p_provider_event_id text,
  p_event_type text,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_provider_refund_reference text,
  p_amount_paise bigint,
  p_occurred_at timestamptz,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_payment private.parcel_payment_records%rowtype;
  v_recorded record;
begin
  if p_event_type = 'payment_captured' then
    select payment.* into v_payment
    from private.parcel_payment_records as payment
    where payment.provider = 'razorpay'
      and payment.provider_order_reference = pg_catalog.btrim(p_provider_order_reference)
    for update;
  elsif p_event_type = 'refund_succeeded' then
    select payment.* into v_payment
    from private.parcel_payment_records as payment
    where payment.provider = 'razorpay'
      and payment.provider_payment_reference = pg_catalog.btrim(p_provider_payment_reference)
    for update;
  else
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'validation_failed', 'message', 'The Razorpay event type is unsupported.'));
    response_status := 400;
    return next;
    return;
  end if;
  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'parcel_not_found', 'message', 'No parcel matches the Razorpay event.'));
    response_status := 404;
    return next;
    return;
  end if;
  if p_amount_paise <> v_payment.expected_amount_paise
    or p_provider_payment_reference !~ '^pay_[A-Za-z0-9]+$'
    or (p_event_type = 'refund_succeeded' and (
      p_provider_refund_reference !~ '^rfnd_[A-Za-z0-9]+$'
      or (v_payment.provider_refund_reference is not null and v_payment.provider_refund_reference <> pg_catalog.btrim(p_provider_refund_reference))
    ))
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object('code', 'provider_reference_conflict', 'message', 'The Razorpay event does not match this parcel.'));
    response_status := 409;
    return next;
    return;
  end if;

  select recorded.* into v_recorded
  from public.record_parcel_payment_event(
    'razorpay', p_provider_event_id, v_payment.parcel_id,
    case when p_event_type = 'payment_captured' then 'payment_captured' else 'refund_completed' end,
    p_amount_paise, p_occurred_at, p_request_digest
  ) as recorded;
  if v_recorded.response_status = 200 then
    update private.parcel_payment_records as payment
    set provider_payment_reference = coalesce(payment.provider_payment_reference, pg_catalog.btrim(p_provider_payment_reference)),
        provider_refund_reference = case when p_event_type = 'refund_succeeded' then pg_catalog.btrim(p_provider_refund_reference) else payment.provider_refund_reference end,
        state = case when p_event_type = 'payment_captured' then 'captured' else 'refunded' end,
        captured_at = case when p_event_type = 'payment_captured' then p_occurred_at else payment.captured_at end,
        refunded_at = case when p_event_type = 'refund_succeeded' then p_occurred_at else payment.refunded_at end,
        version = payment.version + 1,
        updated_at = pg_catalog.now()
    where payment.parcel_id = v_payment.parcel_id;
  end if;
  response_body := v_recorded.response_body;
  response_status := v_recorded.response_status;
  return next;
end;
$$;

revoke execute on function public.get_customer_parcel_deliveries(uuid, integer) from public, anon, authenticated;
revoke execute on function public.prepare_parcel_razorpay_checkout(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.attach_parcel_razorpay_order(uuid, uuid, text, bigint, text) from public, anon, authenticated;
revoke execute on function public.prepare_parcel_razorpay_refund(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.attach_parcel_razorpay_refund(uuid, uuid, text, bigint) from public, anon, authenticated;
revoke execute on function public.record_razorpay_parcel_event(text, text, text, text, text, bigint, timestamptz, text) from public, anon, authenticated;

grant execute on function public.get_customer_parcel_deliveries(uuid, integer) to service_role;
grant execute on function public.prepare_parcel_razorpay_checkout(uuid, uuid) to service_role;
grant execute on function public.attach_parcel_razorpay_order(uuid, uuid, text, bigint, text) to service_role;
grant execute on function public.prepare_parcel_razorpay_refund(uuid, uuid) to service_role;
grant execute on function public.attach_parcel_razorpay_refund(uuid, uuid, text, bigint) to service_role;
grant execute on function public.record_razorpay_parcel_event(text, text, text, text, text, bigint, timestamptz, text) to service_role;
