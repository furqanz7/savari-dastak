-- Align the launch COD validation rule with the already-authoritative launch
-- default. The pay-at-delivery launch deliberately enables COD; retaining the
-- pre-launch "false only" rule made the Admin configuration projection report
-- that valid launch setting as invalid.

update dastak_v1.setting_definitions
set default_value = 'true'::jsonb,
    validation_rules = coalesce(validation_rules, '{}'::jsonb)
      || '{"allowedValues":[true]}'::jsonb,
    updated_at = pg_catalog.now()
where setting_key = 'commerce.allow_cod';
