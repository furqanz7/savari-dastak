create or replace function public.get_dastak_merchant_earnings(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_store_id uuid;
begin
  select store.id into v_store_id
  from private.account_memberships as membership
  join private.merchant_stores as store on store.merchant_account_id = membership.account_id
  where membership.account_id = p_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

  if v_store_id is null then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active approved merchant account is required.'
    ));
    response_status := 403;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'currency', 'INR',
    'completedPaise', coalesce((
      select pg_catalog.sum(order_row.merchant_payable_paise)
      from private.merchant_orders as order_row
      where order_row.store_id = v_store_id
        and order_row.status = 'delivered'
        and order_row.payment_state = 'paid'
    ), 0),
    'pendingPaise', coalesce((
      select pg_catalog.sum(order_row.merchant_payable_paise)
      from private.merchant_orders as order_row
      where order_row.store_id = v_store_id
        and order_row.status not in ('payment_pending', 'delivered', 'cancelled', 'returning_to_merchant')
        and order_row.payment_state = 'paid'
    ), 0),
    'thisWeekPaise', coalesce((
      select pg_catalog.sum(order_row.merchant_payable_paise)
      from private.merchant_orders as order_row
      where order_row.store_id = v_store_id
        and order_row.status = 'delivered'
        and order_row.payment_state = 'paid'
        and order_row.updated_at >= pg_catalog.date_trunc('week', pg_catalog.now())
    ), 0)
  );
  response_status := 200;
  return next;
end;
$$;

create or replace function public.get_dastak_delivery_earnings(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1 from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'delivery_partner'
    and membership.approved_at is not null
    and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now());

  if not found then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'access_denied', 'message', 'An active approved delivery partner account is required.'
    ));
    response_status := 403;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'currency', 'INR',
    'completedPaise', coalesce((
      select pg_catalog.sum(value) from (
        select order_row.courier_payout_paise::bigint as value
        from private.delivery_assignment_attempts as assignment
        join private.merchant_orders as order_row on order_row.id = assignment.order_id
        where assignment.partner_account_id = p_account_id and assignment.status = 'completed'
          and order_row.status = 'delivered' and order_row.payment_state = 'paid'
        union all
        select parcel.courier_payout_paise::bigint
        from private.parcel_assignment_attempts as assignment
        join private.parcel_deliveries as parcel on parcel.id = assignment.parcel_id
        where assignment.partner_account_id = p_account_id and assignment.status = 'completed'
          and parcel.status = 'delivered' and parcel.payment_status = 'paid'
      ) as completed
    ), 0),
    'pendingPaise', coalesce((
      select pg_catalog.sum(value) from (
        select order_row.courier_payout_paise::bigint as value
        from private.delivery_assignment_attempts as assignment
        join private.merchant_orders as order_row on order_row.id = assignment.order_id
        where assignment.partner_account_id = p_account_id and assignment.status = 'accepted'
          and order_row.status not in ('delivered', 'cancelled')
        union all
        select parcel.courier_payout_paise::bigint
        from private.parcel_assignment_attempts as assignment
        join private.parcel_deliveries as parcel on parcel.id = assignment.parcel_id
        where assignment.partner_account_id = p_account_id and assignment.status = 'acknowledged'
          and parcel.status not in ('delivered', 'cancelled')
      ) as pending
    ), 0),
    'thisWeekPaise', coalesce((
      select pg_catalog.sum(value) from (
        select order_row.courier_payout_paise::bigint as value
        from private.delivery_assignment_attempts as assignment
        join private.merchant_orders as order_row on order_row.id = assignment.order_id
        where assignment.partner_account_id = p_account_id and assignment.status = 'completed'
          and order_row.status = 'delivered' and order_row.payment_state = 'paid'
          and assignment.updated_at >= pg_catalog.date_trunc('week', pg_catalog.now())
        union all
        select parcel.courier_payout_paise::bigint
        from private.parcel_assignment_attempts as assignment
        join private.parcel_deliveries as parcel on parcel.id = assignment.parcel_id
        where assignment.partner_account_id = p_account_id and assignment.status = 'completed'
          and parcel.status = 'delivered' and parcel.payment_status = 'paid'
          and assignment.updated_at >= pg_catalog.date_trunc('week', pg_catalog.now())
      ) as completed_this_week
    ), 0)
  );
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.get_dastak_merchant_earnings(uuid) from public, anon, authenticated;
revoke execute on function public.get_dastak_delivery_earnings(uuid) from public, anon, authenticated;
grant execute on function public.get_dastak_merchant_earnings(uuid) to service_role;
grant execute on function public.get_dastak_delivery_earnings(uuid) to service_role;
