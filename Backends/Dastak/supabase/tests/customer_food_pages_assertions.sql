begin;
do $$
declare actor uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; result jsonb; cursor jsonb; ids uuid[] := '{}'; item jsonb; page_count integer := 0;
begin
  loop
    result := dastak_v1_api.list_customer_restaurants_page(actor,null,100,cursor->>'name',(cursor->>'branchId')::uuid);
    for item in select value from jsonb_array_elements(result->'restaurants') loop ids := array_append(ids,(item->'restaurant'->>'branchId')::uuid); end loop;
    page_count := page_count+1; cursor := nullif(result->'nextCursor','null'::jsonb); exit when cursor is null;
    if page_count>3 then raise exception 'cursor did not finish'; end if;
  end loop;
  if cardinality(ids)<>205 or (select count(distinct x) from unnest(ids)x)<>205 then raise exception 'pages truncated or duplicated'; end if;
  result := dastak_v1_api.list_customer_restaurants_page(actor,'Beyond cap dish',100);
  if jsonb_array_length(result->'restaurants')<>1 then raise exception 'global dish search missed branch beyond first 100'; end if;
  result := dastak_v1_api.list_customer_restaurants_page(actor,null,1,null,null,md5('branch205')::uuid);
  if jsonb_array_length(result->'restaurants')<>1 or result->'nextCursor'<>'null'::jsonb then raise exception 'exact branch lookup failed'; end if;
  update dastak_v1.branch_operational_states set is_open=false where branch_id=md5('branch205')::uuid;
  result := dastak_v1_api.list_customer_restaurants_page(actor,null,1,null,null,md5('branch205')::uuid);
  if jsonb_array_length(result->'restaurants')<>0 then raise exception 'closed branch leaked'; end if;
  insert into dastak_v1.operational_pause_controls values(true,'ZONE_FOOD',null,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  if jsonb_array_length(dastak_v1_api.list_customer_restaurants_page(actor)->'restaurants')<>0 then raise exception 'paused zone leaked'; end if;
  begin perform dastak_v1_api.list_customer_restaurants_page(null); raise exception 'actor guard missing'; exception when insufficient_privilege then null; end;
  begin perform dastak_v1_api.list_customer_restaurants_page(actor,null,100,'name',null); raise exception 'partial cursor accepted'; exception when invalid_parameter_value then null; end;
  if has_function_privilege('anon','public.dastak_v1_customer_restaurants_page(text,integer,text,uuid,uuid)','execute') then raise exception 'anonymous execution granted'; end if;
end $$;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
set local role authenticated;
select public.dastak_v1_customer_restaurants_page(null,1);
rollback;
