do $$declare actor uuid:='95000000-0000-4000-8000-000000000031'; org uuid:='95000000-0000-4000-8000-000000000001'; destination uuid:='95000000-0000-4000-8000-000000000091'; data jsonb; begin
  select response_body into data from public.dastak_v1_merchant_royalty_controls_snapshot(actor);
  if data#>>'{subjects,0,canManagePayouts}'<>'true' then raise exception 'Payout permission missing'; end if;
  select response_body into data from public.dastak_v1_merchant_royalty_controls_snapshot('95000000-0000-4000-8000-000000000033');
  if data#>>'{subjects,0,canManagePayouts}'<>'false' then raise exception 'Read-only permission escalated'; end if;
  begin perform public.dastak_v1_request_merchant_royalty_withdrawal_checked(actor,org,100,'wrong',gen_random_uuid(),1); raise exception 'Wrong destination accepted'; exception when serialization_failure then null; end;
  begin perform public.dastak_v1_request_merchant_royalty_withdrawal_checked(actor,org,100,'wrong-version',destination,2); raise exception 'Wrong version accepted'; exception when serialization_failure then null; end;
  begin perform public.dastak_v1_request_merchant_royalty_withdrawal_checked('95000000-0000-4000-8000-000000000033',org,100,'readonly',destination,1); raise exception 'Read-only withdrew'; exception when insufficient_privilege then null; end;
  begin perform public.dastak_v1_request_merchant_royalty_withdrawal_checked(actor,'95000000-0000-4000-8000-000000000002',100,'foreign',destination,1); raise exception 'Foreign organization accepted'; exception when insufficient_privilege then null; end;
  perform public.dastak_v1_request_merchant_royalty_withdrawal_checked(actor,org,100,'first',destination,1);
  if has_function_privilege('authenticated','public.dastak_v1_request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint)','execute')
    or has_function_privilege('anon','public.dastak_v1_merchant_royalty_controls_snapshot(uuid)','execute') then raise exception 'Actor argument exposed to client'; end if;
end$$;
set role service_role;
select * from public.dastak_v1_merchant_royalty_controls_snapshot('95000000-0000-4000-8000-000000000031');
reset role;
