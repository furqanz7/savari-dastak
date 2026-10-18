select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000031',false);
do $$
declare page jsonb; cursor jsonb; total integer:=0; seen uuid[]:='{}'; location_cursor uuid; focus uuid; row jsonb;
begin
  loop
    page:=public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011',null,false,250,cursor->>'name',(cursor->>'skuId')::uuid);
    for row in select * from jsonb_array_elements(page->'skus') loop
      if (row->>'skuId')::uuid=any(seen) then raise exception 'Duplicate product across pages'; end if;
      seen:=array_append(seen,(row->>'skuId')::uuid); total:=total+1;
    end loop;
    cursor:=page->'nextCursor'; exit when cursor='null'::jsonb;
  end loop;
  if total<>5201 then raise exception 'Expected all 5201 authorized products, got %',total; end if;
  foreach row in array array[
    public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011','beyond cap',false,100,null,null),
    public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011','Acme chai',false,100,null,null),
    public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011',null,true,100,null,null)
  ] loop
    if jsonb_array_length(row->'skus')<>1 or row#>>'{skus,0,skuId}'<>'95000000-0000-4000-8000-000000000061'
      then raise exception 'Beyond-cap/alias/storefront search failed'; end if;
    if row#>>'{skus,0,stockQuantity}'<>'11' or row#>>'{skus,0,stockReservedQuantity}'<>'3'
      or row#>>'{skus,0,selectionVersion}'<>'7' or row#>>'{skus,0,imageKey}'<>'cleared.png'
      or row::text like '%UNLICENSED_SECRET%' then raise exception 'Stock/version/media projection mismatch'; end if;
  end loop;
  page:=public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011','Beverages',false,100,null,null);
  if jsonb_array_length(page->'skus')<>100 or page->'nextCursor'='null'::jsonb then raise exception 'Taxonomy search not paged'; end if;
  total:=0; select id into focus from dastak_v1.merchant_branches where organization_id='95000000-0000-4000-8000-000000000001' order by id desc limit 1;
  loop
    page:=public.dastak_v1_merchant_locations_page(100,location_cursor,focus);
    if page::text like '%OTHER_MERCHANT_SECRET%' then raise exception 'Foreign location leaked'; end if;
    if (page#>>'{focusedLocation,id}')::uuid<>focus then raise exception 'Focused location not found outside first page'; end if;
    total:=total+jsonb_array_length(page->'locations');
    location_cursor:=(page->>'nextCursor')::uuid; exit when location_cursor is null;
  end loop;
  if total<>151 then raise exception 'Expected 151 locations, got %',total; end if;
  begin perform public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000012'); raise exception 'Foreign catalogue allowed';
    exception when insufficient_privilege then null; end;
  begin perform dastak_v1_api.merchant_locations_page('95000000-0000-4000-8000-000000000032'); raise exception 'Actor spoof allowed';
    exception when insufficient_privilege then null; end;
  begin perform public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011',null,false,251); raise exception 'Oversized page allowed';
    exception when invalid_parameter_value then null; end;
  begin perform public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011',null,false,100,'partial',null); raise exception 'Partial cursor allowed';
    exception when invalid_parameter_value then null; end;
  if has_function_privilege('anon','public.dastak_v1_merchant_locations_page(integer,uuid,uuid)','execute')
    or has_function_privilege('service_role','public.dastak_v1_merchant_inventory_page(uuid,text,boolean,integer,text,uuid)','execute')
    then raise exception 'Unexpected role grant'; end if;
end $$;
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000032',false);
do $$declare result jsonb; begin
  result:=public.dastak_v1_merchant_locations_page();
  if jsonb_array_length(result->'locations')<>1 or result->>'nextCursor' is not null then raise exception 'Branch scope bypass'; end if;
  update dastak_v1.merchant_users set status='INACTIVE' where id='95000000-0000-4000-8000-000000000022';
  result:=public.dastak_v1_merchant_locations_page();
  if jsonb_array_length(result->'locations')<>0 then raise exception 'Inactive membership visible'; end if;
  update dastak_v1.merchant_users set status='ACTIVE' where id='95000000-0000-4000-8000-000000000022';
  update dastak_v1.merchant_organizations set status='INACTIVE' where id='95000000-0000-4000-8000-000000000001';
  result:=public.dastak_v1_merchant_locations_page();
  if jsonb_array_length(result->'locations')<>0 then raise exception 'Inactive organization visible'; end if;
  update dastak_v1.merchant_organizations set status='ACTIVE' where id='95000000-0000-4000-8000-000000000001';
  update dastak_v1.merchant_permission_grants set revoked_at=now() where merchant_user_id='95000000-0000-4000-8000-000000000022';
  result:=public.dastak_v1_merchant_locations_page();
  if jsonb_array_length(result->'locations')<>0 then raise exception 'Revoked grant still visible'; end if;
  begin perform public.dastak_v1_merchant_inventory_page('95000000-0000-4000-8000-000000000011'); raise exception 'Revoked catalogue permitted';
    exception when insufficient_privilege then null; end;
end $$;
set role authenticated;
select public.dastak_v1_merchant_locations_page();
reset role;
select 'Merchant discovery SQL fixture passed: 5201 products, 151 quiet locations, scope/revocation/media checks' result;
