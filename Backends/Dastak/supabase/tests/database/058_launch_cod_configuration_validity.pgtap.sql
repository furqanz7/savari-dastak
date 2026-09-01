begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  (
    select default_value
    from dastak_v1.setting_definitions
    where setting_key = 'commerce.allow_cod'
  ),
  'true'::jsonb,
  'launch COD remains enabled by the authoritative default'
);

select is(
  dastak_v1.validate_setting_value('commerce.allow_cod', 'true'::jsonb),
  true,
  'the launch COD value passes its own validation contract'
);

select is(
  dastak_v1.validate_setting_value('commerce.allow_cod', 'false'::jsonb),
  false,
  'the launch contract cannot silently disable its only pay-at-delivery option'
);

select * from finish();
rollback;
