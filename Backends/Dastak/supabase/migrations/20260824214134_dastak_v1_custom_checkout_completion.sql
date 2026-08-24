-- Dastak-owned Razorpay Custom Checkout completion evidence.
-- A verified client return is deliberately not payment authority: only the
-- existing authenticated payment.captured webhook can transition an order to PAID.

create table dastak_v1.payment_client_completions (
  id uuid primary key default gen_random_uuid(),
  payment_attempt_id uuid not null unique references dastak_v1.payment_attempts(id),
  payment_id uuid not null references dastak_v1.payments(id),
  order_id uuid not null references dastak_v1.orders(id),
  customer_id uuid not null references public.accounts(id),
  provider text not null default 'RAZORPAY' check (provider = 'RAZORPAY'),
  provider_order_reference text not null check (
    provider_order_reference ~ '^order_[A-Za-z0-9]+$'
  ),
  provider_payment_reference text not null unique check (
    provider_payment_reference ~ '^pay_[A-Za-z0-9]+$'
  ),
  signature_digest text not null check (signature_digest ~ '^[0-9a-f]{64}$'),
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  verified_at timestamptz not null default clock_timestamp(),
  unique (customer_id, idempotency_key)
);

create index payment_client_completions_order_idx
  on dastak_v1.payment_client_completions (order_id, verified_at desc);
create index payment_client_completions_payment_idx
  on dastak_v1.payment_client_completions (payment_id, verified_at desc);
create index payment_client_completions_customer_idx
  on dastak_v1.payment_client_completions (customer_id, verified_at desc);

create trigger payment_client_completions_immutable
before update or delete on dastak_v1.payment_client_completions
for each row execute function dastak_v1.reject_mutation();

alter table dastak_v1.payment_client_completions enable row level security;

create function dastak_v1_api.custom_checkout_completion_context(
  p_actor_id uuid,
  p_order_id uuid,
  p_attempt_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_attempt dastak_v1.payment_attempts%rowtype;
  v_payment dastak_v1.payments%rowtype;
begin
  if p_actor_id is null or (auth.uid() is not null and auth.uid() is distinct from p_actor_id)
    or not exists (
      select 1
      from public.accounts account
      join private.account_memberships membership on membership.account_id = account.id
      where account.id = p_actor_id
        and membership.role = 'customer'
        and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
    ) then
    raise exception using errcode = '42501', message = 'active customer access required';
  end if;

  select attempt.* into v_attempt
  from dastak_v1.payment_attempts attempt
  where attempt.id = p_attempt_id
    and attempt.order_id = p_order_id
    and attempt.customer_id = p_actor_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment attempt not found';
  end if;
  if v_attempt.provider_order_reference is null
    or v_attempt.status not in ('PROVIDER_READY', 'SUCCEEDED', 'LATE_SUCCESS') then
    raise exception using errcode = '55000', message = 'payment attempt is not ready';
  end if;

  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.id = v_attempt.payment_id
    and payment.order_id = p_order_id
    and payment.customer_id = p_actor_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment reservation not found';
  end if;

  return pg_catalog.jsonb_build_object(
    'orderId', v_attempt.order_id,
    'paymentId', v_attempt.payment_id,
    'attemptId', v_attempt.id,
    'providerOrderId', v_attempt.provider_order_reference,
    'amountPaise', v_attempt.amount_paise,
    'currency', v_attempt.currency_code,
    'attemptStatus', v_attempt.status,
    'paymentStatus', v_payment.status,
    'paymentExpiresAt', v_payment.expires_at
  );
end;
$$;

create function dastak_v1_api.record_custom_checkout_completion(
  p_actor_id uuid,
  p_order_id uuid,
  p_attempt_id uuid,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_signature_digest text,
  p_request_digest text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt dastak_v1.payment_attempts%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_existing dastak_v1.payment_client_completions%rowtype;
  v_outcome text;
begin
  if p_actor_id is null or (auth.uid() is not null and auth.uid() is distinct from p_actor_id)
    or not exists (
      select 1
      from public.accounts account
      join private.account_memberships membership on membership.account_id = account.id
      where account.id = p_actor_id
        and membership.role = 'customer'
        and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
    ) then
    raise exception using errcode = '42501', message = 'active customer access required';
  end if;
  if p_provider_order_reference !~ '^order_[A-Za-z0-9]+$'
    or p_provider_payment_reference !~ '^pay_[A-Za-z0-9]+$'
    or p_signature_digest !~ '^[0-9a-f]{64}$'
    or p_request_digest !~ '^[0-9a-f]{64}$'
    or char_length(coalesce(p_idempotency_key, '')) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid checkout completion';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('custom-checkout:' || p_attempt_id::text, 0)
  );

  select completion.* into v_existing
  from dastak_v1.payment_client_completions completion
  where completion.payment_attempt_id = p_attempt_id
     or completion.provider_payment_reference = p_provider_payment_reference
     or (
       completion.customer_id = p_actor_id
       and completion.idempotency_key = p_idempotency_key
     )
  order by completion.verified_at
  limit 1;

  if found then
    if v_existing.customer_id = p_actor_id
      and v_existing.order_id = p_order_id
      and v_existing.payment_attempt_id = p_attempt_id
      and v_existing.provider_order_reference = p_provider_order_reference
      and v_existing.provider_payment_reference = p_provider_payment_reference
      and v_existing.signature_digest = p_signature_digest
      and v_existing.request_digest = p_request_digest then
      select payment.* into v_payment
      from dastak_v1.payments payment
      where payment.id = v_existing.payment_id;

      v_outcome := case
        when v_payment.status = 'SUCCEEDED' then 'PAID'
        when v_payment.status = 'RESERVED'
          and v_payment.expires_at > pg_catalog.clock_timestamp()
          then 'AWAITING_PROVIDER_CONFIRMATION'
        else 'RECONCILIATION_REQUIRED'
      end;

      return pg_catalog.jsonb_build_object(
        'orderId', v_existing.order_id,
        'paymentAttemptId', v_existing.payment_attempt_id,
        'providerPaymentId', v_existing.provider_payment_reference,
        'state', v_outcome,
        'duplicate', true
      );
    end if;
    raise exception using errcode = '23505', message = 'checkout completion conflict';
  end if;

  select attempt.* into v_attempt
  from dastak_v1.payment_attempts attempt
  where attempt.id = p_attempt_id
    and attempt.order_id = p_order_id
    and attempt.customer_id = p_actor_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment attempt not found';
  end if;
  if v_attempt.provider_order_reference is distinct from p_provider_order_reference then
    raise exception using errcode = '22023', message = 'provider order mismatch';
  end if;
  if v_attempt.status not in ('PROVIDER_READY', 'SUCCEEDED', 'LATE_SUCCESS') then
    raise exception using errcode = '55000', message = 'payment attempt cannot accept completion';
  end if;

  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.id = v_attempt.payment_id
    and payment.order_id = p_order_id
    and payment.customer_id = p_actor_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'payment reservation not found';
  end if;

  insert into dastak_v1.payment_client_completions (
    payment_attempt_id, payment_id, order_id, customer_id,
    provider_order_reference, provider_payment_reference,
    signature_digest, request_digest, idempotency_key
  ) values (
    v_attempt.id, v_attempt.payment_id, v_attempt.order_id, v_attempt.customer_id,
    p_provider_order_reference, p_provider_payment_reference,
    p_signature_digest, p_request_digest, p_idempotency_key
  );

  v_outcome := case
    when v_payment.status = 'SUCCEEDED' then 'PAID'
    when v_payment.status = 'RESERVED'
      and v_payment.expires_at > pg_catalog.clock_timestamp()
      then 'AWAITING_PROVIDER_CONFIRMATION'
    else 'RECONCILIATION_REQUIRED'
  end;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'CUSTOM_CHECKOUT_COMPLETION_VERIFIED',
    'payment_attempt',
    v_attempt.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_attempt.order_id,
      'paymentId', v_attempt.payment_id,
      'providerOrderId', p_provider_order_reference,
      'providerPaymentId', p_provider_payment_reference,
      'outcome', v_outcome,
      'paidAuthority', 'payment.captured'
    )
  );

  return pg_catalog.jsonb_build_object(
    'orderId', v_attempt.order_id,
    'paymentAttemptId', v_attempt.id,
    'providerPaymentId', p_provider_payment_reference,
    'state', v_outcome,
    'duplicate', false
  );
end;
$$;

create function public.dastak_v1_custom_checkout_completion_context(
  p_account_id uuid,
  p_order_id uuid,
  p_attempt_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.custom_checkout_completion_context(
    p_account_id, p_order_id, p_attempt_id
  );
$$;

create function public.dastak_v1_record_custom_checkout_completion(
  p_account_id uuid,
  p_order_id uuid,
  p_attempt_id uuid,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_signature_digest text,
  p_request_digest text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.record_custom_checkout_completion(
    p_account_id, p_order_id, p_attempt_id,
    p_provider_order_reference, p_provider_payment_reference,
    p_signature_digest, p_request_digest, p_idempotency_key
  );
$$;

revoke all on table dastak_v1.payment_client_completions
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.custom_checkout_completion_context(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.record_custom_checkout_completion(
  uuid, uuid, uuid, text, text, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_custom_checkout_completion_context(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_record_custom_checkout_completion(
  uuid, uuid, uuid, text, text, text, text, text
) from public, anon, authenticated, service_role;

grant execute on function dastak_v1_api.custom_checkout_completion_context(uuid, uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.record_custom_checkout_completion(
  uuid, uuid, uuid, text, text, text, text, text
) to service_role;
grant execute on function public.dastak_v1_custom_checkout_completion_context(uuid, uuid, uuid)
  to service_role;
grant execute on function public.dastak_v1_record_custom_checkout_completion(
  uuid, uuid, uuid, text, text, text, text, text
) to service_role;

comment on table dastak_v1.payment_client_completions is
  'Immutable server-verified Custom Checkout returns. These never make an order PAID; payment.captured remains authority.';
comment on function dastak_v1_api.record_custom_checkout_completion(
  uuid, uuid, uuid, text, text, text, text, text
) is
  'Records an authenticated, server-signature-verified Razorpay Custom Checkout return idempotently without changing payment state.';
