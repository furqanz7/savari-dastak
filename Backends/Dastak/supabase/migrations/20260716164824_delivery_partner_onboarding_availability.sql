create table private.delivery_partner_applications (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null unique references public.accounts(id) on delete cascade,
  delivery_method text not null check (
    delivery_method in ('walking', 'bicycle', 'bike', 'auto', 'car')
  ),
  identity_evidence_object_path text not null,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'rejected')
  ),
  submitted_at timestamptz not null default pg_catalog.now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.accounts(id),
  review_reason text check (
    review_reason is null or pg_catalog.char_length(review_reason) between 1 and 500
  ),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (id, account_id),
  check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null and review_reason is null)
    or (
      status = 'approved'
      and reviewed_at is not null
      and reviewed_by is not null
    )
    or (
      status = 'rejected'
      and reviewed_at is not null
      and reviewed_by is not null
      and review_reason is not null
    )
  )
);

create table private.delivery_partner_profiles (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  approved_application_id uuid not null unique,
  delivery_method text not null check (
    delivery_method in ('walking', 'bicycle', 'bike', 'auto', 'car')
  ),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  foreign key (approved_application_id, account_id)
    references private.delivery_partner_applications(id, account_id)
);

create table private.delivery_partner_availability (
  account_id uuid primary key
    references private.delivery_partner_profiles(account_id) on delete cascade,
  status text not null default 'offline' check (status in ('offline', 'online')),
  location extensions.geometry(Point, 4326),
  service_zone_id uuid references public.service_zones(id),
  last_seen_at timestamptz not null default pg_catalog.now(),
  available_until timestamptz,
  state_version bigint not null default 1 check (state_version > 0),
  updated_at timestamptz not null default pg_catalog.now(),
  check (
    (
      status = 'offline'
      and location is null
      and service_zone_id is null
      and available_until is null
    )
    or (
      status = 'online'
      and location is not null
      and service_zone_id is not null
      and available_until is not null
      and available_until > last_seen_at
    )
  )
);

create index delivery_partner_applications_reviewed_by_idx
  on private.delivery_partner_applications(reviewed_by);
create index delivery_partner_applications_pending_idx
  on private.delivery_partner_applications(submitted_at, id)
  where status = 'pending';
create index delivery_partner_availability_zone_idx
  on private.delivery_partner_availability(service_zone_id);
create index delivery_partner_availability_expiry_idx
  on private.delivery_partner_availability(available_until)
  where status = 'online';
create index delivery_partner_availability_location_gix
  on private.delivery_partner_availability using gist (location);

alter table private.delivery_partner_applications enable row level security;
alter table private.delivery_partner_profiles enable row level security;
alter table private.delivery_partner_availability enable row level security;

revoke all on table private.delivery_partner_applications from public, anon, authenticated;
revoke all on table private.delivery_partner_profiles from public, anon, authenticated;
revoke all on table private.delivery_partner_availability from public, anon, authenticated;

grant select, insert, update on table private.delivery_partner_applications to service_role;
grant select, insert, update on table private.delivery_partner_profiles to service_role;
grant select, insert, update on table private.delivery_partner_availability to service_role;

drop policy if exists dastak_evidence_update_own on storage.objects;

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
    'deliveryMethod', (application_row).delivery_method
  );
$$;

create or replace function private.delivery_partner_availability_json(
  availability_row private.delivery_partner_availability,
  membership_active boolean
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_is_online boolean;
begin
  if (availability_row).account_id is null then
    return null;
  end if;

  v_is_online := membership_active
    and (availability_row).status = 'online'
    and (availability_row).available_until > pg_catalog.now();

  return pg_catalog.jsonb_build_object(
    'status', case when v_is_online then 'online' else 'offline' end,
    'location', case
      when v_is_online then pg_catalog.jsonb_build_object(
        'latitude', extensions.st_y((availability_row).location),
        'longitude', extensions.st_x((availability_row).location)
      )
      else null
    end,
    'serviceZoneId', case when v_is_online then (availability_row).service_zone_id else null end,
    'availableUntil', case when v_is_online then (availability_row).available_until else null end,
    'stateVersion', (availability_row).state_version
  );
end;
$$;

revoke execute on function private.delivery_partner_application_json(
  private.delivery_partner_applications
) from public, anon, authenticated;
revoke execute on function private.delivery_partner_availability_json(
  private.delivery_partner_availability, boolean
) from public, anon, authenticated;
grant execute on function private.delivery_partner_application_json(
  private.delivery_partner_applications
) to service_role;
grant execute on function private.delivery_partner_availability_json(
  private.delivery_partner_availability, boolean
) to service_role;

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
declare
  v_function_name constant text := 'submit_delivery_partner_application';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.delivery_partner_applications%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
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

  if p_delivery_method is null
    or p_delivery_method not in ('walking', 'bicycle', 'bike', 'auto', 'car')
    or p_identity_evidence_object_path is null
    or p_identity_evidence_object_path <> (
      'dastak-partner/' || p_account_id::text || '/' ||
      pg_catalog.split_part(p_identity_evidence_object_path, '/', 3)
    )
    or pg_catalog.array_length(
      pg_catalog.string_to_array(p_identity_evidence_object_path, '/'),
      1
    ) <> 3
    or nullif(
      pg_catalog.split_part(p_identity_evidence_object_path, '/', 3),
      ''
    ) is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The delivery partner application is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if not exists (
    select 1
    from storage.objects as object
    where object.bucket_id = 'dastak-evidence'
      and object.name = p_identity_evidence_object_path
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

  if exists (
    select 1
    from private.account_memberships as membership
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

  if found and v_application.status = 'pending' then
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
      account_id,
      delivery_method,
      identity_evidence_object_path
    ) values (
      p_account_id,
      p_delivery_method,
      p_identity_evidence_object_path
    )
    returning * into v_application;
  end if;

  v_response_body := private.delivery_partner_application_json(v_application);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, before_state, after_state
  ) values (
    p_account_id,
    'delivery_partner_application_submitted',
    'delivery_partner_application',
    v_application.id,
    v_before_state,
    pg_catalog.to_jsonb(v_application)
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

  select application.*
  into v_application
  from private.delivery_partner_applications as application
  where application.account_id = p_account_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'onboardingState', 'not_applied',
      'applicationId', null,
      'deliveryMethod', null,
      'identityEvidenceObjectPath', null,
      'reviewReason', null,
      'availability', null
    );
    response_status := 200;
    return next;
    return;
  end if;

  select exists (
    select 1
    from private.account_memberships as membership
    where membership.account_id = p_account_id
      and membership.role = 'dastak_partner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
  ) into v_membership_active;

  if v_application.status = 'approved' then
    select availability.*
    into v_availability
    from private.delivery_partner_availability as availability
    where availability.account_id = p_account_id;
  end if;

  response_body := pg_catalog.jsonb_build_object(
    'onboardingState', v_application.status,
    'applicationId', v_application.id,
    'deliveryMethod', v_application.delivery_method,
    'identityEvidenceObjectPath', v_application.identity_evidence_object_path,
    'reviewReason', v_application.review_reason,
    'availability', case
      when v_application.status = 'approved'
        then private.delivery_partner_availability_json(
          v_availability,
          v_membership_active
        )
      else null
    end
  );
  response_status := 200;
  return next;
end;
$$;

create or replace function public.list_delivery_partner_applications(
  p_owner_id uuid
)
returns table (
  application_id uuid,
  account_id uuid,
  display_name text,
  phone_number text,
  delivery_method text,
  identity_evidence_object_path text,
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

  if not found then
    return;
  end if;

  return query
  select
    application.id,
    application.account_id,
    account.display_name,
    account.phone_number,
    application.delivery_method,
    application.identity_evidence_object_path,
    application.status,
    application.submitted_at
  from private.delivery_partner_applications as application
  join public.accounts as account on account.id = application.account_id
  where application.status = 'pending'
  order by application.submitted_at, application.id;
end;
$$;

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

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
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

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active owner can review delivery partner applications.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_application_id is null
    or p_decision not in ('approve', 'reject')
    or (
      p_decision = 'reject'
      and nullif(pg_catalog.btrim(p_reason), '') is null
    )
    or (
      p_reason is not null
      and pg_catalog.char_length(pg_catalog.btrim(p_reason)) > 500
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
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

  select application.*
  into v_application
  from private.delivery_partner_applications as application
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

  update private.delivery_partner_applications as application
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = pg_catalog.now(),
      reviewed_by = p_owner_id,
      review_reason = case
        when p_decision = 'reject' then pg_catalog.btrim(p_reason)
        else null
      end,
      updated_at = pg_catalog.now()
  where application.id = p_application_id
  returning application.* into v_application;

  if p_decision = 'approve' then
    insert into private.account_memberships (account_id, role, approved_at)
    values (v_application.account_id, 'dastak_partner', pg_catalog.now())
    on conflict (account_id, role) do update
    set approved_at = coalesce(
      account_memberships.approved_at,
      excluded.approved_at
    );

    insert into private.delivery_partner_profiles (
      account_id,
      approved_application_id,
      delivery_method
    ) values (
      v_application.account_id,
      v_application.id,
      v_application.delivery_method
    );

    insert into private.delivery_partner_availability (
      account_id,
      status,
      last_seen_at
    ) values (
      v_application.account_id,
      'offline',
      pg_catalog.now()
    );
  end if;

  v_response_body := private.delivery_partner_application_json(v_application);

  insert into audit.events (
    actor_id, action, entity_type, entity_id, reason, before_state, after_state
  ) values (
    p_owner_id,
    'delivery_partner_application_reviewed',
    'delivery_partner_application',
    v_application.id,
    v_application.review_reason,
    v_before_state,
    pg_catalog.to_jsonb(v_application)
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

create or replace function public.set_delivery_partner_availability(
  p_account_id uuid,
  p_online boolean,
  p_latitude double precision,
  p_longitude double precision,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'set_delivery_partner_availability';
  v_existing_dedup private.request_deduplication%rowtype;
  v_availability private.delivery_partner_availability%rowtype;
  v_point extensions.geometry(Point, 4326);
  v_service_zone_id uuid;
  v_has_availability boolean;
  v_was_online boolean := false;
  v_before_state jsonb;
  v_response_body jsonb;
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

  if p_online is null
    or (
      p_online
      and (
        p_latitude is null
        or p_longitude is null
        or p_latitude < -90
        or p_latitude > 90
        or p_longitude < -180
        or p_longitude > 180
      )
    )
    or (not p_online and (p_latitude is not null or p_longitude is not null))
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The delivery partner availability request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform 1
  from private.account_memberships as membership
  join private.delivery_partner_profiles as profile
    on profile.account_id = membership.account_id
  where membership.account_id = p_account_id
    and membership.role = 'dastak_partner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share of membership, profile;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An approved active delivery partner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_online then
    v_point := extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    );

    select zone.id
    into v_service_zone_id
    from public.service_zones as zone
    where zone.active = true
      and extensions.st_covers(zone.boundary, v_point)
    order by zone.id
    limit 1
    for share;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'outside_service_area',
          'message', 'Dastak is not available at this location.'
        )
      );
      response_status := 422;
      return next;
      return;
    end if;
  end if;

  select availability.*
  into v_availability
  from private.delivery_partner_availability as availability
  where availability.account_id = p_account_id
  for update;

  v_has_availability := found;
  if v_has_availability then
    v_was_online := v_availability.status = 'online'
      and v_availability.available_until > pg_catalog.now();
    v_before_state := private.delivery_partner_availability_json(v_availability, true);
  end if;

  if v_has_availability then
    update private.delivery_partner_availability as availability
    set status = case when p_online then 'online' else 'offline' end,
        location = case when p_online then v_point else null end,
        service_zone_id = case when p_online then v_service_zone_id else null end,
        last_seen_at = pg_catalog.now(),
        available_until = case
          when p_online then pg_catalog.now() + interval '15 minutes'
          else null
        end,
        state_version = availability.state_version + 1,
        updated_at = pg_catalog.now()
    where availability.account_id = p_account_id
    returning availability.* into v_availability;
  else
    insert into private.delivery_partner_availability (
      account_id,
      status,
      location,
      service_zone_id,
      last_seen_at,
      available_until
    ) values (
      p_account_id,
      case when p_online then 'online' else 'offline' end,
      case when p_online then v_point else null end,
      case when p_online then v_service_zone_id else null end,
      pg_catalog.now(),
      case when p_online then pg_catalog.now() + interval '15 minutes' else null end
    )
    returning * into v_availability;
  end if;

  v_response_body := private.delivery_partner_availability_json(v_availability, true);

  if p_online and not v_was_online then
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id,
      'delivery_partner_went_online',
      'delivery_partner_availability',
      p_account_id,
      v_before_state,
      v_response_body
    );
  elsif not p_online and v_was_online then
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id,
      'delivery_partner_went_offline',
      'delivery_partner_availability',
      p_account_id,
      v_before_state,
      v_response_body
    );
  end if;

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

revoke execute on function public.submit_delivery_partner_application(
  uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_delivery_partner_application(
  uuid, text, text, text, text
) to service_role;

revoke execute on function public.get_delivery_partner_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.get_delivery_partner_snapshot(uuid) to service_role;

revoke execute on function public.list_delivery_partner_applications(uuid)
  from public, anon, authenticated;
grant execute on function public.list_delivery_partner_applications(uuid) to service_role;

revoke execute on function public.review_delivery_partner_application(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.review_delivery_partner_application(
  uuid, uuid, text, text, text, text
) to service_role;

revoke execute on function public.set_delivery_partner_availability(
  uuid, boolean, double precision, double precision, text, text
) from public, anon, authenticated;
grant execute on function public.set_delivery_partner_availability(
  uuid, boolean, double precision, double precision, text, text
) to service_role;
