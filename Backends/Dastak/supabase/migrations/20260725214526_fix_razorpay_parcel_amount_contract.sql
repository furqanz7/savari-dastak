create or replace function public.record_razorpay_parcel_event(
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
    select payment.*
    into v_payment
    from private.parcel_payment_records as payment
    where payment.provider = 'razorpay'
      and payment.provider_order_reference =
        pg_catalog.btrim(p_provider_order_reference)
    for update;
  elsif p_event_type = 'refund_succeeded' then
    select payment.*
    into v_payment
    from private.parcel_payment_records as payment
    where payment.provider = 'razorpay'
      and payment.provider_payment_reference =
        pg_catalog.btrim(p_provider_payment_reference)
    for update;
  else
    response_body := pg_catalog.jsonb_build_object(
      'error',
      pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The Razorpay event type is unsupported.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error',
      pg_catalog.jsonb_build_object(
        'code', 'parcel_not_found',
        'message', 'No parcel matches the Razorpay event.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if p_amount_paise <> v_payment.expected_amount_paise
    or p_provider_payment_reference !~ '^pay_[A-Za-z0-9]+$'
    or (
      p_event_type = 'refund_succeeded'
      and (
        p_provider_refund_reference !~ '^rfnd_[A-Za-z0-9]+$'
        or (
          v_payment.provider_refund_reference is not null
          and v_payment.provider_refund_reference <>
            pg_catalog.btrim(p_provider_refund_reference)
        )
      )
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error',
      pg_catalog.jsonb_build_object(
        'code', 'provider_reference_conflict',
        'message', 'The Razorpay event does not match this parcel.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select recorded.*
  into v_recorded
  from public.record_parcel_payment_event(
    'razorpay',
    p_provider_event_id,
    v_payment.parcel_id,
    case
      when p_event_type = 'payment_captured' then 'payment_captured'
      else 'refund_completed'
    end,
    p_amount_paise::integer,
    p_occurred_at,
    p_request_digest
  ) as recorded;

  if v_recorded.response_status = 200 then
    update private.parcel_payment_records as payment
    set provider_payment_reference = coalesce(
          payment.provider_payment_reference,
          pg_catalog.btrim(p_provider_payment_reference)
        ),
        provider_refund_reference = case
          when p_event_type = 'refund_succeeded'
            then pg_catalog.btrim(p_provider_refund_reference)
          else payment.provider_refund_reference
        end,
        state = case
          when p_event_type = 'payment_captured' then 'captured'
          else 'refunded'
        end,
        captured_at = case
          when p_event_type = 'payment_captured' then p_occurred_at
          else payment.captured_at
        end,
        refunded_at = case
          when p_event_type = 'refund_succeeded' then p_occurred_at
          else payment.refunded_at
        end,
        version = payment.version + 1,
        updated_at = pg_catalog.now()
    where payment.parcel_id = v_payment.parcel_id;
  end if;

  response_body := v_recorded.response_body;
  response_status := v_recorded.response_status;
  return next;
end;
$$;

revoke execute on function public.record_razorpay_parcel_event(
  text, text, text, text, text, bigint, timestamptz, text
) from public, anon, authenticated;

grant execute on function public.record_razorpay_parcel_event(
  text, text, text, text, text, bigint, timestamptz, text
) to service_role;

notify pgrst, 'reload schema';
