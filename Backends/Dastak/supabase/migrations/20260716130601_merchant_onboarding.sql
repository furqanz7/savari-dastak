create table private.merchant_applications (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null unique references public.accounts(id) on delete cascade,
  business_name text not null check (char_length(trim(business_name)) between 1 and 120),
  business_address text not null check (char_length(trim(business_address)) between 1 and 300),
  evidence_object_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.accounts(id),
  review_reason text check (review_reason is null or char_length(review_reason) between 1 and 500),
  updated_at timestamptz not null default now(),
  check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null)
    or (status in ('approved', 'rejected') and reviewed_at is not null and reviewed_by is not null)
  )
);

alter table private.merchant_applications enable row level security;
revoke all on table private.merchant_applications from public, anon, authenticated;
grant select, insert, update on table private.merchant_applications to service_role;

create policy dastak_merchant_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'merchant'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(split_part(name, '/', 3), '') is not null
);

create policy dastak_merchant_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and array_length(string_to_array(name, '/'), 1) = 3
  and split_part(name, '/', 1) = 'merchant'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(split_part(name, '/', 3), '') is not null
);

create or replace function public.submit_merchant_application(
  p_account_id uuid,
  p_business_name text,
  p_business_address text,
  p_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (
  response_body jsonb,
  response_status integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'submit_merchant_application';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.merchant_applications%rowtype;
  v_response_body jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select *
  into v_existing_dedup
  from private.request_deduplication
  where account_id = p_account_id
    and function_name = v_function_name
    and idempotency_key = p_idempotency_key;

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

  if not exists (select 1 from public.accounts where id = p_account_id) then
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

  if p_evidence_object_path <> (
    'merchant/' || p_account_id::text || '/' ||
    pg_catalog.split_part(p_evidence_object_path, '/', 3)
  )
    or pg_catalog.array_length(pg_catalog.string_to_array(p_evidence_object_path, '/'), 1) <> 3
    or pg_catalog.nullif(pg_catalog.split_part(p_evidence_object_path, '/', 3), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant evidence path is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if not exists (
    select 1
    from storage.objects
    where bucket_id = 'dastak-evidence'
      and name = p_evidence_object_path
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'evidence_not_found',
        'message', 'Upload the merchant evidence before applying.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if exists (
    select 1
    from private.account_memberships
    where account_id = p_account_id
      and role = 'merchant'
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

  select *
  into v_application
  from private.merchant_applications
  where account_id = p_account_id
  for update;

  if found and v_application.status = 'pending' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'merchant_application_pending',
        'message', 'A merchant application is already pending.'
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
    update private.merchant_applications
    set business_name = p_business_name,
        business_address = p_business_address,
        evidence_object_path = p_evidence_object_path,
        status = 'pending',
        submitted_at = pg_catalog.now(),
        reviewed_at = null,
        reviewed_by = null,
        review_reason = null,
        updated_at = pg_catalog.now()
    where id = v_application.id
    returning * into v_application;
  else
    insert into private.merchant_applications (
      account_id,
      business_name,
      business_address,
      evidence_object_path
    ) values (
      p_account_id,
      p_business_name,
      p_business_address,
      p_evidence_object_path
    )
    returning * into v_application;
  end if;

  insert into audit.events (
    actor_id,
    action,
    entity_type,
    entity_id,
    after_state
  ) values (
    p_account_id,
    'merchant_application_submitted',
    'merchant_application',
    v_application.id,
    pg_catalog.to_jsonb(v_application)
  );

  v_response_body := pg_catalog.jsonb_build_object(
    'applicationId', v_application.id,
    'status', v_application.status
  );

  insert into private.request_deduplication (
    account_id,
    function_name,
    idempotency_key,
    request_digest,
    response_body,
    response_status
  ) values (
    p_account_id,
    v_function_name,
    p_idempotency_key,
    p_request_digest,
    v_response_body,
    200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.list_merchant_applications(
  p_owner_id uuid
)
returns table (
  application_id uuid,
  account_id uuid,
  business_name text,
  business_address text,
  evidence_object_path text,
  status text
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1
  from private.account_memberships
  where account_id = p_owner_id
    and role = 'owner'
    and approved_at is not null
    and (suspended_until is null or suspended_until <= pg_catalog.now())
  for share;

  if not found then
    return;
  end if;

  return query
  select
    application.id,
    application.account_id,
    application.business_name,
    application.business_address,
    application.evidence_object_path,
    application.status
  from private.merchant_applications as application
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
returns table (
  response_body jsonb,
  response_status integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'review_merchant_application';
  v_existing_dedup private.request_deduplication%rowtype;
  v_application private.merchant_applications%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || v_function_name, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_application_id::text || ':' || v_function_name, 0)
  );

  select *
  into v_existing_dedup
  from private.request_deduplication
  where account_id = p_owner_id
    and function_name = v_function_name
    and idempotency_key = p_idempotency_key;

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
  from private.account_memberships
  where account_id = p_owner_id
    and role = 'owner'
    and approved_at is not null
    and (suspended_until is null or suspended_until <= pg_catalog.now())
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active owner can review merchant applications.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_decision not in ('approve', 'reject')
    or (p_decision = 'reject' and pg_catalog.nullif(pg_catalog.btrim(p_reason), '') is null)
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

  select *
  into v_application
  from private.merchant_applications
  where id = p_application_id
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

  v_before_state := pg_catalog.to_jsonb(v_application);

  update private.merchant_applications
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      reviewed_at = pg_catalog.now(),
      reviewed_by = p_owner_id,
      review_reason = pg_catalog.nullif(pg_catalog.btrim(p_reason), ''),
      updated_at = pg_catalog.now()
  where id = p_application_id
  returning * into v_application;

  if p_decision = 'approve' then
    insert into private.account_memberships (account_id, role, approved_at)
    values (v_application.account_id, 'merchant', pg_catalog.now())
    on conflict (account_id, role) do update
    set approved_at = pg_catalog.coalesce(
      account_memberships.approved_at,
      excluded.approved_at
    );
  end if;

  insert into audit.events (
    actor_id,
    action,
    entity_type,
    entity_id,
    reason,
    before_state,
    after_state
  ) values (
    p_owner_id,
    'merchant_application_reviewed',
    'merchant_application',
    v_application.id,
    pg_catalog.nullif(pg_catalog.btrim(p_reason), ''),
    v_before_state,
    pg_catalog.to_jsonb(v_application)
  );

  v_response_body := pg_catalog.jsonb_build_object(
    'applicationId', v_application.id,
    'status', v_application.status
  );

  insert into private.request_deduplication (
    account_id,
    function_name,
    idempotency_key,
    request_digest,
    response_body,
    response_status
  ) values (
    p_owner_id,
    v_function_name,
    p_idempotency_key,
    p_request_digest,
    v_response_body,
    200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create or replace function public.resolve_app_access(
  p_account_id uuid,
  p_application text
)
returns table (route text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_required_role private.membership_role;
  v_membership private.account_memberships%rowtype;
begin
  v_required_role := case p_application
    when 'customer' then 'customer'::private.membership_role
    when 'merchant' then 'merchant'::private.membership_role
    when 'admin' then 'owner'::private.membership_role
    else null
  end;

  if v_required_role is null then
    route := 'access_denied';
    return next;
    return;
  end if;

  if not exists (select 1 from public.accounts where id = p_account_id) then
    route := 'needs_profile';
    return next;
    return;
  end if;

  select *
  into v_membership
  from private.account_memberships
  where account_id = p_account_id
    and role = v_required_role;

  if not found then
    if p_application = 'merchant' and exists (
      select 1
      from private.merchant_applications
      where account_id = p_account_id
        and status = 'pending'
    ) then
      route := 'pending_approval';
    else
      route := 'access_denied';
    end if;
    return next;
    return;
  end if;

  if v_membership.suspended_until is not null
    and v_membership.suspended_until > pg_catalog.now()
  then
    route := 'suspended';
    return next;
    return;
  end if;

  if v_required_role in (
    'merchant'::private.membership_role,
    'owner'::private.membership_role
  ) and v_membership.approved_at is null then
    route := 'pending_approval';
    return next;
    return;
  end if;

  route := 'active';
  return next;
end;
$$;

revoke execute on function public.submit_merchant_application(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.submit_merchant_application(uuid, text, text, text, text, text) to service_role;
revoke execute on function public.list_merchant_applications(uuid) from public, anon, authenticated;
grant execute on function public.list_merchant_applications(uuid) to service_role;
revoke execute on function public.review_merchant_application(uuid, uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.review_merchant_application(uuid, uuid, text, text, text, text) to service_role;
revoke execute on function public.resolve_app_access(uuid, text) from public, anon, authenticated;
grant execute on function public.resolve_app_access(uuid, text) to service_role;
