begin;
do $$
declare actor uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; address uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  version timestamptz := '2026-10-08T00:00:00Z'; result jsonb; cursor jsonb; ids uuid[] := '{}'; item jsonb;
  page_count integer := 0; last_distance integer := -1; distance integer;
begin
  loop
    result := dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version,null,1,
      cursor->>'name',(cursor->>'branchId')::uuid,(cursor->>'distanceMeters')::integer);
    if result->>'ordering'<>'NEAREST' then raise exception 'missing distance order'; end if;
    for item in select value from jsonb_array_elements(result->'restaurants') loop
      ids := array_append(ids,(item->'restaurant'->>'branchId')::uuid);
      distance := coalesce((item->'restaurant'->>'distanceMeters')::integer,2147483647);
      if distance < last_distance then raise exception 'not globally nearest first'; end if;
      last_distance := distance;
    end loop;
    page_count := page_count+1; cursor := nullif(result->'nextCursor','null'::jsonb); exit when cursor is null;
    if page_count>205 then raise exception 'cursor did not finish'; end if;
  end loop;
  if cardinality(ids)<>205 or (select count(distinct x) from unnest(ids)x)<>205 then raise exception 'pages truncated or duplicated'; end if;
  if ids[1]<>md5('branch205')::uuid then raise exception 'nearest branch beyond alphabetical cap was missed'; end if;
  if ids[204]<>md5('branch1')::uuid or ids[205]<>md5('branch2')::uuid then raise exception 'unknown coordinates not last'; end if;
  result := dastak_v1_api.list_customer_restaurants_nearest_page(actor,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',version,null,1);
  if result->'restaurants'->0->'restaurant'->>'branchId'<>md5('branch3')::uuid::text then raise exception 'changed origin did not rerank'; end if;
  result := dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version,'Beyond cap dish',100);
  if jsonb_array_length(result->'restaurants')<>1 then raise exception 'global dish search broken'; end if;
  update dastak_v1.branch_operational_states set is_open=false where branch_id=md5('branch205')::uuid;
  if jsonb_array_length(dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version,'Beyond cap dish')->'restaurants')<>0 then raise exception 'closed branch leaked'; end if;
  insert into dastak_v1.operational_pause_controls values(true,'ZONE_FOOD',null,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  if jsonb_array_length(dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version)->'restaurants')<>0 then raise exception 'paused zone leaked'; end if;
  begin perform dastak_v1_api.list_customer_restaurants_nearest_page(null,address,version); raise exception 'actor guard missing'; exception when insufficient_privilege then null; end;
  begin perform dastak_v1_api.list_customer_restaurants_nearest_page(actor,'ffffffff-ffff-4fff-8fff-ffffffffffff',version); raise exception 'other customer address leaked'; exception when insufficient_privilege then null; end;
  begin perform dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version+interval '1 second'); raise exception 'stale location accepted'; exception when invalid_parameter_value then null; end;
  begin perform dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version,null,100,'name',null); raise exception 'partial cursor accepted'; exception when invalid_parameter_value then null; end;
  begin perform dastak_v1_api.list_customer_restaurants_nearest_page(actor,address,version,null,100,'name',md5('branch1')::uuid,-1); raise exception 'invalid distance accepted'; exception when invalid_parameter_value then null; end;
  if has_function_privilege('anon','public.dastak_v1_customer_restaurants_nearest_page(uuid,timestamptz,text,integer,text,uuid,integer)','execute') then raise exception 'anonymous execution granted'; end if;
  if has_function_privilege('authenticated','public.dastak_v1_customer_restaurants_nearest_page(uuid,timestamptz,text,integer,text,uuid,integer)','execute') is not true then raise exception 'authenticated grant missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
set local role authenticated;
select public.dastak_v1_customer_restaurants_nearest_page('dddddddd-dddd-4ddd-8ddd-dddddddddddd','2026-10-08T00:00:00Z',null,1);
rollback;
