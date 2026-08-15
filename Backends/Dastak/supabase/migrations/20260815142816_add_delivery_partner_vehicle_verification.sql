alter table private.delivery_partner_applications
  add column verification_version smallint not null default 1,
  add column vehicle_registration_number text,
  add column vehicle_make_model text,
  add column vehicle_evidence_object_path text;

alter table private.delivery_partner_applications
  add constraint delivery_partner_vehicle_registration_format check (
    vehicle_registration_number is null
    or (
      pg_catalog.char_length(vehicle_registration_number) between 4 and 20
      and vehicle_registration_number ~ '^[A-Z0-9 -]+$'
    )
  ),
  add constraint delivery_partner_vehicle_make_model_length check (
    vehicle_make_model is null
    or pg_catalog.char_length(vehicle_make_model) between 2 and 80
  ),
  add constraint delivery_partner_vehicle_evidence_length check (
    vehicle_evidence_object_path is null
    or pg_catalog.char_length(vehicle_evidence_object_path) between 1 and 500
  ),
  add constraint delivery_partner_verification_version_valid check (
    verification_version in (1, 2)
  ),
  add constraint delivery_partner_v2_vehicle_contract check (
    verification_version = 1
    or (
      delivery_method in ('walking', 'bicycle')
      and vehicle_registration_number is null
      and vehicle_make_model is null
      and vehicle_evidence_object_path is null
    )
    or (
      delivery_method in ('bike', 'auto', 'car')
      and vehicle_registration_number is not null
      and vehicle_make_model is not null
      and vehicle_evidence_object_path is not null
      and vehicle_evidence_object_path <> identity_evidence_object_path
    )
  );

comment on column private.delivery_partner_applications.verification_version is
  'Version 2 applications enforce vehicle verification for bike, auto, and car. Version 1 preserves already-reviewed legacy records.';

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
      (application_row).delivery_method in ('bike', 'auto', 'car')
  );
$$;

create or replace function public.submit_delivery_partner_application_v2(
  p_account_id uuid,
  p_delivery_method text,
  p_identity_evidence_object_path text,
  p_vehicle_registration_number text,
  p_vehicle_make_model text,
  p_vehicle_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'submit_delivery_partner_application';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.delivery_partner_applications%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_requires_vehicle boolean;
  v_vehicle_registration_number text;
  v_vehicle_make_model text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_dedup.request_digest = p_request_digest then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if not exists (
    select 1 from public.accounts as account where account.id = p_account_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required',
        'message', 'Complete the account profile before applying.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_requires_vehicle := p_delivery_method in ('bike', 'auto', 'car');
  v_vehicle_registration_number := pg_catalog.upper(
    pg_catalog.regexp_replace(pg_catalog.btrim(p_vehicle_registration_number), '[[:space:]]+', ' ', 'g')
  );
  v_vehicle_make_model := pg_catalog.regexp_replace(
    pg_catalog.btrim(p_vehicle_make_model), '[[:space:]]+', ' ', 'g'
  );

  if p_delivery_method is null
    or p_delivery_method not in ('walking', 'bicycle', 'bike', 'auto', 'car')
    or p_identity_evidence_object_path is null
    or p_identity_evidence_object_path <> (
      'dastak-partner/' || p_account_id::text || '/' ||
      pg_catalog.split_part(p_identity_evidence_object_path, '/', 3)
    )
    or pg_catalog.array_length(
      pg_catalog.string_to_array(p_identity_evidence_object_path, '/'), 1
    ) <> 3
    or nullif(pg_catalog.split_part(p_identity_evidence_object_path, '/', 3), '') is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or (
      v_requires_vehicle
      and (
        v_vehicle_registration_number is null
        or pg_catalog.char_length(v_vehicle_registration_number) not between 4 and 20
        or v_vehicle_registration_number !~ '^[A-Z0-9 -]+$'
        or v_vehicle_make_model is null
        or pg_catalog.char_length(v_vehicle_make_model) not between 2 and 80
        or p_vehicle_evidence_object_path is null
        or p_vehicle_evidence_object_path = p_identity_evidence_object_path
        or p_vehicle_evidence_object_path <> (
          'dastak-partner/' || p_account_id::text || '/' ||
          pg_catalog.split_part(p_vehicle_evidence_object_path, '/', 3)
        )
        or pg_catalog.array_length(
          pg_catalog.string_to_array(p_vehicle_evidence_object_path, '/'), 1
        ) <> 3
        or nullif(pg_catalog.split_part(p_vehicle_evidence_object_path, '/', 3), '') is null
      )
    )
    or (
      not v_requires_vehicle
      and (
        p_vehicle_registration_number is not null
        or p_vehicle_make_model is not null
        or p_vehicle_evidence_object_path is not null
      )
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', case
          when v_requires_vehicle
            then 'Vehicle registration details and registration proof are required.'
          else 'The delivery partner application is invalid.'
        end
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if not exists (
    select 1 from storage.objects as object
    where object.bucket_id = 'dastak-evidence'
      and object.name = p_identity_evidence_object_path
      and object.owner_id = p_account_id::text
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'evidence_not_found',
        'message', 'Upload identity evidence before applying.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if v_requires_vehicle and not exists (
    select 1 from storage.objects as object
    where object.bucket_id = 'dastak-evidence'
      and object.name = p_vehicle_evidence_object_path
      and object.owner_id = p_account_id::text
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'vehicle_evidence_not_found',
        'message', 'Upload the vehicle registration certificate before applying.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if exists (
    select 1 from private.account_memberships as membership
    where membership.account_id = p_account_id
      and membership.role = 'dastak_partner'
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'delivery_partner_access_exists',
        'message', 'This account already has delivery partner access.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select application.*
  into v_application
  from private.delivery_partner_applications as application
  where application.account_id = p_account_id
  for update;

  if found and v_application.status = 'pending'
    and not (
      v_application.verification_version = 1
      and v_application.delivery_method in ('bike', 'auto', 'car')
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'delivery_partner_application_pending',
        'message', 'A delivery partner application is already pending.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if found and v_application.status = 'approved' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'delivery_partner_access_exists',
        'message', 'This account already has delivery partner access.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if found then
    v_before_state := pg_catalog.to_jsonb(v_application);
    update private.delivery_partner_applications as application
    set delivery_method = p_delivery_method,
        identity_evidence_object_path = p_identity_evidence_object_path,
        verification_version = 2,
        vehicle_registration_number = case when v_requires_vehicle then v_vehicle_registration_number else null end,
        vehicle_make_model = case when v_requires_vehicle then v_vehicle_make_model else null end,
        vehicle_evidence_object_path = case when v_requires_vehicle then p_vehicle_evidence_object_path else null end,
        status = 'pending',
        submitted_at = pg_catalog.now(),
        reviewed_at = null,
        reviewed_by = null,
        review_reason = null,
        updated_at = pg_catalog.now()
    where application.id = v_application.id
    returning application.* into v_application;
  else
    insert into private.delivery_partner_applications (
      account_id, delivery_method, identity_evidence_object_path,
      verification_version, vehicle_registration_number, vehicle_make_model,
      vehicle_evidence_object_path
    ) values (
      p_account_id, p_delivery_method, p_identity_evidence_object_path,
      2,
      case when v_requires_vehicle then v_vehicle_registration_number else null end,
      case when v_requires_vehicle then v_vehicle_make_model else null end,
      case when v_requires_vehicle then p_vehicle_evidence_object_path else null end
    )
    returning * into v_application;
  end if;

  v_response_body := private.delivery_partner_application_json(v_application);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id, 'delivery_partner_application_submitted',
    'delivery_partner_application', v_application.id,
    v_before_state, pg_catalog.to_jsonb(v_application)
  );

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.submit_delivery_partner_application(
  p_account_id uuid,
  p_delivery_method text,
  p_identity_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_delivery_method in ('bike', 'auto', 'car') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'vehicle_verification_required',
        'message', 'Update Dastak to submit vehicle registration details and proof.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  return query
  select result.response_body, result.response_status
  from public.submit_delivery_partner_application_v2(
    p_account_id, p_delivery_method, p_identity_evidence_object_path,
    null, null, null, p_idempotency_key, p_request_digest
  ) as result;
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
    select 1 from public.accounts as account where account.id = p_account_id
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
  from private.delivery_partner_applications as application
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
    and v_application.delivery_method in ('bike', 'auto', 'car')
    and v_application.verification_version < 2;

  select exists (
    select 1 from private.account_memberships as membership
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
    from private.delivery_partner_availability as availability
    where availability.account_id = p_account_id;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'onboardingState', case when v_requires_upgrade then 'rejected' else v_application.status end,
    'applicationId', v_application.id,
    'deliveryMethod', v_application.delivery_method,
    'identityEvidenceObjectPath', v_application.identity_evidence_object_path,
    'vehicleRegistrationNumber', v_application.vehicle_registration_number,
    'vehicleMakeModel', v_application.vehicle_make_model,
    'vehicleEvidenceObjectPath', v_application.vehicle_evidence_object_path,
    'reviewReason', case
      when v_requires_upgrade then 'Add vehicle registration details and registration proof to continue.'
      else v_application.review_reason
    end,
    'availability', case
      when v_application.status = 'approved'
        then private.delivery_partner_availability_json(v_availability, v_membership_active)
      else null
    end
  );
  response_status := 200;
  return next;
end;
$$;

drop function public.list_delivery_partner_applications(uuid);
create function public.list_delivery_partner_applications(
  p_owner_id uuid
)
returns table (
  application_id uuid,
  account_id uuid,
  display_name text,
  phone_number text,
  delivery_method text,
  identity_evidence_object_path text,
  vehicle_registration_number text,
  vehicle_make_model text,
  vehicle_evidence_object_path text,
  status text,
  submitted_at timestamptz
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_owner_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then return; end if;

  return query
  select
    application.id, application.account_id, account.display_name,
    account.phone_number, application.delivery_method,
    application.identity_evidence_object_path,
    application.vehicle_registration_number,
    application.vehicle_make_model,
    application.vehicle_evidence_object_path,
    application.status, application.submitted_at
  from private.delivery_partner_applications as application
  join public.accounts as account on account.id = application.account_id
  where application.status = 'pending'
    and (
      application.delivery_method in ('walking', 'bicycle')
      or application.verification_version >= 2
    )
  order by application.submitted_at, application.id;
end;
$$;

create or replace function private.enforce_delivery_partner_vehicle_approval()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'approved'
    and new.delivery_method in ('bike', 'auto', 'car')
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
  return new;
end;
$$;

drop trigger if exists enforce_delivery_partner_vehicle_approval
  on private.delivery_partner_applications;
create trigger enforce_delivery_partner_vehicle_approval
before update of status on private.delivery_partner_applications
for each row execute function private.enforce_delivery_partner_vehicle_approval();

revoke execute on function private.enforce_delivery_partner_vehicle_approval()
  from public, anon, authenticated;
grant execute on function private.enforce_delivery_partner_vehicle_approval()
  to service_role;

revoke execute on function public.submit_delivery_partner_application_v2(
  uuid, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_delivery_partner_application_v2(
  uuid, text, text, text, text, text, text, text
) to service_role;

revoke execute on function public.list_delivery_partner_applications(uuid)
  from public, anon, authenticated;
grant execute on function public.list_delivery_partner_applications(uuid)
  to service_role;
