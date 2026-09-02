-- Retire walking and bicycle as current delivery methods and replace the customer-facing
-- car option with a goods-vehicle/tempo method. Historical operational enum
-- values remain readable, but no current application or dispatch path can use
-- either retired method.

do $$
begin
  if exists (
    select 1
    from dastak_v1.delivery_missions mission
    join private.delivery_partner_profiles profile
      on profile.account_id = mission.assigned_rider_id
    where profile.delivery_method in ('walking', 'bicycle')
      and mission.status not in ('DELIVERED', 'CANCELLED')
  ) then
    raise exception using
      errcode = '55000',
      message = 'Walking and bicycle cannot be retired while an affected rider has an active mission.';
  end if;

  if exists (
    select 1
    from private.parcel_deliveries parcel
    where parcel.delivery_method in ('walking', 'bicycle')
      and parcel.status not in ('delivered', 'cancelled')
  ) then
    raise exception using
      errcode = '55000',
      message = 'Walking and bicycle cannot be retired while an affected parcel delivery is active.';
  end if;
end;
$$;

alter table private.delivery_partner_applications
  drop constraint delivery_partner_applications_delivery_method_check,
  drop constraint delivery_partner_v2_vehicle_contract;
alter table private.delivery_partner_profiles
  drop constraint delivery_partner_profiles_delivery_method_check;

do $$
declare
  v_reviewer_id uuid;
begin
  if exists (
    select 1
    from private.delivery_partner_applications application
    where application.delivery_method in ('walking', 'bicycle')
      or (
        application.status = 'pending'
        and application.verification_version = 1
        and application.delivery_method in ('bike', 'auto', 'car')
      )
  ) then
    select assignment.account_id
    into v_reviewer_id
    from dastak_v1.admin_role_assignments assignment
    where assignment.slot = 0
      and assignment.role = 'SUPERADMIN'
      and assignment.account_id is not null;

    if v_reviewer_id is null then
      raise exception using
        errcode = '55000',
        message = 'A Superadmin is required to retire an existing delivery method.';
    end if;
  end if;

  update private.delivery_partner_availability availability
  set status = 'offline',
      location = null,
      service_zone_id = null,
      available_until = null,
      last_seen_at = pg_catalog.now(),
      updated_at = pg_catalog.now(),
      state_version = availability.state_version + 1
  where availability.account_id in (
    select profile.account_id
    from private.delivery_partner_profiles profile
    where profile.delivery_method in ('walking', 'bicycle')
  );

  delete from private.account_memberships membership
  where membership.role = 'dastak_partner'
    and membership.account_id in (
      select profile.account_id
      from private.delivery_partner_profiles profile
      where profile.delivery_method in ('walking', 'bicycle')
    );

  delete from private.delivery_partner_profiles profile
  where profile.delivery_method in ('walking', 'bicycle');

  update private.delivery_partner_applications application
  set delivery_method = 'retired',
      status = 'rejected',
      reviewed_at = pg_catalog.now(),
      reviewed_by = coalesce(application.reviewed_by, v_reviewer_id),
      review_reason = 'This delivery method is no longer available. Choose a current method to reapply.',
      updated_at = pg_catalog.now()
  where application.delivery_method in ('walking', 'bicycle')
    or (
      application.status = 'pending'
      and application.verification_version = 1
      and application.delivery_method in ('bike', 'auto', 'car')
    );

  update private.delivery_partner_applications application
  set delivery_method = case application.delivery_method
        when 'bike' then 'motorbike'
        when 'car' then 'goods_vehicle'
        else application.delivery_method
      end,
      updated_at = pg_catalog.now()
  where application.delivery_method in ('bike', 'car');

  update private.delivery_partner_profiles profile
  set delivery_method = case profile.delivery_method
        when 'bike' then 'motorbike'
        when 'car' then 'goods_vehicle'
        else profile.delivery_method
      end,
      updated_at = pg_catalog.now()
  where profile.delivery_method in ('bike', 'car');
end;
$$;

alter table private.delivery_partner_applications
  add constraint delivery_partner_applications_delivery_method_check check (
    delivery_method in (
      'retired', 'motorbike', 'scooter', 'auto', 'goods_vehicle'
    )
  ),
  add constraint delivery_partner_v2_vehicle_contract check (
    verification_version = 1
    or (
      delivery_method = 'retired'
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
  add constraint delivery_partner_profiles_delivery_method_check check (
    delivery_method in (
      'motorbike', 'scooter', 'auto', 'goods_vehicle'
    )
  );

create or replace function private.normalize_delivery_partner_method()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.delivery_method in ('walking', 'bicycle') then
    raise exception using
      errcode = '23514',
      message = 'Walking and bicycle are no longer available delivery methods.';
  elsif new.delivery_method = 'bike' then
    new.delivery_method := 'motorbike';
  elsif new.delivery_method = 'car' then
    new.delivery_method := 'goods_vehicle';
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_delivery_partner_application_method
  on private.delivery_partner_applications;
create trigger normalize_delivery_partner_application_method
before insert or update of delivery_method
on private.delivery_partner_applications
for each row execute function private.normalize_delivery_partner_method();

drop trigger if exists normalize_delivery_partner_profile_method
  on private.delivery_partner_profiles;
create trigger normalize_delivery_partner_profile_method
before insert or update of delivery_method
on private.delivery_partner_profiles
for each row execute function private.normalize_delivery_partner_method();

create or replace function private.reject_retired_parcel_delivery_method()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.delivery_method in ('walking', 'bicycle') then
    raise exception using
      errcode = '23514',
      message = 'Walking and bicycle are no longer available parcel delivery methods.';
  end if;
  return new;
end;
$$;

drop trigger if exists reject_retired_parcel_rate_card_method
  on private.parcel_rate_cards;
create trigger reject_retired_parcel_rate_card_method
before insert or update of delivery_method
on private.parcel_rate_cards
for each row execute function private.reject_retired_parcel_delivery_method();

drop trigger if exists reject_retired_parcel_quote_method
  on private.parcel_quotes;
create trigger reject_retired_parcel_quote_method
before insert or update of delivery_method
on private.parcel_quotes
for each row execute function private.reject_retired_parcel_delivery_method();

drop trigger if exists reject_retired_parcel_delivery_method
  on private.parcel_deliveries;
create trigger reject_retired_parcel_delivery_method
before insert or update of delivery_method
on private.parcel_deliveries
for each row execute function private.reject_retired_parcel_delivery_method();

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
    when 'bike' then p_partner_method in ('bike', 'motorbike', 'scooter')
    when 'auto' then p_partner_method in ('auto', 'car', 'goods_vehicle')
    else false
  end;
$$;

create or replace function private.process_parcel_dispatch(
  p_parcel_id uuid default null::uuid,
  p_service_zone_id uuid default null::uuid
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_assignment private.parcel_assignment_attempts%rowtype;
  v_assignment_id uuid;
  v_before jsonb;
  v_distance_meters double precision;
  v_inserted_count integer := 0;
  v_parcel private.parcel_deliveries%rowtype;
  v_partner_id uuid;
  v_reason text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak:all-delivery-dispatch', 0)
  );

  for v_assignment_id in
    select assignment.id
    from private.parcel_assignment_attempts as assignment
    join private.parcel_deliveries as parcel
      on parcel.id = assignment.parcel_id
    left join private.account_memberships as membership
      on membership.account_id = assignment.partner_account_id
     and membership.role = 'dastak_partner'
    left join private.delivery_partner_availability as availability
      on availability.account_id = assignment.partner_account_id
    where assignment.status = 'offered'
      and (p_parcel_id is null or assignment.parcel_id = p_parcel_id)
      and (
        assignment.respond_by <= pg_catalog.now()
        or parcel.status <> 'assigned'
        or membership.account_id is null
        or membership.approved_at is null
        or membership.suspended_until > pg_catalog.now()
        or availability.account_id is null
        or availability.status <> 'online'
        or availability.available_until <= pg_catalog.now()
        or availability.last_seen_at <= pg_catalog.now() - interval '90 seconds'
        or availability.service_zone_id <> parcel.service_zone_id
      )
    order by assignment.respond_by, assignment.id
    for update of assignment skip locked
  loop
    select assignment.*
    into v_assignment
    from private.parcel_assignment_attempts as assignment
    where assignment.id = v_assignment_id;

    select parcel.*
    into v_parcel
    from private.parcel_deliveries as parcel
    where parcel.id = v_assignment.parcel_id
    for update;

    v_before := private.parcel_assignment_json(v_assignment);
    if v_parcel.status <> 'assigned' then
      v_reason := 'parcel_no_longer_assignable';
      update private.parcel_assignment_attempts as assignment
      set status = 'cancelled',
          responded_at = pg_catalog.now(),
          response_reason = v_reason,
          updated_at = pg_catalog.now()
      where assignment.id = v_assignment.id
        and assignment.status = 'offered'
      returning * into v_assignment;
    else
      v_reason := case
        when v_assignment.respond_by <= pg_catalog.now()
          then 'acknowledgement_expired'
        else 'partner_unavailable'
      end;
      update private.parcel_assignment_attempts as assignment
      set status = 'expired',
          responded_at = pg_catalog.now(),
          response_reason = v_reason,
          updated_at = pg_catalog.now()
      where assignment.id = v_assignment.id
        and assignment.status = 'offered'
      returning * into v_assignment;

      if found then
        update private.parcel_deliveries as parcel
        set status = 'paid',
            assigned_at = null,
            state_version = parcel.state_version + 1,
            updated_at = pg_catalog.now()
        where parcel.id = v_parcel.id
          and parcel.status = 'assigned';

        perform private.record_parcel_assignment_miss(
          v_assignment.partner_account_id
        );
      end if;
    end if;

    if found then
      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason,
        before_state, after_state
      ) values (
        null,
        case
          when v_assignment.status = 'expired'
            then 'parcel_assignment_expired'
          else 'parcel_assignment_cancelled'
        end,
        'parcel_assignment',
        v_assignment.id,
        v_reason,
        v_before,
        private.parcel_assignment_json(v_assignment)
      );
    end if;
  end loop;

  for v_parcel in
    select parcel.*
    from private.parcel_deliveries as parcel
    where parcel.status = 'paid'
      and parcel.payment_status = 'paid'
      and (p_parcel_id is null or parcel.id = p_parcel_id)
      and (
        p_service_zone_id is null
        or parcel.service_zone_id = p_service_zone_id
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as active_assignment
        where active_assignment.parcel_id = parcel.id
          and active_assignment.status in ('offered', 'acknowledged')
      )
    order by parcel.payment_captured_at nulls last,
      parcel.created_at, parcel.id
    for update of parcel skip locked
  loop
    v_partner_id := null;
    v_distance_meters := null;

    select
      availability.account_id,
      extensions.st_distance(
        availability.location::extensions.geography,
        v_parcel.pickup::extensions.geography
      )
    into v_partner_id, v_distance_meters
    from private.delivery_partner_availability as availability
    join private.delivery_partner_profiles as profile
      on profile.account_id = availability.account_id
    join private.account_memberships as membership
      on membership.account_id = availability.account_id
     and membership.role = 'dastak_partner'
    where availability.status = 'online'
      and availability.available_until > pg_catalog.now()
      and availability.last_seen_at > pg_catalog.now() - interval '90 seconds'
      and availability.service_zone_id = v_parcel.service_zone_id
      and private.parcel_method_matches_partner(
        v_parcel.delivery_method,
        profile.delivery_method
      )
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
      and not exists (
        select 1
        from private.delivery_assignment_attempts as merchant_assignment
        where merchant_assignment.partner_account_id = availability.account_id
          and merchant_assignment.status in ('offered', 'accepted')
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as active_partner_assignment
        where active_partner_assignment.partner_account_id = availability.account_id
          and active_partner_assignment.status in ('offered', 'acknowledged')
      )
      and not exists (
        select 1
        from private.parcel_assignment_attempts as recent_attempt
        where recent_attempt.parcel_id = v_parcel.id
          and recent_attempt.partner_account_id = availability.account_id
          and recent_attempt.responded_at > pg_catalog.now() - interval '15 minutes'
      )
    order by
      availability.location operator(extensions.<->) v_parcel.pickup,
      availability.account_id
    limit 1
    for update of availability skip locked;

    if v_partner_id is null then
      continue;
    end if;

    insert into private.parcel_assignment_attempts (
      parcel_id, partner_account_id, attempt_number, status,
      distance_meters, offered_at, respond_by
    ) values (
      v_parcel.id,
      v_partner_id,
      (
        select coalesce(pg_catalog.max(attempt.attempt_number), 0) + 1
        from private.parcel_assignment_attempts as attempt
        where attempt.parcel_id = v_parcel.id
      ),
      'offered',
      v_distance_meters,
      pg_catalog.now(),
      pg_catalog.now() + interval '60 seconds'
    )
    returning * into v_assignment;

    update private.parcel_deliveries as parcel
    set status = 'assigned',
        assigned_at = pg_catalog.now(),
        state_version = parcel.state_version + 1,
        updated_at = pg_catalog.now()
    where parcel.id = v_parcel.id;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, after_state
    ) values (
      null,
      'parcel_assignment_offered',
      'parcel_assignment',
      v_assignment.id,
      private.parcel_assignment_json(v_assignment)
    );

    v_inserted_count := v_inserted_count + 1;
  end loop;

  return v_inserted_count;
end;
$$;

create or replace function private.delivery_partner_application_json(
  application_row private.delivery_partner_applications
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'applicationId', (application_row).id,
    'status', (application_row).status,
    'deliveryMethod', (application_row).delivery_method,
    'vehicleVerificationRequired',
      (application_row).delivery_method in (
        'motorbike', 'scooter', 'auto', 'goods_vehicle'
      )
  );
$$;

create or replace function private.enforce_delivery_partner_vehicle_approval()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'approved'
    and new.delivery_method in ('motorbike', 'scooter', 'auto', 'goods_vehicle')
    and (
      new.verification_version < 2
      or new.vehicle_registration_number is null
      or new.vehicle_make_model is null
      or new.vehicle_evidence_object_path is null
    )
  then
    raise exception using
      errcode = '23514',
      message = 'Vehicle verification is required before approval.';
  end if;
  if new.status = 'approved' and new.delivery_method = 'retired' then
    raise exception using
      errcode = '23514',
      message = 'A retired delivery method cannot be approved.';
  end if;
  return new;
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
  if p_delivery_method not in (
    'motorbike', 'scooter', 'auto', 'goods_vehicle'
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Choose one of the available vehicle types.'
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

create or replace function public.get_delivery_partner_snapshot(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_application private.delivery_partner_applications%rowtype;
  v_availability private.delivery_partner_availability%rowtype;
  v_membership_active boolean := false;
  v_requires_upgrade boolean := false;
begin
  if not exists (
    select 1 from public.accounts account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete the account profile first.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select application.* into v_application
  from private.delivery_partner_applications application
  where application.account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'onboardingState', 'not_applied', 'applicationId', null,
      'deliveryMethod', null, 'identityEvidenceObjectPath', null,
      'vehicleRegistrationNumber', null, 'vehicleMakeModel', null,
      'vehicleEvidenceObjectPath', null, 'reviewReason', null,
      'availability', null
    );
    response_status := 200;
    return next;
    return;
  end if;

  v_requires_upgrade := v_application.status = 'pending'
    and v_application.delivery_method in (
      'motorbike', 'scooter', 'auto', 'goods_vehicle'
    )
    and v_application.verification_version < 2;

  select exists (
    select 1 from private.account_memberships membership
    where membership.account_id = p_account_id
      and membership.role = 'dastak_partner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
  ) into v_membership_active;

  if v_application.status = 'approved' then
    select availability.* into v_availability
    from private.delivery_partner_availability availability
    where availability.account_id = p_account_id;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'onboardingState', case
      when v_requires_upgrade then 'rejected'
      else v_application.status
    end,
    'applicationId', v_application.id,
    'deliveryMethod', v_application.delivery_method,
    'identityEvidenceObjectPath', v_application.identity_evidence_object_path,
    'vehicleRegistrationNumber', v_application.vehicle_registration_number,
    'vehicleMakeModel', v_application.vehicle_make_model,
    'vehicleEvidenceObjectPath', v_application.vehicle_evidence_object_path,
    'reviewReason', case
      when v_requires_upgrade
        then 'Add vehicle registration details and registration proof to continue.'
      else v_application.review_reason
    end,
    'availability', case
      when v_application.status = 'approved'
        then private.delivery_partner_availability_json(
          v_availability, v_membership_active
        )
      else null
    end
  );
  response_status := 200;
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
  if pg_catalog.jsonb_typeof(p_profiles) <> 'array'
    or pg_catalog.jsonb_array_length(p_profiles) <> 4 then
    return false;
  end if;
  for v_profile in
    select value from pg_catalog.jsonb_array_elements(p_profiles)
  loop
    if pg_catalog.jsonb_typeof(v_profile) <> 'object' then return false; end if;
    v_type := v_profile ->> 'transportType';
    if v_type not in ('MOTORBIKE', 'SCOOTER', 'AUTO', 'CAR')
      or v_type = any(v_seen) then
      return false;
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_type);
    select expected.weight_grams, expected.volume_mm3,
      expected.package_count, expected.longest_mm
    into v_expected_weight, v_expected_volume,
      v_expected_packages, v_expected_longest
    from (values
      ('MOTORBIKE', 20000::bigint, 60000000::bigint, 4, 600),
      ('SCOOTER', 25000::bigint, 75000000::bigint, 5, 650),
      ('AUTO', 80000::bigint, 250000000::bigint, 12, 1000),
      ('CAR', 150000::bigint, 500000000::bigint, 20, 1200)
    ) expected(transport_type, weight_grams, volume_mm3, package_count, longest_mm)
    where expected.transport_type = v_type;

    if pg_catalog.jsonb_typeof(v_profile -> 'maxWeightGrams') <> 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxVolumeCubicMillimetres') <> 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxPackageCount') <> 'number'
      or pg_catalog.jsonb_typeof(v_profile -> 'maxLongestSideMillimetres') <> 'number'
      or (v_profile ->> 'maxWeightGrams')::bigint <> v_expected_weight
      or (v_profile ->> 'maxVolumeCubicMillimetres')::bigint <> v_expected_volume
      or (v_profile ->> 'maxPackageCount')::integer <> v_expected_packages
      or (v_profile ->> 'maxLongestSideMillimetres')::integer <> v_expected_longest then
      return false;
    end if;
  end loop;
  return pg_catalog.cardinality(v_seen) = 4;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

update dastak_v1.platform_settings setting
set setting_value = (
      select coalesce(
        pg_catalog.jsonb_agg(item.value order by item.ordinality),
        '[]'::jsonb
      )
      from pg_catalog.jsonb_array_elements(setting.setting_value)
        with ordinality as item(value, ordinality)
      where item.value ->> 'transportType' not in ('WALKING', 'BICYCLE')
    ),
    update_reason = 'Walking and bicycle retired; tempo and goods vehicles use the heavy-load profile.',
    updated_at = pg_catalog.now(),
    version = setting.version + 1
where setting.setting_key = 'delivery.transport_load_profiles'
  and pg_catalog.jsonb_typeof(setting.setting_value) = 'array'
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(setting.setting_value) item
    where item ->> 'transportType' in ('WALKING', 'BICYCLE')
  );

update private.parcel_rate_cards rate_card
set active = false
where rate_card.delivery_method in ('walking', 'bicycle')
  and rate_card.active;

update private.parcel_quotes quote
set consumed_at = pg_catalog.now()
where quote.delivery_method in ('walking', 'bicycle')
  and quote.consumed_at is null
  and not exists (
    select 1 from private.parcel_deliveries parcel
    where parcel.quote_id = quote.id
  );

revoke execute on function private.normalize_delivery_partner_method()
  from public, anon, authenticated;
grant execute on function private.normalize_delivery_partner_method()
  to service_role;
revoke execute on function private.reject_retired_parcel_delivery_method()
  from public, anon, authenticated;
grant execute on function private.reject_retired_parcel_delivery_method()
  to service_role;
revoke execute on function private.parcel_method_matches_partner(text, text)
  from public, anon, authenticated;
grant execute on function private.parcel_method_matches_partner(text, text)
  to service_role;
revoke execute on function public.submit_delivery_partner_application_v3(
  uuid, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_delivery_partner_application_v3(
  uuid, text, text, text, text, text, text, text
) to service_role;
