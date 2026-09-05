begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function('public', 'submit_delivery_partner_application_v3',
  array['uuid','text','text','text','text','text','text','text']);
select hasnt_function('private', 'reject_retired_parcel_delivery_method', array[]::text[]);
select is(has_function_privilege('authenticated',
  'public.submit_delivery_partner_application_v3(uuid,text,text,text,text,text,text,text)', 'EXECUTE'),
  false, 'clients cannot bypass the authenticated Edge handler');
select is(has_function_privilege('service_role',
  'public.submit_delivery_partner_application_v3(uuid,text,text,text,text,text,text,text)', 'EXECUTE'),
  true, 'Edge handler can submit approved method types');
select is(dastak_v1.rider_transport_type('goods_vehicle')::text, 'CAR',
  'goods vehicles retain their heavy-load class');
select is(dastak_v1.rider_transport_type('retired')::text, null, 'retired is not dispatchable');
select ok(private.parcel_method_matches_partner('bike', 'motorbike'), 'motorbike parcel matching remains');
select ok(private.parcel_method_matches_partner('bike', 'scooter'), 'scooter parcel matching remains');
select ok(private.parcel_method_matches_partner('auto', 'goods_vehicle'), 'goods vehicle parcel matching remains');
select ok(dastak_v1.is_valid_transport_load_profiles(
  '[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]'::jsonb
), 'all six original load profiles are accepted');
select ok(not dastak_v1.is_valid_transport_load_profiles(null), 'null load profiles fail closed');
select ok(not dastak_v1.is_valid_transport_load_profiles(
  '[{},{},{},{},{},{}]'::jsonb
), 'incomplete load profiles fail closed');

insert into auth.users(id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated', 'authenticated',
  email, '', now(), now(), now()
from (values
  ('60000000-0000-4000-8000-000000000001'::uuid, 'method-admin@example.test'),
  ('60000000-0000-4000-8000-000000000002'::uuid, 'walking@example.test'),
  ('60000000-0000-4000-8000-000000000003'::uuid, 'bicycle@example.test')
) fixture(id, email);

set local role service_role;
insert into public.accounts(id, display_name, phone_number) values
  ('60000000-0000-4000-8000-000000000001', 'Methods Admin', '+919600000001'),
  ('60000000-0000-4000-8000-000000000002', 'Walking Partner', '+919600000002'),
  ('60000000-0000-4000-8000-000000000003', 'Bicycle Partner', '+919600000003');
insert into private.account_memberships(account_id, role, approved_at) values
  ('60000000-0000-4000-8000-000000000001', 'owner', now()),
  ('60000000-0000-4000-8000-000000000001', 'customer', null),
  ('60000000-0000-4000-8000-000000000002', 'customer', null),
  ('60000000-0000-4000-8000-000000000003', 'customer', null);
insert into public.service_zones(id, name, boundary, active) values(
  '60000000-0000-4000-8000-000000000010', 'Delivery methods test zone',
  extensions.st_geomfromtext('POLYGON((78.50 12.50,78.50 12.80,78.80 12.80,78.80 12.50,78.50 12.50))',4326),
  true
);
insert into storage.objects(bucket_id, name, owner_id) values
  ('dastak-evidence', 'dastak-partner/60000000-0000-4000-8000-000000000002/identity.pdf', '60000000-0000-4000-8000-000000000002'),
  ('dastak-evidence', 'dastak-partner/60000000-0000-4000-8000-000000000003/identity.pdf', '60000000-0000-4000-8000-000000000003');


select is((select response_status from public.submit_delivery_partner_application_v3(
  '60000000-0000-4000-8000-000000000002', 'walking', 'dastak-partner/60000000-0000-4000-8000-000000000002/identity.pdf',
  null, null, null, 'walking-submit', 'walking-digest')),
  200, 'walking submits with identity evidence only');
select is((select delivery_method from private.delivery_partner_applications where account_id = '60000000-0000-4000-8000-000000000002'),
  'walking', 'walking is persisted without being marked retired');
select is((select response_status from public.submit_delivery_partner_application_v3(
  '60000000-0000-4000-8000-000000000002', 'walking', 'dastak-partner/60000000-0000-4000-8000-000000000002/identity.pdf',
  null, null, null, 'walking-submit', 'walking-digest')),
  200, 'walking submission is idempotent');
select is((select count(*)::integer from private.delivery_partner_applications where account_id = '60000000-0000-4000-8000-000000000002'),
  1, 'walking retry creates no duplicate application');
select is((select response_status from public.review_delivery_partner_application(
  '60000000-0000-4000-8000-000000000001',
  (select id from private.delivery_partner_applications where account_id = '60000000-0000-4000-8000-000000000002'),
  'approve', null, 'walking-approve', 'walking-approve-digest')),
  200, 'walking can be approved through normal review');
select is((select delivery_method from private.delivery_partner_profiles where account_id = '60000000-0000-4000-8000-000000000002'),
  'walking', 'walking approved profile is created');
select is((select response_body ->> 'deliveryMethod' from public.get_delivery_partner_snapshot('60000000-0000-4000-8000-000000000002')),
  'walking', 'walking snapshot retains its method');
select is((select response_status from public.set_delivery_partner_availability(
  '60000000-0000-4000-8000-000000000002', true, 12.65, 78.65, 'walking-online', 'walking-online-digest')),
  200, 'walking can go online after approval');
select is(dastak_v1.rider_transport_type('walking')::text, 'WALKING',
  'walking maps into retail dispatch');
select ok(private.parcel_method_matches_partner('walking', 'walking'),
  'walking matches its parcel dispatch method');
select ok(not private.parcel_method_matches_partner('walking', 'motorbike'),
  'walking does not match a different parcel class');

insert into private.parcel_rate_cards(
  service_zone_id, delivery_method, minimum_fare_paise, per_kilometre_paise,
  courier_payout_bps, version, created_by
) values (
  '60000000-0000-4000-8000-000000000010', 'walking', 1000, 100, 8000, 1,
  '60000000-0000-4000-8000-000000000001'
);
select is((select response_status from public.quote_parcel_delivery(
  '60000000-0000-4000-8000-000000000001', 'walking',
  12.65, 78.65, 'Pickup', 12.66, 78.66, 'Dropoff',
  2000, 1600, 'walking-quote', 'walking-quote-digest')),
  200, 'walking can receive a server-priced parcel quote');


select is((select response_status from public.submit_delivery_partner_application_v3(
  '60000000-0000-4000-8000-000000000003', 'bicycle', 'dastak-partner/60000000-0000-4000-8000-000000000003/identity.pdf',
  null, null, null, 'bicycle-submit', 'bicycle-digest')),
  200, 'bicycle submits with identity evidence only');
select is((select delivery_method from private.delivery_partner_applications where account_id = '60000000-0000-4000-8000-000000000003'),
  'bicycle', 'bicycle is persisted without being marked retired');
select is((select response_status from public.submit_delivery_partner_application_v3(
  '60000000-0000-4000-8000-000000000003', 'bicycle', 'dastak-partner/60000000-0000-4000-8000-000000000003/identity.pdf',
  null, null, null, 'bicycle-submit', 'bicycle-digest')),
  200, 'bicycle submission is idempotent');
select is((select count(*)::integer from private.delivery_partner_applications where account_id = '60000000-0000-4000-8000-000000000003'),
  1, 'bicycle retry creates no duplicate application');
select is((select response_status from public.review_delivery_partner_application(
  '60000000-0000-4000-8000-000000000001',
  (select id from private.delivery_partner_applications where account_id = '60000000-0000-4000-8000-000000000003'),
  'approve', null, 'bicycle-approve', 'bicycle-approve-digest')),
  200, 'bicycle can be approved through normal review');
select is((select delivery_method from private.delivery_partner_profiles where account_id = '60000000-0000-4000-8000-000000000003'),
  'bicycle', 'bicycle approved profile is created');
select is((select response_body ->> 'deliveryMethod' from public.get_delivery_partner_snapshot('60000000-0000-4000-8000-000000000003')),
  'bicycle', 'bicycle snapshot retains its method');
select is((select response_status from public.set_delivery_partner_availability(
  '60000000-0000-4000-8000-000000000003', true, 12.65, 78.65, 'bicycle-online', 'bicycle-online-digest')),
  200, 'bicycle can go online after approval');
select is(dastak_v1.rider_transport_type('bicycle')::text, 'BICYCLE',
  'bicycle maps into retail dispatch');
select ok(private.parcel_method_matches_partner('bicycle', 'bicycle'),
  'bicycle matches its parcel dispatch method');
select ok(not private.parcel_method_matches_partner('bicycle', 'motorbike'),
  'bicycle does not match a different parcel class');

insert into private.parcel_rate_cards(
  service_zone_id, delivery_method, minimum_fare_paise, per_kilometre_paise,
  courier_payout_bps, version, created_by
) values (
  '60000000-0000-4000-8000-000000000010', 'bicycle', 1000, 100, 8000, 1,
  '60000000-0000-4000-8000-000000000001'
);
select is((select response_status from public.quote_parcel_delivery(
  '60000000-0000-4000-8000-000000000001', 'bicycle',
  12.65, 78.65, 'Pickup', 12.66, 78.66, 'Dropoff',
  2000, 1600, 'bicycle-quote', 'bicycle-quote-digest')),
  200, 'bicycle can receive a server-priced parcel quote');

select is((select response_status from public.submit_delivery_partner_application_v3(
  '60000000-0000-4000-8000-000000000001', 'goods_vehicle',
  'dastak-partner/60000000-0000-4000-8000-000000000001/identity.pdf',
  null, null, null, 'motor-without-proof', 'motor-without-proof-digest')),
  400, 'motor vehicles still require vehicle verification');
select is((select response_status from public.submit_delivery_partner_application_v3(
  '60000000-0000-4000-8000-000000000001', 'retired',
  'dastak-partner/60000000-0000-4000-8000-000000000001/identity.pdf',
  null, null, null, 'retired-submit', 'retired-digest')),
  400, 'literal retired is not selectable');

select * from finish();
rollback;
