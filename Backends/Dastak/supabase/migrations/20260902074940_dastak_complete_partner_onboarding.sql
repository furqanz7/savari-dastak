-- Complete the approval bridge between the legacy application inbox and the
-- authoritative Dastak V1 merchant domain. Applications remain private and
-- review remains an audited, service-bound operation.

alter table private.merchant_applications
  add column merchant_type dastak_v1.merchant_type,
  add column legal_name text,
  add column location extensions.geometry(Point, 4326),
  add column service_zone_id uuid references public.service_zones(id),
  add column provisioned_organization_id uuid
    references dastak_v1.merchant_organizations(id),
  add column provisioned_branch_id uuid
    references dastak_v1.merchant_branches(id),
  add constraint merchant_applications_launch_type_check check (
    merchant_type is null or merchant_type in ('RETAIL', 'RESTAURANT_CAFE')
  ),
  add constraint merchant_applications_legal_name_check check (
    legal_name is null
    or pg_catalog.char_length(pg_catalog.btrim(legal_name)) between 1 and 160
  ),
  add constraint merchant_applications_location_pair_check check (
    (location is null and service_zone_id is null)
    or (location is not null and service_zone_id is not null)
  ),
  add constraint merchant_applications_provisioning_pair_check check (
    (provisioned_organization_id is null and provisioned_branch_id is null)
    or (provisioned_organization_id is not null and provisioned_branch_id is not null)
  );

create index merchant_applications_service_zone_idx
  on private.merchant_applications (service_zone_id, status);
create unique index merchant_applications_provisioned_org_uidx
  on private.merchant_applications (provisioned_organization_id)
  where provisioned_organization_id is not null;
create unique index merchant_applications_provisioned_branch_uidx
  on private.merchant_applications (provisioned_branch_id)
  where provisioned_branch_id is not null;

-- Legacy applications did not collect the business type or an exact branch
-- location. They cannot be safely provisioned into the V1 merchant domain, so
-- return only incomplete pending records to the applicant for a complete
-- resubmission instead of breaking the Admin queue or guessing their data.
update private.merchant_applications application
set status = 'rejected',
    review_reason = 'Add the business type, legal name, and exact serviceable store location.',
    reviewed_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
where application.status = 'pending'
  and (
    application.merchant_type is null
    or application.legal_name is null
    or application.location is null
    or application.service_zone_id is null
  );

create function public.submit_merchant_application_v2(
  p_account_id uuid,
  p_merchant_type text,
  p_legal_name text,
  p_business_name text,
  p_business_address text,
  p_latitude double precision,
  p_longitude double precision,
  p_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_function_name constant text := 'submit_merchant_application_v2';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.merchant_applications%rowtype;
  v_location extensions.geometry(Point, 4326);
  v_service_zone_id uuid;
  v_service_zone_name text;
  v_before_state jsonb;
  v_response_body jsonb;
  v_merchant_type dastak_v1.merchant_type;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing_dedup
  from private.request_deduplication dedup
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

  if not exists (select 1 from public.accounts account where account.id = p_account_id) then
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

  if p_merchant_type not in ('RETAIL', 'RESTAURANT_CAFE')
    or nullif(pg_catalog.btrim(p_legal_name), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_legal_name)) > 160
    or nullif(pg_catalog.btrim(p_business_name), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_business_name)) > 120
    or nullif(pg_catalog.btrim(p_business_address), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_business_address)) > 300
    or p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Complete the business identity, public store details, and exact store location.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if p_evidence_object_path <> (
    'merchant/' || p_account_id::text || '/' ||
    pg_catalog.split_part(p_evidence_object_path, '/', 3)
  )
    or pg_catalog.array_length(pg_catalog.string_to_array(p_evidence_object_path, '/'), 1) <> 3
    or nullif(pg_catalog.split_part(p_evidence_object_path, '/', 3), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant verification document is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'dastak-evidence'
      and object.name = p_evidence_object_path
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'evidence_not_found',
        'message', 'Upload the merchant verification document before applying.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if exists (
    select 1 from private.account_memberships membership
    where membership.account_id = p_account_id and membership.role = 'merchant'
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_access_exists',
        'message', 'This account already has merchant access.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_merchant_type := p_merchant_type::dastak_v1.merchant_type;
  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude), 4326
  );

  select zone.id, zone.name into v_service_zone_id, v_service_zone_name
  from public.service_zones zone
  where zone.active
    and extensions.st_covers(zone.boundary, v_location)
  order by zone.created_at, zone.id
  limit 1
  for share;

  if v_service_zone_id is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'This store is outside an active Dastak service area.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  select application.* into v_application
  from private.merchant_applications application
  where application.account_id = p_account_id
  for update;

  if found and v_application.status = 'pending' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_application_pending',
        'message', 'A merchant application is already under review.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if found and v_application.status = 'approved' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_access_exists',
        'message', 'This account already has merchant access.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if found then
    v_before_state := pg_catalog.to_jsonb(v_application);
    update private.merchant_applications application
    set merchant_type = v_merchant_type,
        legal_name = pg_catalog.btrim(p_legal_name),
        business_name = pg_catalog.btrim(p_business_name),
        business_address = pg_catalog.btrim(p_business_address),
        location = v_location,
        service_zone_id = v_service_zone_id,
        evidence_object_path = p_evidence_object_path,
        status = 'pending',
        submitted_at = pg_catalog.now(),
        reviewed_at = null,
        reviewed_by = null,
        review_reason = null,
        provisioned_organization_id = null,
        provisioned_branch_id = null,
        updated_at = pg_catalog.now()
    where application.id = v_application.id
    returning application.* into v_application;
  else
    insert into private.merchant_applications (
      account_id, merchant_type, legal_name, business_name, business_address,
      location, service_zone_id, evidence_object_path
    ) values (
      p_account_id, v_merchant_type, pg_catalog.btrim(p_legal_name),
      pg_catalog.btrim(p_business_name), pg_catalog.btrim(p_business_address),
      v_location, v_service_zone_id, p_evidence_object_path
    ) returning * into v_application;
  end if;

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id, 'merchant_application_submitted', 'merchant_application',
    v_application.id, v_before_state, pg_catalog.to_jsonb(v_application)
  );

  v_response_body := pg_catalog.jsonb_build_object(
    'applicationId', v_application.id,
    'status', v_application.status,
    'merchantType', v_application.merchant_type,
    'serviceZoneId', v_application.service_zone_id,
    'serviceZoneName', v_service_zone_name
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

create or replace function public.get_merchant_application_snapshot(
  p_account_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_application private.merchant_applications%rowtype;
  v_service_zone_name text;
begin
  if not exists (select 1 from public.accounts account where account.id = p_account_id) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'profile_required', 'message', 'Complete the account profile first.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select application.* into v_application
  from private.merchant_applications application
  where application.account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'onboardingState', 'not_applied', 'applicationId', null,
      'merchantType', null, 'legalName', null, 'businessName', null,
      'businessAddress', null, 'latitude', null, 'longitude', null,
      'serviceZoneId', null, 'serviceZoneName', null,
      'evidenceObjectPath', null, 'reviewReason', null,
      'organizationId', null, 'branchId', null
    );
    response_status := 200;
    return next;
    return;
  end if;

  select zone.name into v_service_zone_name
  from public.service_zones zone
  where zone.id = v_application.service_zone_id;

  response_body := pg_catalog.jsonb_build_object(
    'onboardingState', v_application.status,
    'applicationId', v_application.id,
    'merchantType', v_application.merchant_type,
    'legalName', v_application.legal_name,
    'businessName', v_application.business_name,
    'businessAddress', v_application.business_address,
    'latitude', case when v_application.location is null then null
      else extensions.st_y(v_application.location) end,
    'longitude', case when v_application.location is null then null
      else extensions.st_x(v_application.location) end,
    'serviceZoneId', v_application.service_zone_id,
    'serviceZoneName', v_service_zone_name,
    'evidenceObjectPath', v_application.evidence_object_path,
    'reviewReason', v_application.review_reason,
    'organizationId', v_application.provisioned_organization_id,
    'branchId', v_application.provisioned_branch_id
  );
  response_status := 200;
  return next;
end;
$$;

drop function public.list_merchant_applications(uuid);
create function public.list_merchant_applications(p_owner_id uuid)
returns table (
  application_id uuid,
  account_id uuid,
  applicant_name text,
  applicant_phone text,
  merchant_type text,
  legal_name text,
  business_name text,
  business_address text,
  latitude double precision,
  longitude double precision,
  service_zone_id uuid,
  service_zone_name text,
  evidence_object_path text,
  status text,
  submitted_at timestamptz
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.is_active_owner(p_owner_id) then return; end if;

  return query
  select application.id, application.account_id, account.display_name,
    account.phone_number, application.merchant_type::text,
    application.legal_name, application.business_name,
    application.business_address,
    extensions.st_y(application.location), extensions.st_x(application.location),
    application.service_zone_id, zone.name, application.evidence_object_path,
    application.status, application.submitted_at
  from private.merchant_applications application
  join public.accounts account on account.id = application.account_id
  left join public.service_zones zone on zone.id = application.service_zone_id
  where application.status = 'pending'
  order by application.submitted_at, application.id;
end;
$$;

create or replace function public.review_merchant_application(
  p_owner_id uuid,
  p_application_id uuid,
  p_decision text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_function_name constant text := 'review_merchant_application';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.merchant_applications%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_organization_id uuid;
  v_branch_id uuid;
  v_merchant_user_id uuid;
  v_service_zone_name text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || v_function_name, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_application_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing_dedup
  from private.request_deduplication dedup
  where dedup.account_id = p_owner_id
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

  if not public.is_active_owner(p_owner_id) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active Admin can review merchant applications.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_decision not in ('approve', 'reject')
    or (p_decision = 'reject' and nullif(pg_catalog.btrim(p_reason), '') is null)
    or (p_reason is not null and pg_catalog.char_length(pg_catalog.btrim(p_reason)) > 500)
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A valid review decision and rejection reason are required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select application.* into v_application
  from private.merchant_applications application
  where application.id = p_application_id
  for update;
  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_application_not_found',
        'message', 'The merchant application was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;
  if v_application.status <> 'pending' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_application_reviewed',
        'message', 'The merchant application was already reviewed.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if p_decision = 'approve' and (
    v_application.merchant_type is null
    or v_application.merchant_type not in ('RETAIL', 'RESTAURANT_CAFE')
    or v_application.legal_name is null
    or v_application.location is null
    or v_application.service_zone_id is null
    or not exists (
      select 1 from public.service_zones zone
      where zone.id = v_application.service_zone_id and zone.active
        and extensions.st_covers(zone.boundary, v_application.location)
    )
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_application_incomplete',
        'message', 'The application needs a valid business type and serviceable store location before approval.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := pg_catalog.to_jsonb(v_application);

  if p_decision = 'approve' then
    insert into dastak_v1.merchant_organizations (
      legal_name, display_name, merchant_type, status, created_by
    ) values (
      v_application.legal_name, v_application.business_name,
      v_application.merchant_type, 'ACTIVE', v_application.account_id
    ) returning id into v_organization_id;

    insert into dastak_v1.merchant_branches (
      organization_id, display_name, service_zone_id, address_snapshot,
      location, capacity_limit, status, created_by
    ) values (
      v_organization_id, v_application.business_name,
      v_application.service_zone_id,
      pg_catalog.jsonb_build_object(
        'line1', v_application.business_address,
        'countryCode', 'IN',
        'latitude', extensions.st_y(v_application.location),
        'longitude', extensions.st_x(v_application.location)
      ),
      v_application.location, 5, 'ACTIVE', v_application.account_id
    ) returning id into v_branch_id;

    insert into dastak_v1.merchant_users (
      organization_id, account_id, status, created_by
    ) values (
      v_organization_id, v_application.account_id, 'ACTIVE', v_application.account_id
    ) returning id into v_merchant_user_id;

    insert into dastak_v1.merchant_permission_grants (
      merchant_user_id, organization_id, bundle_id, branch_id,
      granted_by, grant_reason
    ) values (
      v_merchant_user_id, v_organization_id,
      '10000000-0000-4000-8000-000000000001'::uuid, null,
      p_owner_id, 'Merchant owner access granted after application approval'
    );

    insert into dastak_v1.branch_operational_states (
      branch_id, is_open, accepting_orders, updated_by
    ) values (v_branch_id, false, false, v_application.account_id);

    insert into private.account_memberships (
      account_id, role, approved_at, suspended_until
    ) values (
      v_application.account_id, 'merchant', pg_catalog.now(), null
    ) on conflict (account_id, role) do update
    set approved_at = coalesce(
          private.account_memberships.approved_at, excluded.approved_at
        ),
        suspended_until = null;
  end if;

  update private.merchant_applications application
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = pg_catalog.now(),
      reviewed_by = p_owner_id,
      review_reason = case when p_decision = 'reject'
        then pg_catalog.btrim(p_reason) else null end,
      provisioned_organization_id = case when p_decision = 'approve'
        then v_organization_id else null end,
      provisioned_branch_id = case when p_decision = 'approve'
        then v_branch_id else null end,
      updated_at = pg_catalog.now()
  where application.id = p_application_id
  returning application.* into v_application;

  select zone.name into v_service_zone_name
  from public.service_zones zone
  where zone.id = v_application.service_zone_id;

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason, before_state, after_state
  ) values (
    p_owner_id, 'merchant_application_reviewed', 'merchant_application',
    v_application.id, nullif(pg_catalog.btrim(p_reason), ''),
    v_before_state, pg_catalog.to_jsonb(v_application)
  );

  v_response_body := pg_catalog.jsonb_build_object(
    'applicationId', v_application.id,
    'status', v_application.status,
    'merchantType', v_application.merchant_type,
    'serviceZoneId', v_application.service_zone_id,
    'serviceZoneName', v_service_zone_name,
    'organizationId', v_application.provisioned_organization_id,
    'branchId', v_application.provisioned_branch_id
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_owner_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

comment on function public.review_merchant_application(
  uuid, uuid, text, text, text, text
) is
  'Server-only Admin review command. Runs with its owner privileges so one validated approval can atomically provision the protected V1 merchant organization, branch, owner grant and closed operating state without granting service_role direct write access to merchant runtime tables.';

-- Re-approval and identity recovery must not strand a delivery account on
-- unique profile/availability rows. Keep the reviewed application as the
-- authority and restore the offline runtime state idempotently.
create or replace function public.review_delivery_partner_application(
  p_owner_id uuid,
  p_application_id uuid,
  p_decision text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'review_delivery_partner_application';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.delivery_partner_applications%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || v_function_name, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_application_id::text || ':' || v_function_name, 0)
  );

  select dedup.* into v_existing_dedup
  from private.request_deduplication dedup
  where dedup.account_id = p_owner_id
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

  if not public.is_active_owner(p_owner_id) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active Admin can review delivery partner applications.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;
  if p_decision not in ('approve', 'reject')
    or (p_decision = 'reject' and nullif(pg_catalog.btrim(p_reason), '') is null)
    or (p_reason is not null and pg_catalog.char_length(pg_catalog.btrim(p_reason)) > 500)
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A valid review decision and rejection reason are required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select application.* into v_application
  from private.delivery_partner_applications application
  where application.id = p_application_id
  for update;
  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'delivery_partner_application_not_found',
        'message', 'The delivery partner application was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;
  if v_application.status <> 'pending' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'delivery_partner_application_reviewed',
        'message', 'The delivery partner application was already reviewed.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_before_state := pg_catalog.to_jsonb(v_application);
  update private.delivery_partner_applications application
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = pg_catalog.now(), reviewed_by = p_owner_id,
      review_reason = case when p_decision = 'reject'
        then pg_catalog.btrim(p_reason) else null end,
      updated_at = pg_catalog.now()
  where application.id = p_application_id
  returning application.* into v_application;

  if p_decision = 'approve' then
    insert into private.account_memberships (
      account_id, role, approved_at, suspended_until
    ) values (
      v_application.account_id, 'dastak_partner', pg_catalog.now(), null
    ) on conflict (account_id, role) do update
    set approved_at = coalesce(
          private.account_memberships.approved_at, excluded.approved_at
        ),
        suspended_until = null;

    insert into private.delivery_partner_profiles (
      account_id, approved_application_id, delivery_method
    ) values (
      v_application.account_id, v_application.id, v_application.delivery_method
    ) on conflict (account_id) do update
    set approved_application_id = excluded.approved_application_id,
        delivery_method = excluded.delivery_method,
        updated_at = pg_catalog.now();

    insert into private.delivery_partner_availability (
      account_id, status, location, service_zone_id, last_seen_at,
      available_until, updated_at
    ) values (
      v_application.account_id, 'offline', null, null,
      pg_catalog.now(), null, pg_catalog.now()
    ) on conflict (account_id) do update
    set status = 'offline', location = null, service_zone_id = null,
        last_seen_at = pg_catalog.now(), available_until = null,
        state_version = private.delivery_partner_availability.state_version + 1,
        updated_at = pg_catalog.now();
  end if;

  v_response_body := private.delivery_partner_application_json(v_application);
  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason, before_state, after_state
  ) values (
    p_owner_id, 'delivery_partner_application_reviewed',
    'delivery_partner_application', v_application.id,
    v_application.review_reason, v_before_state, pg_catalog.to_jsonb(v_application)
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_owner_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );
  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.submit_merchant_application_v2(
  uuid, text, text, text, text, double precision, double precision,
  text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_merchant_application_v2(
  uuid, text, text, text, text, double precision, double precision,
  text, text, text
) to service_role;

revoke execute on function public.get_merchant_application_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.get_merchant_application_snapshot(uuid)
  to service_role;
revoke execute on function public.list_merchant_applications(uuid)
  from public, anon, authenticated;
grant execute on function public.list_merchant_applications(uuid)
  to service_role;
revoke execute on function public.review_merchant_application(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.review_merchant_application(
  uuid, uuid, text, text, text, text
) to service_role;
revoke execute on function public.review_delivery_partner_application(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.review_delivery_partner_application(
  uuid, uuid, text, text, text, text
) to service_role;
