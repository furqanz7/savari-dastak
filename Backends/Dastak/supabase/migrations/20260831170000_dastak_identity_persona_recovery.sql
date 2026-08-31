-- One canonical Dastak identity can hold independently onboarded Customer,
-- Merchant and Delivery personas. Phone ownership is verified by Supabase Auth
-- before a persona can be created or recovered.

create type private.dastak_persona as enum ('CUSTOMER', 'MERCHANT', 'DELIVERY');
create type private.dastak_persona_state as enum ('ACTIVE', 'DELETED');
create type private.phone_claim_state as enum ('ACTIVE', 'RECOVERY_ELIGIBLE');

create table private.account_personas (
  account_id uuid not null references public.accounts(id),
  persona private.dastak_persona not null,
  state private.dastak_persona_state not null default 'ACTIVE',
  activated_at timestamptz not null default pg_catalog.clock_timestamp(),
  deleted_at timestamptz,
  deletion_reason text,
  version bigint not null default 1 check (version > 0),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (account_id, persona),
  check (
    (state = 'ACTIVE' and deleted_at is null and deletion_reason is null)
    or
    (state = 'DELETED' and deleted_at is not null
      and pg_catalog.char_length(pg_catalog.btrim(deletion_reason)) between 1 and 240)
  )
);

create table private.account_phone_claims (
  phone_number text primary key check (phone_number ~ '^\+[1-9][0-9]{7,14}$'),
  account_id uuid not null unique references public.accounts(id),
  claim_state private.phone_claim_state not null default 'ACTIVE',
  verified_at timestamptz,
  verification_source text not null check (
    verification_source in ('SUPABASE_PHONE_OTP', 'LEGACY_ACTIVE_PROFILE')
  ),
  recovery_eligible_at timestamptz,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  version bigint not null default 1 check (version > 0),
  check (
    (claim_state = 'ACTIVE' and recovery_eligible_at is null)
    or (claim_state = 'RECOVERY_ELIGIBLE' and recovery_eligible_at is not null)
  ),
  check (
    (verification_source = 'SUPABASE_PHONE_OTP' and verified_at is not null)
    or verification_source = 'LEGACY_ACTIVE_PROFILE'
  )
);

create table private.persona_suspended_merchant_users (
  account_id uuid not null references public.accounts(id),
  merchant_user_id uuid not null references dastak_v1.merchant_users(id),
  suspended_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (account_id, merchant_user_id)
);

create table private.identity_recovery_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  temporary_auth_user_id uuid not null,
  phone_number text not null check (phone_number ~ '^\+[1-9][0-9]{7,14}$'),
  requested_email_digest text not null check (requested_email_digest ~ '^[0-9a-f]{64}$'),
  application text not null check (application in ('customer', 'merchant', 'delivery')),
  display_name text not null check (
    pg_catalog.char_length(pg_catalog.btrim(display_name)) between 1 and 80
  ),
  request_digest text not null check (
    pg_catalog.char_length(pg_catalog.btrim(request_digest)) between 1 and 200
  ),
  state text not null default 'PREPARED' check (state in ('PREPARED', 'COMPLETED', 'FAILED')),
  requested_at timestamptz not null default pg_catalog.clock_timestamp(),
  completed_at timestamptz,
  failure_code text,
  unique (temporary_auth_user_id),
  check (
    (state = 'PREPARED' and completed_at is null and failure_code is null)
    or (state = 'COMPLETED' and completed_at is not null and failure_code is null)
    or (state = 'FAILED' and completed_at is not null
      and pg_catalog.char_length(pg_catalog.btrim(failure_code)) between 1 and 120)
  )
);

create index account_personas_state_idx
  on private.account_personas (persona, state, account_id);
create index identity_recovery_events_account_idx
  on private.identity_recovery_events (account_id, requested_at desc);

alter table private.account_personas enable row level security;
alter table private.account_phone_claims enable row level security;
alter table private.persona_suspended_merchant_users enable row level security;
alter table private.identity_recovery_events enable row level security;

revoke all on table private.account_personas,
  private.account_phone_claims,
  private.persona_suspended_merchant_users,
  private.identity_recovery_events
from public, anon, authenticated;
grant select, insert, update, delete on table private.account_personas,
  private.account_phone_claims,
  private.persona_suspended_merchant_users,
  private.identity_recovery_events
to service_role;

-- Preserve existing, intentional product access during the migration. New
-- personas are created only by the explicit app bootstrap/onboarding paths.
insert into private.account_personas (account_id, persona, state, activated_at)
select membership.account_id,
  case membership.role
    when 'customer' then 'CUSTOMER'::private.dastak_persona
    when 'merchant' then 'MERCHANT'::private.dastak_persona
    else 'DELIVERY'::private.dastak_persona
  end,
  'ACTIVE',
  coalesce(membership.approved_at, membership.created_at)
from private.account_memberships membership
join public.accounts account on account.id = membership.account_id
where account.account_state = 'ACTIVE'
  and membership.role in ('customer', 'merchant', 'dastak_partner')
  and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
on conflict (account_id, persona) do nothing;

do $$
begin
  if exists (
    select account.phone_number
    from public.accounts account
    where account.account_state = 'ACTIVE'
      and account.phone_number <> '+999000000000000'
    group by account.phone_number
    having pg_catalog.count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'Active Dastak accounts contain duplicate phone numbers; resolve them before identity migration.';
  end if;
end;
$$;

insert into private.account_phone_claims (
  phone_number, account_id, claim_state, verified_at, verification_source
)
select account.phone_number, account.id, 'ACTIVE',
  case when account.phone_verification_state = 'verified' then account.updated_at else null end,
  case when account.phone_verification_state = 'verified'
    then 'SUPABASE_PHONE_OTP' else 'LEGACY_ACTIVE_PROFILE' end
from public.accounts account
where account.account_state = 'ACTIVE'
  and account.phone_number <> '+999000000000000';

create function private.dastak_persona_for_membership(p_role private.membership_role)
returns private.dastak_persona
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_role
    when 'customer' then 'CUSTOMER'::private.dastak_persona
    when 'merchant' then 'MERCHANT'::private.dastak_persona
    when 'dastak_partner' then 'DELIVERY'::private.dastak_persona
    else null
  end;
$$;

create function private.identity_has_active_access(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.account_personas persona
    where persona.account_id = p_account_id and persona.state = 'ACTIVE'
  ) or exists (
    select 1 from private.merchant_applications application
    where application.account_id = p_account_id and application.status = 'pending'
  ) or exists (
    select 1 from private.delivery_partner_applications application
    where application.account_id = p_account_id and application.status = 'pending'
  ) or exists (
    select 1 from dastak_v1.admin_role_assignments assignment
    where assignment.account_id = p_account_id
  );
$$;

create function private.sync_dastak_persona_membership()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_persona private.dastak_persona;
begin
  v_persona := private.dastak_persona_for_membership(new.role);
  if v_persona is null then return new; end if;
  if new.suspended_until is null or new.suspended_until <= pg_catalog.now() then
    insert into private.account_personas (
      account_id, persona, state, activated_at, deleted_at, deletion_reason
    ) values (
      new.account_id, v_persona, 'ACTIVE', pg_catalog.clock_timestamp(), null, null
    )
    on conflict (account_id, persona) do update
    set state = 'ACTIVE', deleted_at = null, deletion_reason = null,
        activated_at = pg_catalog.clock_timestamp(),
        updated_at = pg_catalog.clock_timestamp(),
        version = private.account_personas.version + 1;
  end if;
  return new;
end;
$$;

create trigger account_memberships_sync_persona
after insert or update of suspended_until, approved_at on private.account_memberships
for each row execute function private.sync_dastak_persona_membership();

revoke execute on function private.dastak_persona_for_membership(private.membership_role),
  private.identity_has_active_access(uuid),
  private.sync_dastak_persona_membership()
from public, anon, authenticated;
grant execute on function private.dastak_persona_for_membership(private.membership_role),
  private.identity_has_active_access(uuid)
to service_role;

create function public.bootstrap_dastak_persona(
  p_account_id uuid,
  p_application text,
  p_display_name text,
  p_phone_number text,
  p_verified_phone_number text,
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
  if p_verified_phone_number is null or p_verified_phone_number <> p_phone_number then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'phone_verification_required',
      'message', 'Verify this phone number before continuing.'));
    response_status := 409; return next; return;
  end if;
  if p_display_name is null or pg_catalog.char_length(pg_catalog.btrim(p_display_name)) not between 1 and 80
    or p_phone_number !~ '^\+[1-9][0-9]{7,14}$'
    or p_idempotency_key is null or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200
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
      response_body := v_existing.response_body;
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
          'message', 'This verified number belongs to a deleted Dastak identity. Dastak can recover it.'),
        'recoveryAccountId', v_claim.account_id
      );
    else
      response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
        'code', 'phone_number_in_use',
        'message', 'This verified phone number already belongs to an active Dastak identity.'));
    end if;
    response_status := 409; return next; return;
  end if;

  select * into v_account from public.accounts where id = p_account_id for update;
  if not found then
    insert into public.accounts (
      id, display_name, phone_number, phone_verification_state
    ) values (
      p_account_id, pg_catalog.btrim(p_display_name), p_phone_number, 'verified'
    ) returning * into v_account;
  elsif v_account.account_state <> 'ACTIVE' then
    response_body := pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
      'code', 'identity_recovery_unavailable',
      'message', 'This legacy identity requires Dastak Support to recover.'));
    response_status := 409; return next; return;
  else
    update public.accounts
    set display_name = pg_catalog.btrim(p_display_name),
        phone_number = p_phone_number,
        phone_verification_state = 'verified',
        updated_at = pg_catalog.clock_timestamp()
    where id = p_account_id returning * into v_account;
  end if;

  insert into private.account_phone_claims (
    phone_number, account_id, claim_state, verified_at, verification_source
  ) values (
    p_phone_number, p_account_id, 'ACTIVE', pg_catalog.clock_timestamp(), 'SUPABASE_PHONE_OTP'
  )
  on conflict (phone_number) do update
  set claim_state = 'ACTIVE', verified_at = pg_catalog.clock_timestamp(),
      verification_source = 'SUPABASE_PHONE_OTP', recovery_eligible_at = null,
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
    'phoneState', 'verified',
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

create function public.prepare_dastak_persona_deletion(
  p_account_id uuid,
  p_persona text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_persona private.dastak_persona;
  v_role private.membership_role;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_row private.account_personas%rowtype;
begin
  if p_account_id is null or p_persona not in ('CUSTOMER', 'MERCHANT', 'DELIVERY')
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200
  then
    raise exception using errcode = '22023', message = 'A valid persona deletion request is required.';
  end if;
  v_persona := p_persona::private.dastak_persona;
  v_role := case v_persona
    when 'CUSTOMER' then 'customer'::private.membership_role
    when 'MERCHANT' then 'merchant'::private.membership_role
    else 'dastak_partner'::private.membership_role
  end;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':persona:' || p_persona, 0));

  select * into v_row from private.account_personas
  where account_id = p_account_id and persona = v_persona for update;
  if not found or v_row.state = 'DELETED' then
    if not private.identity_has_active_access(p_account_id) then
      update private.account_phone_claims
      set claim_state = 'RECOVERY_ELIGIBLE',
          recovery_eligible_at = coalesce(recovery_eligible_at, v_now),
          updated_at = v_now,
          version = version + 1
      where account_id = p_account_id and claim_state <> 'RECOVERY_ELIGIBLE';
      delete from auth.identities identity
      where identity.user_id = p_account_id and identity.provider = 'phone';
      update auth.users auth_user
      set phone = null, phone_confirmed_at = null,
          phone_change = '', phone_change_token = '', phone_change_sent_at = null,
          updated_at = v_now
      where auth_user.id = p_account_id;
    end if;
    return pg_catalog.jsonb_build_object(
      'deleted', true, 'persona', p_persona, 'alreadyDeleted', true,
      'identityRecoveryEligible', not private.identity_has_active_access(p_account_id));
  end if;

  if v_persona = 'CUSTOMER' and (
    exists (
      select 1 from dastak_v1.orders customer_order
      where customer_order.customer_id = p_account_id
        and customer_order.status not in (
          'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT',
          'DASTAK_FULFILMENT_FAILURE'
        )
    ) or exists (
      select 1 from private.merchant_orders legacy_order
      where legacy_order.customer_account_id = p_account_id
        and legacy_order.status not in ('delivered', 'cancelled')
    ) or exists (
      select 1 from private.parcel_deliveries parcel
      where (parcel.customer_account_id = p_account_id
        or parcel.recipient_account_id = p_account_id)
        and parcel.status not in ('delivered', 'cancelled')
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Complete or cancel active customer orders before deleting Customer.';
  elsif v_persona = 'MERCHANT' and (
    exists (
      select 1
      from dastak_v1.fulfilments fulfilment
      join dastak_v1.merchant_users merchant_user
        on merchant_user.organization_id = fulfilment.organization_id
      where merchant_user.account_id = p_account_id
        and fulfilment.status not in ('COMPLETED', 'RELEASED')
    ) or exists (
      select 1
      from private.merchant_orders legacy_order
      join private.merchant_stores store on store.id = legacy_order.store_id
      where store.merchant_account_id = p_account_id
        and legacy_order.status not in ('delivered', 'cancelled')
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Complete active merchant fulfilments before deleting Merchant.';
  elsif v_persona = 'DELIVERY' and (
    exists (
      select 1 from dastak_v1.delivery_missions mission
      where mission.assigned_rider_id = p_account_id
        and mission.status not in ('DELIVERED', 'CANCELLED')
    ) or exists (
      select 1 from private.delivery_assignment_attempts assignment
      where assignment.partner_account_id = p_account_id
        and assignment.status in ('offered', 'accepted')
    ) or exists (
      select 1 from private.parcel_assignment_attempts assignment
      where assignment.partner_account_id = p_account_id
        and assignment.status in ('offered', 'accepted')
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Complete or release the active delivery before deleting Delivery Partner.';
  end if;

  update private.account_personas
  set state = 'DELETED', deleted_at = v_now,
      deletion_reason = 'Deleted by account owner', updated_at = v_now,
      version = version + 1
  where account_id = p_account_id and persona = v_persona;
  update private.account_memberships
  set suspended_until = 'infinity'::timestamptz
  where account_id = p_account_id and role = v_role;

  if v_persona = 'MERCHANT' then
    insert into private.persona_suspended_merchant_users (
      account_id, merchant_user_id, suspended_at
    )
    select p_account_id, merchant_user.id, v_now
    from dastak_v1.merchant_users merchant_user
    where merchant_user.account_id = p_account_id and merchant_user.status = 'ACTIVE'
    on conflict do nothing;
    update dastak_v1.merchant_users merchant_user
    set status = 'SUSPENDED', updated_at = v_now, version = merchant_user.version + 1
    where merchant_user.account_id = p_account_id and merchant_user.status = 'ACTIVE';
  elsif v_persona = 'DELIVERY' then
    update private.delivery_partner_availability
    set status = 'offline', location = null, service_zone_id = null,
        available_until = null, last_seen_at = v_now, updated_at = v_now,
        state_version = state_version + 1
    where account_id = p_account_id;
  end if;

  if not private.identity_has_active_access(p_account_id) then
    update private.account_phone_claims
    set claim_state = 'RECOVERY_ELIGIBLE', recovery_eligible_at = v_now,
        updated_at = v_now, version = version + 1
    where account_id = p_account_id;
    delete from auth.identities identity
    where identity.user_id = p_account_id and identity.provider = 'phone';
    update auth.users auth_user
    set phone = null, phone_confirmed_at = null,
        phone_change = '', phone_change_token = '', phone_change_sent_at = null,
        updated_at = v_now
    where auth_user.id = p_account_id;
  end if;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_account_id, 'DASTAK_PERSONA_DELETED', 'account_persona', p_account_id,
    pg_catalog.jsonb_build_object('persona', p_persona, 'idempotencyKey', p_idempotency_key)
  );
  return pg_catalog.jsonb_build_object(
    'deleted', true, 'persona', p_persona, 'alreadyDeleted', false,
    'identityRecoveryEligible', not private.identity_has_active_access(p_account_id)
  );
end;
$$;

create function private.sync_admin_identity_phone_claim()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.account_id is not null
    and old.account_id is distinct from new.account_id
    and not private.identity_has_active_access(old.account_id)
  then
    update private.account_phone_claims
    set claim_state = 'RECOVERY_ELIGIBLE',
        recovery_eligible_at = pg_catalog.clock_timestamp(),
        updated_at = pg_catalog.clock_timestamp(),
        version = version + 1
    where account_id = old.account_id;
  end if;
  if new.account_id is not null then
    update private.account_phone_claims
    set claim_state = 'ACTIVE', recovery_eligible_at = null,
        updated_at = pg_catalog.clock_timestamp(), version = version + 1
    where account_id = new.account_id;
  end if;
  return new;
end;
$$;

create trigger admin_role_assignments_sync_identity_claim
after update of account_id on dastak_v1.admin_role_assignments
for each row execute function private.sync_admin_identity_phone_claim();

revoke execute on function private.sync_admin_identity_phone_claim()
from public, anon, authenticated, service_role;

create function public.update_dastak_account_profile(
  p_account_id uuid,
  p_display_name text,
  p_phone_number text,
  p_verified_phone_number text
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
  if p_verified_phone_number is null or p_phone_number <> p_verified_phone_number then
    raise exception using errcode = '28000', message = 'Verify the new phone number before saving it.';
  end if;
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
      message = 'This verified phone number belongs to another Dastak identity.';
  end if;
  select * into strict v_account from public.accounts
  where id = p_account_id and account_state = 'ACTIVE' for update;
  if v_account.phone_number <> p_phone_number then
    delete from private.account_phone_claims where account_id = p_account_id;
  end if;
  insert into private.account_phone_claims (
    phone_number, account_id, claim_state, verified_at, verification_source
  ) values (
    p_phone_number, p_account_id, 'ACTIVE', pg_catalog.clock_timestamp(), 'SUPABASE_PHONE_OTP'
  ) on conflict (phone_number) do update
  set claim_state = 'ACTIVE', verified_at = pg_catalog.clock_timestamp(),
      verification_source = 'SUPABASE_PHONE_OTP', recovery_eligible_at = null,
      updated_at = pg_catalog.clock_timestamp(), version = private.account_phone_claims.version + 1;
  update public.accounts set display_name = pg_catalog.btrim(p_display_name),
    phone_number = p_phone_number, phone_verification_state = 'verified',
    updated_at = pg_catalog.clock_timestamp()
  where id = p_account_id;
  return pg_catalog.jsonb_build_object(
    'displayName', pg_catalog.btrim(p_display_name), 'phoneNumber', p_phone_number);
end;
$$;

create function public.prepare_dastak_identity_recovery(
  p_temporary_auth_user_id uuid,
  p_account_id uuid,
  p_verified_phone_number text,
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
    or p_requested_email_digest !~ '^[0-9a-f]{64}$'
    or p_application not in ('customer', 'merchant', 'delivery')
    or pg_catalog.char_length(pg_catalog.btrim(p_display_name)) not between 1 and 80
    or pg_catalog.char_length(pg_catalog.btrim(p_request_digest)) not between 1 and 200
  then
    raise exception using errcode = '22023', message = 'Invalid identity recovery request.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-phone:' || p_verified_phone_number, 0));
  if not exists (
    select 1 from private.account_phone_claims claim
    where claim.account_id = p_account_id
      and claim.phone_number = p_verified_phone_number
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
    p_account_id, p_temporary_auth_user_id, p_verified_phone_number,
    p_requested_email_digest, p_application, pg_catalog.btrim(p_display_name),
    pg_catalog.btrim(p_request_digest)
  )
  on conflict (temporary_auth_user_id) do update
  set requested_email_digest = excluded.requested_email_digest,
      application = excluded.application,
      display_name = excluded.display_name,
      request_digest = excluded.request_digest
  where private.identity_recovery_events.state = 'PREPARED'
  returning id into v_event_id;
  return v_event_id;
end;
$$;

create function public.complete_dastak_identity_recovery(
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
    or (case when pg_catalog.left(v_temporary.phone, 1) = '+'
      then v_temporary.phone else '+' || v_temporary.phone end) <> v_event.phone_number
    or v_temporary.phone_confirmed_at is null
    or pg_catalog.encode(
      extensions.digest(pg_catalog.lower(pg_catalog.btrim(v_temporary.email)), 'sha256'), 'hex'
    ) <> v_event.requested_email_digest
  then
    raise exception using errcode = '42501', message = 'Verified recovery identity is unavailable.';
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

  -- Replace the old sign-in identities with the newly verified OAuth/phone
  -- identities while retaining the canonical Dastak account id and history.
  delete from private.customer_auth_identities registered
  where registered.account_id in (
    v_event.account_id, v_event.temporary_auth_user_id
  );
  delete from auth.identities identity where identity.user_id = v_event.account_id;
  update auth.identities identity
  set user_id = v_event.account_id, updated_at = pg_catalog.clock_timestamp()
  where identity.user_id = v_event.temporary_auth_user_id;
  delete from auth.users auth_user where auth_user.id = v_event.temporary_auth_user_id;
  update auth.users auth_user
  set email = pg_catalog.lower(pg_catalog.btrim(v_temporary.email)),
      email_confirmed_at = v_temporary.email_confirmed_at,
      phone = v_temporary.phone,
      phone_confirmed_at = v_temporary.phone_confirmed_at,
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
      verified_at = pg_catalog.clock_timestamp(),
      verification_source = 'SUPABASE_PHONE_OTP',
      updated_at = pg_catalog.clock_timestamp(), version = version + 1
  where account_id = v_event.account_id and phone_number = v_event.phone_number;
  select bootstrap.response_status into v_bootstrap_status
  from public.bootstrap_dastak_persona(
    v_event.account_id,
    v_event.application,
    v_event.display_name,
    v_event.phone_number,
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
  v_required_persona private.dastak_persona;
  v_membership private.account_memberships%rowtype;
  v_admin_role dastak_v1.admin_role;
begin
  if p_application = 'admin' then
    if not exists (
      select 1 from public.accounts account
      where account.id = p_account_id and account.account_state = 'ACTIVE'
    ) then
      route := case when dastak_v1_api.admin_email_is_assigned(p_account_id)
        then 'needs_profile' else 'access_denied' end;
      return next; return;
    end if;
    v_admin_role := dastak_v1_api.resolve_admin_role(p_account_id);
    route := case when v_admin_role is null then 'access_denied' else 'active' end;
    return next; return;
  end if;

  v_required_role := case p_application
    when 'customer' then 'customer'::private.membership_role
    when 'merchant' then 'merchant'::private.membership_role
    when 'delivery' then 'dastak_partner'::private.membership_role
    else null end;
  v_required_persona := case p_application
    when 'customer' then 'CUSTOMER'::private.dastak_persona
    when 'merchant' then 'MERCHANT'::private.dastak_persona
    when 'delivery' then 'DELIVERY'::private.dastak_persona
    else null end;
  if v_required_role is null then route := 'access_denied'; return next; return; end if;
  if not exists (
    select 1 from public.accounts account
    where account.id = p_account_id and account.account_state = 'ACTIVE'
  ) then route := 'needs_profile'; return next; return; end if;
  if exists (
    select 1 from private.account_personas persona
    where persona.account_id = p_account_id and persona.persona = v_required_persona
      and persona.state = 'DELETED'
  ) then route := 'needs_profile'; return next; return; end if;

  select * into v_membership from private.account_memberships
  where account_id = p_account_id and role = v_required_role;
  if not found then
    if p_application = 'customer' then route := 'needs_profile';
    elsif p_application = 'merchant' and exists (
      select 1 from private.merchant_applications
      where account_id = p_account_id and status = 'pending'
    ) then route := 'pending_approval';
    elsif p_application = 'delivery' and exists (
      select 1 from private.delivery_partner_applications
      where account_id = p_account_id and status = 'pending'
    ) then route := 'pending_approval';
    else route := 'access_denied'; end if;
    return next; return;
  end if;
  if v_membership.suspended_until is not null
    and v_membership.suspended_until > pg_catalog.now() then route := 'suspended';
  elsif v_required_role in ('merchant', 'dastak_partner') and v_membership.approved_at is null
    then route := 'pending_approval';
  else route := 'active'; end if;
  return next;
end;
$$;

create function public.dastak_identity_retirement_inventory()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with superadmin as (
    select assignment.account_id
    from dastak_v1.admin_role_assignments assignment
    where assignment.slot = 0 and assignment.role = 'SUPERADMIN'
  )
  select pg_catalog.jsonb_build_object(
    'activeAccounts', (select pg_catalog.count(*) from public.accounts account
      where account.account_state = 'ACTIVE'),
    'superadminAssignments', (select pg_catalog.count(*)
      from dastak_v1.admin_role_assignments assignment
      where assignment.slot = 0 and assignment.account_id is not null),
    'executiveAdminAssignments', (select pg_catalog.count(*)
      from dastak_v1.admin_role_assignments assignment
      where assignment.slot in (1, 2) and assignment.account_id is not null),
    'superadminActivePersonas', (select pg_catalog.count(*)
      from private.account_personas persona
      where persona.account_id = (select account_id from superadmin)
        and persona.state = 'ACTIVE'),
    'nonSuperadminAccounts', (select pg_catalog.count(*) from public.accounts account
      where account.id is distinct from (select account_id from superadmin)),
    'nonSuperadminActivePersonas', (select pg_catalog.count(*)
      from private.account_personas persona
      where persona.account_id is distinct from (select account_id from superadmin)
        and persona.state = 'ACTIVE'),
    'nonSuperadminPhoneClaims', (select pg_catalog.count(*)
      from private.account_phone_claims claim
      where claim.account_id is distinct from (select account_id from superadmin)),
    'nonSuperadminActiveCustomerOrders', (select pg_catalog.count(*)
      from dastak_v1.orders customer_order
      where customer_order.customer_id is distinct from (select account_id from superadmin)
        and customer_order.status not in (
          'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT',
          'DASTAK_FULFILMENT_FAILURE'
        )),
    'nonSuperadminActiveMerchantFulfilments', (select pg_catalog.count(distinct fulfilment.id)
      from dastak_v1.fulfilments fulfilment
      join dastak_v1.merchant_users merchant_user
        on merchant_user.organization_id = fulfilment.organization_id
      where merchant_user.account_id is distinct from (select account_id from superadmin)
        and fulfilment.status not in ('COMPLETED', 'RELEASED')),
    'nonSuperadminActiveDeliveryMissions', (select pg_catalog.count(*)
      from dastak_v1.delivery_missions mission
      where mission.assigned_rider_id is distinct from (select account_id from superadmin)
        and mission.status not in ('DELIVERED', 'CANCELLED')),
    'allActiveCustomerOrders', (select pg_catalog.count(*)
      from dastak_v1.orders customer_order
      where customer_order.status not in (
        'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT',
        'DASTAK_FULFILMENT_FAILURE'
      )),
    'allActiveMerchantFulfilments', (select pg_catalog.count(*)
      from dastak_v1.fulfilments fulfilment
      where fulfilment.status not in ('COMPLETED', 'RELEASED')),
    'allActiveDeliveryMissions', (select pg_catalog.count(*)
      from dastak_v1.delivery_missions mission
      where mission.status not in ('DELIVERED', 'CANCELLED')),
    'allActiveLegacyMerchantOrders', (select pg_catalog.count(*)
      from private.merchant_orders legacy_order
      where legacy_order.status not in ('delivered', 'cancelled')),
    'allActiveLegacyParcelDeliveries', (select pg_catalog.count(*)
      from private.parcel_deliveries parcel
      where parcel.status not in ('delivered', 'cancelled')),
    'nonSuperadminPendingMerchantApplications', (select pg_catalog.count(*)
      from private.merchant_applications application
      where application.account_id is distinct from (select account_id from superadmin)
        and application.status = 'pending'),
    'nonSuperadminPendingDeliveryApplications', (select pg_catalog.count(*)
      from private.delivery_partner_applications application
      where application.account_id is distinct from (select account_id from superadmin)
        and application.status = 'pending')
  );
$$;

revoke execute on function public.bootstrap_dastak_persona(uuid, text, text, text, text, text, text),
  public.prepare_dastak_persona_deletion(uuid, text, text),
  public.update_dastak_account_profile(uuid, text, text, text),
  public.prepare_dastak_identity_recovery(uuid, uuid, text, text, text, text, text),
  public.complete_dastak_identity_recovery(uuid, boolean, text)
from public, anon, authenticated;
grant execute on function public.bootstrap_dastak_persona(uuid, text, text, text, text, text, text),
  public.prepare_dastak_persona_deletion(uuid, text, text),
  public.update_dastak_account_profile(uuid, text, text, text),
  public.prepare_dastak_identity_recovery(uuid, uuid, text, text, text, text, text),
  public.complete_dastak_identity_recovery(uuid, boolean, text)
to service_role;

revoke execute on function public.resolve_app_access(uuid, text)
from public, anon, authenticated;
grant execute on function public.resolve_app_access(uuid, text) to service_role;

revoke execute on function public.dastak_identity_retirement_inventory()
from public, anon, authenticated;
grant execute on function public.dastak_identity_retirement_inventory() to service_role;

comment on table private.account_personas is
  'Independent Customer, Merchant and Delivery onboarding/deletion state for one canonical Dastak identity.';
comment on table private.account_phone_claims is
  'One canonical identity per verified E.164 phone. Recovery eligibility never transfers an active identity.';
