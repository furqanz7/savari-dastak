create or replace function public.get_customer_delivery_addresses(p_account_id uuid)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete your Dastak profile before saving an address.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'addresses', coalesce(
      (
        select pg_catalog.jsonb_agg(
          private.customer_delivery_address_json(address_row)
          order by address_row.is_default desc,
            address_row.updated_at desc,
            address_row.id
        )
        from private.customer_delivery_addresses as address_row
        where address_row.account_id = p_account_id
      ),
      '[]'::jsonb
    )
  );
  response_status := 200;
  return next;
end;
$$;
