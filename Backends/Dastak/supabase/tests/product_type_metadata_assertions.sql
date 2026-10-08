do $test$
declare previous record; current_function record; result jsonb; invalid_value jsonb;
begin
  select * into strict previous from public.product_type_original;
  select pg_get_functiondef(oid) as definition,proacl,prosecdef,proconfig,proowner into strict current_function from pg_proc where oid='dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer)'::regprocedure;
  assert current_function.definition=replace(previous.definition,'''variant'', sku.variant_name,','''variant'', sku.variant_name,
        ''attributes'', pg_catalog.jsonb_build_object(''productType'', sku.attribute_data->''productType''),');
  assert current_function.proacl is not distinct from previous.proacl;
  assert current_function.prosecdef=previous.prosecdef and current_function.proconfig=previous.proconfig and current_function.proowner=previous.proowner;
  assert (select convalidated from pg_constraint where conname='skus_product_type_valid' and conrelid='dastak_v1.skus'::regclass);
  result:=dastak_v1_api.merchant_canonical_catalogue_snapshot('00000000-0000-4000-8000-000000000001');
  assert result->0->'attributes'='{"productType":"Full Cream"}'::jsonb,'Expose classification only, not arbitrary attributes';
  assert result->0->>'variant'='Vanilla','Variant is separate';
  assert result->1->'attributes'='{"productType":null}'::jsonb,'Do not invent classification';
  assert (select attribute_data->'ingredients'='["Milk"]'::jsonb from dastak_v1.skus where id=1),'No backfill or attribute replacement';
  update dastak_v1.skus set attribute_data=jsonb_build_object('productType',repeat('a',100)) where id=2;
  for invalid_value in select value from jsonb_array_elements(jsonb_build_array(3,true,jsonb_build_object('name','Toned'),'','  ',repeat('a',101),E'Toned\nMilk')) loop
    begin
      update dastak_v1.skus set attribute_data=jsonb_build_object('productType',invalid_value) where id=2;
      raise exception 'Invalid classification accepted: %',invalid_value;
    exception when check_violation then null;
    end;
  end loop;
  update dastak_v1.skus set attribute_data='{"productType":null}' where id=2;
  update dastak_v1.skus set attribute_data='{}' where id=2;
end;
$test$;
set role authenticated;
do $actor$ begin
  assert jsonb_array_length(dastak_v1_api.merchant_canonical_catalogue_snapshot('00000000-0000-4000-8000-000000000001'))=2;
  begin
    perform dastak_v1_api.merchant_canonical_catalogue_snapshot('00000000-0000-4000-8000-000000000002');
    raise exception 'Foreign actor accepted';
  exception when insufficient_privilege then null;
  end;
end; $actor$;
reset role;
set role anon;
do $anon$ begin
  begin
    perform dastak_v1_api.merchant_canonical_catalogue_snapshot('00000000-0000-4000-8000-000000000001');
    raise exception 'Anonymous invocation accepted';
  exception when insufficient_privilege then null;
  end;
end; $anon$;
reset role;
select 'Product Type SQL constraints, exact projection preservation and role guards passed' as result;
