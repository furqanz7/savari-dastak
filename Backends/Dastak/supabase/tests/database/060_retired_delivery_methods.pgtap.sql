begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'public',
  'submit_delivery_partner_application_v3',
  array['uuid', 'text', 'text', 'text', 'text', 'text', 'text', 'text']
);
select has_function(
  'private',
  'normalize_delivery_partner_method',
  array[]::text[]
);
select has_function(
  'private',
  'reject_retired_parcel_delivery_method',
  array[]::text[]
);
select has_function(
  'private',
  'parcel_method_matches_partner',
  array['text', 'text']
);

select is(
  has_function_privilege(
    'authenticated',
    'public.submit_delivery_partner_application_v3(uuid,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot bypass the delivery-partner Edge Function'
);
select is(
  has_function_privilege(
    'service_role',
    'public.submit_delivery_partner_application_v3(uuid,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'the authenticated Edge Function may submit current delivery methods'
);

select is(
  dastak_v1.rider_transport_type('walking')::text,
  null,
  'walking has no current dispatch transport mapping'
);
select is(
  dastak_v1.rider_transport_type('bicycle')::text,
  null,
  'bicycle has no current dispatch transport mapping'
);
select is(
  dastak_v1.rider_transport_type('goods_vehicle')::text,
  'CAR',
  'goods vehicles use the internal heavy-load capacity class'
);

select ok(
  dastak_v1.is_valid_transport_load_profiles(
    '[{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]'::jsonb
  ),
  'the four-profile production capacity contract remains valid'
);

select ok(
  private.parcel_method_matches_partner('bike', 'motorbike'),
  'motorbikes can serve the internal bike parcel capacity class'
);
select ok(
  private.parcel_method_matches_partner('bike', 'scooter'),
  'scooters can serve the internal bike parcel capacity class'
);
select ok(
  private.parcel_method_matches_partner('auto', 'auto'),
  'autos can serve the internal auto parcel capacity class'
);
select ok(
  private.parcel_method_matches_partner('auto', 'goods_vehicle'),
  'goods vehicles can serve the internal auto parcel capacity class'
);
select ok(
  not private.parcel_method_matches_partner('bicycle', 'motorbike'),
  'a retired bicycle parcel cannot match a current partner'
);
select ok(
  not private.parcel_method_matches_partner('walking', 'goods_vehicle'),
  'a retired walking parcel cannot match a current partner'
);

select is(
  (
    select response_status
    from public.submit_delivery_partner_application_v3(
      '60000000-0000-4000-8000-000000000001',
      'walking', 'retired/identity.jpg', null, null, null,
      'retired-walking', 'retired-walking-digest'
    )
  ),
  400,
  'walking cannot be submitted through the authoritative application RPC'
);
select is(
  (
    select response_status
    from public.submit_delivery_partner_application_v3(
      '60000000-0000-4000-8000-000000000001',
      'bicycle', 'retired/identity.jpg', null, null, null,
      'retired-bicycle', 'retired-bicycle-digest'
    )
  ),
  400,
  'bicycle cannot be submitted through the authoritative application RPC'
);
select is(
  (
    select response_status
    from public.submit_delivery_partner_application_v3(
      '60000000-0000-4000-8000-000000000001',
      'car', 'retired/identity.jpg', null, null, null,
      'retired-car', 'retired-car-digest'
    )
  ),
  400,
  'passenger car is not a current customer-facing application method'
);

select has_trigger(
  'private', 'parcel_rate_cards',
  'reject_retired_parcel_rate_card_method',
  'new rate cards cannot re-enable retired parcel methods'
);
select has_trigger(
  'private', 'parcel_quotes',
  'reject_retired_parcel_quote_method',
  'new quotes cannot use retired parcel methods'
);
select has_trigger(
  'private', 'parcel_deliveries',
  'reject_retired_parcel_delivery_method',
  'new parcels cannot use retired parcel methods'
);

select throws_ok(
  $$insert into private.parcel_rate_cards (
      service_zone_id, delivery_method, minimum_fare_paise,
      per_kilometre_paise, courier_payout_bps, version, created_by
    ) values (
      '60000000-0000-4000-8000-000000000002', 'walking',
      1000, 100, 8000, 1,
      '60000000-0000-4000-8000-000000000003'
    )$$,
  '23514',
  'Walking and bicycle are no longer available parcel delivery methods.',
  'the database rejects a new walking parcel rate card before foreign-key checks'
);

select * from finish();
rollback;
