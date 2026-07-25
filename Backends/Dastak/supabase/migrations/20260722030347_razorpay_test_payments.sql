alter table private.merchant_order_payment_records
  add column provider_refund_reference text check (
    provider_refund_reference is null
    or pg_catalog.char_length(provider_refund_reference) between 1 and 200
  );

create unique index merchant_order_payment_provider_order_unique
  on private.merchant_order_payment_records (provider, provider_order_reference)
  where provider is not null and provider_order_reference is not null;

create unique index merchant_order_payment_provider_refund_unique
  on private.merchant_order_payment_records (provider, provider_refund_reference)
  where provider is not null and provider_refund_reference is not null;

create function public.prepare_merchant_order_razorpay_checkout(
  p_account_id uuid,
  p_order_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_order private.merchant_orders%rowtype;
  v_payment private.merchant_order_payment_records%rowtype;
begin
  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.customer_account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  select payment.*
  into v_payment
  from private.merchant_order_payment_records as payment
  where payment.order_id = v_order.id
  for update;

  if v_order.status <> 'payment_pending'
    or v_order.payment_state <> 'payment_pending'
    or v_payment.state <> 'pending'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order is not awaiting payment.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_payment.provider is not null and v_payment.provider <> 'razorpay' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'provider_reference_conflict',
        'message', 'This order is already attached to another payment provider.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'orderId', v_order.id,
    'providerOrderId', v_payment.provider_order_reference,
    'amountPaise', v_payment.expected_amount_paise,
    'currency', v_payment.currency,
    'receipt', 'dst_' || pg_catalog.replace(v_order.id::text, '-', '')
  );
  response_status := 200;
  return next;
end;
$$;

create function public.attach_merchant_order_razorpay_order(
  p_account_id uuid,
  p_order_id uuid,
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
  v_order private.merchant_orders%rowtype;
  v_payment private.merchant_order_payment_records%rowtype;
  v_provider_order_reference text := pg_catalog.btrim(p_provider_order_reference);
begin
  if nullif(v_provider_order_reference, '') is null
    or v_provider_order_reference !~ '^order_[A-Za-z0-9]+$'
    or pg_catalog.char_length(v_provider_order_reference) > 200
    or p_amount_paise is null or p_amount_paise <= 0
    or p_currency is null
    or pg_catalog.upper(pg_catalog.btrim(p_currency)) <> 'INR'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The Razorpay order is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
    and merchant_order.customer_account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  select payment.*
  into v_payment
  from private.merchant_order_payment_records as payment
  where payment.order_id = v_order.id
  for update;

  if v_order.status <> 'payment_pending'
    or v_order.payment_state <> 'payment_pending'
    or v_payment.state <> 'pending'
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order is not awaiting payment.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_payment.expected_amount_paise <> p_amount_paise
    or v_payment.currency <> pg_catalog.upper(pg_catalog.btrim(p_currency))
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'payment_amount_mismatch',
        'message', 'The Razorpay order does not match the server total.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_payment.provider_order_reference is not null
    and (
      v_payment.provider <> 'razorpay'
      or v_payment.provider_order_reference <> v_provider_order_reference
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'provider_reference_conflict',
        'message', 'This order already has a different provider reference.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if exists (
    select 1
    from private.merchant_order_payment_records as other_payment
    where other_payment.provider = 'razorpay'
      and other_payment.provider_order_reference = v_provider_order_reference
      and other_payment.order_id <> v_order.id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'provider_reference_conflict',
        'message', 'The Razorpay order reference is already in use.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_payment.provider_order_reference is null then
    update private.merchant_order_payment_records as payment
    set provider = 'razorpay',
        provider_order_reference = v_provider_order_reference,
        version = payment.version + 1,
        updated_at = pg_catalog.now()
    where payment.order_id = v_order.id;

    insert into audit.events (action, entity_type, entity_id, after_state)
    values (
      'merchant_order_razorpay_order_attached',
      'merchant_order_payment',
      v_order.id,
      pg_catalog.jsonb_build_object(
        'provider', 'razorpay',
        'providerOrderId', v_provider_order_reference
      )
    );
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'orderId', v_order.id,
    'providerOrderId', v_provider_order_reference,
    'amountPaise', v_payment.expected_amount_paise,
    'currency', v_payment.currency,
    'receipt', 'dst_' || pg_catalog.replace(v_order.id::text, '-', '')
  );
  response_status := 200;
  return next;
end;
$$;

create function public.prepare_merchant_order_razorpay_refund(
  p_account_id uuid,
  p_order_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_order private.merchant_orders%rowtype;
  v_payment private.merchant_order_payment_records%rowtype;
  v_authorized boolean := false;
begin
  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  v_authorized := v_order.customer_account_id = p_account_id
    or exists (
      select 1
      from private.merchant_stores as store
      join private.account_memberships as membership
        on membership.account_id = store.merchant_account_id
      where store.id = v_order.store_id
        and store.merchant_account_id = p_account_id
        and membership.role = 'merchant'
        and membership.approved_at is not null
        and (
          membership.suspended_until is null
          or membership.suspended_until <= pg_catalog.now()
        )
    )
    or exists (
      select 1
      from private.account_memberships as membership
      where membership.account_id = p_account_id
        and membership.role = 'owner'
        and membership.approved_at is not null
        and (
          membership.suspended_until is null
          or membership.suspended_until <= pg_catalog.now()
        )
    );

  if not v_authorized then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'This account cannot process the order refund.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select payment.*
  into v_payment
  from private.merchant_order_payment_records as payment
  where payment.order_id = v_order.id
  for update;

  if v_payment.provider <> 'razorpay'
    or v_payment.provider_payment_reference is null
    or v_payment.state not in ('refund_pending', 'refunded')
    or v_payment.refund_reserved_paise <= 0
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order does not have an eligible Razorpay refund.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'orderId', v_order.id,
    'providerPaymentId', v_payment.provider_payment_reference,
    'providerRefundId', v_payment.provider_refund_reference,
    'amountPaise', v_payment.refund_reserved_paise,
    'currency', v_payment.currency,
    'receipt', 'dst_rf_' || pg_catalog.replace(v_order.id::text, '-', ''),
    'refundState', case when v_payment.state = 'refunded' then 'processed' else 'pending' end
  );
  response_status := 200;
  return next;
end;
$$;

create function public.attach_merchant_order_razorpay_refund(
  p_account_id uuid,
  p_order_id uuid,
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
  v_provider_refund_reference text := pg_catalog.btrim(p_provider_refund_reference);
  v_existing_refund_reference text;
begin
  if nullif(v_provider_refund_reference, '') is null
    or v_provider_refund_reference !~ '^rfnd_[A-Za-z0-9]+$'
    or pg_catalog.char_length(v_provider_refund_reference) > 200
    or p_amount_paise is null or p_amount_paise <= 0
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The Razorpay refund is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select prepared.*
  into v_prepared
  from public.prepare_merchant_order_razorpay_refund(p_account_id, p_order_id) as prepared;

  if v_prepared.response_status <> 200 then
    response_body := v_prepared.response_body;
    response_status := v_prepared.response_status;
    return next;
    return;
  end if;

  v_body := v_prepared.response_body;
  v_existing_refund_reference := v_body ->> 'providerRefundId';
  if (v_body ->> 'amountPaise')::bigint <> p_amount_paise then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'refund_amount_mismatch',
        'message', 'The Razorpay refund does not match the reserved amount.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_existing_refund_reference is not null
    and v_existing_refund_reference <> v_provider_refund_reference
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'provider_reference_conflict',
        'message', 'This order already has a different refund reference.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_existing_refund_reference is null then
    update private.merchant_order_payment_records as payment
    set provider_refund_reference = v_provider_refund_reference,
        version = payment.version + 1,
        updated_at = pg_catalog.now()
    where payment.order_id = p_order_id;

    insert into audit.events (action, entity_type, entity_id, after_state)
    values (
      'merchant_order_razorpay_refund_attached',
      'merchant_order_payment',
      p_order_id,
      pg_catalog.jsonb_build_object(
        'provider', 'razorpay',
        'providerRefundId', v_provider_refund_reference,
        'amountPaise', p_amount_paise
      )
    );
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'orderId', p_order_id,
    'providerRefundId', v_provider_refund_reference,
    'refundState', v_body ->> 'refundState'
  );
  response_status := case when v_body ->> 'refundState' = 'processed' then 200 else 202 end;
  return next;
end;
$$;

create function public.record_razorpay_merchant_order_event(
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
  v_order_id uuid;
  v_existing_refund_reference text;
begin
  if p_event_type = 'payment_captured' then
    select payment.order_id
    into v_order_id
    from private.merchant_order_payment_records as payment
    where payment.provider = 'razorpay'
      and payment.provider_order_reference = pg_catalog.btrim(p_provider_order_reference);
  elsif p_event_type = 'refund_succeeded' then
    select payment.order_id, payment.provider_refund_reference
    into v_order_id, v_existing_refund_reference
    from private.merchant_order_payment_records as payment
    where payment.provider = 'razorpay'
      and payment.provider_payment_reference = pg_catalog.btrim(p_provider_payment_reference)
    for update;
  else
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The Razorpay event type is unsupported.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if v_order_id is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'No Dastak order matches the Razorpay event.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  if p_event_type = 'refund_succeeded' then
    if nullif(pg_catalog.btrim(p_provider_refund_reference), '') is null
      or pg_catalog.btrim(p_provider_refund_reference) !~ '^rfnd_[A-Za-z0-9]+$'
      or (
        v_existing_refund_reference is not null
        and v_existing_refund_reference <> pg_catalog.btrim(p_provider_refund_reference)
      )
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'provider_reference_conflict',
          'message', 'The Razorpay refund reference does not match this order.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    if v_existing_refund_reference is null then
      update private.merchant_order_payment_records as payment
      set provider_refund_reference = pg_catalog.btrim(p_provider_refund_reference),
          version = payment.version + 1,
          updated_at = pg_catalog.now()
      where payment.order_id = v_order_id;
    end if;
  end if;

  return query
  select recorded.response_body, recorded.response_status
  from public.record_merchant_order_payment_event(
    v_order_id,
    'razorpay',
    p_provider_event_id,
    p_event_type,
    p_provider_order_reference,
    p_provider_payment_reference,
    p_amount_paise,
    p_occurred_at,
    p_request_digest
  ) as recorded;
end;
$$;

revoke execute on function public.prepare_merchant_order_razorpay_checkout(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.attach_merchant_order_razorpay_order(uuid, uuid, text, bigint, text)
  from public, anon, authenticated;
revoke execute on function public.prepare_merchant_order_razorpay_refund(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.attach_merchant_order_razorpay_refund(uuid, uuid, text, bigint)
  from public, anon, authenticated;
revoke execute on function public.record_razorpay_merchant_order_event(
  text, text, text, text, text, bigint, timestamp with time zone, text
) from public, anon, authenticated;

grant execute on function public.prepare_merchant_order_razorpay_checkout(uuid, uuid)
  to service_role;
grant execute on function public.attach_merchant_order_razorpay_order(uuid, uuid, text, bigint, text)
  to service_role;
grant execute on function public.prepare_merchant_order_razorpay_refund(uuid, uuid)
  to service_role;
grant execute on function public.attach_merchant_order_razorpay_refund(uuid, uuid, text, bigint)
  to service_role;
grant execute on function public.record_razorpay_merchant_order_event(
  text, text, text, text, text, bigint, timestamp with time zone, text
) to service_role;
