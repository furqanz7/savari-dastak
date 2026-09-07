begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    'ae000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-owner@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ae000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-outsider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    'ae000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'orders-rider@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  );

insert into public.accounts (id, display_name, phone_number) values
  ('ae000000-0000-4000-8000-000000000001', 'Orders Owner', '+919501000201'),
  ('ae000000-0000-4000-8000-000000000002', 'Orders Outsider', '+919501000202'),
  ('ae000000-0000-4000-8000-000000000003', 'Orders Rider', '+919501000203');
insert into private.account_memberships (account_id, role) values
  ('ae000000-0000-4000-8000-000000000001', 'customer'),
  ('ae000000-0000-4000-8000-000000000002', 'customer'),
  ('ae000000-0000-4000-8000-000000000003', 'dastak_partner');

insert into public.service_zones (id, name, boundary, coverage_radius_m)
values (
  'ae200000-0000-4000-8000-000000000001',
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
  'ae210000-0000-4000-8000-000000000001',
  'Customer Orders Test Merchant', 'Customer Orders Merchant',
  'RETAIL', 'ACTIVE', 'ae000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id,
  address_snapshot, location, capacity_limit, status, created_by
) values (
  'ae220000-0000-4000-8000-000000000001',
  'ae210000-0000-4000-8000-000000000001',
  'Private Retail Branch', 'ae200000-0000-4000-8000-000000000001',
  '{"line1":"Private pickup address"}',
  extensions.st_setsrid(extensions.st_makepoint(78.621, 12.681), 4326),
  5, 'ACTIVE', 'ae000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values (
  'ae230000-0000-4000-8000-000000000001', 'ae210000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000002', 'ACTIVE', 'ae000000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_permission_grants (
  merchant_user_id, organization_id, bundle_id, branch_id, granted_by, grant_reason
) values (
  'ae230000-0000-4000-8000-000000000001', 'ae210000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002', 'ae220000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000001', 'Cancellation notification fixture.'
);

select is(has_function_privilege('authenticated',
 'public.dastak_v1_register_app_device_token(uuid,text,text,text,text)', 'EXECUTE'), false,
 'only the authenticated Edge service can choose a registration account');
select is(has_table_privilege('authenticated','public.dastak_device_tokens','SELECT'),false,
 'clients cannot inspect other account tokens');
select throws_ok($$select public.dastak_v1_register_app_device_token(
 'ae000000-0000-4000-8000-000000000002','token','ios','com.unknown.app','production')$$,
 '22023','invalid notification application','unknown application rejected');

select public.dastak_v1_register_device_token('ae000000-0000-4000-8000-000000000002','shared-token','ios');
select public.dastak_v1_register_app_device_token('ae000000-0000-4000-8000-000000000002','shared-token','ios','com.dastak.app','production');
select is((select count(*) from public.dastak_device_tokens where device_token='shared-token'),
 1::bigint, 'upgrading a legacy Customer token does not duplicate it');
select public.dastak_v1_register_app_device_token('ae000000-0000-4000-8000-000000000002','shared-token','ios','com.dastak.merchant','production');
select public.dastak_v1_register_app_device_token('ae000000-0000-4000-8000-000000000002','shared-token','ios','com.dastak.merchant','sandbox');
select is((select count(*) from public.dastak_device_tokens where device_token='shared-token'),
 3::bigint, 'same token value is isolated by application and APNs environment');

insert into dastak_v1.orders(id,display_order_number,customer_id,order_type,status,submitted_at,version)
values('ae100000-0000-4000-8000-000000000001','PUSH-APP-TEST','ae000000-0000-4000-8000-000000000002','RETAIL_ONLY','MATCHING',now(),2);
insert into dastak_v1.domain_events_outbox(
 event_key,aggregate_type,aggregate_id,aggregate_version,event_type,actor_id,payload
) values
 ('app-routing:customer','ORDER','ae100000-0000-4000-8000-000000000001',2,'ORDER_SUBMITTED','ae000000-0000-4000-8000-000000000002',
  jsonb_build_object('orderId','ae100000-0000-4000-8000-000000000001')),
 ('app-routing:merchant','ORDER','ae100000-0000-4000-8000-000000000001',2,'MERCHANT_OPPORTUNITY_OFFERED','ae000000-0000-4000-8000-000000000002',
  jsonb_build_object('orderId','ae100000-0000-4000-8000-000000000001','branchId','ae220000-0000-4000-8000-000000000001'));
select public.dastak_v1_fanout_outbox('app-routing',100);
select is((select count(*) from dastak_v1.notification_deliveries d
 join dastak_v1.notification_intents i on i.id=d.intent_id
 where i.recipient_account_id='ae000000-0000-4000-8000-000000000002'),3::bigint,
 'fanout creates one Customer delivery and two Merchant environment deliveries');
select is((select count(*) from dastak_v1.notification_deliveries d
 join dastak_v1.notification_intents i on i.id=d.intent_id
 join public.dastak_device_tokens t on t.id=d.device_token_id
 where i.recipient_account_id='ae000000-0000-4000-8000-000000000002' and
 ((i.notification_type like 'merchant.%' and t.application_id <> 'com.dastak.merchant')
 or (i.notification_type like 'customer.%' and t.application_id <> 'com.dastak.app'))),
 0::bigint,'notifications never cross Customer and Merchant applications');

-- A different account signs in after fanout, before delivery.
select public.dastak_v1_register_app_device_token('ae000000-0000-4000-8000-000000000001','shared-token','ios','com.dastak.merchant','production');
create temp table app_claims as select public.dastak_v1_claim_notification_deliveries('app-routing',100) as body;
select is((select jsonb_array_length(body) from app_claims),2,
 'queued notifications for the previous signed-in account are suppressed');
select is((select count(*) from app_claims,jsonb_array_elements(body) j
 where j->>'applicationId'='com.dastak.merchant' and j->>'apnsEnvironment'='sandbox'),
 1::bigint,'worker receives the exact Merchant application and environment');

-- A stale provider failure must not invalidate a registration refreshed during delivery.
select public.dastak_v1_register_app_device_token('ae000000-0000-4000-8000-000000000002','shared-token','ios','com.dastak.merchant','sandbox');
select public.dastak_v1_complete_notification_delivery(
 (j->>'deliveryId')::uuid,'app-routing',false,true,410,'{"reason":"Unregistered"}'
) from app_claims,jsonb_array_elements(body) j where j->>'applicationId'='com.dastak.merchant';
select ok((select disabled_at is null from public.dastak_device_tokens
 where device_token='shared-token' and application_id='com.dastak.merchant' and apns_environment='sandbox'),
 'stale provider result cannot disable a newly observed token');
select ok(exists(select 1 from dastak_v1.notification_routes
 where event_type='RESTAURANT_REQUEST_OFFERED' and audience='MERCHANT' and enabled),
 'food requests have a Merchant notification route');
select * from finish();
rollback;
