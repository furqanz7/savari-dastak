set check_function_bodies = on;

create or replace function public.dastak_v1_prepare_razorpay_checkout_mode(
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

  -- Snapshot the provider mode once. The payment-attempt guard requires every
  -- real update to advance the optimistic version by exactly one.
  update dastak_v1.payment_attempts attempt
  set provider_mode = v_mode,
      version = attempt.version + 1
  where attempt.id = v_attempt_id
    and attempt.provider_mode is null
    and attempt.provider_order_reference is null;

  if not found and not exists (
    select 1
    from dastak_v1.payment_attempts attempt
    where attempt.id = v_attempt_id
      and attempt.provider_mode = v_mode
  ) then
    raise exception using errcode = '22023', message = 'payment provider mode mismatch';
  end if;

  return dastak_v1_api.payment_attempt_json(v_attempt_id);
end;
$$;

