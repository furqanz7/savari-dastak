-- Dastak phone numbers are mandatory profile/contact data, not an Auth factor.
-- Apple or Google remains the only sign-in authority. The profile phone claim
-- remains canonical and unique across active Dastak identities.

alter table private.account_phone_claims
  drop constraint account_phone_claims_verification_source_check,
  drop constraint account_phone_claims_check1;

update private.account_phone_claims
set verified_at = null,
    verification_source = 'PROFILE_ENTRY',
    updated_at = pg_catalog.clock_timestamp(),
    version = version + 1
where verification_source <> 'PROFILE_ENTRY' or verified_at is not null;

alter table private.account_phone_claims
  add constraint account_phone_claims_verification_source_check check (
    verification_source = 'PROFILE_ENTRY'
  ),
  add constraint account_phone_claims_check1 check (
    verification_source = 'PROFILE_ENTRY' and verified_at is null
  );

update public.accounts
set phone_verification_state = 'unverified',
    updated_at = pg_catalog.clock_timestamp()
where phone_verification_state <> 'unverified';

-- Remove any legacy Supabase Phone Auth material. The business phone remains
-- in public.accounts/private.account_phone_claims and OAuth access is unchanged.
delete from auth.identities where provider = 'phone';
update auth.users
set phone = null,
    phone_confirmed_at = null,
    phone_change = '',
    phone_change_token = '',
    phone_change_sent_at = null,
    updated_at = pg_catalog.clock_timestamp()
where phone is not null
   or phone_confirmed_at is not null
   or coalesce(phone_change, '') <> ''
   or coalesce(phone_change_token, '') <> ''
   or phone_change_sent_at is not null;

create function public.bootstrap_dastak_persona(
  p_account_id uuid,
  p_application text,
  p_display_name text,
  p_phone_number text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_function_name text := 'bootstrap_dastak_persona:' || p_application;
  v_existing private.request_deduplication%rowtype;
  v_account public.accounts%rowtype;
  v_claim private.account_phone_claims%rowtype;
  v_persona private.dastak_persona;
  v_was_deleted boolean := false;
  v_response jsonb;
begin
  if p_application not in ('customer', 'merchant', 'delivery', 'admin') then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'invalid_application', 'message', 'A supported Dastak app is required.'));
    response_status := 400; return next; return;
  end if;
  if p_display_name is null
    or pg_catalog.char_length(pg_catalog.btrim(p_display_name)) not between 1 and 80
    or p_phone_number !~ '^\+[1-9][0-9]{7,14}$'
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200
  then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'validation_failed', 'message', 'Valid profile details are required.'));
    response_status := 400; return next; return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-phone:' || p_phone_number, 0));
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0));

  select * into v_existing from private.request_deduplication
  where account_id = p_account_id and function_name = v_function_name
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_digest <> p_request_digest then
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The request key was already used with different details.'));
      response_status := 409;
    else
      response_body := case when v_existing.response_status = 200
        then v_existing.response_body || pg_catalog.jsonb_build_object('phoneRecorded', true)
        else v_existing.response_body end;
      response_status := v_existing.response_status;
    end if;
    return next; return;
  end if;

  select * into v_claim from private.account_phone_claims
  where phone_number = p_phone_number for update;
  if found and v_claim.account_id <> p_account_id then
    if v_claim.claim_state = 'RECOVERY_ELIGIBLE'
      and not private.identity_has_active_access(v_claim.account_id)
      and not exists (
        select 1 from dastak_v1.admin_role_assignments assignment
        where assignment.account_id = v_claim.account_id and assignment.slot = 0
      )
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'identity_recovery_required',
          'message', 'This number belongs to a deleted Dastak identity. Dastak can recover it.'),
        'recoveryAccountId', v_claim.account_id
      );
    else
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'phone_number_in_use',
        'message', 'This phone number already belongs to an active Dastak identity.'));
    end if;
    response_status := 409; return next; return;
  end if;

  select * into v_account from public.accounts where id = p_account_id for update;
  if not found then
    insert into public.accounts (
      id, display_name, phone_number, phone_verification_state
    ) values (
      p_account_id, pg_catalog.btrim(p_display_name), p_phone_number, 'unverified'
    ) returning * into v_account;
  elsif v_account.account_state <> 'ACTIVE' then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'identity_recovery_unavailable',
      'message', 'This legacy identity requires Dastak Support to recover.'));
    response_status := 409; return next; return;
  else
    if v_account.phone_number <> p_phone_number then
      delete from private.account_phone_claims
      where account_id = p_account_id and phone_number <> p_phone_number;
    end if;
    update public.accounts
    set display_name = pg_catalog.btrim(p_display_name),
        phone_number = p_phone_number,
        phone_verification_state = 'unverified',
        updated_at = pg_catalog.clock_timestamp()
    where id = p_account_id returning * into v_account;
  end if;

  insert into private.account_phone_claims (
    phone_number, account_id, claim_state, verified_at, verification_source
  ) values (
    p_phone_number, p_account_id, 'ACTIVE', null, 'PROFILE_ENTRY'
  )
  on conflict (phone_number) do update
  set claim_state = 'ACTIVE', verified_at = null,
      verification_source = 'PROFILE_ENTRY', recovery_eligible_at = null,
      updated_at = pg_catalog.clock_timestamp(),
      version = private.account_phone_claims.version + 1;

  v_persona := case p_application
    when 'customer' then 'CUSTOMER'::private.dastak_persona
    when 'merchant' then 'MERCHANT'::private.dastak_persona
    when 'delivery' then 'DELIVERY'::private.dastak_persona
    else null
  end;

  if v_persona is not null then
    select persona.state = 'DELETED' into v_was_deleted
    from private.account_personas persona
    where persona.account_id = p_account_id and persona.persona = v_persona;
  end if;

  if p_application = 'customer' then
    insert into private.account_memberships (account_id, role, suspended_until)
    values (p_account_id, 'customer', null)
    on conflict (account_id, role) do update set suspended_until = null;
  elsif p_application = 'merchant' and coalesce(v_was_deleted, false)
    and exists (
      select 1 from private.merchant_applications application
      where application.account_id = p_account_id and application.status = 'approved'
    )
  then
    update private.account_memberships set suspended_until = null
    where account_id = p_account_id and role = 'merchant';
    update dastak_v1.merchant_users merchant_user set status = 'ACTIVE',
      updated_at = pg_catalog.clock_timestamp(), version = merchant_user.version + 1
    where merchant_user.id in (
      select suspension.merchant_user_id
      from private.persona_suspended_merchant_users suspension
      where suspension.account_id = p_account_id
    ) and merchant_user.status = 'SUSPENDED';
    delete from private.persona_suspended_merchant_users
    where account_id = p_account_id;
  elsif p_application = 'delivery' and coalesce(v_was_deleted, false)
    and exists (
      select 1 from private.delivery_partner_applications application
      where application.account_id = p_account_id and application.status = 'approved'
    )
  then
    update private.account_memberships set suspended_until = null
    where account_id = p_account_id and role = 'dastak_partner';
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'accountId', p_account_id,
    'application', p_application,
    'phoneRecorded', true,
    'personaRecovered', coalesce(v_was_deleted, false)
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response, 200
  );
  response_body := v_response; response_status := 200; return next;
end;
$$;

-- Backward-compatible database signature: the legacy proof argument is ignored.
create or replace function public.bootstrap_dastak_persona(
  p_account_id uuid,
  p_application text,
  p_display_name text,
  p_phone_number text,
  p_verified_phone_number text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select * from public.bootstrap_dastak_persona(
    p_account_id, p_application, p_display_name, p_phone_number,
    p_idempotency_key, p_request_digest
  );
$$;

create function public.update_dastak_account_profile(
  p_account_id uuid,
  p_display_name text,
  p_phone_number text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account public.accounts%rowtype;
  v_claim private.account_phone_claims%rowtype;
begin
  if pg_catalog.char_length(pg_catalog.btrim(p_display_name)) not between 1 and 80
    or p_phone_number !~ '^\+[1-9][0-9]{7,14}$'
  then
    raise exception using errcode = '22023', message = 'Valid profile details are required.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-phone:' || p_phone_number, 0));
  select * into v_claim from private.account_phone_claims
  where phone_number = p_phone_number for update;
  if found and v_claim.account_id <> p_account_id then
    raise exception using errcode = '23505',
      message = 'This phone number belongs to another Dastak identity.';
  end if;
  select * into strict v_account from public.accounts
  where id = p_account_id and account_state = 'ACTIVE' for update;
  if v_account.phone_number <> p_phone_number then
    delete from private.account_phone_claims where account_id = p_account_id;
  end if;
  insert into private.account_phone_claims (
    phone_number, account_id, claim_state, verified_at, verification_source
  ) values (
    p_phone_number, p_account_id, 'ACTIVE', null, 'PROFILE_ENTRY'
  ) on conflict (phone_number) do update
  set claim_state = 'ACTIVE', verified_at = null,
      verification_source = 'PROFILE_ENTRY', recovery_eligible_at = null,
      updated_at = pg_catalog.clock_timestamp(),
      version = private.account_phone_claims.version + 1;
  update public.accounts set display_name = pg_catalog.btrim(p_display_name),
    phone_number = p_phone_number, phone_verification_state = 'unverified',
    updated_at = pg_catalog.clock_timestamp()
  where id = p_account_id;
  return pg_catalog.jsonb_build_object(
    'displayName', pg_catalog.btrim(p_display_name), 'phoneNumber', p_phone_number);
end;
$$;

-- Retain the old function signature for database compatibility, but it no
-- longer verifies or consumes any Auth phone proof.
create or replace function public.update_dastak_account_profile(
  p_account_id uuid,
  p_display_name text,
  p_phone_number text,
  p_verified_phone_number text
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select public.update_dastak_account_profile(
    p_account_id, p_display_name, p_phone_number
  );
$$;

create function public.prepare_dastak_profile_phone_recovery(
  p_temporary_auth_user_id uuid,
  p_account_id uuid,
  p_profile_phone_number text,
  p_requested_email_digest text,
  p_application text,
  p_display_name text,
  p_request_digest text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  if p_temporary_auth_user_id is null or p_account_id is null
    or p_temporary_auth_user_id = p_account_id
    or p_profile_phone_number !~ '^\+[1-9][0-9]{7,14}$'
    or p_requested_email_digest !~ '^[0-9a-f]{64}$'
    or p_application not in ('customer', 'merchant', 'delivery')
    or pg_catalog.char_length(pg_catalog.btrim(p_display_name)) not between 1 and 80
    or pg_catalog.char_length(pg_catalog.btrim(p_request_digest)) not between 1 and 200
  then
    raise exception using errcode = '22023', message = 'Invalid identity recovery request.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-phone:' || p_profile_phone_number, 0));
  if not exists (
    select 1 from private.account_phone_claims claim
    where claim.account_id = p_account_id
      and claim.phone_number = p_profile_phone_number
      and claim.claim_state = 'RECOVERY_ELIGIBLE'
  ) or private.identity_has_active_access(p_account_id)
    or exists (
      select 1 from dastak_v1.admin_role_assignments assignment
      where assignment.account_id = p_account_id
    )
  then
    raise exception using errcode = '42501', message = 'This identity is not eligible for recovery.';
  end if;
  insert into private.identity_recovery_events (
    account_id, temporary_auth_user_id, phone_number, requested_email_digest,
    application, display_name, request_digest
  ) values (
    p_account_id, p_temporary_auth_user_id, p_profile_phone_number,
    p_requested_email_digest, p_application, pg_catalog.btrim(p_display_name),
    pg_catalog.btrim(p_request_digest)
  )
  on conflict (temporary_auth_user_id) do update
  set requested_email_digest = excluded.requested_email_digest,
      phone_number = excluded.phone_number,
      application = excluded.application,
      display_name = excluded.display_name,
      request_digest = excluded.request_digest
  where private.identity_recovery_events.state = 'PREPARED'
  returning id into v_event_id;
  return v_event_id;
end;
$$;

create or replace function public.complete_dastak_identity_recovery(
  p_event_id uuid,
  p_succeeded boolean,
  p_failure_code text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_event private.identity_recovery_events%rowtype;
  v_temporary auth.users%rowtype;
  v_bootstrap_status integer;
begin
  select * into v_event from private.identity_recovery_events
  where id = p_event_id and state = 'PREPARED' for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Identity recovery event is unavailable.';
  end if;

  if not p_succeeded then
    update private.identity_recovery_events
    set state = 'FAILED', completed_at = pg_catalog.clock_timestamp(),
        failure_code = coalesce(nullif(pg_catalog.btrim(p_failure_code), ''), 'RECOVERY_FAILED')
    where id = p_event_id;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-phone:' || v_event.phone_number, 0));
  select * into v_temporary from auth.users
  where id = v_event.temporary_auth_user_id for update;
  if not found
    or v_temporary.email is null or v_temporary.email_confirmed_at is null
    or pg_catalog.encode(
      extensions.digest(pg_catalog.lower(pg_catalog.btrim(v_temporary.email)), 'sha256'), 'hex'
    ) <> v_event.requested_email_digest
    or not exists (
      select 1 from auth.identities identity
      where identity.user_id = v_event.temporary_auth_user_id
        and identity.provider in ('apple', 'google')
    )
  then
    raise exception using errcode = '42501', message = 'OAuth recovery identity is unavailable.';
  end if;
  if private.identity_has_active_access(v_event.account_id)
    or exists (
      select 1 from dastak_v1.admin_role_assignments assignment
      where assignment.account_id = v_event.account_id
    )
    or not exists (
      select 1 from private.account_phone_claims claim
      where claim.account_id = v_event.account_id
        and claim.phone_number = v_event.phone_number
        and claim.claim_state = 'RECOVERY_ELIGIBLE'
    )
  then
    raise exception using errcode = '42501', message = 'This identity is no longer eligible for recovery.';
  end if;

  delete from private.customer_auth_identities registered
  where registered.account_id in (
    v_event.account_id, v_event.temporary_auth_user_id
  );
  delete from auth.identities identity where identity.user_id = v_event.account_id;
  update auth.identities identity
  set user_id = v_event.account_id, updated_at = pg_catalog.clock_timestamp()
  where identity.user_id = v_event.temporary_auth_user_id
    and identity.provider in ('apple', 'google');
  delete from auth.identities identity
  where identity.user_id = v_event.temporary_auth_user_id;
  delete from auth.users auth_user where auth_user.id = v_event.temporary_auth_user_id;
  update auth.users auth_user
  set email = pg_catalog.lower(pg_catalog.btrim(v_temporary.email)),
      email_confirmed_at = v_temporary.email_confirmed_at,
      phone = null,
      phone_confirmed_at = null,
      phone_change = '',
      phone_change_token = '',
      phone_change_sent_at = null,
      raw_app_meta_data = v_temporary.raw_app_meta_data,
      raw_user_meta_data = v_temporary.raw_user_meta_data,
      updated_at = pg_catalog.clock_timestamp()
  where auth_user.id = v_event.account_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Canonical Dastak identity is unavailable.';
  end if;
  insert into private.customer_auth_identities (
    account_id, provider, provider_subject_digest, link_kind, linked_at
  )
  select v_event.account_id,
         identity.provider,
         extensions.digest(identity.provider_id, 'sha256'),
         'ORIGIN'::private.customer_identity_link_kind,
         pg_catalog.clock_timestamp()
  from auth.identities identity
  where identity.user_id = v_event.account_id
    and identity.provider in ('apple', 'google');
  update private.account_phone_claims
  set claim_state = 'ACTIVE', recovery_eligible_at = null,
      verified_at = null,
      verification_source = 'PROFILE_ENTRY',
      updated_at = pg_catalog.clock_timestamp(), version = version + 1
  where account_id = v_event.account_id and phone_number = v_event.phone_number;
  select bootstrap.response_status into v_bootstrap_status
  from public.bootstrap_dastak_persona(
    v_event.account_id,
    v_event.application,
    v_event.display_name,
    v_event.phone_number,
    'identity-recovery:' || v_event.id::text,
    v_event.request_digest
  ) bootstrap;
  if v_bootstrap_status <> 200 then
    raise exception using errcode = 'P0001', message = 'Recovered persona could not be activated.';
  end if;
  update private.identity_recovery_events
  set state = 'COMPLETED', completed_at = pg_catalog.clock_timestamp(), failure_code = null
  where id = p_event_id;
end;
$$;

revoke execute on function public.bootstrap_dastak_persona(uuid, text, text, text, text, text),
  public.bootstrap_dastak_persona(uuid, text, text, text, text, text, text),
  public.update_dastak_account_profile(uuid, text, text),
  public.update_dastak_account_profile(uuid, text, text, text),
  public.prepare_dastak_identity_recovery(uuid, uuid, text, text, text, text, text),
  public.prepare_dastak_profile_phone_recovery(uuid, uuid, text, text, text, text, text),
  public.complete_dastak_identity_recovery(uuid, boolean, text)
from public, anon, authenticated;

revoke execute on function public.bootstrap_dastak_persona(uuid, text, text, text, text, text, text),
  public.update_dastak_account_profile(uuid, text, text, text),
  public.prepare_dastak_identity_recovery(uuid, uuid, text, text, text, text, text)
from service_role;

grant execute on function public.bootstrap_dastak_persona(uuid, text, text, text, text, text),
  public.update_dastak_account_profile(uuid, text, text),
  public.prepare_dastak_profile_phone_recovery(uuid, uuid, text, text, text, text, text),
  public.complete_dastak_identity_recovery(uuid, boolean, text)
to service_role;

comment on table private.account_phone_claims is
  'One canonical Dastak identity per mandatory E.164 profile phone. The phone is contact data, not an authentication or OTP factor.';
comment on function public.bootstrap_dastak_persona(uuid, text, text, text, text, text) is
  'Records mandatory profile contact data and bootstraps only the requested Dastak application without Phone Auth.';
