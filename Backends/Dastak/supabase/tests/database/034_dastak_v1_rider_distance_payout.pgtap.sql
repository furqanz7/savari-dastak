begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_column(
  'dastak_v1', 'delivery_missions', 'delivery_distance_meters',
  'delivery mission snapshots authoritative Dastak distance'
);
select has_column(
  'dastak_v1', 'delivery_missions', 'rider_payout_quote_paise',
  'delivery mission snapshots quoted rider payout'
);
select has_column(
  'dastak_v1', 'delivery_missions', 'rider_payout_quote_snapshot',
  'delivery mission snapshots payout policy inputs'
);
select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'dastak_v1' and table_name = 'delivery_missions'
      and column_name in (
        'delivery_distance_meters', 'rider_payout_quote_paise',
        'rider_payout_quote_snapshot'
      ) and is_nullable = 'NO'
  ),
  3::bigint,
  'all mission payout snapshot fields are structurally required'
);
select has_trigger(
  'dastak_v1', 'delivery_missions', 'delivery_missions_quote_rider_payout',
  'mission creation calculates the authoritative payout quote'
);
select has_trigger(
  'dastak_v1', 'delivery_missions', 'delivery_missions_00_payout_snapshot_guard',
  'mission payout quote is immutable'
);
select is(
  (
    select count(*) from dastak_v1.setting_definitions
    where setting_key = 'settlement.rider_distance_payout'
      and value_type = 'JSON' and protected and requires_explicit_value
      and default_value is null
  ),
  1::bigint,
  'distance-band payout requires explicit protected production configuration'
);
select is(
  (
    select count(*) from dastak_v1.setting_definitions
    where setting_key = 'settlement.rider_flat_payout_paise'
  ),
  0::bigint,
  'flat rider payout is not a production dependency'
);
select is(
  (
    select validation_rules from dastak_v1.setting_definitions
    where setting_key = 'settlement.merchant_commission_bps'
  ),
  '{"minimum":0,"maximum":0}'::jsonb,
  'launch merchant commission remains locked at zero basis points'
);

with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(0, value), 1500::bigint,
  '0 metres earns the base payout') from policy;
with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(1000, value), 1500::bigint,
  '1000 metres remains in the base band') from policy;
with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(1001, value), 2000::bigint,
  '1001 metres starts the second payout band') from policy;
with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(2000, value), 2000::bigint,
  '2000 metres remains in the second payout band') from policy;
with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(2001, value), 2500::bigint,
  '2001 metres starts the third payout band') from policy;
with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(10000, value), 6000::bigint,
  'larger exact-band distance remains deterministic') from policy;
with policy(value) as (values (
  '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"STARTED_DISTANCE_BAND"}'::jsonb
))
select is(dastak_v1_api.calculate_rider_distance_payout(10001, value), 6500::bigint,
  'larger started distance band rounds upward once') from policy;

select is(
  dastak_v1.is_valid_rider_distance_payout(
    '{"base_distance_meters":1000,"base_payout_paise":1500,"increment_distance_meters":1000,"increment_payout_paise":500,"rounding":"NEAREST"}'::jsonb
  ),
  false,
  'unsupported payout rounding is rejected'
);

select * from finish();
rollback;
