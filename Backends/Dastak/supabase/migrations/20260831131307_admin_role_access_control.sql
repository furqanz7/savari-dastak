-- Dastak Admin access is an explicit, email-bound platform assignment.
-- One immutable Superadmin and at most two replaceable Executive Admins exist.

create type dastak_v1.admin_role as enum (
  'SUPERADMIN',
  'EXECUTIVE_ADMIN'
);

insert into dastak_v1.permission_bundles (
  id, bundle_key, display_name, scope, description
) values (
  '10000000-0000-4000-8000-00000000000d',
  'executive_admin',
  'Executive admin',
  'PLATFORM',
  'All Dastak Admin operating powers except assigning platform roles.'
);

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
select '10000000-0000-4000-8000-00000000000d'::uuid,
       definition.permission_key
from dastak_v1.permission_definitions definition
where definition.permission_key like 'platform.%'
  and definition.permission_key <> 'platform.permissions.manage';

create table dastak_v1.admin_role_assignments (
  slot smallint primary key check (slot between 0 and 2),
  role dastak_v1.admin_role not null,
  email_normalized text,
  account_id uuid references public.accounts(id),
  assigned_by uuid references public.accounts(id),
  assigned_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (slot = 0 and role = 'SUPERADMIN')
    or (slot in (1, 2) and role = 'EXECUTIVE_ADMIN')
  ),
  check (
    email_normalized is null
    or (
      email_normalized = pg_catalog.lower(pg_catalog.btrim(email_normalized))
      and pg_catalog.char_length(email_normalized) between 3 and 320
      and email_normalized ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    )
  ),
  check (account_id is null or email_normalized is not null),
  check (
    (email_normalized is null and assigned_by is null and assigned_at is null)
    or (email_normalized is not null and assigned_by is not null and assigned_at is not null)
  )
);

create unique index admin_role_assignments_email_uidx
  on dastak_v1.admin_role_assignments (email_normalized)
  where email_normalized is not null;
create unique index admin_role_assignments_account_uidx
  on dastak_v1.admin_role_assignments (account_id)
  where account_id is not null;
create index admin_role_assignments_account_idx
  on dastak_v1.admin_role_assignments (account_id);
create index admin_role_assignments_assigned_by_idx
  on dastak_v1.admin_role_assignments (assigned_by);

alter table dastak_v1.admin_role_assignments enable row level security;
revoke all on table dastak_v1.admin_role_assignments
  from public, anon, authenticated, service_role;

create function dastak_v1.guard_admin_role_assignment()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'Admin assignment slots cannot be deleted.';
  end if;

  if tg_op = 'UPDATE' then
    if old.slot = 0 and new is distinct from old then
      raise exception using errcode = '42501', message = 'The Superadmin assignment is immutable.';
    end if;
    if new.slot is distinct from old.slot or new.role is distinct from old.role then
      raise exception using errcode = '42501', message = 'Admin assignment slot identity is immutable.';
    end if;
    if new.version <> old.version + 1 then
      raise exception using errcode = '22023', message = 'Admin assignment version must increment exactly once.';
    end if;
  end if;

  if new.slot = 0 and (new.email_normalized is null or new.account_id is null) then
    raise exception using errcode = '23514', message = 'The Superadmin assignment must remain bound.';
  end if;

  if new.account_id is not null and not exists (
    select 1
    from public.accounts account
    join auth.users auth_user on auth_user.id = account.id
    where account.id = new.account_id
      and account.account_state = 'ACTIVE'
      and auth_user.email_confirmed_at is not null
      and pg_catalog.lower(auth_user.email) = new.email_normalized
  ) then
    raise exception using errcode = '23514', message = 'Admin assignment must match an active verified account email.';
  end if;

  return new;
end;
$$;

revoke execute on function dastak_v1.guard_admin_role_assignment()
  from public, anon, authenticated, service_role;

create trigger admin_role_assignments_guard
before insert or update or delete on dastak_v1.admin_role_assignments
for each row execute function dastak_v1.guard_admin_role_assignment();

create function dastak_v1_api.admin_role_for_actor(p_account_id uuid)
returns dastak_v1.admin_role
language sql
stable
security definer
set search_path = ''
as $$
  select assignment.role
  from dastak_v1.admin_role_assignments assignment
  join public.accounts account
    on account.id = assignment.account_id
    and account.account_state = 'ACTIVE'
  join auth.users auth_user
    on auth_user.id = assignment.account_id
    and pg_catalog.lower(auth_user.email) = assignment.email_normalized
  join private.account_memberships membership
    on membership.account_id = assignment.account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where assignment.account_id = p_account_id;
$$;

create function dastak_v1_api.is_superadmin(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select dastak_v1_api.admin_role_for_actor(p_account_id) = 'SUPERADMIN';
$$;

create function dastak_v1_api.assert_superadmin(p_account_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_account_id is null or p_account_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if not dastak_v1_api.is_superadmin(p_account_id) then
    raise exception using errcode = '42501', message = 'Superadmin access required.';
  end if;
end;
$$;

revoke execute on function dastak_v1_api.admin_role_for_actor(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1_api.is_superadmin(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1_api.assert_superadmin(uuid)
  from public, anon, authenticated, service_role;

create function dastak_v1_api.ensure_admin_capabilities(
  p_account_id uuid,
  p_role dastak_v1.admin_role,
  p_actor_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_bundle_id uuid;
begin
  if not exists (
    select 1 from public.accounts account
    where account.id = p_account_id and account.account_state = 'ACTIVE'
  ) then
    raise exception using errcode = '42501', message = 'An active account is required.';
  end if;

  insert into private.account_memberships (
    account_id, role, approved_at, suspended_until
  ) values (
    p_account_id, 'owner', pg_catalog.clock_timestamp(), null
  )
  on conflict (account_id, role) do update
  set approved_at = coalesce(private.account_memberships.approved_at, excluded.approved_at),
      suspended_until = null;

  select bundle.id into v_bundle_id
  from dastak_v1.permission_bundles bundle
  where bundle.bundle_key = case p_role
    when 'SUPERADMIN' then 'platform_super_admin'
    else 'executive_admin'
  end
    and bundle.scope = 'PLATFORM'
    and bundle.active;

  if v_bundle_id is null then
    raise exception using errcode = 'P0002', message = 'Admin permission bundle is unavailable.';
  end if;

  update dastak_v1.platform_permission_grants grant_row
  set revoked_by = p_actor_id,
      revoke_reason = 'Admin role capability alignment',
      revoked_at = pg_catalog.clock_timestamp(),
      version = grant_row.version + 1
  where grant_row.account_id = p_account_id
    and grant_row.revoked_at is null
    and grant_row.bundle_id in (
      select bundle.id from dastak_v1.permission_bundles bundle
      where bundle.bundle_key in ('platform_super_admin', 'executive_admin')
    )
    and grant_row.bundle_id <> v_bundle_id;

  if not exists (
    select 1 from dastak_v1.platform_permission_grants grant_row
    where grant_row.account_id = p_account_id
      and grant_row.bundle_id = v_bundle_id
      and grant_row.revoked_at is null
  ) then
    insert into dastak_v1.platform_permission_grants (
      account_id, bundle_id, granted_by, grant_reason
    ) values (
      p_account_id, v_bundle_id, p_actor_id, 'Admin role capability assignment'
    );
  end if;
end;
$$;

create function dastak_v1_api.remove_admin_capabilities(
  p_account_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from dastak_v1.admin_role_assignments assignment
    where assignment.slot = 0 and assignment.account_id = p_account_id
  ) then
    raise exception using errcode = '42501', message = 'The Superadmin cannot be changed.';
  end if;

  update dastak_v1.platform_permission_grants grant_row
  set revoked_by = p_actor_id,
      revoke_reason = 'Executive Admin assignment changed',
      revoked_at = pg_catalog.clock_timestamp(),
      version = grant_row.version + 1
  where grant_row.account_id = p_account_id
    and grant_row.revoked_at is null
    and grant_row.bundle_id in (
      select bundle.id from dastak_v1.permission_bundles bundle
      where bundle.bundle_key in ('platform_super_admin', 'executive_admin')
    );

  delete from private.account_memberships membership
  where membership.account_id = p_account_id
    and membership.role = 'owner';
end;
$$;

revoke execute on function dastak_v1_api.ensure_admin_capabilities(uuid, dastak_v1.admin_role, uuid)
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1_api.remove_admin_capabilities(uuid, uuid)
  from public, anon, authenticated, service_role;

create function dastak_v1_api.bootstrap_superadmin(p_account_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_existing dastak_v1.admin_role_assignments%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-admin-superadmin-bootstrap', 0)
  );

  select pg_catalog.lower(auth_user.email) into v_email
  from auth.users auth_user
  join public.accounts account on account.id = auth_user.id
  where auth_user.id = p_account_id
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null
    and account.account_state = 'ACTIVE';

  if v_email is null then
    raise exception using errcode = '42501', message = 'An active email-backed account is required.';
  end if;

  select assignment.* into v_existing
  from dastak_v1.admin_role_assignments assignment
  where assignment.slot = 0
  for update;

  if found and v_existing.account_id is distinct from p_account_id then
    raise exception using errcode = '42501', message = 'The Superadmin is already established.';
  end if;

  if not found then
    insert into dastak_v1.admin_role_assignments (
      slot, role, email_normalized, account_id,
      assigned_by, assigned_at
    ) values (
      0, 'SUPERADMIN', v_email, p_account_id,
      p_account_id, pg_catalog.clock_timestamp()
    );
    insert into dastak_v1.admin_role_assignments (slot, role)
    values (1, 'EXECUTIVE_ADMIN'), (2, 'EXECUTIVE_ADMIN');

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_account_id,
      'SUPERADMIN_ESTABLISHED',
      'admin_role_assignment',
      p_account_id,
      pg_catalog.jsonb_build_object('slot', 0, 'immutable', true)
    );
  end if;

  perform dastak_v1_api.ensure_admin_capabilities(
    p_account_id, 'SUPERADMIN', p_account_id
  );

  return pg_catalog.jsonb_build_object(
    'established', true,
    'role', 'SUPERADMIN',
    'slot', 0
  );
end;
$$;

revoke execute on function dastak_v1_api.bootstrap_superadmin(uuid)
  from public, anon, authenticated, service_role;

create function dastak_v1_api.admin_email_is_assigned(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users auth_user
    join dastak_v1.admin_role_assignments assignment
      on assignment.email_normalized = pg_catalog.lower(auth_user.email)
    where auth_user.id = p_account_id
      and auth_user.email is not null
  );
$$;

create function dastak_v1_api.resolve_admin_role(p_account_id uuid)
returns dastak_v1.admin_role
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_assignment dastak_v1.admin_role_assignments%rowtype;
begin
  select pg_catalog.lower(auth_user.email) into v_email
  from auth.users auth_user
  join public.accounts account on account.id = auth_user.id
  where auth_user.id = p_account_id
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null
    and account.account_state = 'ACTIVE';

  if v_email is null then return null; end if;

  select assignment.* into v_assignment
  from dastak_v1.admin_role_assignments assignment
  where assignment.email_normalized = v_email
  for update;

  if not found then return null; end if;
  if v_assignment.account_id is not null
    and v_assignment.account_id is distinct from p_account_id then
    return null;
  end if;

  if v_assignment.account_id is null then
    update dastak_v1.admin_role_assignments assignment
    set account_id = p_account_id,
        updated_at = pg_catalog.clock_timestamp(),
        version = assignment.version + 1
    where assignment.slot = v_assignment.slot;

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_account_id,
      'ADMIN_EMAIL_ASSIGNMENT_BOUND',
      'admin_role_assignment',
      p_account_id,
      pg_catalog.jsonb_build_object(
        'slot', v_assignment.slot,
        'role', v_assignment.role
      )
    );
  end if;

  perform dastak_v1_api.ensure_admin_capabilities(
    p_account_id, v_assignment.role, coalesce(v_assignment.assigned_by, p_account_id)
  );
  return v_assignment.role;
end;
$$;

revoke execute on function dastak_v1_api.admin_email_is_assigned(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1_api.resolve_admin_role(uuid)
  from public, anon, authenticated, service_role;

create function dastak_v1_api.admin_access_snapshot(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role dastak_v1.admin_role;
  v_slots jsonb;
begin
  if p_actor_id is null or p_actor_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  v_role := dastak_v1_api.admin_role_for_actor(p_actor_id);
  if v_role is null then
    raise exception using errcode = '42501', message = 'Admin access required.';
  end if;

  if v_role = 'SUPERADMIN' then
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'slot', assignment.slot,
        'role', assignment.role,
        'email', assignment.email_normalized,
        'linked', assignment.account_id is not null,
        'version', assignment.version
      ) order by assignment.slot
    ) into v_slots
    from dastak_v1.admin_role_assignments assignment;
  else
    v_slots := '[]'::jsonb;
  end if;

  return pg_catalog.jsonb_build_object(
    'role', v_role,
    'canManageAdmins', v_role = 'SUPERADMIN',
    'slots', coalesce(v_slots, '[]'::jsonb)
  );
end;
$$;

create function dastak_v1_api.set_executive_admin(
  p_actor_id uuid,
  p_slot smallint,
  p_email text,
  p_expected_version bigint,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_assignment dastak_v1.admin_role_assignments%rowtype;
  v_email text := nullif(pg_catalog.lower(pg_catalog.btrim(p_email)), '');
  v_new_account_id uuid;
  v_old_account_id uuid;
begin
  perform dastak_v1_api.assert_superadmin(p_actor_id);
  if p_slot not in (1, 2)
    or p_expected_version is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500 then
    raise exception using errcode = '22023', message = 'Valid Executive Admin assignment details are required.';
  end if;
  if v_email is not null and (
    pg_catalog.char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ) then
    raise exception using errcode = '22023', message = 'Enter a valid email address.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-executive-admin-slots', 0)
  );
  select assignment.* into v_assignment
  from dastak_v1.admin_role_assignments assignment
  where assignment.slot = p_slot
  for update;

  if not found or v_assignment.role <> 'EXECUTIVE_ADMIN' then
    raise exception using errcode = 'P0002', message = 'Executive Admin slot not found.';
  end if;
  -- A lost response can be retried safely when the requested end-state already
  -- exists; differing stale writes still fail the optimistic version check.
  if v_assignment.email_normalized is not distinct from v_email then
    return pg_catalog.jsonb_build_object(
      'slot', v_assignment.slot,
      'role', v_assignment.role,
      'email', v_assignment.email_normalized,
      'linked', v_assignment.account_id is not null,
      'version', v_assignment.version
    );
  end if;
  if v_assignment.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'Executive Admin assignment changed. Refresh and try again.';
  end if;

  if v_email is not null then
    if exists (
      select 1 from dastak_v1.admin_role_assignments assignment
      where assignment.email_normalized = v_email
        and assignment.slot <> p_slot
    ) then
      raise exception using errcode = '23505', message = 'That email already has an Admin assignment.';
    end if;

    select auth_user.id into v_new_account_id
    from auth.users auth_user
    join public.accounts account on account.id = auth_user.id
    where pg_catalog.lower(auth_user.email) = v_email
      and auth_user.email_confirmed_at is not null
      and account.account_state = 'ACTIVE';

    if v_new_account_id is not null and exists (
      select 1 from dastak_v1.admin_role_assignments assignment
      where assignment.account_id = v_new_account_id
        and assignment.slot <> p_slot
    ) then
      raise exception using errcode = '23505', message = 'That account already has an Admin assignment.';
    end if;
  end if;

  v_old_account_id := v_assignment.account_id;
  update dastak_v1.admin_role_assignments assignment
  set email_normalized = v_email,
      account_id = v_new_account_id,
      assigned_by = case when v_email is null then null else p_actor_id end,
      assigned_at = case when v_email is null then null else pg_catalog.clock_timestamp() end,
      updated_at = pg_catalog.clock_timestamp(),
      version = assignment.version + 1
  where assignment.slot = p_slot
  returning * into v_assignment;

  if v_old_account_id is not null
    and v_old_account_id is distinct from v_new_account_id then
    perform dastak_v1_api.remove_admin_capabilities(v_old_account_id, p_actor_id);
  end if;
  if v_new_account_id is not null then
    perform dastak_v1_api.ensure_admin_capabilities(
      v_new_account_id, 'EXECUTIVE_ADMIN', p_actor_id
    );
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    case when v_email is null
      then 'EXECUTIVE_ADMIN_CLEARED'
      else 'EXECUTIVE_ADMIN_ASSIGNED'
    end,
    'admin_role_assignment',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'slot', p_slot,
      'linked', v_new_account_id is not null,
      'reason', pg_catalog.btrim(p_reason)
    )
  );

  return pg_catalog.jsonb_build_object(
    'slot', v_assignment.slot,
    'role', v_assignment.role,
    'email', v_assignment.email_normalized,
    'linked', v_assignment.account_id is not null,
    'version', v_assignment.version
  );
end;
$$;

revoke execute on function dastak_v1_api.admin_access_snapshot(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1_api.set_executive_admin(uuid, smallint, text, bigint, text)
  from public, anon, authenticated, service_role;

-- These functions live in the unexposed internal API schema. The public
-- security-invoker wrappers below need only these two narrow execute grants.
grant execute on function dastak_v1_api.admin_access_snapshot(uuid)
  to authenticated;
grant execute on function dastak_v1_api.set_executive_admin(uuid, smallint, text, bigint, text)
  to authenticated;

-- resolve_app_access is executed by the authenticated Edge boundary using the
-- service role. Its internal calls remain unavailable to browser clients.
grant execute on function dastak_v1_api.admin_email_is_assigned(uuid)
  to service_role;
grant execute on function dastak_v1_api.resolve_admin_role(uuid)
  to service_role;

create function public.dastak_admin_access_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_access_snapshot(auth.uid());
$$;

create function public.dastak_set_executive_admin(
  p_slot smallint,
  p_email text,
  p_expected_version bigint,
  p_reason text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.set_executive_admin(
    auth.uid(), p_slot, p_email, p_expected_version, p_reason
  );
$$;

revoke execute on function public.dastak_admin_access_snapshot()
  from public, anon;
revoke execute on function public.dastak_set_executive_admin(smallint, text, bigint, text)
  from public, anon;
grant execute on function public.dastak_admin_access_snapshot()
  to authenticated;
grant execute on function public.dastak_set_executive_admin(smallint, text, bigint, text)
  to authenticated;

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
  v_admin_role dastak_v1.admin_role;
begin
  if p_application = 'admin' then
    if not exists (
      select 1 from public.accounts account
      where account.id = p_account_id and account.account_state = 'ACTIVE'
    ) then
      route := case
        when dastak_v1_api.admin_email_is_assigned(p_account_id) then 'needs_profile'
        else 'access_denied'
      end;
      return next;
      return;
    end if;

    v_admin_role := dastak_v1_api.resolve_admin_role(p_account_id);
    route := case when v_admin_role is null then 'access_denied' else 'active' end;
    return next;
    return;
  end if;

  v_required_role := case p_application
    when 'customer' then 'customer'::private.membership_role
    when 'merchant' then 'merchant'::private.membership_role
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

  select * into v_membership
  from private.account_memberships
  where account_id = p_account_id and role = v_required_role;

  if not found then
    if p_application = 'merchant' and exists (
      select 1 from private.merchant_applications
      where account_id = p_account_id and status = 'pending'
    ) then
      route := 'pending_approval';
    else
      route := 'access_denied';
    end if;
    return next;
    return;
  end if;

  if v_membership.suspended_until is not null
    and v_membership.suspended_until > pg_catalog.now() then
    route := 'suspended';
  elsif v_required_role = 'merchant' and v_membership.approved_at is null then
    route := 'pending_approval';
  else
    route := 'active';
  end if;
  return next;
end;
$$;

create or replace function public.is_active_owner(p_account_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from private.account_memberships membership
    where membership.account_id = p_account_id
      and membership.role = 'owner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
  );
$$;

create or replace function dastak_v1_api.actor_has_platform_permission(
  p_actor_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor_id is not null
    and exists (
      select 1
      from dastak_v1.platform_permission_grants permission_grant
      join dastak_v1.permission_bundles bundle
        on bundle.id = permission_grant.bundle_id
        and bundle.scope = 'PLATFORM'
        and bundle.active
      join dastak_v1.permission_bundle_permissions bundle_permission
        on bundle_permission.bundle_id = bundle.id
      join private.account_memberships membership
        on membership.account_id = permission_grant.account_id
        and membership.role = 'owner'
        and membership.approved_at is not null
      where permission_grant.account_id = p_actor_id
        and permission_grant.revoked_at is null
        and bundle_permission.permission_key = p_permission_key
        and (
          membership.suspended_until is null
          or membership.suspended_until <= pg_catalog.now()
        )
    );
$$;

create function dastak_v1.guard_immutable_superadmin_auth()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from dastak_v1.admin_role_assignments assignment
    where assignment.slot = 0 and assignment.account_id = old.id
  ) then
    if tg_op = 'DELETE' then
      raise exception using errcode = '42501', message = 'The Superadmin Auth account cannot be deleted.';
    end if;
    if new.email is distinct from old.email
      or new.banned_until is distinct from old.banned_until then
      raise exception using errcode = '42501', message = 'The Superadmin email cannot be changed.';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create function dastak_v1.guard_immutable_superadmin_account()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from dastak_v1.admin_role_assignments assignment
    where assignment.slot = 0
      and assignment.account_id = old.id
  ) then
    if tg_op = 'DELETE' then
      raise exception using errcode = '42501', message = 'The Superadmin account cannot be deleted or disabled.';
    end if;
    if new.account_state is distinct from old.account_state then
      raise exception using errcode = '42501', message = 'The Superadmin account cannot be deleted or disabled.';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create function dastak_v1.guard_immutable_superadmin_membership()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.role = 'owner' and exists (
    select 1 from dastak_v1.admin_role_assignments assignment
    where assignment.slot = 0 and assignment.account_id = old.account_id
  ) then
    if tg_op = 'DELETE' then
      raise exception using errcode = '42501', message = 'The Superadmin membership is immutable.';
    end if;
    if new.approved_at is distinct from old.approved_at
      or new.suspended_until is distinct from old.suspended_until then
      raise exception using errcode = '42501', message = 'The Superadmin membership is immutable.';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create function dastak_v1.guard_immutable_superadmin_grant()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from dastak_v1.admin_role_assignments assignment
    join dastak_v1.permission_bundles bundle on bundle.id = old.bundle_id
    where assignment.slot = 0
      and assignment.account_id = old.account_id
      and bundle.bundle_key = 'platform_super_admin'
  ) and new.revoked_at is not null then
    raise exception using errcode = '42501', message = 'The Superadmin permission grant is immutable.';
  end if;
  return new;
end;
$$;

revoke execute on function dastak_v1.guard_immutable_superadmin_auth()
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1.guard_immutable_superadmin_account()
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1.guard_immutable_superadmin_membership()
  from public, anon, authenticated, service_role;
revoke execute on function dastak_v1.guard_immutable_superadmin_grant()
  from public, anon, authenticated, service_role;

create trigger admin_superadmin_auth_delete_guard
before delete on auth.users
for each row execute function dastak_v1.guard_immutable_superadmin_auth();
create trigger admin_superadmin_auth_email_guard
before update of email, banned_until on auth.users
for each row execute function dastak_v1.guard_immutable_superadmin_auth();
create trigger admin_superadmin_account_guard
before update of account_state or delete on public.accounts
for each row execute function dastak_v1.guard_immutable_superadmin_account();
create trigger admin_superadmin_membership_guard
before update or delete on private.account_memberships
for each row execute function dastak_v1.guard_immutable_superadmin_membership();
create trigger admin_superadmin_grant_guard
before update on dastak_v1.platform_permission_grants
for each row execute function dastak_v1.guard_immutable_superadmin_grant();

comment on table dastak_v1.admin_role_assignments is
  'Fixed Dastak Admin slots: immutable Superadmin slot 0 and replaceable Executive Admin slots 1 and 2.';

-- A cleaned deployment may contain exactly the founder account that is to
-- become the permanent Superadmin. Bootstrap that unambiguous account during
-- rollout; never guess when multiple active verified accounts exist. Empty
-- development databases remain bootstrappable later through the private DBA
-- function above.
do $$
declare
  v_account_id uuid;
  v_account_count bigint;
begin
  select pg_catalog.count(*)
  into v_account_count
  from public.accounts account
  join auth.users auth_user on auth_user.id = account.id
  where account.account_state = 'ACTIVE'
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null;

  if v_account_count > 1 then
    raise exception using
      errcode = 'P0003',
      message = 'Superadmin bootstrap requires one unambiguous active verified account.';
  elsif v_account_count = 1 then
    select account.id into strict v_account_id
    from public.accounts account
    join auth.users auth_user on auth_user.id = account.id
    where account.account_state = 'ACTIVE'
      and auth_user.email is not null
      and auth_user.email_confirmed_at is not null;

    perform dastak_v1_api.bootstrap_superadmin(v_account_id);
  end if;
end;
$$;
