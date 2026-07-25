create or replace function public.get_customer_parcel_deliveries(
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

revoke execute on function public.get_customer_parcel_deliveries(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.get_customer_parcel_deliveries(uuid, integer) to service_role;

notify pgrst, 'reload schema';
