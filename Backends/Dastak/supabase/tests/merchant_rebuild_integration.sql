-- Appended before finish/rollback in the real Wave-1 contract fixture.
-- All application helpers, projections, triggers and financial delegates are
-- the original migrated functions. No provider or hosted service is involved.
reset role;
create temporary table merchant_integration_context as
select id,order_id from dastak_v1.fulfilments
where branch_id='97000000-0000-4000-8000-000000000021' limit 1;
grant select on merchant_integration_context to authenticated;
select is((select count(*) from merchant_integration_context),1::bigint,'integration has a real command-created fulfilment');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000003',true);
create temporary table merchant_integration_detail as select public.dastak_v1_merchant_order_detail(
 '97000000-0000-4000-8000-000000000021','FULFILMENT',(select id from merchant_integration_context)) body;
select is((select body#>>'{order,id}' from merchant_integration_detail),
 (select order_id::text from merchant_integration_context),'detail resolves original historical order through real projections');
select ok((select body::text like '%Wave One Product%' from merchant_integration_detail),'detail contains the actual product snapshot');
select ok((select not (body ? 'customer') and not (body ? 'deliveryAddress') and not (body ? 'totalPaise') from merchant_integration_detail),
 'detail does not return Customer private/full-total fields');
select is(jsonb_array_length(public.dastak_v1_merchant_fulfilment_history(
 '97000000-0000-4000-8000-000000000021',null,null,1)->'fulfilments'),1,'released fulfilment is discoverable through history');
select is(jsonb_array_length(public.dastak_v1_merchant_locations_page(1)->'locations'),1,'directory discovers authorized fixture business');
select is(public.dastak_v1_merchant_locations_page(1)#>>'{locations,0,id}',
 '97000000-0000-4000-8000-000000000021','directory does not adopt foreign branch');
select is(public.dastak_v1_merchant_inventory_page('97000000-0000-4000-8000-000000000021',
 'Wave One Product',true,1)#>>'{skus,0,skuId}','97000000-0000-4000-8000-000000000013',
 'selected catalogue uses original search helpers and actual stock selection');
select is(public.dastak_v1_merchant_inventory_page('97000000-0000-4000-8000-000000000021',
 'Wave One Product',true,1)#>>'{skus,0,stockQuantity}','20','cancelled order restored stock projects correctly');
select lives_ok($paging$do $body$
declare page jsonb; cursor jsonb; seen uuid[]:='{}'; product jsonb;
begin
 loop
  page:=public.dastak_v1_merchant_inventory_page('97000000-0000-4000-8000-000000000021',null,false,7,
   cursor->>'name',(cursor->>'skuId')::uuid);
  for product in select * from jsonb_array_elements(page->'skus') loop
   if (product->>'skuId')::uuid=any(seen) then raise exception 'Repeated catalogue SKU'; end if;
   seen:=array_append(seen,(product->>'skuId')::uuid);
  end loop;
  cursor:=page->'nextCursor';exit when cursor='null'::jsonb;
 end loop;
 if cardinality(seen)<90 or not '97000000-0000-4000-8000-000000000013'::uuid=any(seen) then
  raise exception 'Incomplete actual seeded catalogue';
 end if;
end $body$$paging$,'real seeded catalogue traverses multiple pages without duplicates or missing fixture product');
select throws_ok($$select public.dastak_v1_merchant_inventory_page('97000000-0000-4000-8000-000000000031')$$,
 '42501','Merchant catalogue is unavailable','foreign inventory is denied by actual permission helper');
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000004',true);
select throws_ok($$select public.dastak_v1_merchant_order_detail('97000000-0000-4000-8000-000000000021',
 'FULFILMENT',(select id from merchant_integration_context))$$,'P0002','Merchant order not found','foreign order detail is denied');
select throws_ok($$select public.dastak_v1_merchant_fulfilment_history('97000000-0000-4000-8000-000000000021')$$,
 '42501','Merchant history unavailable','foreign history is denied');
reset role;

-- The fixture's branch-management bundle is insufficient for organization
-- payout management. Grant only the existing read permission first.
insert into dastak_v1.permission_bundles(id,bundle_key,display_name,scope,description)
values('97000000-0000-4000-8000-000000000080','merchant_rebuild_read','Rebuild Read','MERCHANT','Rollback-only earnings reader');
insert into dastak_v1.permission_bundle_permissions(bundle_id,permission_key)
values('97000000-0000-4000-8000-000000000080','merchant.earnings.read');
insert into dastak_v1.merchant_permission_grants(merchant_user_id,organization_id,bundle_id,granted_by,grant_reason)
values('97000000-0000-4000-8000-000000000022','97000000-0000-4000-8000-000000000020',
 '97000000-0000-4000-8000-000000000080','97000000-0000-4000-8000-000000000002','Rollback-only integration read');
set local role service_role;
select is((select response_body#>>'{subjects,0,canManagePayouts}' from public.dastak_v1_merchant_royalty_controls_snapshot(
 '97000000-0000-4000-8000-000000000003')),'false','real earnings reader cannot gain withdrawal authority');
select throws_ok($$select public.dastak_v1_request_merchant_royalty_withdrawal_checked('97000000-0000-4000-8000-000000000003',
 '97000000-0000-4000-8000-000000000020',100,'reader-denied','97000000-0000-4000-8000-000000000099',1)$$,
 '42501','Royalty withdrawal permission required','service boundary still denies read-only Merchant withdrawal');
reset role;
insert into dastak_v1.merchant_permission_grants(merchant_user_id,organization_id,bundle_id,granted_by,grant_reason)
values('97000000-0000-4000-8000-000000000022','97000000-0000-4000-8000-000000000020',
 '10000000-0000-4000-8000-000000000001','97000000-0000-4000-8000-000000000002','Rollback-only integration owner');
select is((select response_body#>>'{subjects,0,canManagePayouts}' from public.dastak_v1_merchant_royalty_controls_snapshot(
 '97000000-0000-4000-8000-000000000003')),'true','management capability is independent of zero available balance');
select dastak_v1_api.post_balanced_financial_transaction(
 'MERCHANT:REBUILD:EARNING','MERCHANT_ROYALTY_EARNING',5000,'MERCHANT_FULFILMENT_COST',null,null,
 'MERCHANT_ROYALTY_PAYABLE','MERCHANT_ORGANIZATION','97000000-0000-4000-8000-000000000020',
 null,null,null,null,null,null,null,null,'Rollback-only integrated earning','{"test":true}');
create temporary table merchant_integration_destination as select dastak_v1_api.register_royalty_payout_destination(
 '97000000-0000-4000-8000-000000000003','MERCHANT_ORGANIZATION','97000000-0000-4000-8000-000000000020',
 'UPI','TEST_PAYOUT','synthetic-only-token','UPI • te***@test','{"test":true}') body;
grant select on merchant_integration_destination to service_role;
set local role service_role;
select throws_ok($$select public.dastak_v1_request_merchant_royalty_withdrawal_checked('97000000-0000-4000-8000-000000000003',
 '97000000-0000-4000-8000-000000000020',100,'wrong-destination','97000000-0000-4000-8000-000000000099',1)$$,
 '40001','REVIEWED_PAYOUT_DESTINATION_CHANGED','wrong reviewed destination rejected before real reservation');
create temporary table merchant_integration_withdrawal as select public.dastak_v1_request_merchant_royalty_withdrawal_checked(
 '97000000-0000-4000-8000-000000000003','97000000-0000-4000-8000-000000000020',1000,'integrated-original',
 (select (body->>'destinationId')::uuid from merchant_integration_destination),1) body;
grant select on merchant_integration_withdrawal to postgres;
select is((select body->>'status' from merchant_integration_withdrawal),'REQUESTED','checked wrapper delegates actual reservation');
reset role;
select is(dastak_v1_api.royalty_balance_paise('MERCHANT_ORGANIZATION','97000000-0000-4000-8000-000000000020'),
 4000::bigint,'actual balanced journal reserves exactly the requested amount');
select is((select count(*) from dastak_v1.financial_journal_transactions where transaction_type='WITHDRAWAL_RESERVATION'),
 1::bigint,'one reservation transaction exists');
select is((select count(*) from dastak_v1.financial_journal_lines l join dastak_v1.financial_journal_transactions t on t.id=l.transaction_id
 where t.transaction_type='WITHDRAWAL_RESERVATION'),2::bigint,'reservation has actual balanced debit/credit lines');
select dastak_v1_api.register_royalty_payout_destination(
 '97000000-0000-4000-8000-000000000003','MERCHANT_ORGANIZATION','97000000-0000-4000-8000-000000000020',
 'UPI','TEST_PAYOUT','synthetic-only-token-new','UPI • ne***@test','{"test":true}');
set local role service_role;
select is(public.dastak_v1_request_merchant_royalty_withdrawal_checked(
 '97000000-0000-4000-8000-000000000003','97000000-0000-4000-8000-000000000020',1000,'integrated-original',
 (select (body->>'destinationId')::uuid from merchant_integration_destination),1)->>'withdrawalId',
 (select body->>'withdrawalId' from merchant_integration_withdrawal),'original receipt replays after real destination replacement');
select throws_ok($$select public.dastak_v1_request_merchant_royalty_withdrawal_checked('97000000-0000-4000-8000-000000000003',
 '97000000-0000-4000-8000-000000000020',1000,'new-stale',
 (select (body->>'destinationId')::uuid from merchant_integration_destination),1)$$,
 '40001','REVIEWED_PAYOUT_DESTINATION_CHANGED','new request cannot use inactive old destination');
select throws_ok($$select public.dastak_v1_request_merchant_royalty_withdrawal_checked('97000000-0000-4000-8000-000000000003',
 '97000000-0000-4000-8000-000000000020',999,'integrated-original',
 (select (body->>'destinationId')::uuid from merchant_integration_destination),1)$$,
 '22023','idempotency key was already used with a different request','real delegate rejects changed amount under original key');
reset role;
select is(dastak_v1_api.royalty_balance_paise('MERCHANT_ORGANIZATION','97000000-0000-4000-8000-000000000020'),
 4000::bigint,'replay and rejected changes do not reserve funds again');
select is((select count(*) from dastak_v1.financial_journal_transactions where transaction_type='WITHDRAWAL_RESERVATION'),
 1::bigint,'no duplicate real journal reservation');
select is((select destination_snapshot->>'providerDestinationReference' from dastak_v1.royalty_withdrawals
 where id=(select (body->>'withdrawalId')::uuid from merchant_integration_withdrawal)),
 'synthetic-only-token','original withdrawal retains original immutable provider destination');
select ok((select bool_and(balance=0) from (select transaction_id,
 sum(case direction when 'DEBIT' then amount_paise else -amount_paise end) balance
 from dastak_v1.financial_journal_lines group by transaction_id) q),'all financial journals remain balanced');
select is((select count(*) from dastak_v1.domain_events_outbox where event_type='ROYALTY_WITHDRAWAL_REQUESTED'),
 1::bigint,'exactly one real withdrawal notification intent is written');
select ok(not has_function_privilege('authenticated',
 'public.dastak_v1_request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint)','EXECUTE'),
 'actor-supplied checked withdrawal remains inaccessible to clients');
