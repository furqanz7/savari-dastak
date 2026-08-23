begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'restaurant_menu_categories', 'restaurant categories exist');
select has_table('dastak_v1', 'restaurant_menu_items', 'restaurant items exist');
select has_table('dastak_v1', 'restaurant_menu_option_groups', 'restaurant option groups exist');
select has_table('dastak_v1', 'restaurant_menu_options', 'restaurant options exist');
select has_table('dastak_v1', 'restaurant_order_requests', 'binding restaurant requests exist');
select has_table('dastak_v1', 'restaurant_capacity_commitments', 'restaurant commitments exist');
select has_column('dastak_v1', 'orders', 'restaurant_branch_id', 'parent order fixes one restaurant branch');
select has_column('dastak_v1', 'order_lines', 'food_selection_snapshot', 'food choice is snapshotted');
select has_column('dastak_v1', 'fulfilments', 'source_restaurant_request_id', 'food fulfilment has exact source');
select is((select count(*) from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'dastak_v1'
    and relation.relname in ('restaurant_menu_categories','restaurant_menu_items',
      'restaurant_menu_option_groups','restaurant_menu_options',
      'restaurant_order_requests','restaurant_capacity_commitments')
    and not relation.relrowsecurity), 0::bigint, 'all restaurant tables use RLS');
select is(has_function_privilege('anon',
  'public.dastak_v1_customer_restaurants(text,integer)', 'EXECUTE'), false,
  'restaurant discovery requires an authenticated customer');
select is(has_function_privilege('anon',
  'public.dastak_v1_respond_restaurant_request(uuid,text,integer,text,bigint,text)',
  'EXECUTE'), false, 'anonymous callers cannot answer restaurant requests');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
('99700000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','restaurant-customer@example.test','',now(),now(),now()),
('99700000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','restaurant-owner@example.test','',now(),now(),now()),
('99700000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','restaurant-merchant@example.test','',now(),now(),now());

insert into public.accounts (id, display_name, phone_number) values
('99700000-0000-4000-8000-000000000001','Restaurant Customer','+919970000001'),
('99700000-0000-4000-8000-000000000002','Restaurant Owner','+919970000002'),
('99700000-0000-4000-8000-000000000003','Restaurant Merchant','+919970000003');
insert into private.account_memberships (account_id, role, approved_at) values
('99700000-0000-4000-8000-000000000001','customer',null),
('99700000-0000-4000-8000-000000000002','owner',now()),
('99700000-0000-4000-8000-000000000003','merchant',now());

insert into public.service_zones (id, name, boundary, active) values (
  '99700000-0000-4000-8000-000000000010','Restaurant Zone',
  extensions.st_geomfromtext('POLYGON((78 12,79 12,79 13,78 13,78 12))',4326),true
);
insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values
('99700000-0000-4000-8000-000000000020','V1 Cafe Private Limited','V1 Cafe',
 'RESTAURANT_CAFE','ACTIVE','99700000-0000-4000-8000-000000000002'),
('99700000-0000-4000-8000-000000000030','V1 Retail Private Limited','Hidden Retail',
 'RETAIL','ACTIVE','99700000-0000-4000-8000-000000000002');
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, service_zone_id, address_snapshot,
  location, capacity_limit, status, created_by
) values
('99700000-0000-4000-8000-000000000021','99700000-0000-4000-8000-000000000020',
 'V1 Cafe Central','99700000-0000-4000-8000-000000000010',
 '{"description":"Fresh food"}',extensions.st_setsrid(extensions.st_makepoint(78.62,12.68),4326),
 5,'ACTIVE','99700000-0000-4000-8000-000000000002'),
('99700000-0000-4000-8000-000000000031','99700000-0000-4000-8000-000000000030',
 'Secret Retail Branch','99700000-0000-4000-8000-000000000010','{}',
 extensions.st_setsrid(extensions.st_makepoint(78.61,12.68),4326),5,'ACTIVE',
 '99700000-0000-4000-8000-000000000002');
insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values
('99700000-0000-4000-8000-000000000021',true,true,'99700000-0000-4000-8000-000000000003'),
('99700000-0000-4000-8000-000000000031',true,true,'99700000-0000-4000-8000-000000000003');
insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values
('99700000-0000-4000-8000-000000000022','99700000-0000-4000-8000-000000000020',
 '99700000-0000-4000-8000-000000000003','ACTIVE','99700000-0000-4000-8000-000000000002'),
('99700000-0000-4000-8000-000000000032','99700000-0000-4000-8000-000000000030',
 '99700000-0000-4000-8000-000000000003','ACTIVE','99700000-0000-4000-8000-000000000002');
insert into dastak_v1.merchant_permission_grants (
  id, merchant_user_id, organization_id, bundle_id, branch_id, granted_by, grant_reason
) values
('99700000-0000-4000-8000-000000000023','99700000-0000-4000-8000-000000000022',
 '99700000-0000-4000-8000-000000000020','10000000-0000-4000-8000-000000000002',
 '99700000-0000-4000-8000-000000000021','99700000-0000-4000-8000-000000000002',
 'Restaurant V1 branch tests.'),
('99700000-0000-4000-8000-000000000033','99700000-0000-4000-8000-000000000032',
 '99700000-0000-4000-8000-000000000030','10000000-0000-4000-8000-000000000002',
 '99700000-0000-4000-8000-000000000031','99700000-0000-4000-8000-000000000002',
 'Mixed V1 retail tests.');

insert into dastak_v1.restaurant_menu_categories (
  id, organization_id, branch_id, name, sort_order, status, created_by, updated_by
) values (
  '99700000-0000-4000-8000-000000000040','99700000-0000-4000-8000-000000000020',
  '99700000-0000-4000-8000-000000000021','Breakfast',1,'ACTIVE',
  '99700000-0000-4000-8000-000000000003','99700000-0000-4000-8000-000000000003'
);
insert into dastak_v1.restaurant_menu_items (
  id, category_id, organization_id, branch_id, name, description,
  base_price_paise, logistics_attributes, status, created_by, updated_by
) values (
  '99700000-0000-4000-8000-000000000041','99700000-0000-4000-8000-000000000040',
  '99700000-0000-4000-8000-000000000020','99700000-0000-4000-8000-000000000021',
  'Masala Dosa','Prepared fresh',7000,
  '{"weightGrams":600,"lengthMillimetres":250,"widthMillimetres":180,"heightMillimetres":80}',
  'ACTIVE','99700000-0000-4000-8000-000000000003','99700000-0000-4000-8000-000000000003'
);
insert into dastak_v1.restaurant_menu_option_groups (
  id, menu_item_id, organization_id, branch_id, name, selection_type,
  minimum_selections, maximum_selections, status, created_by, updated_by
) values (
  '99700000-0000-4000-8000-000000000042','99700000-0000-4000-8000-000000000041',
  '99700000-0000-4000-8000-000000000020','99700000-0000-4000-8000-000000000021',
  'Spice','SINGLE',1,1,'ACTIVE','99700000-0000-4000-8000-000000000003',
  '99700000-0000-4000-8000-000000000003'
);
insert into dastak_v1.restaurant_menu_options (
  id, option_group_id, menu_item_id, organization_id, branch_id,
  name, price_delta_paise, status, created_by, updated_by
) values
('99700000-0000-4000-8000-000000000043','99700000-0000-4000-8000-000000000042',
 '99700000-0000-4000-8000-000000000041','99700000-0000-4000-8000-000000000020',
 '99700000-0000-4000-8000-000000000021','Mild',0,'ACTIVE',
 '99700000-0000-4000-8000-000000000003','99700000-0000-4000-8000-000000000003'),
('99700000-0000-4000-8000-000000000044','99700000-0000-4000-8000-000000000042',
 '99700000-0000-4000-8000-000000000041','99700000-0000-4000-8000-000000000020',
 '99700000-0000-4000-8000-000000000021','Extra spicy',500,'ACTIVE',
 '99700000-0000-4000-8000-000000000003','99700000-0000-4000-8000-000000000003');

insert into dastak_v1.categories (id,name,slug,status,created_by) values
('99700000-0000-4000-8000-000000000050','Retail','restaurant-test-retail','ACTIVE',
 '99700000-0000-4000-8000-000000000002');
insert into dastak_v1.subcategories (id,category_id,name,slug,status,created_by) values
('99700000-0000-4000-8000-000000000051','99700000-0000-4000-8000-000000000050',
 'Essentials','restaurant-test-essentials','ACTIVE','99700000-0000-4000-8000-000000000002');
insert into dastak_v1.skus (
  id,subcategory_id,canonical_name,slug,pack_size,list_price_paise,selling_price_paise,
  logistics_attributes,status,created_by
) values (
  '99700000-0000-4000-8000-000000000052','99700000-0000-4000-8000-000000000051',
  'Water','restaurant-test-water','1 L',2500,2000,
  '{"weightGrams":1000,"lengthMillimetres":300,"widthMillimetres":90,"heightMillimetres":90}',
  'ACTIVE','99700000-0000-4000-8000-000000000002'
);
insert into dastak_v1.merchant_sku_selections (branch_id,sku_id,state,selected_by) values
('99700000-0000-4000-8000-000000000031','99700000-0000-4000-8000-000000000052',
 'SELECTED','99700000-0000-4000-8000-000000000003');

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
('99700000-0000-4000-8000-000000000060','matching.retail_radius_meters','GLOBAL','3000',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000061','retail.prep_time_options_minutes','GLOBAL','[10,15,20]',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000062','matching.wave2_timeout_seconds','GLOBAL','180',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000063','matching.wave2_hold_seconds','GLOBAL','180',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000064','payment.reservation_seconds','GLOBAL','300',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000065','matching.wave2_max_pickup_route_meters','GLOBAL','5000',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000066','matching.operational_reliability_bps','GLOBAL','5000',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000067','delivery.transport_load_profiles','GLOBAL',
 '[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000068','delivery.default_sku_logistics','GLOBAL',
 '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-000000000069','settlement.merchant_commission_bps','GLOBAL','0',
 '99700000-0000-4000-8000-000000000002','Restaurant V1 tests.'),
('99700000-0000-4000-8000-00000000006a','merchant.reachability_stale_seconds','GLOBAL','300',
 '99700000-0000-4000-8000-000000000002','Restaurant local merchant heartbeat threshold.')
on conflict do nothing;

select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
select is(jsonb_array_length(public.dastak_v1_customer_restaurants(null,50)->'restaurants'),
  1, 'customer sees active Restaurant/Cafe discovery');
select ok(public.dastak_v1_customer_restaurants(null,50)::text ~ 'V1 Cafe'
  and public.dastak_v1_customer_restaurants(null,50)::text !~ 'Hidden Retail',
  'customer sees restaurant identity while retail identity remains hidden');

create temp table tap_restaurant_orders (
  sequence integer primary key, order_id uuid not null, request_id uuid not null
) on commit drop;
do $$
declare
  v_sequence integer;
  v_order jsonb;
  v_request_id uuid;
begin
  for v_sequence in 1..6 loop
    perform pg_catalog.set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
    v_order := dastak_v1_api.submit_order(
      '99700000-0000-4000-8000-000000000001', 'restaurant-food-' || v_sequence, 0,
      pg_catalog.jsonb_build_object(
        'restaurantBranchId','99700000-0000-4000-8000-000000000021',
        'deliveryAddress',pg_catalog.jsonb_build_object(
          'line1','1 Cafe Road','countryCode','IN','latitude',12.68,'longitude',78.63
        ),
        'recipient',pg_catalog.jsonb_build_object(
          'name','Restaurant Customer','phoneNumber','+919970000001'
        ),
        'lines',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
          'lineType','FOOD_MENU_ITEM','menuItemId','99700000-0000-4000-8000-000000000041',
          'optionIds',pg_catalog.jsonb_build_array('99700000-0000-4000-8000-000000000043'),
          'quantity',1
        ))
      )
    );
    select request.id into v_request_id from dastak_v1.restaurant_order_requests request
    where request.order_id = (v_order->>'id')::uuid;
    perform pg_catalog.set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000003',true);
    perform dastak_v1_api.respond_restaurant_request(
      '99700000-0000-4000-8000-000000000003',v_request_id,'CONFIRM',20,null,1,
      'restaurant-confirm-' || v_sequence
    );
    insert into tap_restaurant_orders values (v_sequence,(v_order->>'id')::uuid,v_request_id);
  end loop;
end;
$$;
grant select on tap_restaurant_orders to service_role;

select is((select status::text from dastak_v1.orders where id =
  (select order_id from tap_restaurant_orders where sequence=1)), 'AWAITING_PAYMENT',
  'food-only order is fully secured before payment');
select is((select fulfilment_type::text from dastak_v1.fulfilments where order_id =
  (select order_id from tap_restaurant_orders where sequence=1)), 'FOOD',
  'restaurant confirmation creates a real food fulfilment');
select is((select count(*) from dastak_v1.fulfilment_lines fulfilment_line
  join dastak_v1.order_lines line on line.id=fulfilment_line.order_line_id
  where line.order_id=(select order_id from tap_restaurant_orders where sequence=1)
    and fulfilment_line.confirmed_quantity=line.quantity), 1::bigint,
  'restaurant confirmation binds the exact food request');
select is((select active_order_count_snapshot from dastak_v1.restaurant_capacity_commitments
  where order_id=(select order_id from tap_restaurant_orders where sequence=6)), 6,
  'sixth active restaurant order records its true capacity context');
select ok((select accepted_above_threshold from dastak_v1.restaurant_capacity_commitments
  where order_id=(select order_id from tap_restaurant_orders where sequence=6)),
  'default threshold five is soft and order six may be accepted');
select is((select count(*) from dastak_v1.restaurant_capacity_commitments
  where status='COMMITTED'), 6::bigint, 'every accepted food order owns one commitment');
select is((select unit_price_paise from dastak_v1.order_lines where order_id=
  (select order_id from tap_restaurant_orders where sequence=1)), 7000::bigint,
  'food price is server-authoritative and snapshotted');
select ok((select food_selection_snapshot->'options' @>
  '[{"name":"Mild"}]'::jsonb from dastak_v1.order_lines where order_id=
  (select order_id from tap_restaurant_orders where sequence=1)),
  'selected variants/add-ons are snapshotted');

-- A real Restaurant/Cafe fulfilment enters the existing payment/preparation/Ready spine.
set local role service_role;
create temp table tap_restaurant_payment_attempt on commit drop as
select public.dastak_v1_prepare_razorpay_checkout(
  '99700000-0000-4000-8000-000000000001',
  (select order_id from tap_restaurant_orders where sequence=2),
  'restaurant-food-payment'
) body;
select public.dastak_v1_attach_razorpay_order(
  '99700000-0000-4000-8000-000000000001',
  (select (body->>'attemptId')::uuid from tap_restaurant_payment_attempt),
  'order_restaurantfood',
  (select (body->>'amountPaise')::bigint from tap_restaurant_payment_attempt),
  'INR'
);
create temp table tap_restaurant_capture on commit drop as
select * from public.dastak_v1_record_razorpay_event(
  'event_restaurant_food_capture','payment_captured',
  'order_restaurantfood','pay_restaurantfood',null,
  (select (body->>'amountPaise')::bigint from tap_restaurant_payment_attempt),
  now(),repeat('d',64)
);
reset role;
select is((select response_status from tap_restaurant_capture),200,
  'restaurant payment succeeds only after the food commitment is secured');
select is((select status::text from dastak_v1.orders where id=
  (select order_id from tap_restaurant_orders where sequence=2)),'PREPARING',
  'restaurant order enters preparation after payment');
select is((select status::text from dastak_v1.fulfilments where order_id=
  (select order_id from tap_restaurant_orders where sequence=2)),'PREPARING',
  'food fulfilment enters the generic preparation state');
select ok((select prep_started_at is not null and estimated_ready_at =
  prep_started_at + pg_catalog.make_interval(mins=>promised_prep_minutes)
  from dastak_v1.fulfilments where order_id=
  (select order_id from tap_restaurant_orders where sequence=2)),
  'food preparation uses the immutable merchant promise and server clock');

insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values (
  'dastak-evidence',
  'merchant-ready/99700000-0000-4000-8000-000000000003/99700000-0000-4000-8000-000000000099.jpg',
  '99700000-0000-4000-8000-000000000003',
  '99700000-0000-4000-8000-000000000003',
  '{"mimetype":"image/jpeg","size":2048}'::jsonb
);
create temp table tap_restaurant_ready_fulfilment on commit drop as
select id,version from dastak_v1.fulfilments where order_id=
  (select order_id from tap_restaurant_orders where sequence=2);
grant select,update on tap_restaurant_ready_fulfilment to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000003',true);
select public.dastak_v1_declare_fulfilment_packages(
  (select id from tap_restaurant_ready_fulfilment),
  'restaurant-food-packages',
  (select version from tap_restaurant_ready_fulfilment),1
);
update tap_restaurant_ready_fulfilment set version=version+1;
select public.dastak_v1_add_fulfilment_ready_evidence(
  (select id from tap_restaurant_ready_fulfilment),null,
  'merchant-ready/99700000-0000-4000-8000-000000000003/99700000-0000-4000-8000-000000000099.jpg',
  'restaurant-food-evidence',
  (select version from tap_restaurant_ready_fulfilment)
);
update tap_restaurant_ready_fulfilment set version=version+1;
select public.dastak_v1_mark_fulfilment_ready(
  (select id from tap_restaurant_ready_fulfilment),
  'restaurant-food-ready',
  (select version from tap_restaurant_ready_fulfilment)
);
reset role;
select is((select status::text from dastak_v1.fulfilments where order_id=
  (select order_id from tap_restaurant_orders where sequence=2)),'READY',
  'Restaurant/Cafe uses irreversible generic Ready');
select is((select count(*) from dastak_v1.packages package join dastak_v1.fulfilments fulfilment
  on fulfilment.id=package.fulfilment_id where fulfilment.order_id=
  (select order_id from tap_restaurant_orders where sequence=2)
  and package.status='READY'),1::bigint,
  'restaurant package declaration and evidence finalize one pickup package');
select is((select amount_paise from dastak_v1.settlement_entries settlement
  join dastak_v1.fulfilments fulfilment on fulfilment.id=settlement.fulfilment_id
  where fulfilment.order_id=(select order_id from tap_restaurant_orders where sequence=2)
    and settlement.subject_type='MERCHANT_ORGANIZATION'),7000::bigint,
  'zero commission preserves the correctly fulfilling restaurant earning snapshot');
select is((select (dastak_v1_api.merchant_fulfilment_json(
  '99700000-0000-4000-8000-000000000003',fulfilment.id)->'lines'->0->>'menuItemId')::uuid
  from dastak_v1.fulfilments fulfilment where fulfilment.order_id=
  (select order_id from tap_restaurant_orders where sequence=2)),
  '99700000-0000-4000-8000-000000000041'::uuid,
  'merchant preparation projection retains exact food selection');

insert into dastak_v1.customer_issues (
  id,order_id,customer_id,order_line_id,category,status,description
) values
('99700000-0000-4000-8000-000000000080',
 (select order_id from tap_restaurant_orders where sequence=2),
 '99700000-0000-4000-8000-000000000001',
 (select id from dastak_v1.order_lines where order_id=
  (select order_id from tap_restaurant_orders where sequence=2)),
 'OTHER','OPEN','Prepared food issue for physical-return rejection.'),
('99700000-0000-4000-8000-000000000081',
 (select order_id from tap_restaurant_orders where sequence=2),
 '99700000-0000-4000-8000-000000000001',
 (select id from dastak_v1.order_lines where order_id=
  (select order_id from tap_restaurant_orders where sequence=2)),
 'OTHER','OPEN','Prepared food issue for non-return refund resolution.');
insert into dastak_v1.returns (
  id,order_id,source,customer_issue_id,status,physical_return_required,
  reason,requested_by
) values
('99700000-0000-4000-8000-000000000082',
 (select order_id from tap_restaurant_orders where sequence=2),
 'CUSTOMER_ISSUE','99700000-0000-4000-8000-000000000080',
 'REQUESTED',true,'Prepared food must not enter reverse custody.',
 '99700000-0000-4000-8000-000000000001'),
('99700000-0000-4000-8000-000000000083',
 (select order_id from tap_restaurant_orders where sequence=2),
 'CUSTOMER_ISSUE','99700000-0000-4000-8000-000000000081',
 'REQUESTED',false,'Prepared food may use refund without physical return.',
 '99700000-0000-4000-8000-000000000001');
select throws_ok(
  $$insert into dastak_v1.return_lines(return_id,order_line_id,quantity,reason)
    select '99700000-0000-4000-8000-000000000082',line.id,1,
      'Physical prepared-food return forbidden.'
    from dastak_v1.order_lines line
    where line.order_id=(select order_id from tap_restaurant_orders where sequence=2)$$,
  '55000','PREPARED_FOOD_PHYSICAL_RETURN_FORBIDDEN',
  'prepared food is structurally rejected from physical reverse custody'
);
insert into dastak_v1.return_lines(return_id,order_line_id,quantity,reason)
select '99700000-0000-4000-8000-000000000083',line.id,1,
  'Investigation may resolve with a non-return refund.'
from dastak_v1.order_lines line
where line.order_id=(select order_id from tap_restaurant_orders where sequence=2);
select is((select count(*) from dastak_v1.return_lines where return_id=
  '99700000-0000-4000-8000-000000000083'),1::bigint,
  'prepared-food investigation may retain a refund-without-return resolution record');

select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
select ok((dastak_v1_api.order_json(
  (select order_id from tap_restaurant_orders where sequence=1),
  '99700000-0000-4000-8000-000000000001')->'restaurant'->>'name')='V1 Cafe',
  'customer order retains the selected restaurant identity');
select ok(dastak_v1_api.order_json(
  (select order_id from tap_restaurant_orders where sequence=1),
  '99700000-0000-4000-8000-000000000001')::text !~ 'Secret Retail Branch',
  'customer order projection never leaks retail merchant identity');

alter table dastak_v1.payments disable trigger payments_guard;
update dastak_v1.payments set reserved_at=now()-interval '6 minutes',
  expires_at=now()-interval '1 second'
where order_id=(select order_id from tap_restaurant_orders where sequence=1);
alter table dastak_v1.payments enable trigger payments_guard;
grant select on tap_restaurant_orders to service_role;
set local role service_role;
select ok(dastak_v1_api.expire_payment_reservation(
  (select order_id from tap_restaurant_orders where sequence=1)),
  'payment expiry executes for food order');
reset role;
select is((select status::text from dastak_v1.restaurant_capacity_commitments where order_id=
  (select order_id from tap_restaurant_orders where sequence=1)), 'RELEASED',
  'payment expiry releases restaurant commitment');
select is((select status::text from dastak_v1.fulfilments where order_id=
  (select order_id from tap_restaurant_orders where sequence=1)), 'RELEASED',
  'payment expiry releases food fulfilment');

select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
create temp table tap_mixed_order on commit drop as
select public.dastak_v1_submit_order('restaurant-mixed',0,pg_catalog.jsonb_build_object(
  'restaurantBranchId','99700000-0000-4000-8000-000000000021',
  'deliveryAddress',pg_catalog.jsonb_build_object(
    'line1','2 Mixed Road','countryCode','IN','latitude',12.68,'longitude',78.63),
  'recipient',pg_catalog.jsonb_build_object(
    'name','Restaurant Customer','phoneNumber','+919970000001'),
  'lines',pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('lineType','FOOD_MENU_ITEM',
      'menuItemId','99700000-0000-4000-8000-000000000041',
      'optionIds',pg_catalog.jsonb_build_array('99700000-0000-4000-8000-000000000044'),
      'quantity',1),
    pg_catalog.jsonb_build_object('lineType','RETAIL_SKU',
      'skuId','99700000-0000-4000-8000-000000000052','quantity',1)
  )
)) body;
reset role;
select is((select body->>'orderType' from tap_mixed_order),'MIXED',
  'food and retail submit as one mixed parent order');
select is((select count(*) from dastak_v1.restaurant_order_requests where order_id=
  (select (body->>'id')::uuid from tap_mixed_order)),1::bigint,
  'mixed order creates exactly one selected-restaurant request');
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000003',true);
select public.dastak_v1_respond_restaurant_request(
  (select id from dastak_v1.restaurant_order_requests where order_id=
    (select (body->>'id')::uuid from tap_mixed_order)),
  'CONFIRM',25,null,1,'restaurant-mixed-confirm');
select is((select status::text from dastak_v1.orders where id=
  (select (body->>'id')::uuid from tap_mixed_order)),'MATCHING',
  'restaurant winner alone cannot bypass the full-security coordinator');
select public.dastak_v1_accept_wave1_opportunity(
  (select id from dastak_v1.merchant_opportunities where order_id=
    (select (body->>'id')::uuid from tap_mixed_order) and branch_id=
    '99700000-0000-4000-8000-000000000031'),
  'restaurant-mixed-retail-confirm',1,10);
reset role;
select is((select status::text from dastak_v1.orders where id=
  (select (body->>'id')::uuid from tap_mixed_order)),'AWAITING_PAYMENT',
  'mixed order opens payment only after food and retail are secured');
select is((select count(*) from dastak_v1.fulfilments where order_id=
  (select (body->>'id')::uuid from tap_mixed_order) and status='RESERVED_PREPAYMENT'),
  2::bigint,'mixed parent has both required fulfilments');
select ok((dastak_v1_api.food_security_snapshot(
  (select (body->>'id')::uuid from tap_mixed_order))->>'secured')::boolean,
  'mixed food security includes combined transport and pickup route feasibility');

grant select on tap_mixed_order to service_role;
set local role service_role;
create temp table tap_mixed_payment_attempt on commit drop as
select public.dastak_v1_prepare_razorpay_checkout(
  '99700000-0000-4000-8000-000000000001',
  (select (body->>'id')::uuid from tap_mixed_order),'restaurant-mixed-payment'
) body;
select public.dastak_v1_attach_razorpay_order(
  '99700000-0000-4000-8000-000000000001',
  (select (body->>'attemptId')::uuid from tap_mixed_payment_attempt),
  'order_restaurantmixed',
  (select (body->>'amountPaise')::bigint from tap_mixed_payment_attempt),'INR'
);
select * from public.dastak_v1_record_razorpay_event(
  'event_restaurant_mixed_capture','payment_captured',
  'order_restaurantmixed','pay_restaurantmixed',null,
  (select (body->>'amountPaise')::bigint from tap_mixed_payment_attempt),
  now(),repeat('e',64)
);
reset role;
select is((select count(*) from dastak_v1.fulfilments where order_id=
  (select (body->>'id')::uuid from tap_mixed_order) and status='PREPARING'
  and prep_started_at is not null),2::bigint,
  'one payment atomically starts both food and retail preparation');

select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
create temp table tap_declined_food on commit drop as
select public.dastak_v1_submit_order('restaurant-decline',0,pg_catalog.jsonb_build_object(
  'restaurantBranchId','99700000-0000-4000-8000-000000000021',
  'deliveryAddress',pg_catalog.jsonb_build_object(
    'line1','3 Decline Road','countryCode','IN','latitude',12.68,'longitude',78.63),
  'recipient',pg_catalog.jsonb_build_object(
    'name','Restaurant Customer','phoneNumber','+919970000001'),
  'lines',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'lineType','FOOD_MENU_ITEM','menuItemId','99700000-0000-4000-8000-000000000041',
    'optionIds',pg_catalog.jsonb_build_array('99700000-0000-4000-8000-000000000043'),
    'quantity',1)))) body;
reset role;
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000003',true);
select public.dastak_v1_respond_restaurant_request(
  (select id from dastak_v1.restaurant_order_requests where order_id=
    (select (body->>'id')::uuid from tap_declined_food)),
  'DECLINE',null,'Kitchen unavailable',1,'restaurant-decline-response');
reset role;
select is((select status::text from dastak_v1.orders where id=
  (select (body->>'id')::uuid from tap_declined_food)),'UNAVAILABLE',
  'selected restaurant decline makes food unavailable without rerouting');
select is((select count(*) from dastak_v1.fulfilments where order_id=
  (select (body->>'id')::uuid from tap_declined_food)),0::bigint,
  'declined food request never fabricates a replacement fulfilment');

select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000001',true);
create temp table tap_cancelled_food on commit drop as
select public.dastak_v1_submit_order('restaurant-cancel',0,pg_catalog.jsonb_build_object(
  'restaurantBranchId','99700000-0000-4000-8000-000000000021',
  'deliveryAddress',pg_catalog.jsonb_build_object(
    'line1','4 Cancel Road','countryCode','IN','latitude',12.68,'longitude',78.63),
  'recipient',pg_catalog.jsonb_build_object(
    'name','Restaurant Customer','phoneNumber','+919970000001'),
  'lines',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'lineType','FOOD_MENU_ITEM','menuItemId','99700000-0000-4000-8000-000000000041',
    'optionIds',pg_catalog.jsonb_build_array('99700000-0000-4000-8000-000000000043'),
    'quantity',1)))) body;
select public.dastak_v1_cancel_prepayment_order(
  (select (body->>'id')::uuid from tap_cancelled_food),'restaurant-cancel-command',2);
reset role;
select is((select status::text from dastak_v1.restaurant_order_requests where order_id=
  (select (body->>'id')::uuid from tap_cancelled_food)),'RELEASED',
  'pre-payment cancellation releases an unconfirmed restaurant request');
select is((select count(*) from dastak_v1.restaurant_capacity_commitments where order_id=
  (select (body->>'id')::uuid from tap_cancelled_food)),0::bigint,
  'cancelling before restaurant confirmation creates no capacity commitment');

select * from finish();
rollback;
