do $$declare result jsonb; begin
 result:=public.dastak_v1_customer_active_orders();
 assert (result->>'totalCount')::integer=3,'old unfinished orders discovered behind completed history';
 assert jsonb_array_length(result->'orders')=3;
 assert result->'orders'->0->>'kind'='merchant','legacy identity retained';
 assert result->'orders'->1->>'service'='food','Food lane retained';
 assert not exists(select 1 from jsonb_array_elements(result->'orders') row where row->>'id' in ('00000000-0000-4000-8000-000000000993','00000000-0000-4000-8000-000000000996')),'no other customer leakage';
 begin perform private.customer_active_order_discovery('99999999-9999-4999-8999-999999999999'); raise exception 'actor override accepted'; exception when insufficient_privilege then null; end;
 assert not has_function_privilege('anon','public.dastak_v1_customer_active_orders()','execute');
 assert has_function_privilege('authenticated','public.dastak_v1_customer_active_orders()','execute');
end;$$;
insert into dastak_v1.orders(id,customer_id,status) select md5('active-'||i)::uuid,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','PREPARING' from generate_series(1,25)i;
do $$declare result jsonb; begin
 result:=public.dastak_v1_customer_active_orders();
 assert (result->>'totalCount')::integer=28 and jsonb_array_length(result->'orders')=20,'bounded hints with truthful total';
end;$$;
select set_config('request.jwt.claim.sub','',false);
do $$begin
 begin perform public.dastak_v1_customer_active_orders(); raise exception 'unauthenticated discovery accepted'; exception when insufficient_privilege then null; end;
end;$$;
select 'Owned active-order discovery assertions passed' as result;
