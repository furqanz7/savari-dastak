-- Small owned read model: discovery does not change orders, carts or payments.
create index orders_customer_active_discovery_idx on dastak_v1.orders(customer_id,created_at desc,id desc)
 where status not in ('DELIVERED','UNAVAILABLE','PAYMENT_EXPIRED','CANCELLED_PREPAYMENT','CANCELLED','DASTAK_FULFILMENT_FAILURE');
create index merchant_orders_customer_active_discovery_idx on private.merchant_orders(customer_account_id,created_at desc,id desc)
 where status not in ('delivered','cancelled');
create function private.customer_active_order_discovery(p_actor_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform dastak_v1_api.assert_customer_actor(p_actor_id);
 if p_actor_id is null or p_actor_id is distinct from auth.uid() then raise exception using errcode='42501',message='customer required'; end if;
 with active as materialized (
  select id,'v1'::text kind,case when order_type='FOOD_ONLY' then 'food' else 'grocery' end service,
   status::text status,version,created_at
  from dastak_v1.orders where customer_id=p_actor_id
   and status not in ('DELIVERED','UNAVAILABLE','PAYMENT_EXPIRED','CANCELLED_PREPAYMENT','CANCELLED','DASTAK_FULFILMENT_FAILURE')
  union all
  select id,'merchant','grocery',status,state_version,created_at from private.merchant_orders
   where customer_account_id=p_actor_id and status not in ('delivered','cancelled')
 ), page as (select * from active order by created_at desc,id desc,kind limit 20)
 select jsonb_build_object('totalCount',(select count(*) from active),'orders',coalesce((select jsonb_agg(
  jsonb_build_object('id',id,'kind',kind,'service',service,'status',status,'version',version,'createdAt',created_at)
  order by created_at desc,id desc,kind) from page),'[]'::jsonb)) into result;
 return result;
end;$$;
create function public.dastak_v1_customer_active_orders() returns jsonb language sql stable security invoker set search_path='' as $$
 select private.customer_active_order_discovery(auth.uid());
$$;
revoke all on function private.customer_active_order_discovery(uuid),public.dastak_v1_customer_active_orders() from public,anon,service_role;
grant execute on function private.customer_active_order_discovery(uuid),public.dastak_v1_customer_active_orders() to authenticated;
