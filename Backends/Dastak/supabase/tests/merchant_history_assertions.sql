select set_config('request.jwt.claim.sub','99000000-0000-4000-8000-000000000001',false);
do $$
declare
 actor uuid='99000000-0000-4000-8000-000000000001';
 branch uuid='99000000-0000-4000-8000-000000000011';
 old_active text='99000000-0000-4000-8000-000000000041';
 result jsonb; page jsonb; next_at timestamptz; next_id uuid;
 ids uuid[]='{}'; row jsonb; count_pages integer=0;
begin
 if not dastak_v1_api.merchant_fulfilment_is_history('READY','DELIVERED')
   or dastak_v1_api.merchant_fulfilment_is_history('READY','PREPARING')
   or not dastak_v1_api.merchant_fulfilment_is_history('RELEASED','PREPARING')
 then raise exception 'Terminal classification is inconsistent';end if;
 result:=dastak_v1_api.list_merchant_fulfilments(actor,1);
 if jsonb_array_length(result->'fulfilments')<>2 or not exists(
   select 1 from jsonb_array_elements(result->'fulfilments') x where x->>'id'=old_active
 ) then raise exception 'Old active work was displaced by history';end if;
 if result->'recoveryOpportunities' is distinct from (select payload->'recoveryOpportunities' from fixture_previous_feed)
 or result->'returnReceipts' is distinct from (select payload->'returnReceipts' from fixture_previous_feed)
 or result->'settlements' is distinct from (select payload->'settlements' from fixture_previous_feed)
 then raise exception 'Other operations feeds changed';end if;
 loop
   page:=dastak_v1_api.merchant_fulfilment_history(actor,branch,next_at,next_id,37);
   count_pages:=count_pages+1;
   for row in select * from jsonb_array_elements(page->'fulfilments') loop
     if (row->>'id')::uuid=any(ids) or row->>'id'=old_active
       or row->>'branchId'<>branch::text then raise exception 'Duplicate, active or foreign history row';end if;
     ids:=array_append(ids,(row->>'id')::uuid);
   end loop;
   exit when page->'nextCursor'='null'::jsonb;
   next_at:=(page->'nextCursor'->>'committedAt')::timestamptz;
   next_id:=(page->'nextCursor'->>'id')::uuid;
   if count_pages>10 then raise exception 'Cursor never progressed';end if;
 end loop;
 if cardinality(ids)<>151 or count_pages<>5
   or not '99000000-0000-4000-8000-000000000043'::uuid=any(ids)
 then raise exception 'History was truncated or COMPLETED was misclassified: %, %',cardinality(ids),count_pages;end if;
 -- Cursor ties preserve all six fractional timestamp digits.
 page:=dastak_v1_api.merchant_fulfilment_history(actor,branch,null,null,1);
 if (page->'nextCursor'->>'committedAt')::timestamptz<>'2026-10-01T00:00:00.123456Z'::timestamptz
 then raise exception 'Timestamp precision lost';end if;
 begin perform dastak_v1_api.merchant_fulfilment_history(actor,'99000000-0000-4000-8000-000000000012'); raise exception 'Foreign branch allowed';
 exception when insufficient_privilege then null;end;
 begin perform dastak_v1_api.merchant_fulfilment_history(actor,branch,now(),null);raise exception 'Partial cursor allowed';
 exception when invalid_parameter_value then null;end;
 begin perform dastak_v1_api.merchant_fulfilment_history(actor,branch,null,null,101);raise exception 'Unbounded page allowed';
 exception when invalid_parameter_value then null;end;
 begin perform dastak_v1_api.merchant_fulfilment_history('99000000-0000-4000-8000-000000000002',branch);raise exception 'Forged actor allowed';
 exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.dastak_v1_merchant_fulfilment_history(uuid,timestamptz,uuid,integer)','execute')
 or has_function_privilege('service_role','dastak_v1_api.merchant_fulfilment_history(uuid,uuid,timestamptz,uuid,integer)','execute')
 or not has_function_privilege('authenticated','public.dastak_v1_merchant_fulfilment_history(uuid,timestamptz,uuid,integer)','execute')
 then raise exception 'Incorrect function grants';end if;
end;$$;
set role authenticated;
do $$begin
 if jsonb_array_length(public.dastak_v1_merchant_fulfilment_history('99000000-0000-4000-8000-000000000011')->'fulfilments')<>50
 then raise exception 'Public wrapper did not return its bounded page';end if;
end;$$;
reset role;
select set_config('request.jwt.claim.sub','99000000-0000-4000-8000-000000000002',false);
do $$begin
 begin perform public.dastak_v1_merchant_fulfilment_history('99000000-0000-4000-8000-000000000011');
 raise exception 'Respond-only actor read managed history';exception when insufficient_privilege then null;end;
end;$$;
select 'Merchant active/history fixture passed' as result;
