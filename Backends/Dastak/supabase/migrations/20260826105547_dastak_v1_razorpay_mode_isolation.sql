-- Keep Razorpay Test and Live provider identities transactionally isolated.
-- Existing rows predate explicit mode tracking and remain NULL rather than
-- being reinterpreted. Every new Edge Function payment path uses the mode-aware
-- RPCs below and may set the mode once; it can never change afterwards.

alter table dastak_v1.payment_attempts
  add column provider_mode text
  check (provider_mode is null or provider_mode in ('TEST', 'LIVE'));

alter table dastak_v1.payment_provider_events
  add column provider_mode text
  check (provider_mode is null or provider_mode in ('TEST', 'LIVE'));

alter table dastak_v1.payment_client_completions
  add column provider_mode text
  check (provider_mode is null or provider_mode in ('TEST', 'LIVE'));

alter table dastak_v1.refunds
  add column provider_mode text
  check (provider_mode is null or provider_mode in ('TEST', 'LIVE'));

alter table dastak_v1.refund_provider_events
  add column provider_mode text
  check (provider_mode is null or provider_mode in ('TEST', 'LIVE'));

create function dastak_v1_api.require_razorpay_provider_mode(p_mode text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_mode is null or p_mode not in ('TEST', 'LIVE') then
    raise exception using
      errcode = '22023',
      message = 'invalid Razorpay provider mode';
  end if;
  return p_mode;
end;
$$;

create function dastak_v1_api.preserve_razorpay_provider_mode()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.provider_mode is not null
    and new.provider_mode is distinct from old.provider_mode then
    raise exception using
      errcode = '22023',
      message = 'Razorpay provider mode is immutable';
  end if;
  return new;
end;
$$;

create trigger payment_attempts_preserve_provider_mode
before update on dastak_v1.payment_attempts
for each row execute function dastak_v1_api.preserve_razorpay_provider_mode();

create trigger refunds_preserve_provider_mode
before update on dastak_v1.refunds
for each row execute function dastak_v1_api.preserve_razorpay_provider_mode();

create function dastak_v1_api.derive_payment_completion_provider_mode()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_mode text;
begin
  select attempt.provider_mode into v_mode
  from dastak_v1.payment_attempts attempt
  where attempt.id = new.payment_attempt_id;
  if v_mode is null then
    if new.provider_mode is not null then
      raise exception using errcode = '22023', message = 'payment provider mode mismatch';
    end if;
    return new;
  end if;
  if new.provider_mode is not null and new.provider_mode <> v_mode then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;
  new.provider_mode := v_mode;
  return new;
end;
$$;

create trigger payment_client_completions_provider_mode
before insert on dastak_v1.payment_client_completions
for each row execute function dastak_v1_api.derive_payment_completion_provider_mode();

create function dastak_v1_api.derive_payment_event_provider_mode()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_mode text;
begin
  select attempt.provider_mode into v_mode
  from dastak_v1.payment_attempts attempt
  where attempt.id = new.payment_attempt_id;
  if v_mode is null then
    if new.provider_mode is not null then
      raise exception using errcode = '22023', message = 'payment provider mode mismatch';
    end if;
    return new;
  end if;
  if new.provider_mode is not null and new.provider_mode <> v_mode then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;
  new.provider_mode := v_mode;
  return new;
end;
$$;

create trigger payment_provider_events_provider_mode
before insert on dastak_v1.payment_provider_events
for each row execute function dastak_v1_api.derive_payment_event_provider_mode();

create function dastak_v1_api.derive_refund_provider_mode()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_mode text;
begin
  select attempt.provider_mode into v_mode
  from dastak_v1.payment_attempts attempt
  where attempt.payment_id = new.payment_id
    and attempt.provider_payment_reference = new.provider_payment_reference
  order by attempt.succeeded_at desc nulls last, attempt.created_at desc
  limit 1;

  if v_mode is not null then
    if new.provider_mode is not null and new.provider_mode <> v_mode then
      raise exception using errcode = '22023', message = 'refund provider mode mismatch';
    end if;
    new.provider_mode := v_mode;
  end if;
  return new;
end;
$$;

create trigger refunds_derive_provider_mode
before insert on dastak_v1.refunds
for each row execute function dastak_v1_api.derive_refund_provider_mode();

create function dastak_v1_api.derive_refund_event_provider_mode()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_mode text;
begin
  select refund.provider_mode into v_mode
  from dastak_v1.refunds refund
  where refund.id = new.refund_id;
  if v_mode is null then
    if new.provider_mode is not null then
      raise exception using errcode = '22023', message = 'refund provider mode mismatch';
    end if;
    return new;
  end if;
  if new.provider_mode is not null and new.provider_mode <> v_mode then
    raise exception using errcode = '22023', message = 'refund provider mode mismatch';
  end if;
  new.provider_mode := v_mode;
  return new;
end;
$$;

create trigger refund_provider_events_provider_mode
before insert on dastak_v1.refund_provider_events
for each row execute function dastak_v1_api.derive_refund_event_provider_mode();

create or replace function dastak_v1_api.payment_attempt_json(p_attempt_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'attemptId', attempt.id,
    'paymentId', attempt.payment_id,
    'entityId', attempt.order_id,
    'orderId', attempt.order_id,
    'status', attempt.status,
    'amountPaise', attempt.amount_paise,
    'currency', attempt.currency_code,
    'receipt', attempt.provider_receipt,
    'providerMode', attempt.provider_mode,
    'providerOrderId', attempt.provider_order_reference,
    'providerPaymentId', attempt.provider_payment_reference,
    'failureCode', attempt.failure_code,
    'paymentExpiresAt', payment.expires_at,
    'reservationActive', payment.status = 'RESERVED'
      and payment.expires_at > pg_catalog.clock_timestamp()
  )
  from dastak_v1.payment_attempts attempt
  join dastak_v1.payments payment on payment.id = attempt.payment_id
  where attempt.id = p_attempt_id;
$$;

create function public.dastak_v1_prepare_razorpay_checkout_mode(
  p_account_id uuid,
  p_order_id uuid,
  p_idempotency_key text,
  p_provider_mode text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_response jsonb;
  v_attempt_id uuid;
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  v_response := dastak_v1_api.prepare_razorpay_checkout(
    p_account_id, p_order_id, p_idempotency_key
  );
  v_attempt_id := (v_response ->> 'attemptId')::uuid;

  update dastak_v1.payment_attempts attempt
  set provider_mode = v_mode
  where attempt.id = v_attempt_id
    and (
      attempt.provider_mode = v_mode
      or (
        attempt.provider_mode is null
        and attempt.provider_order_reference is null
      )
    );
  if not found then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;
  return dastak_v1_api.payment_attempt_json(v_attempt_id);
end;
$$;

create function public.dastak_v1_attach_razorpay_order_mode(
  p_account_id uuid,
  p_attempt_id uuid,
  p_provider_order_reference text,
  p_amount_paise bigint,
  p_currency text,
  p_provider_mode text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  if not exists (
    select 1 from dastak_v1.payment_attempts attempt
    where attempt.id = p_attempt_id and attempt.provider_mode = v_mode
  ) then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;
  return dastak_v1_api.attach_razorpay_order(
    p_account_id, p_attempt_id, p_provider_order_reference,
    p_amount_paise, p_currency
  );
end;
$$;

create function public.dastak_v1_custom_checkout_completion_context_mode(
  p_account_id uuid,
  p_order_id uuid,
  p_attempt_id uuid,
  p_provider_mode text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_response jsonb;
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  if not exists (
    select 1 from dastak_v1.payment_attempts attempt
    where attempt.id = p_attempt_id
      and attempt.order_id = p_order_id
      and attempt.provider_mode = v_mode
  ) then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;
  v_response := dastak_v1_api.custom_checkout_completion_context(
    p_account_id, p_order_id, p_attempt_id
  );
  return v_response || pg_catalog.jsonb_build_object('providerMode', v_mode);
end;
$$;

create function public.dastak_v1_record_custom_checkout_completion_mode(
  p_account_id uuid,
  p_order_id uuid,
  p_attempt_id uuid,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_signature_digest text,
  p_request_digest text,
  p_idempotency_key text,
  p_provider_mode text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_response jsonb;
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  if not exists (
    select 1 from dastak_v1.payment_attempts attempt
    where attempt.id = p_attempt_id
      and attempt.order_id = p_order_id
      and attempt.provider_mode = v_mode
      and attempt.provider_order_reference = p_provider_order_reference
  ) then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;
  v_response := dastak_v1_api.record_custom_checkout_completion(
    p_account_id, p_order_id, p_attempt_id,
    p_provider_order_reference, p_provider_payment_reference,
    p_signature_digest, p_request_digest, p_idempotency_key
  );
  return v_response || pg_catalog.jsonb_build_object('providerMode', v_mode);
end;
$$;

create function public.dastak_v1_prepare_razorpay_refund_mode(
  p_account_id uuid,
  p_refund_id uuid,
  p_idempotency_key text,
  p_provider_mode text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_response jsonb;
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  if not exists (
    select 1 from dastak_v1.refunds refund
    where refund.id = p_refund_id and refund.provider_mode = v_mode
  ) then
    raise exception using errcode = '22023', message = 'refund provider mode mismatch';
  end if;
  v_response := dastak_v1_api.prepare_razorpay_refund(
    p_account_id, p_refund_id, p_idempotency_key
  );
  return v_response || pg_catalog.jsonb_build_object('providerMode', v_mode);
end;
$$;

create function public.dastak_v1_attach_razorpay_refund_mode(
  p_account_id uuid,
  p_refund_id uuid,
  p_provider_refund_reference text,
  p_amount_paise bigint,
  p_provider_mode text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_response jsonb;
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  if not exists (
    select 1 from dastak_v1.refunds refund
    where refund.id = p_refund_id and refund.provider_mode = v_mode
  ) then
    raise exception using errcode = '22023', message = 'refund provider mode mismatch';
  end if;
  v_response := dastak_v1_api.attach_razorpay_refund(
    p_account_id, p_refund_id, p_provider_refund_reference, p_amount_paise
  );
  return v_response || pg_catalog.jsonb_build_object('providerMode', v_mode);
end;
$$;

create function public.dastak_v1_record_razorpay_event_mode(
  p_provider_event_id text,
  p_event_type text,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_provider_refund_reference text,
  p_amount_paise bigint,
  p_occurred_at timestamptz,
  p_request_digest text,
  p_provider_mode text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mode text := dastak_v1_api.require_razorpay_provider_mode(p_provider_mode);
begin
  if p_event_type = 'payment_captured' and p_provider_refund_reference is null then
    if exists (
      select 1 from dastak_v1.payment_attempts attempt
      where attempt.provider_order_reference = p_provider_order_reference
        and attempt.provider_mode = v_mode
    ) then
      null;
    elsif v_mode = 'LIVE' and exists (
      select 1 from dastak_v1.payment_attempts attempt
      where attempt.provider_order_reference = p_provider_order_reference
        and attempt.provider_mode is null
    ) then
      -- Production V1 attempts created before this migration were necessarily
      -- Live. Preserve their webhook path during the rolling Edge/database
      -- cutover without ever allowing a Test webhook to claim them.
      null;
    elsif exists (
      select 1 from dastak_v1.payment_attempts attempt
      where attempt.provider_order_reference = p_provider_order_reference
    ) then
      return query select pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'provider_mode_mismatch',
          'message', 'The webhook mode does not match this payment.'
        )
      ), 409;
      return;
    else
      return query select pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'payment_not_found',
          'message', 'No Dastak V1 payment matched this provider mode.'
        )
      ), 404;
      return;
    end if;
  elsif p_event_type = 'refund_succeeded' and p_provider_refund_reference is not null then
    if exists (
      select 1 from dastak_v1.refunds refund
      where refund.provider_refund_reference = p_provider_refund_reference
        and refund.provider_mode = v_mode
    ) then
      null;
    elsif v_mode = 'LIVE' and exists (
      select 1 from dastak_v1.refunds refund
      where refund.provider_refund_reference = p_provider_refund_reference
        and refund.provider_mode is null
    ) then
      null;
    elsif exists (
      select 1 from dastak_v1.refunds refund
      where refund.provider_refund_reference = p_provider_refund_reference
    ) then
      return query select pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'provider_mode_mismatch',
          'message', 'The webhook mode does not match this refund.'
        )
      ), 409;
      return;
    else
      return query select pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'payment_not_found',
          'message', 'No Dastak V1 refund matched this provider mode.'
        )
      ), 404;
      return;
    end if;
  end if;

  return query select * from public.dastak_v1_record_razorpay_event(
    p_provider_event_id, p_event_type, p_provider_order_reference,
    p_provider_payment_reference, p_provider_refund_reference,
    p_amount_paise, p_occurred_at, p_request_digest
  );
end;
$$;

revoke all on function dastak_v1_api.require_razorpay_provider_mode(text)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.preserve_razorpay_provider_mode()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.derive_payment_completion_provider_mode()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.derive_payment_event_provider_mode()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.derive_refund_provider_mode()
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.derive_refund_event_provider_mode()
  from public, anon, authenticated, service_role;

revoke all on function public.dastak_v1_prepare_razorpay_checkout_mode(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_attach_razorpay_order_mode(
  uuid, uuid, text, bigint, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_custom_checkout_completion_context_mode(
  uuid, uuid, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_record_custom_checkout_completion_mode(
  uuid, uuid, uuid, text, text, text, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_prepare_razorpay_refund_mode(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_attach_razorpay_refund_mode(
  uuid, uuid, text, bigint, text
) from public, anon, authenticated, service_role;
revoke all on function public.dastak_v1_record_razorpay_event_mode(
  text, text, text, text, text, bigint, timestamptz, text, text
) from public, anon, authenticated, service_role;

grant execute on function public.dastak_v1_prepare_razorpay_checkout_mode(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.dastak_v1_attach_razorpay_order_mode(
  uuid, uuid, text, bigint, text, text
) to service_role;
grant execute on function public.dastak_v1_custom_checkout_completion_context_mode(
  uuid, uuid, uuid, text
) to service_role;
grant execute on function public.dastak_v1_record_custom_checkout_completion_mode(
  uuid, uuid, uuid, text, text, text, text, text, text
) to service_role;
grant execute on function public.dastak_v1_prepare_razorpay_refund_mode(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.dastak_v1_attach_razorpay_refund_mode(
  uuid, uuid, text, bigint, text
) to service_role;
grant execute on function public.dastak_v1_record_razorpay_event_mode(
  text, text, text, text, text, bigint, timestamptz, text, text
) to service_role;

comment on column dastak_v1.payment_attempts.provider_mode is
  'Immutable Razorpay credential environment for this provider order. NULL only for pre-migration history.';
comment on function public.dastak_v1_record_razorpay_event_mode(
  text, text, text, text, text, bigint, timestamptz, text, text
) is
  'Accepts a Razorpay webhook only when its verified Test/Live secret matches the immutable payment or refund mode.';
