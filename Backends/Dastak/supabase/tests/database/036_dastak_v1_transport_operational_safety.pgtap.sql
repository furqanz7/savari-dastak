begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create temp table tap_locked_transport_profiles(value jsonb) on commit drop;
insert into tap_locked_transport_profiles values (
  '[{"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},{"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500},{"transportType":"MOTORBIKE","maxWeightGrams":20000,"maxVolumeCubicMillimetres":60000000,"maxPackageCount":4,"maxLongestSideMillimetres":600},{"transportType":"SCOOTER","maxWeightGrams":25000,"maxVolumeCubicMillimetres":75000000,"maxPackageCount":5,"maxLongestSideMillimetres":650},{"transportType":"AUTO","maxWeightGrams":80000,"maxVolumeCubicMillimetres":250000000,"maxPackageCount":12,"maxLongestSideMillimetres":1000},{"transportType":"CAR","maxWeightGrams":150000,"maxVolumeCubicMillimetres":500000000,"maxPackageCount":20,"maxLongestSideMillimetres":1200}]'::jsonb
);

select extensions.has_type('dastak_v1', 'rider_escalation_state', 'rider escalation state exists');
select extensions.has_type('dastak_v1', 'operational_pause_scope', 'named pause scope exists');
select extensions.has_table('dastak_v1', 'operational_pause_controls', 'scoped pause truth exists');
select extensions.is((select count(*)::integer from dastak_v1.setting_definitions
  where setting_key in ('delivery.rider_stall_threshold_seconds',
    'delivery.rider_unresponsive_threshold_seconds')), 2, 'both rider thresholds are explicit settings');
select extensions.is((select count(*)::integer from dastak_v1.permission_definitions
  where permission_key in ('platform.delivery.operations.manage',
    'platform.operational_safety.manage')), 2, 'safety actions use named permissions');

select extensions.has_column('dastak_v1', 'delivery_missions', 'rider_last_contact_at', 'rider contact is authoritative');
select extensions.has_column('dastak_v1', 'delivery_missions', 'rider_last_progress_at', 'rider progress is authoritative');
select extensions.has_column('dastak_v1', 'delivery_missions', 'stall_detected_at', 'stall timestamp exists');
select extensions.has_column('dastak_v1', 'delivery_missions', 'unresponsive_detected_at', 'unresponsive timestamp exists');
select extensions.has_column('dastak_v1', 'delivery_missions', 'escalation_state', 'escalation state exists');
select extensions.has_column('dastak_v1', 'delivery_missions', 'escalated_at', 'escalation timestamp exists');
select extensions.has_column('dastak_v1', 'delivery_missions', 'escalation_reason', 'escalation reason exists');
select extensions.has_column('dastak_v1', 'delivery_missions', 'escalated_by', 'operator attribution exists');

select extensions.has_function('dastak_v1_api', 'transport_load_snapshot',
  array['numeric','numeric','integer','numeric','boolean','jsonb']);
select extensions.has_function('dastak_v1_api', 'process_rider_escalations',
  array['integer','timestamp with time zone']);
select extensions.has_function('public', 'dastak_v1_rider_heartbeat',
  array['uuid','uuid','bigint']);
select extensions.has_function('public', 'dastak_v1_manage_rider_escalation',
  array['uuid','text','text','bigint','text']);
select extensions.has_function('public', 'dastak_v1_set_operational_pause',
  array['text','uuid','boolean','text','bigint','text']);
select extensions.has_function('public', 'dastak_v1_admin_operational_safety', array[]::text[]);

select extensions.ok(dastak_v1.is_valid_transport_load_profiles(value),
  'locked six-profile configuration is accepted') from tap_locked_transport_profiles;
select extensions.ok(not dastak_v1.is_valid_transport_load_profiles(
  (select value - 5 from tap_locked_transport_profiles)
), 'all six profiles are required');
select extensions.ok(not dastak_v1.is_valid_transport_load_profiles(
  pg_catalog.jsonb_set((select value from tap_locked_transport_profiles),
    '{0,maxPackageCount}', '3'::jsonb)
), 'a changed locked transport limit is rejected');
select extensions.ok(dastak_v1.is_valid_default_sku_logistics(
  '{"weightGrams":1000,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}'
), 'locked unknown-SKU fallback is accepted');
select extensions.ok(not dastak_v1.is_valid_default_sku_logistics(
  '{"weightGrams":999,"volumeCubicMillimetres":4000000,"longestSideMillimetres":300}'
), 'changed unknown-SKU fallback is rejected');

with limits(transport_type, weight_grams, volume_mm3, packages, longest_mm) as (values
  ('WALKING',5000::numeric,20000000::numeric,2,400::numeric),
  ('BICYCLE',10000,35000000,3,500), ('MOTORBIKE',20000,60000000,4,600),
  ('SCOOTER',25000,75000000,5,650), ('AUTO',80000,250000000,12,1000),
  ('CAR',150000,500000000,20,1200)
)
select extensions.ok(
  dastak_v1_api.transport_load_snapshot(
    weight_grams, volume_mm3, packages, longest_mm, true,
    (select value from tap_locked_transport_profiles)
  ) -> 'eligibleTransportTypes' @> pg_catalog.to_jsonb(array[transport_type]),
  transport_type || ' accepts every exact locked limit'
) from limits;

with limits(transport_type, weight_grams, volume_mm3, packages, longest_mm) as (values
  ('WALKING',5000::numeric,20000000::numeric,2,400::numeric),
  ('BICYCLE',10000,35000000,3,500), ('MOTORBIKE',20000,60000000,4,600),
  ('SCOOTER',25000,75000000,5,650), ('AUTO',80000,250000000,12,1000),
  ('CAR',150000,500000000,20,1200)
)
select extensions.ok(not (
  dastak_v1_api.transport_load_snapshot(
    weight_grams + 1, 1, 1, 1, true,
    (select value from tap_locked_transport_profiles)
  ) -> 'eligibleTransportTypes' @> pg_catalog.to_jsonb(array[transport_type])
), transport_type || ' rejects weight above its cap') from limits;

with limits(transport_type, weight_grams, volume_mm3, packages, longest_mm) as (values
  ('WALKING',5000::numeric,20000000::numeric,2,400::numeric),
  ('BICYCLE',10000,35000000,3,500), ('MOTORBIKE',20000,60000000,4,600),
  ('SCOOTER',25000,75000000,5,650), ('AUTO',80000,250000000,12,1000),
  ('CAR',150000,500000000,20,1200)
)
select extensions.ok(not (
  dastak_v1_api.transport_load_snapshot(
    1, volume_mm3 + 1, 1, 1, true,
    (select value from tap_locked_transport_profiles)
  ) -> 'eligibleTransportTypes' @> pg_catalog.to_jsonb(array[transport_type])
), transport_type || ' rejects volume above its cap') from limits;

with limits(transport_type, weight_grams, volume_mm3, packages, longest_mm) as (values
  ('WALKING',5000::numeric,20000000::numeric,2,400::numeric),
  ('BICYCLE',10000,35000000,3,500), ('MOTORBIKE',20000,60000000,4,600),
  ('SCOOTER',25000,75000000,5,650), ('AUTO',80000,250000000,12,1000),
  ('CAR',150000,500000000,20,1200)
)
select extensions.ok(not (
  dastak_v1_api.transport_load_snapshot(
    1, 1, packages + 1, 1, true,
    (select value from tap_locked_transport_profiles)
  ) -> 'eligibleTransportTypes' @> pg_catalog.to_jsonb(array[transport_type])
), transport_type || ' rejects package count above its cap') from limits;

with limits(transport_type, weight_grams, volume_mm3, packages, longest_mm) as (values
  ('WALKING',5000::numeric,20000000::numeric,2,400::numeric),
  ('BICYCLE',10000,35000000,3,500), ('MOTORBIKE',20000,60000000,4,600),
  ('SCOOTER',25000,75000000,5,650), ('AUTO',80000,250000000,12,1000),
  ('CAR',150000,500000000,20,1200)
)
select extensions.ok(not (
  dastak_v1_api.transport_load_snapshot(
    1, 1, 1, longest_mm + 1, true,
    (select value from tap_locked_transport_profiles)
  ) -> 'eligibleTransportTypes' @> pg_catalog.to_jsonb(array[transport_type])
), transport_type || ' rejects longest side above its cap') from limits;

select extensions.has_trigger('dastak_v1', 'fulfilments',
  'fulfilments_revalidate_transport_after_packages', 'package declaration revalidates transport');
select extensions.has_trigger('dastak_v1', 'packages',
  'packages_enforce_final_transport_before_pickup', 'pickup enforces final transport');
select extensions.has_trigger('dastak_v1', 'order_context_snapshots',
  'order_context_snapshots_enforce_zone_pause', 'new orders enforce zone pause');
select extensions.has_trigger('dastak_v1', 'merchant_opportunities',
  'merchant_opportunities_enforce_emergency_pause', 'new merchant work enforces branch pause');
select extensions.has_trigger('dastak_v1', 'delivery_offers',
  'delivery_offers_enforce_rider_pause', 'new rider work enforces rider pause');

select * from extensions.finish();
rollback;
