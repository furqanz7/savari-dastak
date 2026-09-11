begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'private', 'delivery_partner_active_work',
  array['uuid', 'text', 'uuid', 'uuid'],
  'one shared active-work predicate exists'
);
select has_function(
  'dastak_v1_api', 'return_arrival_eligibility',
  array['uuid', 'uuid'],
  'return arrival eligibility is server authoritative'
);
select has_column(
  'private', 'delivery_partner_availability', 'tracking_return_mission_id',
  'return tracking is bound to its mission'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_partner_availability', 'SELECT'),
  false,
  'raw rider GPS remains private'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.return_arrival_eligibility(uuid,uuid)',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot bypass the return projection or arrival command'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(uuid)',
    'EXECUTE'
  ),
  false,
  'rider destination projection stays behind authenticated Edge binding'
);
select is(
  has_function_privilege(
    'service_role',
    'dastak_v1_api.assign_return_rider_pre_group_a(uuid,uuid,uuid,bigint,text)',
    'EXECUTE'
  ),
  false,
  'service role cannot bypass the globally locked return assignment wrapper'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('d7400000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'group-a-owner@example.test', '', now(), now(), now()),
  ('d7400000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'group-a-customer@example.test', '', now(), now(), now()),
  ('d7400000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'group-a-rider-one@example.test', '', now(), now(), now()),
  ('d7400000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'group-a-rider-two@example.test', '', now(), now(), now()),
  ('d7400000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'group-a-outsider@example.test', '', now(), now(), now());

insert into public.accounts (id, display_name, phone_number) values
  ('d7400000-0000-4000-8000-000000000001', 'Group A Owner', '+919740000001'),
  ('d7400000-0000-4000-8000-000000000002', 'Group A Customer', '+919740000002'),
  ('d7400000-0000-4000-8000-000000000003', 'Group A Rider One', '+919740000003'),
  ('d7400000-0000-4000-8000-000000000004', 'Group A Rider Two', '+919740000004'),
  ('d7400000-0000-4000-8000-000000000005', 'Group A Outsider', '+919740000005');

insert into private.account_memberships (account_id, role, approved_at) values
  ('d7400000-0000-4000-8000-000000000001', 'owner', now()),
  ('d7400000-0000-4000-8000-000000000002', 'customer', null),
  ('d7400000-0000-4000-8000-000000000003', 'dastak_partner', now()),
  ('d7400000-0000-4000-8000-000000000004', 'dastak_partner', now()),
  ('d7400000-0000-4000-8000-000000000005', 'customer', null);

insert into public.service_zones (id, name, boundary, active) values (
  'd7400000-0000-4000-8000-000000000010',
  'Group A Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.5 12.5,78.8 12.5,78.8 12.8,78.5 12.8,78.5 12.5))', 4326
  ),
  true
);

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  'd7400000-0000-4000-8000-000000000020',
  'Group A Merchant Private Limited', 'Group A Merchant',
  'RETAIL', 'ACTIVE', 'd7400000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id,
  address_snapshot, location, capacity_limit, status, created_by
) values (
  'd7400000-0000-4000-8000-000000000021',
  'd7400000-0000-4000-8000-000000000020', 'Group A Return Branch',
  'd7400000-0000-4000-8000-000000000010',
  '{"line1":"21 Return Road"}',
  extensions.st_setsrid(extensions.st_makepoint(78.64, 12.69), 4326),
  5, 'ACTIVE', 'd7400000-0000-4000-8000-000000000001'
);

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by
) values
  ('d7400000-0000-4000-8000-000000000030',
   'd7400000-0000-4000-8000-000000000003', 'walking',
   'dastak-partner/d7400000-0000-4000-8000-000000000003/identity.pdf',
   'approved', now(), 'd7400000-0000-4000-8000-000000000001'),
  ('d7400000-0000-4000-8000-000000000031',
   'd7400000-0000-4000-8000-000000000004', 'walking',
   'dastak-partner/d7400000-0000-4000-8000-000000000004/identity.pdf',
   'approved', now(), 'd7400000-0000-4000-8000-000000000001');
insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values
  ('d7400000-0000-4000-8000-000000000003',
   'd7400000-0000-4000-8000-000000000030', 'walking'),
  ('d7400000-0000-4000-8000-000000000004',
   'd7400000-0000-4000-8000-000000000031', 'walking');
insert into private.delivery_partner_availability (
  account_id, status, location, service_zone_id, last_seen_at, available_until
) values
  ('d7400000-0000-4000-8000-000000000003', 'online',
   extensions.st_setsrid(extensions.st_makepoint(78.62, 12.68), 4326),
   'd7400000-0000-4000-8000-000000000010', now(), now() + interval '30 minutes'),
  ('d7400000-0000-4000-8000-000000000004', 'online',
   extensions.st_setsrid(extensions.st_makepoint(78.64, 12.69), 4326),
   'd7400000-0000-4000-8000-000000000010', now(), now() + interval '30 minutes');

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, fully_secured_at, paid_at, delivered_at
) values
  ('d7400000-0000-4000-8000-000000000040', 'DSK-GROUP-A-0001',
   'd7400000-0000-4000-8000-000000000002', 'RETAIL_ONLY', 'DELIVERED',
   now() - interval '2 hours', now() - interval '110 minutes',
   now() - interval '65 minutes', now() - interval '1 hour'),
  ('d7400000-0000-4000-8000-000000000041', 'DSK-GROUP-A-0002',
   'd7400000-0000-4000-8000-000000000002', 'RETAIL_ONLY', 'DELIVERED',
   now() - interval '2 hours', now() - interval '110 minutes',
   now() - interval '65 minutes', now() - interval '1 hour');
insert into dastak_v1.order_context_snapshots (
  order_id, delivery_address, recipient, snapshot_hash
) values
  ('d7400000-0000-4000-8000-000000000040',
   '{"label":"Home","line1":"40 Customer Road","latitude":12.68,"longitude":78.62}',
   '{"name":"Group A Customer","phoneNumber":"+919740000002"}',
   extensions.digest('group-a-customer-one', 'sha256')),
  ('d7400000-0000-4000-8000-000000000041',
   '{"label":"Home","line1":"41 Customer Road","latitude":12.681,"longitude":78.621}',
   '{"name":"Group A Customer","phoneNumber":"+919740000002"}',
   extensions.digest('group-a-customer-two', 'sha256'));

insert into dastak_v1.customer_issues (
  id, order_id, customer_id, category, status, description
) values
  ('d7400000-0000-4000-8000-000000000050',
   'd7400000-0000-4000-8000-000000000040',
   'd7400000-0000-4000-8000-000000000002', 'OTHER', 'UNDER_REVIEW',
   'Return customer arrival test fixture.'),
  ('d7400000-0000-4000-8000-000000000051',
   'd7400000-0000-4000-8000-000000000041',
   'd7400000-0000-4000-8000-000000000002', 'OTHER', 'UNDER_REVIEW',
   'Return merchant arrival test fixture.');
insert into dastak_v1.returns (
  id, order_id, source, customer_issue_id, status, physical_return_required,
  reason, requested_by, decided_by, decided_at
) values
  ('d7400000-0000-4000-8000-000000000060',
   'd7400000-0000-4000-8000-000000000040', 'CUSTOMER_ISSUE',
   'd7400000-0000-4000-8000-000000000050', 'CUSTOMER_PICKUP', true,
   'Customer arrival proximity fixture.', 'd7400000-0000-4000-8000-000000000002',
   'd7400000-0000-4000-8000-000000000001', now()),
  ('d7400000-0000-4000-8000-000000000061',
   'd7400000-0000-4000-8000-000000000041', 'CUSTOMER_ISSUE',
   'd7400000-0000-4000-8000-000000000051', 'IN_RIDER_CUSTODY', true,
   'Merchant arrival proximity fixture.', 'd7400000-0000-4000-8000-000000000002',
   'd7400000-0000-4000-8000-000000000001', now());
insert into dastak_v1.return_missions (
  id, return_id, order_id, status, assigned_rider_id,
  assigned_transport_type, assigned_at, arrived_customer_at, pickup_completed_at
) values
  ('d7400000-0000-4000-8000-000000000070',
   'd7400000-0000-4000-8000-000000000060',
   'd7400000-0000-4000-8000-000000000040', 'ASSIGNED',
   'd7400000-0000-4000-8000-000000000003', 'WALKING', now() - interval '1 minute',
   null, null),
  ('d7400000-0000-4000-8000-000000000071',
   'd7400000-0000-4000-8000-000000000061',
   'd7400000-0000-4000-8000-000000000041', 'RETURNING_TO_MERCHANTS',
   'd7400000-0000-4000-8000-000000000004', 'WALKING', now() - interval '10 minutes',
   now() - interval '8 minutes', now() - interval '5 minutes');
insert into dastak_v1.return_stops (
  id, return_mission_id, return_id, branch_id, stop_sequence, status, package_count
) values
  ('d7400000-0000-4000-8000-000000000080',
   'd7400000-0000-4000-8000-000000000070',
   'd7400000-0000-4000-8000-000000000060',
   'd7400000-0000-4000-8000-000000000021', 1, 'PENDING', 1),
  ('d7400000-0000-4000-8000-000000000081',
   'd7400000-0000-4000-8000-000000000071',
   'd7400000-0000-4000-8000-000000000061',
   'd7400000-0000-4000-8000-000000000021', 1, 'PENDING', 1);
insert into dastak_v1.return_verifications (
  id, return_id, return_mission_id, return_stop_id,
  handoff_type, status, code_digest
) values
  ('d7400000-0000-4000-8000-000000000090',
   'd7400000-0000-4000-8000-000000000060',
   'd7400000-0000-4000-8000-000000000070',
   'd7400000-0000-4000-8000-000000000080',
   'RETURN_RIDER_TO_MERCHANT', 'INACTIVE',
   extensions.digest('group-a-stop-code-one', 'sha256')),
  ('d7400000-0000-4000-8000-000000000091',
   'd7400000-0000-4000-8000-000000000061',
   'd7400000-0000-4000-8000-000000000071',
   'd7400000-0000-4000-8000-000000000081',
   'RETURN_RIDER_TO_MERCHANT', 'INACTIVE',
   extensions.digest('group-a-stop-code-two', 'sha256'));

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', 'd7400000-0000-4000-8000-000000000005', true
);
select throws_ok(
  $$select dastak_v1_api.assign_return_rider(
    'd7400000-0000-4000-8000-000000000005',
    'd7400000-0000-4000-8000-000000000070',
    'd7400000-0000-4000-8000-000000000003',
    0,
    'group-a-unauthorized-assignment'
  )$$,
  '42501', 'platform permission required',
  'return assignment denies an unauthorized actor before exposing active work'
);
reset role;
select set_config('request.jwt.claim.sub', '', true);

create function pg_temp.publish_return_location(
  mission_id uuid, rider_id uuid, base_location extensions.geometry,
  distance_meters double precision, accuracy_meters double precision
) returns jsonb language plpgsql as $$
declare
  projected extensions.geometry;
begin
  update private.delivery_partner_availability
  set tracking_received_at = pg_catalog.clock_timestamp() - interval '3 seconds'
  where account_id = rider_id and tracking_return_mission_id = mission_id;
  projected := extensions.st_project(
    base_location::extensions.geography, distance_meters, 0
  )::extensions.geometry;
  return public.dastak_v1_publish_mission_location(
    rider_id, mission_id, extensions.st_y(projected), extensions.st_x(projected),
    accuracy_meters, pg_catalog.clock_timestamp()
  );
end;
$$;

select is(
  dastak_v1_api.return_arrival_eligibility(
    'd7400000-0000-4000-8000-000000000070', null
  ) ->> 'reason',
  'LOCATION_REQUIRED',
  'return arrival starts locked without a mission-bound sample'
);

select lives_ok(
  $$select pg_temp.publish_return_location(
    'd7400000-0000-4000-8000-000000000070',
    'd7400000-0000-4000-8000-000000000003',
    extensions.st_setsrid(extensions.st_makepoint(78.62,12.68),4326), 51, 5
  )$$,
  'rider can publish a return-mission GPS sample'
);
select is(
  dastak_v1_api.return_arrival_eligibility(
    'd7400000-0000-4000-8000-000000000070', null
  ) ->> 'reason',
  'TOO_FAR',
  '51 metre return-customer arrival is ineligible'
);
select throws_ok(
  $$update dastak_v1.return_missions
    set status='AT_CUSTOMER', arrived_customer_at=now(), version=version+1
    where id='d7400000-0000-4000-8000-000000000070'$$,
  'P0001', 'RETURN_ARRIVAL_LOCATION_REQUIRED',
  'database rejects return-customer arrival outside 50 metres'
);

update private.delivery_partner_availability
set tracking_recorded_at = pg_catalog.clock_timestamp() - interval '31 seconds',
    tracking_received_at = pg_catalog.clock_timestamp() - interval '31 seconds'
where account_id = 'd7400000-0000-4000-8000-000000000003';
select is(
  dastak_v1_api.return_arrival_eligibility(
    'd7400000-0000-4000-8000-000000000070', null
  ) ->> 'reason',
  'LOCATION_STALE',
  'stale return-customer location is ineligible'
);
select throws_ok(
  $$update dastak_v1.return_missions
    set status='AT_CUSTOMER', arrived_customer_at=now(), version=version+1
    where id='d7400000-0000-4000-8000-000000000070'$$,
  'P0001', 'RETURN_ARRIVAL_LOCATION_REQUIRED',
  'database rejects stale return-customer arrival'
);

select pg_temp.publish_return_location(
  'd7400000-0000-4000-8000-000000000070',
  'd7400000-0000-4000-8000-000000000003',
  extensions.st_setsrid(extensions.st_makepoint(78.62,12.68),4326), 10, 36
);
select is(
  dastak_v1_api.return_arrival_eligibility(
    'd7400000-0000-4000-8000-000000000070', null
  ) ->> 'reason',
  'LOCATION_INACCURATE',
  'inaccurate return-customer location is ineligible'
);
select throws_ok(
  $$update dastak_v1.return_missions
    set status='AT_CUSTOMER', arrived_customer_at=now(), version=version+1
    where id='d7400000-0000-4000-8000-000000000070'$$,
  'P0001', 'RETURN_ARRIVAL_LOCATION_REQUIRED',
  'database rejects inaccurate return-customer arrival'
);

select pg_temp.publish_return_location(
  'd7400000-0000-4000-8000-000000000070',
  'd7400000-0000-4000-8000-000000000003',
  extensions.st_setsrid(extensions.st_makepoint(78.62,12.68),4326), 49, 5
);
select is(
  dastak_v1_api.return_arrival_eligibility(
    'd7400000-0000-4000-8000-000000000070', null
  ) ->> 'reason',
  'ELIGIBLE',
  'fresh accurate return-customer location within 50 metres is eligible'
);
select lives_ok(
  $$update dastak_v1.return_missions
    set status='AT_CUSTOMER', arrived_customer_at=now(), version=version+1
    where id='d7400000-0000-4000-8000-000000000070'$$,
  'valid within-50-metre return-customer arrival succeeds'
);

select pg_temp.publish_return_location(
  'd7400000-0000-4000-8000-000000000071',
  'd7400000-0000-4000-8000-000000000004',
  (select location from dastak_v1.merchant_branches
   where id='d7400000-0000-4000-8000-000000000021'), 49, 5
);
select is(
  dastak_v1_api.return_arrival_eligibility(
    'd7400000-0000-4000-8000-000000000071',
    'd7400000-0000-4000-8000-000000000081'
  ) ->> 'reason',
  'ELIGIBLE',
  'fresh accurate merchant-stop location within 50 metres is eligible'
);
select lives_ok(
  $$update dastak_v1.return_stops
    set status='ARRIVED', arrived_at=now(), version=version+1
    where id='d7400000-0000-4000-8000-000000000081'$$,
  'valid within-50-metre return merchant-stop arrival succeeds'
);

select throws_ok(
  $$select dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(
    'd7400000-0000-4000-8000-000000000005'
  )$$,
  '42501', 'permission denied',
  'an unrelated account cannot access a return destination or tracking projection'
);
select is(
  dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(
    'd7400000-0000-4000-8000-000000000004'
  ) #>> '{returnMission,stops,0,branch,location,latitude}',
  '12.69',
  'assigned rider receives the applicable return merchant coordinate'
);
select is(
  dastak_v1_api.delivery_partner_snapshot_pre_launch_payment(
    'd7400000-0000-4000-8000-000000000004'
  ) #>> '{returnMission,stops,0,canArrive}',
  'false',
  'completed arrival immediately reconciles the projected action capability'
);

select * from finish();
rollback;
