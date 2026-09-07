begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    'ce000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-owner@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ce000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-outsider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ce000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-rider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (id, display_name, phone_number) values
  ('ce000000-0000-4000-8000-000000000001', 'Orders Owner', '+919500000201'),
  ('ce000000-0000-4000-8000-000000000002', 'Orders Outsider', '+919500000202'),
  ('ce000000-0000-4000-8000-000000000003', 'Orders Rider', '+919500000203');
insert into private.account_memberships (account_id, role) values
  ('ce000000-0000-4000-8000-000000000001', 'customer'),
  ('ce000000-0000-4000-8000-000000000002', 'customer'),
  ('ce000000-0000-4000-8000-000000000003', 'dastak_partner');

insert into public.service_zones (id, name, boundary, coverage_radius_m)
values (
  'ce200000-0000-4000-8000-000000000001',
  'Customer Orders Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.5 12.5,78.8 12.5,78.8 12.8,78.5 12.8,78.5 12.5))',
    4326
  ),
  10000
);

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  'ce210000-0000-4000-8000-000000000001',
  'Customer Orders Test Merchant', 'Customer Orders Merchant',
  'RETAIL', 'ACTIVE', 'ce000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id,
  address_snapshot, location, capacity_limit, status, created_by
) values (
  'ce220000-0000-4000-8000-000000000001',
  'ce210000-0000-4000-8000-000000000001',
  'Private Retail Branch', 'ce200000-0000-4000-8000-000000000001',
  '{"line1":"Private pickup address"}',
  extensions.st_setsrid(extensions.st_makepoint(78.621, 12.681), 4326),
  5, 'ACTIVE', 'ce000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values (
  'ce230000-0000-4000-8000-000000000001', 'ce210000-0000-4000-8000-000000000001',
  'ce000000-0000-4000-8000-000000000002', 'ACTIVE', 'ce000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_permission_grants (
  merchant_user_id, organization_id, bundle_id, branch_id, granted_by, grant_reason
) values (
  'ce230000-0000-4000-8000-000000000001', 'ce210000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002', 'ce220000-0000-4000-8000-000000000001',
  'ce000000-0000-4000-8000-000000000001', 'Cancellation notification fixture.'
);
insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, fully_secured_at, paid_at
) values (
  'ce100000-0000-4000-8000-000000000002', 'DSK-ORDERS-0002',
  'ce000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'PREPARING',
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() - interval '25 minutes',
  null
);
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values (
  'ce100000-0000-4000-8000-000000000002',
  '{"label":"Home","line1":"2 Test Road","countryCode":"IN","latitude":12.68,"longitude":78.62}',
  '{"name":"Orders Owner","phoneNumber":"+919500000201"}',
  pg_catalog.decode(pg_catalog.repeat('01', 32), 'hex')
);
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values (
  'ce100000-0000-4000-8000-000000000002', 'PAID', 1000, 1000
);
insert into dastak_v1.matching_attempts (
  id, order_id, wave, status, started_at, expires_at
) values (
  'ce250000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000002', 'WAVE_1', 'OPEN',
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes'
);
insert into dastak_v1.platform_settings(setting_key,scope_type,setting_value,updated_by,update_reason)
values('merchant.reachability_stale_seconds','GLOBAL','120',
'ce000000-0000-4000-8000-000000000001','Cancellation fixture reachability.');
insert into dastak_v1.merchant_branch_reachability(branch_id,last_seen_at,reported_by)
values('ce220000-0000-4000-8000-000000000001',clock_timestamp(),'ce000000-0000-4000-8000-000000000001');
insert into dastak_v1.merchant_opportunities (
  id, matching_attempt_id, order_id, organization_id, branch_id,
  status, started_at, expires_at, promised_prep_minutes,
  responded_by, responded_at
) values (
  'ce260000-0000-4000-8000-000000000001',
  'ce250000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000002',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001', 'SELECTED',
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes', 10,
  'ce000000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp() - interval '25 minutes'
);
insert into dastak_v1.fulfilments (
  id, order_id, organization_id, branch_id, source_opportunity_id,
  fulfilment_type, status, promised_prep_minutes, committed_at,
  prep_started_at, estimated_ready_at
) values (
  'ce270000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000002',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001',
  'ce260000-0000-4000-8000-000000000001',
  'RETAIL', 'PREPARING', 10,
  pg_catalog.clock_timestamp() - interval '25 minutes',
  pg_catalog.clock_timestamp() - interval '20 minutes',
  pg_catalog.clock_timestamp() - interval '10 minutes'
);

insert into dastak_v1.category_types (
  id, name, slug, status, created_by
) values (
  '97000000-0000-4000-8000-000000000009',
  'Wave One Type', 'wave-one-type', 'ACTIVE',
  'ce000000-0000-4000-8000-000000000001'
);

insert into dastak_v1.categories (
  id, category_type_id, name, slug, status, created_by
) values (
  '97000000-0000-4000-8000-000000000011',
  '97000000-0000-4000-8000-000000000009',
  'Wave One Category',
  'wave-one-category',
  'ACTIVE',
  'ce000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '97000000-0000-4000-8000-000000000012',
  '97000000-0000-4000-8000-000000000011',
  'Wave One Subcategory',
  'wave-one-subcategory',
  'ACTIVE',
  'ce000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, status,
  qa_status, qa_verified_at, qa_verified_by, created_by
) values (
  '97000000-0000-4000-8000-000000000013',
  '97000000-0000-4000-8000-000000000012',
  'Wave One Product',
  'wave-one-product',
  '1 unit',
  1200,
  1000,
  'DRAFT',
  'VERIFIED', now(),
  'ce000000-0000-4000-8000-000000000001',
  'ce000000-0000-4000-8000-000000000001'
);

insert into private.account_memberships(account_id, role, approved_at)
values ('ce000000-0000-4000-8000-000000000001', 'owner', now());
insert into dastak_v1.platform_permission_grants(account_id,bundle_id,granted_by,grant_reason)
values ('ce000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-00000000000c',
'ce000000-0000-4000-8000-000000000001','Cancellation contract test.');
insert into dastak_v1.payments(id,order_id,customer_id,status,amount_paise,currency_code,reserved_at,expires_at,cancelled_at)
values('cc000000-0000-4000-8000-000000000001','ce100000-0000-4000-8000-000000000002',
'ce000000-0000-4000-8000-000000000001','CANCELLED',2000,'INR',now()-interval '25 minutes',now(),now());
insert into dastak_v1.launch_payment_commitments(order_id,customer_id,retired_payment_id,amount_paise,currency_code,secured_at,reservation_expires_at)
values('ce100000-0000-4000-8000-000000000002','ce000000-0000-4000-8000-000000000001',
'cc000000-0000-4000-8000-000000000001',2000,'INR',now()-interval '25 minutes',now());
insert into dastak_v1.order_lines(id,order_id,line_type,sku_id,product_name_snapshot,quantity,unit_price_paise,status)
values('cc000000-0000-4000-8000-000000000002','ce100000-0000-4000-8000-000000000002',
'RETAIL_SKU','97000000-0000-4000-8000-000000000013','Cancellation stock fixture',2,1000,'FULFILLING');
insert into dastak_v1.fulfilment_lines(fulfilment_id,order_line_id,confirmed_quantity)
values('ce270000-0000-4000-8000-000000000001','cc000000-0000-4000-8000-000000000002',2);
insert into dastak_v1.merchant_sku_selections(branch_id,sku_id,state,selected_by,stock_quantity)
values('ce220000-0000-4000-8000-000000000001','97000000-0000-4000-8000-000000000013',
'SELECTED','ce000000-0000-4000-8000-000000000001',10);
select set_config('request.jwt.claim.sub','ce000000-0000-4000-8000-000000000001',true);
insert into dastak_v1.inventory_holds(id,fulfilment_id,order_line_id,branch_id,held_quantity,held_at)
values('cc000000-0000-4000-8000-000000000003','ce270000-0000-4000-8000-000000000001',
'cc000000-0000-4000-8000-000000000002','ce220000-0000-4000-8000-000000000001',2,now());
insert into dastak_v1.retail_capacity_slots(branch_id,fulfilment_id,held_at)
values('ce220000-0000-4000-8000-000000000001','ce270000-0000-4000-8000-000000000001',now());
insert into dastak_v1.packages(id,order_id,fulfilment_id,package_number,status,current_custody_owner_type,current_custody_owner_id,declared_by)
values('cc000000-0000-4000-8000-000000000004','ce100000-0000-4000-8000-000000000002',
'ce270000-0000-4000-8000-000000000001',1,'DECLARED','MERCHANT_BRANCH',
'ce220000-0000-4000-8000-000000000001','ce000000-0000-4000-8000-000000000001');
insert into dastak_v1.platform_settings(setting_key,scope_type,setting_value,updated_by,update_reason)
values('settlement.rider_distance_payout','GLOBAL',
'{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}',
'ce000000-0000-4000-8000-000000000001','Cancellation contract test.');
-- A production order may not yet have any dispatch mission.
savepoint no_mission_fixture;
select lives_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Owner cancelled before dispatch',1,'no-mission')$q$,
'cancellation works before a mission exists');
select is((select stock_quantity from dastak_v1.merchant_sku_selections where branch_id='ce220000-0000-4000-8000-000000000001'),10,'pre-dispatch cancellation restores stock');
rollback to no_mission_fixture;
insert into dastak_v1.delivery_missions(order_id,transport_snapshot,pickup_count)
values('ce100000-0000-4000-8000-000000000002','{}',1);

select is((select stock_quantity from dastak_v1.merchant_sku_selections where branch_id='ce220000-0000-4000-8000-000000000001'),8,'reservation deducts stock first');
select is(has_function_privilege('anon','public.dastak_v1_admin_cancel_order(uuid,text,bigint,text)','execute'),false,'anonymous cancellation denied');
select is(has_table_privilege('authenticated','dastak_v1.order_cancellations','insert'),false,'no direct cancellation writes');
select is((select relrowsecurity from pg_class where oid='dastak_v1.order_cancellations'::regclass),true,'cancellation audit enforces RLS');
select set_config('request.jwt.claim.sub','ce000000-0000-4000-8000-000000000002',true);
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Customer requested cancellation',1,'test-cancel')$q$,
'42501','platform permission required','customer cannot cancel confirmed orders as admin');
select set_config('request.jwt.claim.sub','ce000000-0000-4000-8000-000000000001',true);
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Customer requested cancellation',99,'test-cancel')$q$,
'40001','stale order version','stale version changes nothing');
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','short',1,'test-cancel')$q$,
'22023','Valid reason, version and idempotency key required.','reason is mandatory');
select throws_ok($q$update dastak_v1.orders set status='CANCELLED',version=version+1 where id='ce100000-0000-4000-8000-000000000002'$q$,
'42501','audited admin cancellation command required','status cannot be forced directly');

savepoint paid_fixture;
update dastak_v1.orders set paid_at=now(),version=version+1 where id='ce100000-0000-4000-8000-000000000002';
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Customer requested cancellation',2,'test-paid')$q$,
'55000','Payment has been collected. Use the refund and recovery workflow.','collected payment blocks cancellation');
rollback to paid_fixture;
savepoint pickup_fixture;
update dastak_v1.delivery_missions set first_package_picked_up_at=now(),version=version+1
where order_id='ce100000-0000-4000-8000-000000000002';
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Customer requested cancellation',1,'test-pickup')$q$,
'55000','Pickup or delivery has started. Use the recovery workflow.','historical pickup timestamp blocks cancellation');
rollback to pickup_fixture;

-- A failure at the final event write must roll back stock and every state change.
create function pg_temp.reject_cancel_event() returns trigger language plpgsql as $$
begin
  if new.event_type = 'ORDER_CANCELLED' then raise exception 'injected cancellation event failure'; end if;
  return new;
end;
$$;
create trigger test_cancel_event_failure before insert on dastak_v1.domain_events_outbox
for each row execute function pg_temp.reject_cancel_event();
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Owner requested cancellation',1,'atomic-failure')$q$,
'P0001','injected cancellation event failure','final event failure rolls back cancellation');
select is((select status::text from dastak_v1.orders where id='ce100000-0000-4000-8000-000000000002'),'PREPARING','failed cancellation preserves order');
select is((select stock_quantity from dastak_v1.merchant_sku_selections where branch_id='ce220000-0000-4000-8000-000000000001'),8,'failed cancellation preserves reserved stock');
select is((select count(*) from dastak_v1.order_cancellations),0::bigint,'failed cancellation leaves no audit record');
drop trigger test_cancel_event_failure on dastak_v1.domain_events_outbox;

select is(dastak_v1_api.admin_execution_trace('ce000000-0000-4000-8000-000000000001',
'ce100000-0000-4000-8000-000000000002')#>>'{cancellation,canCancel}','true','eligible admin sees cancellation action');
set local role authenticated;
create temp table cancel_result as select public.dastak_v1_admin_cancel_order(
'ce100000-0000-4000-8000-000000000002','Customer requested cancellation',1,'test-cancel') body;
reset role;
select is((select body->>'status' from cancel_result),'CANCELLED','successful terminal status');
select is((select status::text from dastak_v1.fulfilments where id='ce270000-0000-4000-8000-000000000001'),'RELEASED','merchant work released');
select is((select status::text from dastak_v1.packages where id='cc000000-0000-4000-8000-000000000004'),'CANCELLED','packages cancelled');
select is((select status::text from dastak_v1.delivery_missions where order_id='ce100000-0000-4000-8000-000000000002'),'CANCELLED','mission cancelled');
select is((select status::text from dastak_v1.order_lines where id='cc000000-0000-4000-8000-000000000002'),'CANCELLED','lines cancelled not refunded');
select is((select stock_quantity from dastak_v1.merchant_sku_selections where branch_id='ce220000-0000-4000-8000-000000000001'),10,'stock restored');
select is((select stock_reserved_quantity from dastak_v1.merchant_sku_selections where branch_id='ce220000-0000-4000-8000-000000000001'),0,'reserved count cleared');
select is((select status::text from dastak_v1.retail_capacity_slots where fulfilment_id='ce270000-0000-4000-8000-000000000001'),'RELEASED','capacity released');
select is(public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Customer requested cancellation',1,'test-cancel'),
(select body from cancel_result),'retry returns original response');
select is((select stock_quantity from dastak_v1.merchant_sku_selections where branch_id='ce220000-0000-4000-8000-000000000001'),10,'retry does not restore stock twice');
select throws_ok($q$select public.dastak_v1_admin_cancel_order('ce100000-0000-4000-8000-000000000002','Different cancellation reason',1,'test-cancel')$q$,
'22023','idempotency key was already used with a different request','idempotency cannot change reason');
select is((select count(*) from dastak_v1.order_cancellations),1::bigint,'one immutable cancellation');
select is((select count(*) from dastak_v1.order_state_journal where to_status='CANCELLED'),1::bigint,'one state journal entry');
select is((select count(*) from dastak_v1.domain_events_outbox where event_type='ORDER_CANCELLED'),1::bigint,'one notification event');
select is((select account_id from dastak_v1_api.notification_recipients(
  (select id from dastak_v1.domain_events_outbox where event_type='ORDER_CANCELLED'), 'MERCHANT')),
  'ce000000-0000-4000-8000-000000000002'::uuid,
  'released merchant still receives the cancellation notification');
select is((select account_id from dastak_v1_api.notification_recipients(
  (select id from dastak_v1.domain_events_outbox where event_type='ORDER_CANCELLED'), 'CUSTOMER')),
  'ce000000-0000-4000-8000-000000000001'::uuid,
  'customer receives the cancellation notification');
select is(dastak_v1_api.launch_payment_customer_json('ce100000-0000-4000-8000-000000000002')->>'state','NOT_APPLICABLE','customer has no payment due');
select is(dastak_v1_api.launch_payment_customer_json('ce100000-0000-4000-8000-000000000002')->>'payAtDoorstep','false','no doorstep payment prompt');
select is(dastak_v1_api.launch_payment_admin_json('ce100000-0000-4000-8000-000000000002')->>'collectionStatus','NOT_APPLICABLE','admin has no collection due');
select is(dastak_v1_api.admin_command_center('ce000000-0000-4000-8000-000000000001')#>>'{commerce,activeOrders}','0','cancelled orders excluded from active count');
select throws_ok($q$update dastak_v1.fulfilments set status='READY',version=version+1 where id='ce270000-0000-4000-8000-000000000001'$q$,
'55000','ORDER_CANCELLED','late merchant command rejected');
select throws_ok($q$insert into dastak_v1.delivery_missions(order_id,transport_snapshot,pickup_count) values('ce100000-0000-4000-8000-000000000002','{}',1)$q$,
'55000','ORDER_CANCELLED','late dispatch insert rejected');
select throws_ok($q$update dastak_v1.order_cancellations set reason='Replace audit reason'$q$,
'P0001','order cancellation records are immutable','cancellation history immutable');
select * from finish();
rollback;
