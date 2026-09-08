-- End-to-end domain commands against isolated transaction fixtures.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
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

create function pg_temp.command(action text,code text default null,path text default null,key text default null)
returns integer language sql as $$
 select response_status from public.dastak_v1_advance_final_delivery(
 'ce000000-0000-4000-8000-000000000003','ce280000-0000-4000-8000-000000000001',
 action,path,code,coalesce(key,action),action||coalesce(code,'')||coalesce(path,''));
$$;
create function pg_temp.loc(distance_m double precision,accuracy double precision default 5)
returns jsonb language plpgsql as $$
declare point extensions.geometry;
begin
 point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(78.62,12.68),4326)::extensions.geography,
 distance_m,0)::extensions.geometry;
 -- Advance the throttle clock without any sleep or production changes.
 update private.delivery_partner_availability set tracking_received_at=clock_timestamp()-interval '3 seconds'
 where account_id='ce000000-0000-4000-8000-000000000003' and tracking_mission_id is not null;
 return public.dastak_v1_publish_mission_location('ce000000-0000-4000-8000-000000000003',
 'ce280000-0000-4000-8000-000000000001',extensions.st_y(point),extensions.st_x(point),accuracy,clock_timestamp());
end; $$;
create function pg_temp.collect(outcome text,key text) returns integer language sql as $$
 select response_status from public.dastak_v1_record_launch_payment_collection(
 'ce000000-0000-4000-8000-000000000003','ce280000-0000-4000-8000-000000000001',
 outcome,'CASH',null,case when outcome='FAILED' then 'Customer retry requested' end,
 (select version from dastak_v1.delivery_missions where id='ce280000-0000-4000-8000-000000000001'),key);
$$;
select is(has_table_privilege('authenticated','private.delivery_partner_availability','SELECT'),false,
 'raw GPS remains private');
select is(has_function_privilege('authenticated','public.dastak_v1_publish_mission_location(uuid,uuid,double precision,double precision,double precision,timestamptz)','EXECUTE'),
 false,'only authenticated Edge rider binding can publish');
select is(has_function_privilege('authenticated','dastak_v1_api.delivery_tracking_json(uuid)','EXECUTE'),
 false,'tracking helper is not a coordinate lookup bypass');

select throws_ok($$select public.dastak_v1_publish_mission_location('ce000000-0000-4000-8000-000000000002',
 'ce280000-0000-4000-8000-000000000001',12.68,78.62,5,clock_timestamp())$$,
 '42501','MISSION_NOT_ASSIGNED','foreign rider cannot publish a sample');
select throws_ok($$select public.dastak_v1_publish_mission_location('ce000000-0000-4000-8000-000000000003',
 'ce280000-0000-4000-8000-000000000001','NaN',78.62,5,clock_timestamp())$$,
 '22023','INVALID_LOCATION_SAMPLE','non-finite coordinates rejected');
select throws_ok($$select public.dastak_v1_publish_mission_location('ce000000-0000-4000-8000-000000000003',
 'ce280000-0000-4000-8000-000000000001',12.68,78.62,5,clock_timestamp()+interval '1 minute')$$,
 '22023','INVALID_LOCATION_SAMPLE','future location rejected');
select throws_ok($$select public.dastak_v1_publish_mission_location('ce000000-0000-4000-8000-000000000003',
 'ce280000-0000-4000-8000-000000000001',12.68,78.62,5,clock_timestamp()-interval '2 minutes')$$,
 '22023','INVALID_LOCATION_SAMPLE','buffered stale location rejected');
select throws_ok($$select pg_temp.command('ARRIVE_CUSTOMER')$$,
 'P0001','ARRIVAL_LOCATION_REQUIRED','arrival without fresh GPS fails at the database boundary');
select is(pg_temp.command('VERIFY_CUSTOMER_PIN','123456'),409,'PIN is locked before arrival');
select is(pg_temp.command('COMPLETE_DELIVERY'),409,'completion is locked before arrival');
select lives_ok($$select pg_temp.loc(51)$$,'assigned rider reports location');
select is(dastak_v1_api.arrival_eligibility('ce280000-0000-4000-8000-000000000001')->>'eligible','false',
 '51 metres is outside the arrival radius');
select throws_ok($$select pg_temp.command('ARRIVE_CUSTOMER',null,null,'too-far')$$,
 'P0001','ARRIVAL_LOCATION_REQUIRED','51m location cannot bypass UI');
select lives_ok($$select pg_temp.loc(49)$$,'49m sample accepted');
select is(dastak_v1_api.arrival_eligibility('ce280000-0000-4000-8000-000000000001')->>'eligible','true',
 '49 metres is eligible');
select lives_ok($$select pg_temp.loc(1,80)$$,'coarse fixes may inform map without enabling arrival');
select is(dastak_v1_api.arrival_eligibility('ce280000-0000-4000-8000-000000000001')->>'reason','LOCATION_INACCURATE',
 'low accuracy remains ineligible');
select pg_temp.loc(1);
update private.delivery_partner_availability set tracking_recorded_at=now()-interval '31 seconds'
 where account_id='ce000000-0000-4000-8000-000000000003';
select is(dastak_v1_api.arrival_eligibility('ce280000-0000-4000-8000-000000000001')->>'reason','LOCATION_STALE',
 'stale fixes remain ineligible even if their point is at the door');
select pg_temp.loc(1);
-- Going offline for new offers does not interrupt the assigned journey.
update private.delivery_partner_availability set status='offline',location=null,service_zone_id=null,available_until=null,
 state_version=state_version+1 where account_id='ce000000-0000-4000-8000-000000000003';
select lives_ok($$select pg_temp.loc(2)$$,'mission reporting survives offline discovery availability');
select is(dastak_v1_api.delivery_tracking_json('ce100000-0000-4000-8000-000000000003')->>'riderName','Orders Rider',
 'assigned rider is projected independently of online availability');
select is(dastak_v1_api.order_json('ce100000-0000-4000-8000-000000000003',
 'ce000000-0000-4000-8000-000000000002'),null::jsonb,'another customer cannot read tracking');
insert into dastak_v1.merchant_users(id,organization_id,account_id,status,created_by) values(
 'ce340000-0000-4000-8000-000000000001','ce210000-0000-4000-8000-000000000001',
 'ce000000-0000-4000-8000-000000000002','ACTIVE','ce000000-0000-4000-8000-000000000001');
insert into dastak_v1.merchant_permission_grants(merchant_user_id,organization_id,bundle_id,branch_id,granted_by,grant_reason)
values('ce340000-0000-4000-8000-000000000001','ce210000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000002','ce220000-0000-4000-8000-000000000001',
 'ce000000-0000-4000-8000-000000000001','Tracking permission fixture.');
select is(dastak_v1_api.merchant_fulfilment_json('ce000000-0000-4000-8000-000000000002',
 'ce270000-0000-4000-8000-000000000002')->'tracking'->>'riderName','Orders Rider',
 'involved merchant can track the assigned rider after pickup');
select throws_ok($$select dastak_v1_api.merchant_fulfilment_json('ce000000-0000-4000-8000-000000000003',
 'ce270000-0000-4000-8000-000000000002')$$,'P0002','fulfilment not found','unrelated actor cannot use merchant tracking');
select ok(not (dastak_v1_api.merchant_fulfilment_json('ce000000-0000-4000-8000-000000000002',
 'ce270000-0000-4000-8000-000000000002')->'tracking' ? 'customerDestination'),
 'merchant tracking does not expose the customer destination');
update dastak_v1.merchant_users set status='REVOKED',version=version+1
 where id='ce340000-0000-4000-8000-000000000001';
select throws_ok($$select dastak_v1_api.merchant_fulfilment_json('ce000000-0000-4000-8000-000000000002',
 'ce270000-0000-4000-8000-000000000002')$$,'P0002','fulfilment not found','revoked merchant access cannot retain tracking access');
select is(pg_temp.command('ARRIVE_CUSTOMER',null,null,'near'),200,'fresh nearby location unlocks arrival');
select is(pg_temp.command('VERIFY_DELIVERY','123456',null,'old-client'),409,'old completion command cannot skip PIN stage');
select is(pg_temp.command('COMPLETE_DELIVERY',null,null,'before-pin'),409,'completion blocked before PIN');
select throws_ok($$select pg_temp.collect('COLLECTED','before-pin')$$,
 'P0001','DELIVERY_PIN_REQUIRED','payment cannot be collected before PIN');
select throws_ok($$insert into dastak_v1.delivery_evidence(order_id,mission_id,verification_handoff_id,
 evidence_type,object_path,content_type,captured_by,captured_at)
 values('ce100000-0000-4000-8000-000000000003','ce280000-0000-4000-8000-000000000001',
 'ce290000-0000-4000-8000-000000000001','RIDER_PRE_DELIVERY_PHOTO','early.jpg','image/jpeg',
 'ce000000-0000-4000-8000-000000000003',clock_timestamp())$$,
 'P0001','DELIVERY_PIN_REQUIRED','even direct evidence writes require the preceding PIN');
select is(pg_temp.command('VERIFY_CUSTOMER_PIN','654321',null,'wrong-pin'),409,'wrong PIN rejected');
select is((select failed_attempts from dastak_v1.verification_handoffs
 where id='ce290000-0000-4000-8000-000000000001'),1,'PIN attempt limits remain effective');
select is(pg_temp.command('VERIFY_CUSTOMER_PIN','123456',null,'right-pin'),200,'correct PIN verifies without photo or payment');
select is((select status::text from dastak_v1.delivery_missions where id='ce280000-0000-4000-8000-000000000001'),
 'ARRIVED','PIN does not complete delivery');
select is(pg_temp.command('VERIFY_CUSTOMER_PIN','123456',null,'right-pin'),200,'PIN retry is idempotent');
select is(pg_temp.command('COMPLETE_DELIVERY',null,null,'before-photo'),409,'photo required after PIN');
select throws_ok($$select pg_temp.collect('COLLECTED','before-photo')$$,
 'P0001','DELIVERY_PHOTO_REQUIRED','payment cannot be collected before the photo');
select throws_ok($$update dastak_v1.verification_handoffs set pin_verified_at=null,pin_verified_by=null,version=version+1
 where id='ce290000-0000-4000-8000-000000000001'$$,'P0001','verified delivery PIN is immutable','PIN verification cannot be cleared');

-- Existing immutable storage/evidence contract, exercised through the public command.
insert into storage.objects(bucket_id,name,owner_id,metadata) values('dastak-evidence',
 'rider-delivery/ce000000-0000-4000-8000-000000000003/ce320000-0000-4000-8000-000000000001.jpg',
 'ce000000-0000-4000-8000-000000000003','{"mimetype":"image/jpeg","size":1000}');
select is(pg_temp.command('ADD_DELIVERY_EVIDENCE',null,
 'rider-delivery/ce000000-0000-4000-8000-000000000003/ce320000-0000-4000-8000-000000000001.jpg'),200,
 'photo after verified PIN is recorded');
select ok(dastak_v1_api.delivery_photo_ready('ce280000-0000-4000-8000-000000000001',
 'ce000000-0000-4000-8000-000000000003'),'photo covers all packages');
select throws_ok($$select pg_temp.command('COMPLETE_DELIVERY',null,null,'before-payment')$$,
 '55000','LAUNCH_PAYMENT_COLLECTION_REQUIRED','completion still requires authoritative payment');
select is((select status::text from dastak_v1.verification_handoffs where id='ce290000-0000-4000-8000-000000000001'),
 'ACTIVE','failed completion rolls back handoff consumption');
select is(pg_temp.collect('FAILED','retry-payment'),200,'failed collection is recorded after the photo');
select is(pg_temp.collect('COLLECTED','payment-success'),200,'payment is collected after PIN and photo');
select is(pg_temp.collect('COLLECTED','payment-success'),200,'collection retry does not double charge');
select is((select count(*) from dastak_v1.launch_payment_collection_attempts where outcome='COLLECTED'
 and order_id='ce100000-0000-4000-8000-000000000003'),1::bigint,'exactly one successful collection');
select is(pg_temp.command('COMPLETE_DELIVERY',null,null,'done'),200,'delivery completes only after all four prerequisites');
select is(pg_temp.command('COMPLETE_DELIVERY',null,null,'done'),200,'completion replay is idempotent');
select is((select status::text from dastak_v1.orders where id='ce100000-0000-4000-8000-000000000003'),
 'DELIVERED','order lifecycle completes');
select is((select current_custody_owner_type::text from dastak_v1.packages where id='ce300000-0000-4000-8000-000000000001'),
 'CUSTOMER','package custody transfers exactly at completion');
select is(dastak_v1_api.delivery_tracking_json('ce100000-0000-4000-8000-000000000003'),null::jsonb,
 'completed deliveries no longer expose rider tracking');
select is((select tracking_location is null from private.delivery_partner_availability
 where account_id='ce000000-0000-4000-8000-000000000003'),true,'completion erases the last mission GPS fix');

-- A fresh next-order pickup fixture exercises the same radius at the merchant.
insert into dastak_v1.orders(id,display_order_number,customer_id,order_type,status,submitted_at,paid_at)
values('ce100000-0000-4000-8000-000000000004','DSK-TRACKING-PICKUP',
 'ce000000-0000-4000-8000-000000000001','RETAIL_ONLY','PAID',now(),now());
insert into dastak_v1.order_context_snapshots
select (jsonb_populate_record(null::dastak_v1.order_context_snapshots,to_jsonb(c)||jsonb_build_object(
 'order_id','ce100000-0000-4000-8000-000000000004'))).*
from dastak_v1.order_context_snapshots c where order_id='ce100000-0000-4000-8000-000000000003';
insert into dastak_v1.matching_attempts
select (jsonb_populate_record(null::dastak_v1.matching_attempts,to_jsonb(a)||jsonb_build_object(
 'id','ce250000-0000-4000-8000-000000000004','order_id','ce100000-0000-4000-8000-000000000004'))).*
from dastak_v1.matching_attempts a where id='ce250000-0000-4000-8000-000000000002';
insert into dastak_v1.merchant_opportunities
select (jsonb_populate_record(null::dastak_v1.merchant_opportunities,to_jsonb(o)||jsonb_build_object(
 'id','ce260000-0000-4000-8000-000000000004','order_id','ce100000-0000-4000-8000-000000000004',
 'matching_attempt_id','ce250000-0000-4000-8000-000000000004'))).*
from dastak_v1.merchant_opportunities o where id='ce260000-0000-4000-8000-000000000002';
insert into dastak_v1.fulfilments(id,order_id,organization_id,branch_id,source_opportunity_id,fulfilment_type,status,
 promised_prep_minutes,committed_at,prep_started_at,estimated_ready_at)
values('ce270000-0000-4000-8000-000000000004','ce100000-0000-4000-8000-000000000004',
 'ce210000-0000-4000-8000-000000000001','ce220000-0000-4000-8000-000000000001',
 'ce260000-0000-4000-8000-000000000004','RETAIL','PREPARING',10,now(),now(),now()+interval '10 minutes');
insert into dastak_v1.delivery_missions(id,order_id,status,assigned_rider_id,
 assigned_transport_type,transport_snapshot,pickup_count,assigned_at)
values('ce280000-0000-4000-8000-000000000004','ce100000-0000-4000-8000-000000000004',
 'EN_ROUTE_TO_PICKUPS','ce000000-0000-4000-8000-000000000003','MOTORBIKE','{}',1,now()-interval '1 minute');
insert into dastak_v1.delivery_stops(id,mission_id,order_id,fulfilment_id,branch_id,stop_sequence)
values('ce310000-0000-4000-8000-000000000004','ce280000-0000-4000-8000-000000000004',
 'ce100000-0000-4000-8000-000000000004','ce270000-0000-4000-8000-000000000004',
 'ce220000-0000-4000-8000-000000000001',1);
create function pg_temp.pickup_loc(metres double precision) returns void language plpgsql as $$
declare point extensions.geometry;
begin
 point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(78.621,12.681),4326)::extensions.geography,
 metres,0)::extensions.geometry;
 update private.delivery_partner_availability set tracking_received_at=clock_timestamp()-interval '3 seconds'
 where account_id='ce000000-0000-4000-8000-000000000003' and tracking_mission_id is not null;
 perform public.dastak_v1_publish_mission_location('ce000000-0000-4000-8000-000000000003',
 'ce280000-0000-4000-8000-000000000004',extensions.st_y(point),extensions.st_x(point),5,clock_timestamp());
end; $$;
select lives_ok($$select pg_temp.pickup_loc(51)$$,'new mission starts a separate location scope');
select throws_ok($$update dastak_v1.delivery_stops set status='ARRIVED',arrived_at=clock_timestamp(),version=version+1
 where id='ce310000-0000-4000-8000-000000000004'$$,'P0001','ARRIVAL_LOCATION_REQUIRED',
 'merchant arrival also rejects 51 metres at the database boundary');
select pg_temp.pickup_loc(49);
select lives_ok($$update dastak_v1.delivery_stops set status='ARRIVED',arrived_at=clock_timestamp(),version=version+1
 where id='ce310000-0000-4000-8000-000000000004'$$,'merchant arrival succeeds within 50 metres');
select lives_ok($$update dastak_v1.delivery_missions set status='REASSIGNING',assigned_rider_id=null,
 assigned_transport_type=null,assigned_at=null,version=version+1 where id='ce280000-0000-4000-8000-000000000004'$$,
 'pre-custody rider release remains available');
select is((select tracking_location is null from private.delivery_partner_availability
 where account_id='ce000000-0000-4000-8000-000000000003'),true,'reassignment erases the former rider location');
select * from finish();
rollback;
