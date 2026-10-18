set role authenticated;
set request.jwt.claim.sub='99000000-0000-4000-8000-000000000001';
do $test$
declare result jsonb; kind text; target uuid;
begin
  for kind,target in select * from (values
    ('FULFILMENT','99000000-0000-4000-8000-000000000041'::uuid),
    ('OPPORTUNITY','99000000-0000-4000-8000-000000000051'::uuid),
    ('RESTAURANT_REQUEST','99000000-0000-4000-8000-000000000052'::uuid),
    ('RECOVERY','99000000-0000-4000-8000-000000000053'::uuid),
    ('RETURN','99000000-0000-4000-8000-000000000062'::uuid)) v(kind,target)
  loop
    result:=public.dastak_v1_merchant_order_detail('99000000-0000-4000-8000-000000000011',kind,target);
    assert result#>>'{order,displayOrderNumber}'='DSK-OLD-001';
    assert jsonb_array_length(result->'records')=3;
    assert jsonb_array_length(result->'returns')=1;
    assert jsonb_array_length(result->'settlements')=1;
    assert jsonb_array_length(result->'recoveryOffers')=1;
    assert result::text not like '%PRIVATE_SECRET%' and result::text not like '%OTHER_STORE_SECRET%';
    assert result::text not like '%pickupCode%' and result::text not like '%receiptCode%' and result::text not like '%objectPath%';
    assert result::text not like '%"tracking"%' and result::text not like '%"totalPaise"%','No tracking or customer-wide total';
    assert result#>>'{records,0,lines,0,selection,options,0,name}'='Less sugar';
    assert result#>>'{records,0,productSubtotalPaise}'='1000';
  end loop;
  begin
    perform public.dastak_v1_merchant_order_detail('99000000-0000-4000-8000-000000000012','FULFILMENT','99000000-0000-4000-8000-000000000042');
    raise exception 'Same-organization foreign location authorized';
  exception when no_data_found then null; end;
  begin
    perform public.dastak_v1_merchant_order_detail('99000000-0000-4000-8000-000000000011','FULFILMENT','99000000-0000-4000-8000-000000000042');
    raise exception 'Target branch mismatch authorized';
  exception when no_data_found then null; end;
  begin
    perform dastak_v1_api.merchant_order_detail('99000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000011','FULFILMENT','99000000-0000-4000-8000-000000000041');
    raise exception 'Forged actor accepted';
  exception when insufficient_privilege then null; end;
end;
$test$;
set request.jwt.claim.sub='99000000-0000-4000-8000-000000000002';
do $limited$
declare result jsonb;
begin
  result:=public.dastak_v1_merchant_order_detail('99000000-0000-4000-8000-000000000011','OPPORTUNITY','99000000-0000-4000-8000-000000000051');
  assert jsonb_array_length(result->'records')=2;
  assert jsonb_array_length(result->'returns')=0 and jsonb_array_length(result->'settlements')=0;
  begin
    perform public.dastak_v1_merchant_order_detail('99000000-0000-4000-8000-000000000011','FULFILMENT','99000000-0000-4000-8000-000000000041');
    raise exception 'Respond-only actor received fulfilment';
  exception when no_data_found then null; end;
end;
$limited$;
reset role;
do $grants$
begin
 assert dastak_v1_api.merchant_detail_record('FULFILMENT','{"lines":null,"evidence":null,"problemReports":null,"recoveryCases":null,"delivery":null}') -> 'lines' = '[]'::jsonb;
 assert dastak_v1_api.merchant_detail_record('FULFILMENT','{"lines":[{"selection":{"options":null}}]}') #> '{lines,0,selection,options}' = '[]'::jsonb;
 assert dastak_v1_api.merchant_detail_record('OPPORTUNITY','{"startedAt":"2026-10-18T00:00:00Z"}') ->> 'offeredAt' = '2026-10-18T00:00:00Z';
 assert not has_function_privilege('anon','public.dastak_v1_merchant_order_detail(uuid,text,uuid)','execute');
 assert not has_function_privilege('service_role','public.dastak_v1_merchant_order_detail(uuid,text,uuid)','execute');
 assert not has_function_privilege('authenticated','dastak_v1_api.merchant_detail_record(text,jsonb)','execute');
 assert (select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='dastak_v1_api.merchant_order_detail(uuid,uuid,text,uuid)'::regprocedure);
end;
$grants$;
select 'Merchant detail: all target kinds, historical lookup, branch/actor/least-privilege, payload privacy and grants passed' as result;
