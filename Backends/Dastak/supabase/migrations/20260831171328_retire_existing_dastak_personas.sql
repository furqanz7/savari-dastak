-- Owner-authorized one-time reset of Dastak personas. Canonical Auth/account
-- rows and business history remain intact so a deleted identity can recover.

create function private.retire_existing_dastak_personas()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_superadmin_id uuid;
  v_superadmin_count bigint;
  v_account_count bigint;
  v_active_personas bigint;
  v_executive_assignments bigint;
  v_pending_applications bigint;
  v_record record;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-owner-authorized-persona-reset', 0)
  );

  select pg_catalog.count(*) into v_account_count
  from public.accounts account
  where account.account_state = 'ACTIVE';

  select pg_catalog.count(*)
  into v_superadmin_count
  from dastak_v1.admin_role_assignments assignment
  where assignment.slot = 0
    and assignment.role = 'SUPERADMIN'
    and assignment.account_id is not null;

  -- Fresh development databases have no founder identity yet. Production or
  -- any populated environment must never guess which identity is Superadmin.
  if v_account_count = 0 and v_superadmin_count = 0 then
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'reason', 'EMPTY_ENVIRONMENT'
    );
  end if;
  if v_superadmin_count <> 1 or v_superadmin_id is null then
    if v_superadmin_count = 1 then
      select assignment.account_id into v_superadmin_id
      from dastak_v1.admin_role_assignments assignment
      where assignment.slot = 0
        and assignment.role = 'SUPERADMIN'
        and assignment.account_id is not null;
    end if;
  end if;
  if v_superadmin_count <> 1 or v_superadmin_id is null then
    raise exception using
      errcode = '55000',
      message = 'Persona retirement requires exactly one immutable Superadmin.';
  end if;
  if not exists (
    select 1
    from dastak_v1.admin_role_assignments assignment
    join public.accounts account on account.id = assignment.account_id
    join auth.users auth_user on auth_user.id = assignment.account_id
    join private.account_memberships membership
      on membership.account_id = assignment.account_id
      and membership.role = 'owner'
      and membership.approved_at is not null
      and (membership.suspended_until is null
        or membership.suspended_until <= v_now)
    where assignment.slot = 0
      and assignment.account_id = v_superadmin_id
      and account.account_state = 'ACTIVE'
      and auth_user.email is not null
      and auth_user.email_confirmed_at is not null
      and pg_catalog.lower(auth_user.email) = assignment.email_normalized
  ) then
    raise exception using
      errcode = '55000',
      message = 'The immutable Superadmin identity is not healthy.';
  end if;

  -- No identity is retired while it owns in-flight customer, merchant, or
  -- delivery work in either the launch domain or preserved legacy domain.
  if exists (
    select 1 from dastak_v1.orders customer_order
    where customer_order.status not in (
      'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT',
      'DASTAK_FULFILMENT_FAILURE'
    )
  ) or exists (
    select 1 from dastak_v1.fulfilments fulfilment
    where fulfilment.status not in ('COMPLETED', 'RELEASED')
  ) or exists (
    select 1 from dastak_v1.delivery_missions mission
    where mission.status not in ('DELIVERED', 'CANCELLED')
  ) or exists (
    select 1 from private.merchant_orders legacy_order
    where legacy_order.status not in ('delivered', 'cancelled')
  ) or exists (
    select 1 from private.parcel_deliveries parcel
    where parcel.status not in ('delivered', 'cancelled')
  ) then
    raise exception using
      errcode = '55000',
      message = 'Complete or cancel all active Dastak work before retiring identities.';
  end if;

  -- Lock canonical identities in a deterministic order before changing their
  -- persona and sign-in state.
  perform account.id
  from public.accounts account
  order by account.id
  for update;

  select pg_catalog.count(*) into v_active_personas
  from private.account_personas persona
  where persona.state = 'ACTIVE';
  select pg_catalog.count(*) into v_executive_assignments
  from dastak_v1.admin_role_assignments assignment
  where assignment.slot in (1, 2)
    and assignment.email_normalized is not null;
  select
    (select pg_catalog.count(*) from private.merchant_applications application
      where application.status = 'pending')
    +
    (select pg_catalog.count(*) from private.delivery_partner_applications application
      where application.status = 'pending')
  into v_pending_applications;

  -- Clear the two replaceable Executive Admin slots and their capabilities.
  for v_record in
    select assignment.slot, assignment.account_id
    from dastak_v1.admin_role_assignments assignment
    where assignment.slot in (1, 2)
      and assignment.email_normalized is not null
    order by assignment.slot
    for update
  loop
    if v_record.account_id is not null then
      perform dastak_v1_api.remove_admin_capabilities(
        v_record.account_id, v_superadmin_id
      );
    end if;
    update dastak_v1.admin_role_assignments assignment
    set email_normalized = null,
        account_id = null,
        assigned_by = null,
        assigned_at = null,
        updated_at = v_now,
        version = assignment.version + 1
    where assignment.slot = v_record.slot;
  end loop;

  -- Revoke any stale platform-admin grant and owner membership that is not
  -- anchored to the immutable assignment.
  update dastak_v1.platform_permission_grants grant_row
  set revoked_by = v_superadmin_id,
      revoke_reason = 'Owner-authorized existing account retirement',
      revoked_at = v_now,
      version = grant_row.version + 1
  where grant_row.account_id <> v_superadmin_id
    and grant_row.revoked_at is null
    and grant_row.bundle_id in (
      select bundle.id
      from dastak_v1.permission_bundles bundle
      where bundle.bundle_key in ('platform_super_admin', 'executive_admin')
    );
  delete from private.account_memberships membership
  where membership.account_id <> v_superadmin_id
    and membership.role = 'owner';

  -- Pending applications are retained as reviewed history and may be
  -- resubmitted later through the mandatory onboarding flow.
  update private.merchant_applications application
  set status = 'rejected',
      reviewed_at = v_now,
      reviewed_by = v_superadmin_id,
      review_reason = 'Retired during owner-authorized account reset',
      updated_at = v_now
  where application.status = 'pending';
  update private.delivery_partner_applications application
  set status = 'rejected',
      reviewed_at = v_now,
      reviewed_by = v_superadmin_id,
      review_reason = 'Retired during owner-authorized account reset',
      updated_at = v_now
  where application.status = 'pending';

  update private.account_personas persona
  set state = 'DELETED',
      deleted_at = v_now,
      deletion_reason = 'Owner-authorized existing account retirement',
      updated_at = v_now,
      version = persona.version + 1
  where persona.state = 'ACTIVE';
  update private.account_memberships membership
  set suspended_until = 'infinity'::timestamptz
  where membership.role in ('customer', 'merchant', 'dastak_partner')
    and (membership.suspended_until is null
      or membership.suspended_until <> 'infinity'::timestamptz);

  insert into private.persona_suspended_merchant_users (
    account_id, merchant_user_id, suspended_at
  )
  select merchant_user.account_id, merchant_user.id, v_now
  from dastak_v1.merchant_users merchant_user
  where merchant_user.status = 'ACTIVE'
  on conflict (account_id, merchant_user_id) do nothing;
  update dastak_v1.merchant_users merchant_user
  set status = 'SUSPENDED',
      updated_at = v_now,
      version = merchant_user.version + 1
  where merchant_user.status = 'ACTIVE';
  update private.delivery_partner_availability availability
  set status = 'offline',
      location = null,
      service_zone_id = null,
      available_until = null,
      last_seen_at = v_now,
      updated_at = v_now,
      state_version = availability.state_version + 1
  where availability.status <> 'offline'
    or availability.location is not null
    or availability.service_zone_id is not null
    or availability.available_until is not null;

  -- End/revoke every non-Superadmin device and Auth session. Existing access
  -- tokens still fail persona/Admin resolution immediately.
  insert into private.revoked_account_sessions (
    session_id, account_id, revoked_by, reason, revoked_at
  )
  select session.session_id, session.account_id, v_superadmin_id,
         'Owner-authorized account retirement', v_now
  from private.account_sessions session
  where session.account_id <> v_superadmin_id
    and session.ended_at is null
  on conflict (session_id) do nothing;
  update private.account_sessions session
  set ended_at = coalesce(session.ended_at, v_now)
  where session.account_id <> v_superadmin_id
    and session.ended_at is null;
  update public.dastak_device_tokens token
  set disabled_at = coalesce(token.disabled_at, v_now),
      disabled_reason = coalesce(
        token.disabled_reason, 'Owner-authorized account retirement'
      ),
      version = case when token.disabled_at is null
        then token.version + 1 else token.version end
  where token.account_id <> v_superadmin_id;
  update auth.refresh_tokens refresh_token
  set revoked = true,
      updated_at = v_now
  where refresh_token.user_id in (
    select account.id::text
    from public.accounts account
    where account.id <> v_superadmin_id
  );
  delete from auth.sessions auth_session
  where auth_session.user_id in (
    select account.id
    from public.accounts account
    where account.id <> v_superadmin_id
  );

  update private.customer_identity_link_intents intent
  set status = 'CANCELLED', cancelled_at = v_now
  where intent.account_id <> v_superadmin_id
    and intent.status = 'PENDING';
  update private.account_phone_claims claim
  set claim_state = 'RECOVERY_ELIGIBLE',
      recovery_eligible_at = coalesce(claim.recovery_eligible_at, v_now),
      updated_at = v_now,
      version = claim.version + 1
  where claim.account_id <> v_superadmin_id
    and claim.claim_state <> 'RECOVERY_ELIGIBLE';
  delete from auth.identities identity
  where identity.user_id <> v_superadmin_id
    and identity.provider = 'phone';
  update auth.users auth_user
  set phone = null,
      phone_confirmed_at = null,
      phone_change = '',
      phone_change_token = '',
      phone_change_sent_at = null,
      updated_at = v_now
  where auth_user.id <> v_superadmin_id
    and auth_user.id in (select account.id from public.accounts account);

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    v_superadmin_id,
    'EXISTING_DASTAK_IDENTITIES_RETIRED',
    'identity_retirement',
    v_superadmin_id,
    pg_catalog.jsonb_build_object(
      'activePersonasRetired', v_active_personas,
      'executiveAssignmentsCleared', v_executive_assignments,
      'pendingApplicationsRetired', v_pending_applications,
      'canonicalHistoryPreserved', true,
      'superadminPreserved', true
    )
  );

  if exists (
    select 1 from private.account_personas persona
    where persona.state = 'ACTIVE'
  ) or exists (
    select 1 from dastak_v1.admin_role_assignments assignment
    where assignment.slot in (1, 2)
      and assignment.email_normalized is not null
  ) or exists (
    select 1 from private.account_memberships membership
    where membership.role in ('customer', 'merchant', 'dastak_partner')
      and (membership.suspended_until is null
        or membership.suspended_until <= v_now)
  ) then
    raise exception using
      errcode = '55000',
      message = 'Existing Dastak identity retirement did not reach the required state.';
  end if;

  return pg_catalog.jsonb_build_object(
    'applied', true,
    'activePersonasRetired', v_active_personas,
    'executiveAssignmentsCleared', v_executive_assignments,
    'pendingApplicationsRetired', v_pending_applications,
    'superadminPreserved', true,
    'canonicalHistoryPreserved', true
  );
end;
$$;

revoke execute on function private.retire_existing_dastak_personas()
from public, anon, authenticated, service_role, supabase_auth_admin;

comment on function private.retire_existing_dastak_personas() is
  'Owner-authorized, DBA-only persona retirement preserving canonical identity and business history.';

do $$
begin
  perform private.retire_existing_dastak_personas();
end;
$$;
