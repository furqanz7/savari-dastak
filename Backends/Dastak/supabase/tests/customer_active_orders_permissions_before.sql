grant usage on schema auth,dastak_v1_api to authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
set role authenticated;
do $$begin
 begin
  perform public.dastak_v1_customer_active_orders();
  raise exception 'Expected inaccessible private schema before repair';
 exception when insufficient_privilege then
  assert sqlerrm='permission denied for schema private',sqlerrm;
 end;
end;$$;
reset role;
