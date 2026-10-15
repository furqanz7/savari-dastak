begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
select ok(has_function_privilege('service_role','public.dastak_delivery_partner_order_detail(uuid,text,uuid)','EXECUTE'), 'Edge service can read owned full order');
select ok(not has_function_privilege('authenticated','public.dastak_delivery_partner_order_detail(uuid,text,uuid)','EXECUTE'), 'Clients cannot supply their own actor to the detail RPC');
select ok(not has_function_privilege('anon','public.dastak_delivery_partner_order_detail(uuid,text,uuid)','EXECUTE'), 'Anonymous full order read is denied');
select ok(not has_function_privilege('service_role','dastak_v1_api.delivery_partner_legacy_order_detail(uuid,text,uuid)','EXECUTE'), 'Legacy helper cannot bypass approval wrapper');
select throws_ok($$select public.dastak_delivery_partner_order_detail('11111111-1111-4111-8111-111111111111','V1_DELIVERY','22222222-2222-4222-8222-222222222222')$$, '42501','active delivery access required','Unapproved actor cannot read another rider order');
-- Reuse the established isolated tracking fixture; no production commands run.
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

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by
) values (
  'ce230000-0000-4000-8000-000000000001',
  'ce000000-0000-4000-8000-000000000003', 'motorbike',
  'dastak-partner/ce000000-0000-4000-8000-000000000003/id.jpg',
  'approved', pg_catalog.now(), 'ce000000-0000-4000-8000-000000000001'
);
insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values (
  'ce000000-0000-4000-8000-000000000003',
  'ce230000-0000-4000-8000-000000000001', 'motorbike'
);
insert into private.delivery_partner_availability (
  account_id, status, location, service_zone_id, last_seen_at, available_until
) values (
  'ce000000-0000-4000-8000-000000000003', 'online',
  extensions.st_setsrid(extensions.st_makepoint(78.622, 12.682), 4326),
  'ce200000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp() + interval '30 minutes'
);

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
  (
    'ce240000-0000-4000-8000-000000000001',
    'settlement.rider_distance_payout', 'GLOBAL',
    '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}',
    'ce000000-0000-4000-8000-000000000001',
    'Customer Orders projection test configuration'
  ),
  (
    'ce240000-0000-4000-8000-000000000002',
    'merchant.reachability_stale_seconds', 'GLOBAL', '120',
    'ce000000-0000-4000-8000-000000000001',
    'Customer Orders projection test reachability'
  );
insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values (
  'ce220000-0000-4000-8000-000000000001', true, true,
  'ce000000-0000-4000-8000-000000000001'
);

-- Current approval and online coverage are required before order admission.
update private.account_memberships set approved_at=now()
where account_id='ce000000-0000-4000-8000-000000000003' and role='dastak_partner';
\ir fixtures/customer-area.sql.inc
select pg_temp.available_rider('ce200000-0000-4000-8000-000000000001','ce000000-0000-4000-8000-000000000001');
-- These hand-built historical projection fixtures predate admission/fee v1.
-- Real current admission is covered separately; never turn its triggers off.
alter table dastak_v1.orders alter column availability_policy_version set default 0;
alter table dastak_v1.orders alter column checkout_pricing_version set default 0;
insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, fully_secured_at, paid_at
) values (
  'ce100000-0000-4000-8000-000000000003', 'DSK-ORDERS-0003',
  'ce000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'OUT_FOR_DELIVERY',
  pg_catalog.clock_timestamp() - interval '60 minutes',
  pg_catalog.clock_timestamp() - interval '55 minutes',
  null
);
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values (
  'ce100000-0000-4000-8000-000000000003',
  '{"label":"Home","line1":"3 Test Road","countryCode":"IN","latitude":12.68,"longitude":78.62}',
  '{"name":"Orders Owner","phoneNumber":"+919500000201"}',
  pg_catalog.decode(pg_catalog.repeat('02', 32), 'hex')
);
insert into dastak_v1.order_price_snapshots (
  order_id, snapshot_kind, subtotal_paise, total_paise
) values (
  'ce100000-0000-4000-8000-000000000003', 'FULLY_SECURED', 1000, 1000
);
insert into dastak_v1.matching_attempts (
  id, order_id, wave, status, started_at, expires_at
) values (
  'ce250000-0000-4000-8000-000000000002',
  'ce100000-0000-4000-8000-000000000003', 'WAVE_1', 'OPEN',
  pg_catalog.clock_timestamp() - interval '60 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes'
);
insert into dastak_v1.merchant_opportunities (
  id, matching_attempt_id, order_id, organization_id, branch_id,
  status, started_at, expires_at, promised_prep_minutes,
  responded_by, responded_at
) values (
  'ce260000-0000-4000-8000-000000000002',
  'ce250000-0000-4000-8000-000000000002',
  'ce100000-0000-4000-8000-000000000003',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001', 'SELECTED',
  pg_catalog.clock_timestamp() - interval '60 minutes',
  pg_catalog.clock_timestamp() + interval '30 minutes', 10,
  'ce000000-0000-4000-8000-000000000001',
  pg_catalog.clock_timestamp() - interval '55 minutes'
);
insert into dastak_v1.fulfilments (
  id, order_id, organization_id, branch_id, source_opportunity_id,
  fulfilment_type, status, promised_prep_minutes, committed_at,
  prep_started_at, estimated_ready_at, ready_at, actual_ready_at, package_count
) values (
  'ce270000-0000-4000-8000-000000000002',
  'ce100000-0000-4000-8000-000000000003',
  'ce210000-0000-4000-8000-000000000001',
  'ce220000-0000-4000-8000-000000000001',
  'ce260000-0000-4000-8000-000000000002',
  'RETAIL', 'PICKED_UP', 10,
  pg_catalog.clock_timestamp() - interval '55 minutes',
  pg_catalog.clock_timestamp() - interval '50 minutes',
  pg_catalog.clock_timestamp() - interval '40 minutes',
  pg_catalog.statement_timestamp() - interval '42 minutes',
  pg_catalog.statement_timestamp() - interval '42 minutes', 1
);
insert into dastak_v1.delivery_missions (
  id, order_id, status, assigned_rider_id, assigned_transport_type,
  transport_snapshot, pickup_count, assigned_at,
  first_package_picked_up_at, all_packages_picked_up_at, out_for_delivery_at
) values (
  'ce280000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000003', 'OUT_FOR_DELIVERY',
  'ce000000-0000-4000-8000-000000000003', 'MOTORBIKE', '{}', 1,
  pg_catalog.clock_timestamp() - interval '30 minutes',
  pg_catalog.clock_timestamp() - interval '20 minutes',
  pg_catalog.clock_timestamp() - interval '19 minutes',
  pg_catalog.clock_timestamp() - interval '18 minutes'
);
insert into dastak_v1.verification_handoffs (
  id, order_id, mission_id, fulfilment_id, handoff_type, status,
  code_digest, activated_at
) values (
  'ce290000-0000-4000-8000-000000000001',
  'ce100000-0000-4000-8000-000000000003',
  'ce280000-0000-4000-8000-000000000001', null,
  'RIDER_TO_CUSTOMER', 'ACTIVE',
  private.dastak_v1_handoff_digest('123456'),
  pg_catalog.clock_timestamp() - interval '18 minutes'
);
-- The customer flow starts at a real final-leg mission with one package in rider custody.
insert into dastak_v1.platform_settings(setting_key,scope_type,setting_value,updated_by,update_reason)
values('delivery.verification_invalid_attempt_limit','GLOBAL','3',
 'ce000000-0000-4000-8000-000000000001','Tracking sequence test configuration.');
insert into dastak_v1.payments(id,order_id,customer_id,status,amount_paise,currency_code,reserved_at,expires_at,cancelled_at)
values('ce330000-0000-4000-8000-000000000001','ce100000-0000-4000-8000-000000000003',
 'ce000000-0000-4000-8000-000000000001','CANCELLED',1000,'INR',now()-interval '1 hour',now(),now());
insert into dastak_v1.launch_payment_commitments(order_id,customer_id,retired_payment_id,amount_paise,currency_code,secured_at,reservation_expires_at)
values('ce100000-0000-4000-8000-000000000003','ce000000-0000-4000-8000-000000000001',
 'ce330000-0000-4000-8000-000000000001',1000,'INR',now()-interval '1 hour',now());
update private.account_memberships set approved_at=now()
 where account_id='ce000000-0000-4000-8000-000000000003' and role='dastak_partner';
insert into dastak_v1.packages(id,order_id,fulfilment_id,package_number,status,
  current_custody_owner_type,current_custody_owner_id,declared_by,ready_at,picked_up_at)
values('ce300000-0000-4000-8000-000000000001','ce100000-0000-4000-8000-000000000003',
  'ce270000-0000-4000-8000-000000000002',1,'IN_TRANSIT','RIDER',
  'ce000000-0000-4000-8000-000000000003','ce000000-0000-4000-8000-000000000001',
  now()-interval '40 minutes',now()-interval '20 minutes');
insert into dastak_v1.delivery_stops(id,mission_id,order_id,fulfilment_id,branch_id,
 stop_sequence,status,declared_package_count,completed_at)
values('ce310000-0000-4000-8000-000000000001','ce280000-0000-4000-8000-000000000001',
 'ce100000-0000-4000-8000-000000000003','ce270000-0000-4000-8000-000000000002',
 'ce220000-0000-4000-8000-000000000001',1,'COMPLETED',1,now()-interval '20 minutes');


insert into dastak_v1.order_lines(order_id,line_type,sku_id,product_name_snapshot,pack_size_snapshot,quantity,unit_price_paise)
values('ce100000-0000-4000-8000-000000000003','RETAIL_SKU',(select id from dastak_v1.skus order by id limit 1),'Gate sample milk','500 ml',2,500);
create function pg_temp.detail(actor uuid default 'ce000000-0000-4000-8000-000000000003',kind text default 'V1_DELIVERY',work uuid default 'ce280000-0000-4000-8000-000000000001')
returns jsonb language sql as $$ select public.dastak_delivery_partner_order_detail(actor,kind,work); $$;
select is(pg_temp.detail()->>'kind','V1_DELIVERY','Assigned rider can read their active work');
select is(pg_temp.detail()#>>'{order,lines,0,name}','Gate sample milk','Full order includes immutable product name');
select is(pg_temp.detail()#>>'{order,lines,0,quantity}','2','Full order includes quantity');
select is(pg_temp.detail()#>>'{order,price,totalPaise}','1000','Full order uses server bill');
select is(pg_temp.detail()#>>'{order,recipient,phoneNumber}','+919500000201','Assigned active rider sees customer contact');
select is(pg_temp.detail()#>>'{collection,state}','PAYMENT_DUE_AT_DELIVERY','Doorstep collection is projected without mutation');
select is(pg_temp.detail()->>'terminal','false','Active mission is not terminal');
select is(pg_catalog.jsonb_array_length(pg_temp.detail()->'pickupStops'),1,'Pickup stops are included');
select ok(not (pg_temp.detail()->'order' ?| array['payment','delivery','tracking','support']),'Customer PIN, tracking and provider projections are not exposed');
select throws_ok($$select pg_temp.detail('ce000000-0000-4000-8000-000000000002')$$,'42501','active delivery access required','Non-rider cannot read owned work');
update private.delivery_partner_profiles set governance_status='SUSPENDED',suspended_at=now(),suspended_by='ce000000-0000-4000-8000-000000000001',suspension_reason='Isolated gate suspension' where account_id='ce000000-0000-4000-8000-000000000003';
select throws_ok($$select pg_temp.detail()$$,'42501','active delivery access required','Suspended rider cannot read contact');
update private.delivery_partner_profiles set governance_status='ACTIVE',suspended_at=null,suspended_by=null,suspension_reason=null where account_id='ce000000-0000-4000-8000-000000000003';
select throws_ok($$select pg_temp.detail(kind => 'V1_DELIVERY',work => '11111111-1111-4111-8111-111111111111')$$,'P0002','delivery work not found','Approved rider cannot read unrelated work');
select throws_ok($$select pg_temp.detail(kind => 'LEGACY_DELIVERY',work => '11111111-1111-4111-8111-111111111111')$$,'P0002','delivery work not found','Legacy helper enforces assignment ownership');
select throws_ok($$select pg_temp.detail(kind => 'PARCEL',work => '11111111-1111-4111-8111-111111111111')$$,'P0002','delivery work not found','Parcel helper enforces assignment ownership');
insert into dastak_v1.delivery_missions(id,order_id,status,assigned_rider_id,assigned_transport_type,transport_snapshot,pickup_count,assigned_at,all_packages_picked_up_at,out_for_delivery_at,arrived_customer_at,delivered_at)
values('ce280000-0000-4000-8000-000000000002','ce100000-0000-4000-8000-000000000003','DELIVERED','ce000000-0000-4000-8000-000000000003','MOTORBIKE','{}',1,now(),now(),now(),now(),now());
select is(pg_temp.detail(work => 'ce280000-0000-4000-8000-000000000002')->>'terminal','true','Delivered mission remains readable as historical work');
select is(pg_temp.detail(work => 'ce280000-0000-4000-8000-000000000002')#>'{order,recipient}','null'::jsonb,'Historical recipient is redacted');
select is(pg_temp.detail(work => 'ce280000-0000-4000-8000-000000000002')#>'{order,deliveryAddress}','null'::jsonb,'Historical customer address is redacted');
insert into private.account_memberships(account_id,role,approved_at)
values('ce000000-0000-4000-8000-000000000002','dastak_partner',now());
insert into private.delivery_partner_applications(id,account_id,delivery_method,identity_evidence_object_path,status,reviewed_at,reviewed_by)
values('ce230000-0000-4000-8000-000000000002','ce000000-0000-4000-8000-000000000002','walking','dastak-partner/ce000000-0000-4000-8000-000000000002/id.jpg','approved',now(),'ce000000-0000-4000-8000-000000000001');
insert into private.delivery_partner_profiles(account_id,approved_application_id,delivery_method)
values('ce000000-0000-4000-8000-000000000002','ce230000-0000-4000-8000-000000000002','walking');
select throws_ok($$select pg_temp.detail('ce000000-0000-4000-8000-000000000002')$$,'P0002','delivery work not found','Another approved rider cannot read the assigned order');
insert into dastak_v1.customer_issues(id,order_id,customer_id,category,description) values
('ce410000-0000-4000-8000-000000000001','ce100000-0000-4000-8000-000000000003','ce000000-0000-4000-8000-000000000001','DAMAGED','Isolated return fixture'),
('ce410000-0000-4000-8000-000000000002','ce100000-0000-4000-8000-000000000003','ce000000-0000-4000-8000-000000000001','DAMAGED','Isolated historical return fixture');
insert into dastak_v1.returns(id,order_id,source,customer_issue_id,status,physical_return_required,reason,requested_by) values
('ce420000-0000-4000-8000-000000000001','ce100000-0000-4000-8000-000000000003','CUSTOMER_ISSUE','ce410000-0000-4000-8000-000000000001','APPROVED',true,'Isolated return fixture','ce000000-0000-4000-8000-000000000001'),
('ce420000-0000-4000-8000-000000000002','ce100000-0000-4000-8000-000000000003','CUSTOMER_ISSUE','ce410000-0000-4000-8000-000000000002','APPROVED',true,'Isolated historical return fixture','ce000000-0000-4000-8000-000000000001');
insert into dastak_v1.return_missions(id,return_id,order_id,status,assigned_rider_id,assigned_transport_type,assigned_at,completed_at) values
('ce430000-0000-4000-8000-000000000001','ce420000-0000-4000-8000-000000000001','ce100000-0000-4000-8000-000000000003','ASSIGNED','ce000000-0000-4000-8000-000000000002','WALKING',now(),null),
('ce430000-0000-4000-8000-000000000002','ce420000-0000-4000-8000-000000000002','ce100000-0000-4000-8000-000000000003','COMPLETED','ce000000-0000-4000-8000-000000000002','WALKING',now(),now());
insert into dastak_v1.return_stops(return_mission_id,return_id,branch_id,stop_sequence,status,package_count) values
('ce430000-0000-4000-8000-000000000001','ce420000-0000-4000-8000-000000000001','ce220000-0000-4000-8000-000000000001',1,'PENDING',1),
('ce430000-0000-4000-8000-000000000002','ce420000-0000-4000-8000-000000000002','ce220000-0000-4000-8000-000000000001',1,'PENDING',1);
select is(pg_temp.detail('ce000000-0000-4000-8000-000000000002','RETURN','ce430000-0000-4000-8000-000000000001')->>'terminal','false','Assigned return is readable');
select is(pg_temp.detail('ce000000-0000-4000-8000-000000000002','RETURN','ce430000-0000-4000-8000-000000000001')#>>'{pickupStops,0,name}','Private Retail Branch','Return destination is projected');
select is(pg_temp.detail('ce000000-0000-4000-8000-000000000002','RETURN','ce430000-0000-4000-8000-000000000001')->'collection','null'::jsonb,'Return read never requests another doorstep collection');
select is(pg_temp.detail('ce000000-0000-4000-8000-000000000002','RETURN','ce430000-0000-4000-8000-000000000002')->>'terminal','true','Completed return is historical');
select is(pg_temp.detail('ce000000-0000-4000-8000-000000000002','RETURN','ce430000-0000-4000-8000-000000000002')#>'{order,recipient}','null'::jsonb,'Completed return hides recipient');
select is(pg_temp.detail('ce000000-0000-4000-8000-000000000002','RETURN','ce430000-0000-4000-8000-000000000002')#>'{order,deliveryAddress}','null'::jsonb,'Completed return hides customer address');
select * from finish();
rollback;
