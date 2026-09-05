-- Restore non-motor delivery options without reviving retired approvals or quotes.
-- Motor-vehicle verification, aliases, and goods-vehicle support are unchanged.
alter table private.delivery_partner_applications
  drop constraint delivery_partner_applications_delivery_method_check,
  drop constraint delivery_partner_v2_vehicle_contract,
  add constraint delivery_partner_applications_delivery_method_check check (
    delivery_method in ('retired', 'walking', 'bicycle', 'motorbike', 'scooter', 'auto', 'goods_vehicle')
  ),
  add constraint delivery_partner_v2_vehicle_contract check (
    verification_version = 1
    or (
      delivery_method in ('retired', 'walking', 'bicycle')
      and vehicle_registration_number is null
      and vehicle_make_model is null
      and vehicle_evidence_object_path is null
    )
    or (
      delivery_method in ('motorbike', 'scooter', 'auto', 'goods_vehicle')
      and vehicle_registration_number is not null
      and vehicle_make_model is not null
      and vehicle_evidence_object_path is not null
      and vehicle_evidence_object_path <> identity_evidence_object_path
    )
  );

alter table private.delivery_partner_profiles
  drop constraint delivery_partner_profiles_delivery_method_check,
  add constraint delivery_partner_profiles_delivery_method_check check (
    delivery_method in ('walking', 'bicycle', 'motorbike', 'scooter', 'auto', 'goods_vehicle')
  );

create or replace function private.normalize_delivery_partner_method()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.delivery_method = 'bike' then
    new.delivery_method := 'motorbike';
  elsif new.delivery_method = 'car' then
    new.delivery_method := 'goods_vehicle';
  end if;
  return new;
end;
$$;

drop trigger reject_retired_parcel_rate_card_method on private.parcel_rate_cards;
drop trigger reject_retired_parcel_quote_method on private.parcel_quotes;
drop trigger reject_retired_parcel_delivery_method on private.parcel_deliveries;
drop function private.reject_retired_parcel_delivery_method();

create or replace function private.parcel_method_matches_partner(
  p_parcel_method text,
  p_partner_method text
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_parcel_method
    when 'walking' then p_partner_method = 'walking'
    when 'bicycle' then p_partner_method = 'bicycle'
    when 'bike' then p_partner_method in ('bike', 'motorbike', 'scooter')
    when 'auto' then p_partner_method in ('auto', 'car', 'goods_vehicle')
    else false
  end;
$$;

create or replace function public.submit_delivery_partner_application_v3(
  p_account_id uuid,
  p_delivery_method text,
  p_identity_evidence_object_path text,
  p_vehicle_registration_number text,
  p_vehicle_make_model text,
  p_vehicle_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mapped_method text;
  v_result record;
begin
  if p_delivery_method is null or p_delivery_method not in (
    'walking', 'bicycle', 'motorbike', 'scooter', 'auto', 'goods_vehicle'
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Choose one of the available delivery methods.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_mapped_method := case p_delivery_method
    when 'motorbike' then 'bike'
    when 'scooter' then 'auto'
    when 'goods_vehicle' then 'car'
    else p_delivery_method
  end;

  select result.* into v_result
  from public.submit_delivery_partner_application_v2(
    p_account_id, v_mapped_method, p_identity_evidence_object_path,
    p_vehicle_registration_number, p_vehicle_make_model,
    p_vehicle_evidence_object_path, p_idempotency_key, p_request_digest
  ) result;
  response_status := v_result.response_status;
  response_body := v_result.response_body;

  if response_status = 200 then
    update private.delivery_partner_applications application
    set delivery_method = p_delivery_method,
        updated_at = pg_catalog.now()
    where application.account_id = p_account_id
      and application.status = 'pending';
    response_body := pg_catalog.jsonb_set(
      response_body,
      '{deliveryMethod}',
      pg_catalog.to_jsonb(p_delivery_method),
      true
    );
  end if;
  return next;
end;
$$;

create or replace function dastak_v1.rider_transport_type(p_delivery_method text)
returns dastak_v1.transport_type
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_delivery_method
    when 'walking' then 'WALKING'::dastak_v1.transport_type
    when 'bicycle' then 'BICYCLE'::dastak_v1.transport_type
    when 'bike' then 'MOTORBIKE'::dastak_v1.transport_type
    when 'motorbike' then 'MOTORBIKE'::dastak_v1.transport_type
    when 'scooter' then 'SCOOTER'::dastak_v1.transport_type
    when 'auto' then 'AUTO'::dastak_v1.transport_type
    when 'car' then 'CAR'::dastak_v1.transport_type
    when 'goods_vehicle' then 'CAR'::dastak_v1.transport_type
    else null
  end;
$$;

create or replace function dastak_v1.is_valid_transport_load_profiles(
  p_profiles jsonb
)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_profile jsonb;
  v_type text;
  v_seen text[] := '{}'::text[];
  v_expected_weight bigint;
  v_expected_volume bigint;
  v_expected_packages integer;
  v_expected_longest integer;
begin
  if pg_catalog.jsonb_typeof(p_profiles) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_profiles) <> 6 then
    return false;
  end if;
  for v_profile in
    select value from pg_catalog.jsonb_array_elements(p_profiles)
  loop
    if pg_catalog.jsonb_typeof(v_profile) <> 'object' then return false; end if;
    v_type := v_profile ->> 'transportType';
    if v_type is null or v_type not in ('WALKING', 'BICYCLE', 'MOTORBIKE', 'SCOOTER', 'AUTO', 'CAR')
      or v_type = any(v_seen) then
      return false;
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_type);
    select expected.weight_grams, expected.volume_mm3,
      expected.package_count, expected.longest_mm
    into v_expected_weight, v_expected_volume,
      v_expected_packages, v_expected_longest
    from (values
      ('WALKING', 5000::bigint, 20000000::bigint, 2, 400),
      ('BICYCLE', 10000::bigint, 35000000::bigint, 3, 500),
      ('MOTORBIKE', 20000::bigint, 60000000::bigint, 4, 600),
      ('SCOOTER', 25000::bigint, 75000000::bigint, 5, 650),
      ('AUTO', 80000::bigint, 250000000::bigint, 12, 1000),
      ('CAR', 150000::bigint, 500000000::bigint, 20, 1200)
    ) expected(transport_type, weight_grams, volume_mm3, package_count, longest_mm)
    where expected.transport_type = v_type;

    if pg_catalog.jsonb_typeof(v_profile -> 'maxWeightGrams') is distinct from 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxVolumeCubicMillimetres') is distinct from 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxPackageCount') is distinct from 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxLongestSideMillimetres') is distinct from 'number'
      or (v_profile ->> 'maxWeightGrams')::bigint <> v_expected_weight
      or (v_profile ->> 'maxVolumeCubicMillimetres')::bigint <> v_expected_volume
      or (v_profile ->> 'maxPackageCount')::integer <> v_expected_packages
      or (v_profile ->> 'maxLongestSideMillimetres')::integer <> v_expected_longest then
      return false;
    end if;
  end loop;
  return pg_catalog.cardinality(v_seen) = 6;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

-- Reintroduce the original locked capacities; preserve all motor profiles.
update dastak_v1.platform_settings setting
set setting_value = '[
      {"transportType":"WALKING","maxWeightGrams":5000,"maxVolumeCubicMillimetres":20000000,"maxPackageCount":2,"maxLongestSideMillimetres":400},
      {"transportType":"BICYCLE","maxWeightGrams":10000,"maxVolumeCubicMillimetres":35000000,"maxPackageCount":3,"maxLongestSideMillimetres":500}
    ]'::jsonb || (
      select pg_catalog.jsonb_agg(item.value order by item.ordinality)
      from pg_catalog.jsonb_array_elements(setting.setting_value)
        with ordinality as item(value, ordinality)
      where item.value ->> 'transportType' not in ('WALKING', 'BICYCLE')
    ),
    update_reason = 'Restore walking and bicycle with their original non-motor load limits.',
    updated_at = pg_catalog.now(),
    version = setting.version + 1
where setting.setting_key = 'delivery.transport_load_profiles';

-- Rate cards remain operator-managed. There are no existing walking/bicycle
-- rate cards in production; do not invent prices or reactivate historical rates.
-- Retired applications remain rejected and must go through normal reapplication.
revoke execute on function private.normalize_delivery_partner_method()
  from public, anon, authenticated;
grant execute on function private.normalize_delivery_partner_method() to service_role;
revoke execute on function private.parcel_method_matches_partner(text, text)
  from public, anon, authenticated;
grant execute on function private.parcel_method_matches_partner(text, text) to service_role;
revoke execute on function public.submit_delivery_partner_application_v3(
  uuid, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_delivery_partner_application_v3(
  uuid, text, text, text, text, text, text, text
) to service_role;
