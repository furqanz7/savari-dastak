-- Dastak V1 Step 6: durable notifications, explicit platform RBAC and
-- launch-critical invariant monitoring. Business state never depends on push.

alter table public.dastak_device_tokens
  add column disabled_at timestamptz,
  add column disabled_reason text,
  add column version bigint not null default 1 check (version > 0),
  add constraint dastak_device_tokens_disabled_state_check check (
    (disabled_at is null and disabled_reason is null)
    or (
      disabled_at is not null
      and pg_catalog.char_length(pg_catalog.btrim(disabled_reason)) between 3 and 300
    )
  );

create index dastak_device_tokens_active_account_idx
  on public.dastak_device_tokens (account_id, platform, last_seen_at desc)
  where disabled_at is null;

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'notifications.outbox_max_attempts', 'INTEGER',
    'Maximum fan-out attempts before a domain event is dead-lettered.',
    '8'::jsonb, '{"minimum":1,"maximum":100}'::jsonb, true, false
  ),
  (
    'notifications.delivery_max_attempts', 'INTEGER',
    'Maximum provider attempts for one device notification.',
    '8'::jsonb, '{"minimum":1,"maximum":100}'::jsonb, true, false
  ),
  (
    'notifications.retry_base_seconds', 'DURATION_SECONDS',
    'Base duration for exponential notification retry backoff.',
    '15'::jsonb, '{"minimum":1,"maximum":3600}'::jsonb, true, false
  ),
  (
    'notifications.claim_stale_seconds', 'DURATION_SECONDS',
    'Duration after which an abandoned worker claim may be recovered.',
    '120'::jsonb, '{"minimum":30,"maximum":3600}'::jsonb, true, false
  ),
  (
    'observability.outbox_stale_seconds', 'DURATION_SECONDS',
    'Age at which an unpublished domain event makes launch health degraded.',
    '300'::jsonb, '{"minimum":60,"maximum":86400}'::jsonb, true, false
  );

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values
  (
    'platform.customer_support.manage',
    'Inspect and resolve customer support cases within policy.',
    'SENSITIVE'
  ),
  (
    'platform.system_health.read',
    'Inspect launch health, invariant incidents and asynchronous backlogs.',
    'SENSITIVE'
  ),
  (
    'platform.system_health.manage',
    'Run launch invariant monitors and acknowledge operational recovery.',
    'HIGHLY_SENSITIVE'
  ),
  (
    'platform.notifications.manage',
    'Inspect and operate the durable notification delivery system.',
    'HIGHLY_SENSITIVE'
  );

insert into dastak_v1.permission_bundles (
  id, bundle_key, display_name, scope, description
) values
  (
    '10000000-0000-4000-8000-00000000000a',
    'customer_support', 'Customer support', 'PLATFORM',
    'Inspect orders and resolve customer issues without finance or catalogue powers.'
  ),
  (
    '10000000-0000-4000-8000-00000000000b',
    'system_health_operator', 'System health operator', 'PLATFORM',
    'Inspect launch invariants and operate asynchronous delivery recovery.'
  ),
  (
    '10000000-0000-4000-8000-00000000000c',
    'platform_super_admin', 'Platform super admin', 'PLATFORM',
    'Explicit audited access to every platform permission.'
  );

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values
  ('10000000-0000-4000-8000-00000000000a', 'platform.orders.trace'),
  ('10000000-0000-4000-8000-00000000000a', 'platform.customer_support.manage'),
  ('10000000-0000-4000-8000-00000000000b', 'platform.orders.trace'),
  ('10000000-0000-4000-8000-00000000000b', 'platform.system_health.read'),
  ('10000000-0000-4000-8000-00000000000b', 'platform.system_health.manage'),
  ('10000000-0000-4000-8000-00000000000b', 'platform.notifications.manage');

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
select '10000000-0000-4000-8000-00000000000c'::uuid, definition.permission_key
from dastak_v1.permission_definitions definition
where definition.permission_key like 'platform.%';

-- Preserve current founder/operator access, but turn it into an explicit,
-- auditable grant. A future `owner` membership alone grants no V1 platform power.
insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
)
select membership.account_id,
  '10000000-0000-4000-8000-00000000000c'::uuid,
  membership.account_id,
  'Step 6 explicit platform RBAC bootstrap'
from private.account_memberships membership
where membership.role = 'owner'
  and membership.approved_at is not null
  and (
    membership.suspended_until is null
    or membership.suspended_until <= pg_catalog.now()
  )
  and not exists (
    select 1
    from dastak_v1.platform_permission_grants grant_row
    where grant_row.account_id = membership.account_id
      and grant_row.bundle_id = '10000000-0000-4000-8000-00000000000c'::uuid
      and grant_row.revoked_at is null
  );

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

create or replace function dastak_v1_api.actor_has_merchant_permission(
  p_actor_id uuid,
  p_organization_id uuid,
  p_permission_key text,
  p_branch_id uuid default null
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
      from dastak_v1.merchant_users merchant_user
      join dastak_v1.merchant_organizations organization
        on organization.id = merchant_user.organization_id
        and organization.status = 'ACTIVE'
      join dastak_v1.merchant_permission_grants permission_grant
        on permission_grant.merchant_user_id = merchant_user.id
        and permission_grant.organization_id = merchant_user.organization_id
      join dastak_v1.permission_bundles bundle
        on bundle.id = permission_grant.bundle_id
        and bundle.scope = 'MERCHANT'
        and bundle.active
      join dastak_v1.permission_bundle_permissions bundle_permission
        on bundle_permission.bundle_id = permission_grant.bundle_id
      where merchant_user.account_id = p_actor_id
        and merchant_user.organization_id = p_organization_id
        and merchant_user.status = 'ACTIVE'
        and permission_grant.revoked_at is null
        and bundle_permission.permission_key = p_permission_key
        and (
          permission_grant.branch_id is null
          or permission_grant.branch_id = p_branch_id
        )
    );
$$;

create or replace function dastak_v1_api.grant_merchant_permission_bundle(
  p_actor_id uuid,
  p_merchant_user_id uuid,
  p_bundle_id uuid,
  p_branch_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
  v_grant_id uuid;
begin
  select merchant_user.organization_id into v_organization_id
  from dastak_v1.merchant_users merchant_user
  where merchant_user.id = p_merchant_user_id;

  if v_organization_id is null then
    raise exception 'merchant user not found';
  end if;
  if not (
    dastak_v1_api.actor_has_platform_permission(
      p_actor_id, 'platform.permissions.manage'
    )
    or dastak_v1_api.actor_has_merchant_permission(
      p_actor_id, v_organization_id, 'merchant.permissions.manage', p_branch_id
    )
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  insert into dastak_v1.merchant_permission_grants (
    merchant_user_id, organization_id, bundle_id, branch_id,
    granted_by, grant_reason
  ) values (
    p_merchant_user_id, v_organization_id, p_bundle_id, p_branch_id,
    p_actor_id, p_reason
  ) returning id into v_grant_id;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'MERCHANT_PERMISSION_GRANTED',
    'merchant_permission_grant', v_grant_id,
    pg_catalog.jsonb_build_object(
      'organizationId', v_organization_id,
      'merchantUserId', p_merchant_user_id,
      'bundleId', p_bundle_id,
      'branchId', p_branch_id
    )
  );
  return v_grant_id;
end;
$$;

create or replace function dastak_v1_api.revoke_merchant_permission_grant(
  p_actor_id uuid,
  p_grant_id uuid,
  p_expected_version bigint,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant dastak_v1.merchant_permission_grants%rowtype;
begin
  select grant_row.* into v_grant
  from dastak_v1.merchant_permission_grants grant_row
  where grant_row.id = p_grant_id
  for update;
  if not found then raise exception 'permission grant not found'; end if;
  if v_grant.revoked_at is not null then return; end if;
  if v_grant.version <> p_expected_version then
    raise exception using errcode = '40001', message = 'stale permission grant version';
  end if;
  if not (
    dastak_v1_api.actor_has_platform_permission(
      p_actor_id, 'platform.permissions.manage'
    )
    or dastak_v1_api.actor_has_merchant_permission(
      p_actor_id, v_grant.organization_id,
      'merchant.permissions.manage', v_grant.branch_id
    )
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  update dastak_v1.merchant_permission_grants grant_row
  set revoked_by = p_actor_id,
      revoke_reason = p_reason,
      revoked_at = pg_catalog.now(),
      version = grant_row.version + 1
  where grant_row.id = p_grant_id;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'MERCHANT_PERMISSION_REVOKED',
    'merchant_permission_grant', p_grant_id,
    pg_catalog.jsonb_build_object('organizationId', v_grant.organization_id)
  );
end;
$$;

create or replace function dastak_v1_api.set_platform_setting(
  p_actor_id uuid,
  p_setting_key text,
  p_scope_type dastak_v1.setting_scope_type,
  p_scope_id uuid,
  p_value jsonb,
  p_expected_version bigint,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setting dastak_v1.platform_settings%rowtype;
  v_id uuid;
begin
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.settings.manage'
  );
  if not dastak_v1.validate_setting_value(p_setting_key, p_value) then
    raise exception 'invalid setting value';
  end if;
  select setting.* into v_setting
  from dastak_v1.platform_settings setting
  where setting.setting_key = p_setting_key
    and setting.scope_type = p_scope_type
    and setting.scope_id is not distinct from p_scope_id
  for update;
  if found then
    if v_setting.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'stale setting version';
    end if;
    update dastak_v1.platform_settings setting
    set setting_value = p_value,
        updated_by = p_actor_id,
        update_reason = p_reason,
        version = setting.version + 1
    where setting.id = v_setting.id
    returning setting.id into v_id;
  else
    if p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'setting does not exist';
    end if;
    insert into dastak_v1.platform_settings (
      setting_key, scope_type, scope_id, setting_value,
      updated_by, update_reason
    ) values (
      p_setting_key, p_scope_type, p_scope_id, p_value,
      p_actor_id, p_reason
    ) returning id into v_id;
  end if;
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'PLATFORM_SETTING_CHANGED', 'platform_setting', v_id,
    pg_catalog.jsonb_build_object(
      'settingKey', p_setting_key, 'scopeType', p_scope_type
    )
  );
  return v_id;
end;
$$;

create function dastak_v1_api.grant_platform_permission_bundle(
  p_actor_id uuid,
  p_account_id uuid,
  p_bundle_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'grantPlatformPermissionBundle';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_grant dastak_v1.platform_permission_grants%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.permissions.manage'
  );
  if p_account_id is null or p_bundle_id is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid platform grant';
  end if;
  if not public.is_active_owner(p_account_id) then
    raise exception using errcode = '42501', message = 'active platform account required';
  end if;
  if not exists (
    select 1 from dastak_v1.permission_bundles bundle
    where bundle.id = p_bundle_id and bundle.scope = 'PLATFORM' and bundle.active
  ) then
    raise exception using errcode = '22023', message = 'active platform bundle required';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'accountId', p_account_id, 'bundleId', p_bundle_id,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select grant_row.* into v_grant
  from dastak_v1.platform_permission_grants grant_row
  where grant_row.account_id = p_account_id
    and grant_row.bundle_id = p_bundle_id
    and grant_row.revoked_at is null
  for update;
  if not found then
    insert into dastak_v1.platform_permission_grants (
      account_id, bundle_id, granted_by, grant_reason
    ) values (
      p_account_id, p_bundle_id, p_actor_id, pg_catalog.btrim(p_reason)
    ) returning * into v_grant;
  end if;
  v_response := pg_catalog.jsonb_build_object(
    'grantId', v_grant.id, 'accountId', v_grant.account_id,
    'bundleId', v_grant.bundle_id, 'version', v_grant.version
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_grant.id
  );
  return v_response;
end;
$$;

create function dastak_v1_api.revoke_platform_permission_grant(
  p_actor_id uuid,
  p_grant_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'revokePlatformPermissionGrant';
  v_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_grant dastak_v1.platform_permission_grants%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.permissions.manage'
  );
  if p_grant_id is null or p_expected_version is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 3 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null then
    raise exception using errcode = '22023', message = 'invalid platform revocation';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'grantId', p_grant_id, 'expectedVersion', p_expected_version,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;
  select grant_row.* into v_grant
  from dastak_v1.platform_permission_grants grant_row
  where grant_row.id = p_grant_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'grant not found'; end if;
  if v_grant.revoked_at is null then
    if v_grant.version <> p_expected_version then
      raise exception using errcode = '40001', message = 'stale platform grant version';
    end if;
    update dastak_v1.platform_permission_grants grant_row
    set revoked_by = p_actor_id, revoke_reason = pg_catalog.btrim(p_reason),
        revoked_at = pg_catalog.clock_timestamp(), version = grant_row.version + 1
    where grant_row.id = v_grant.id
    returning * into v_grant;
  end if;
  v_response := pg_catalog.jsonb_build_object(
    'grantId', v_grant.id, 'revoked', true, 'version', v_grant.version
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_hash,
    v_response, 200, v_grant.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_grant_platform_permission_bundle(
  p_account_id uuid,
  p_bundle_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.grant_platform_permission_bundle(
    auth.uid(), p_account_id, p_bundle_id, p_reason, p_idempotency_key
  );
$$;

create function public.dastak_v1_revoke_platform_permission_grant(
  p_grant_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.revoke_platform_permission_grant(
    auth.uid(), p_grant_id, p_expected_version, p_reason, p_idempotency_key
  );
$$;

create type dastak_v1.notification_delivery_status as enum (
  'PENDING', 'IN_FLIGHT', 'SENT', 'DEAD_LETTER', 'SUPPRESSED'
);

create table dastak_v1.notification_routes (
  event_type text not null,
  audience text not null check (audience in ('CUSTOMER', 'MERCHANT', 'RIDER')),
  notification_type text not null check (
    notification_type ~ '^[a-z][a-z0-9_.]{2,119}$'
  ),
  platform text not null default 'ios' check (platform = 'ios'),
  title text not null check (pg_catalog.char_length(title) between 1 and 80),
  body text not null check (pg_catalog.char_length(body) between 1 and 220),
  enabled boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  primary key (event_type, audience, notification_type)
);

create table dastak_v1.notification_intents (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references dastak_v1.domain_events_outbox(id),
  recipient_account_id uuid not null references public.accounts(id),
  notification_type text not null,
  platform text not null check (platform = 'ios'),
  title text not null,
  body text not null,
  payload jsonb not null check (pg_catalog.jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default pg_catalog.now(),
  unique (event_id, recipient_account_id, notification_type)
);

create index notification_intents_recipient_idx
  on dastak_v1.notification_intents (recipient_account_id, created_at desc);

create table dastak_v1.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  intent_id uuid not null references dastak_v1.notification_intents(id),
  event_id uuid not null references dastak_v1.domain_events_outbox(id),
  recipient_account_id uuid not null references public.accounts(id),
  device_token_id uuid not null references public.dastak_device_tokens(id),
  status dastak_v1.notification_delivery_status not null default 'PENDING',
  available_at timestamptz not null default pg_catalog.now(),
  locked_at timestamptz,
  locked_by text,
  attempts integer not null default 0 check (attempts >= 0),
  provider_status integer,
  provider_response text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (intent_id, device_token_id),
  check (
    (status = 'PENDING' and locked_at is null and locked_by is null and sent_at is null)
    or (status = 'IN_FLIGHT' and locked_at is not null and locked_by is not null and sent_at is null)
    or (status = 'SENT' and locked_at is null and locked_by is null and sent_at is not null)
    or (status in ('DEAD_LETTER', 'SUPPRESSED') and locked_at is null and locked_by is null)
  )
);

create index notification_deliveries_claim_idx
  on dastak_v1.notification_deliveries (available_at, created_at, id)
  where status = 'PENDING';
create index notification_deliveries_health_idx
  on dastak_v1.notification_deliveries (status, updated_at, id);
create index notification_deliveries_event_idx
  on dastak_v1.notification_deliveries (event_id, status);
create index notification_deliveries_recipient_idx
  on dastak_v1.notification_deliveries (recipient_account_id, created_at desc);
create index notification_deliveries_token_idx
  on dastak_v1.notification_deliveries (device_token_id, status);

insert into dastak_v1.notification_routes (
  event_type, audience, notification_type, title, body
) values
  ('ORDER_SUBMITTED', 'CUSTOMER', 'customer.order_submitted', 'Finding your items', 'We are securing every exact item in your order.'),
  ('PAYMENT_WINDOW_STARTED', 'CUSTOMER', 'customer.payment_ready', 'Your order is secured', 'Complete payment while your items remain reserved.'),
  ('PAYMENT_ATTEMPT_FAILED', 'CUSTOMER', 'customer.payment_failed', 'Payment did not complete', 'Your items remain reserved. You can try payment again.'),
  ('PAYMENT_CONFIRMED', 'CUSTOMER', 'customer.payment_confirmed', 'Payment confirmed', 'Your order is now being prepared.'),
  ('PAYMENT_RESERVATION_EXPIRED', 'CUSTOMER', 'customer.payment_expired', 'Reservation expired', 'Payment was not completed in time and the item reservation was released.'),
  ('PREPARATION_STARTED', 'CUSTOMER', 'customer.preparing', 'Preparing your order', 'Your order is being prepared.'),
  ('RIDER_ASSIGNED', 'CUSTOMER', 'customer.rider_assigned', 'Picking up your order', 'A delivery partner is collecting every package.'),
  ('ORDER_OUT_FOR_DELIVERY', 'CUSTOMER', 'customer.out_for_delivery', 'Your order is on the way', 'Keep your in-app delivery code ready for handoff.'),
  ('RIDER_ARRIVED_CUSTOMER', 'CUSTOMER', 'customer.rider_arrived', 'Your delivery partner has arrived', 'Share the in-app delivery code with the recipient after checking the packages.'),
  ('ORDER_DELIVERED', 'CUSTOMER', 'customer.delivered', 'Order delivered', 'Every package was handed over and verified.'),
  ('ORDER_UNAVAILABLE', 'CUSTOMER', 'customer.unavailable', 'Order unavailable', 'We could not secure every exact item. You were not charged.'),
  ('ORDER_CANCELLED_PREPAYMENT', 'CUSTOMER', 'customer.cancelled', 'Order cancelled', 'Your unpaid order and item reservations were cancelled.'),
  ('RECOVERY_STARTED', 'CUSTOMER', 'customer.recovery_started', 'We are fixing an item issue', 'Dastak is securing the same exact item.'),
  ('RECOVERY_SUCCEEDED', 'CUSTOMER', 'customer.recovery_succeeded', 'Exact item secured', 'Your order can continue without a substitution.'),
  ('RECOVERY_FAILED', 'CUSTOMER', 'customer.recovery_failed', 'Item recovery update', 'The exact item could not be recovered. Refund handling is in progress.'),
  ('DELIVERY_RECOVERY_STARTED', 'CUSTOMER', 'customer.delivery_recovery', 'Delivery support is helping', 'Operations is resolving a delivery problem.'),
  ('CUSTOMER_ISSUE_REPORTED', 'CUSTOMER', 'customer.issue_reported', 'Issue received', 'Support has received your report and evidence.'),
  ('REFUND_CREATED', 'CUSTOMER', 'customer.refund_started', 'Refund started', 'Your original-payment-method refund is being processed.'),
  ('REFUND_COMPLETED', 'CUSTOMER', 'customer.refund_completed', 'Refund completed', 'Your refund was completed to the original payment method.'),
  ('RETURN_APPROVED', 'CUSTOMER', 'customer.return_approved', 'Return approved', 'Follow the in-app return steps and keep every package ready.'),
  ('RETURN_RIDER_ASSIGNED', 'CUSTOMER', 'customer.return_rider_assigned', 'Return pickup assigned', 'A delivery partner was assigned to collect your return.'),
  ('RETURN_PICKUP_VERIFIED', 'CUSTOMER', 'customer.return_picked_up', 'Return collected', 'Your return packages are on their way back.'),
  ('RETURN_RECEIPT_VERIFIED', 'CUSTOMER', 'customer.return_received', 'Return received', 'The merchant verified receipt of every return package.'),
  ('MERCHANT_OPPORTUNITY_OFFERED', 'MERCHANT', 'merchant.opportunity', 'New Dastak request', 'Confirm the exact requested items before the timer expires.'),
  ('RECOVERY_OPPORTUNITY_OFFERED', 'MERCHANT', 'merchant.recovery_opportunity', 'Exact-item recovery request', 'Confirm the exact SKU and full quantity before the timer expires.'),
  ('PREPARATION_STARTED', 'MERCHANT', 'merchant.preparation_started', 'Payment confirmed', 'Start preparing the selected fulfilment now.'),
  ('RIDER_ASSIGNED', 'MERCHANT', 'merchant.rider_assigned', 'Rider assigned', 'A delivery partner is heading to the pickup stops.'),
  ('RIDER_ARRIVED_PICKUP', 'MERCHANT', 'merchant.rider_arrived', 'Rider arrived', 'Verify every declared package before handoff.'),
  ('RETURN_RIDER_ASSIGNED', 'MERCHANT', 'merchant.return_incoming', 'Return incoming', 'A return rider will bring packages for verified receipt.'),
  ('RIDER_POOL_OPENED', 'RIDER', 'rider.mission_offer', 'New delivery mission', 'Review the pickup count, route and required transport before accepting.'),
  ('RIDER_ASSIGNED', 'RIDER', 'rider.assigned', 'Mission assigned', 'You won this mission. Continue to the pickup stops.'),
  ('FULFILMENT_READY', 'RIDER', 'rider.fulfilment_ready', 'Pickup is ready', 'A pickup stop has marked every package Ready.'),
  ('RETURN_RIDER_ASSIGNED', 'RIDER', 'rider.return_assigned', 'Return mission assigned', 'Collect and transfer every return package using in-app verification.');

create function dastak_v1.guard_notification_route()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.event_type is distinct from old.event_type
      or new.audience is distinct from old.audience
      or new.notification_type is distinct from old.notification_type
      or new.platform is distinct from old.platform
      or new.created_at is distinct from old.created_at then
      raise exception 'notification route identity cannot change';
    end if;
    if new.version <> old.version + 1 then
      raise exception 'notification route version must increment exactly once';
    end if;
    new.updated_at := pg_catalog.now();
  end if;
  return new;
end;
$$;

create function dastak_v1.guard_notification_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.intent_id is distinct from old.intent_id
    or new.event_id is distinct from old.event_id
    or new.recipient_account_id is distinct from old.recipient_account_id
    or new.device_token_id is distinct from old.device_token_id
    or new.created_at is distinct from old.created_at then
    raise exception 'notification delivery identity cannot change';
  end if;
  if new.attempts < old.attempts then
    raise exception 'notification attempts cannot decrease';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger notification_routes_guard
before update on dastak_v1.notification_routes
for each row execute function dastak_v1.guard_notification_route();
create trigger notification_routes_no_delete
before delete on dastak_v1.notification_routes
for each row execute function dastak_v1.reject_delete();
create trigger notification_intents_immutable
before update or delete on dastak_v1.notification_intents
for each row execute function dastak_v1.reject_mutation();
create trigger notification_deliveries_guard
before update on dastak_v1.notification_deliveries
for each row execute function dastak_v1.guard_notification_delivery();
create trigger notification_deliveries_no_delete
before delete on dastak_v1.notification_deliveries
for each row execute function dastak_v1.reject_delete();

create function dastak_v1_api.event_order_id(p_event_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event dastak_v1.domain_events_outbox%rowtype;
  v_order_id uuid;
  v_text text;
begin
  select event.* into v_event
  from dastak_v1.domain_events_outbox event
  where event.id = p_event_id;
  if not found then return null; end if;
  v_text := v_event.payload ->> 'orderId';
  if v_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return v_text::uuid;
  end if;
  if v_event.aggregate_type = 'ORDER' then return v_event.aggregate_id; end if;
  if v_event.aggregate_type = 'FULFILMENT' then
    select fulfilment.order_id into v_order_id
    from dastak_v1.fulfilments fulfilment where fulfilment.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'DELIVERY_MISSION' then
    select mission.order_id into v_order_id
    from dastak_v1.delivery_missions mission where mission.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'RECOVERY_CASE' then
    select recovery.order_id into v_order_id
    from dastak_v1.recovery_cases recovery where recovery.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'RETURN' then
    select customer_return.order_id into v_order_id
    from dastak_v1.returns customer_return where customer_return.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'RETURN_MISSION' then
    select mission.order_id into v_order_id
    from dastak_v1.return_missions mission where mission.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'REFUND' then
    select refund.order_id into v_order_id
    from dastak_v1.refunds refund where refund.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'CUSTOMER_ISSUE' then
    select issue.order_id into v_order_id
    from dastak_v1.customer_issues issue where issue.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'MERCHANT_OPPORTUNITY' then
    select opportunity.order_id into v_order_id
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'RECOVERY_OPPORTUNITY' then
    select recovery.order_id into v_order_id
    from dastak_v1.recovery_opportunities opportunity
    join dastak_v1.recovery_cases recovery
      on recovery.id = opportunity.recovery_case_id
    where opportunity.id = v_event.aggregate_id;
  end if;
  return v_order_id;
end;
$$;

create function dastak_v1_api.notification_recipients(
  p_event_id uuid,
  p_audience text
)
returns table(account_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event dastak_v1.domain_events_outbox%rowtype;
  v_order_id uuid;
  v_branch_id uuid;
  v_text text;
begin
  select event.* into v_event
  from dastak_v1.domain_events_outbox event
  where event.id = p_event_id;
  if not found then return; end if;
  v_order_id := dastak_v1_api.event_order_id(p_event_id);
  if p_audience = 'CUSTOMER' then
    return query
      select customer_order.customer_id
      from dastak_v1.orders customer_order
      where customer_order.id = v_order_id;
    return;
  end if;
  if p_audience = 'RIDER' then
    v_text := v_event.payload ->> 'riderId';
    if v_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      account_id := v_text::uuid;
      return next;
      return;
    end if;
    if v_event.event_type = 'RIDER_POOL_OPENED' then
      return query
        select distinct offer.rider_id
        from dastak_v1.delivery_offers offer
        where offer.mission_id = v_event.aggregate_id
          and offer.status = 'OFFERED'
          and offer.respond_by > pg_catalog.now();
      return;
    end if;
    return query
      select distinct mission.assigned_rider_id
      from dastak_v1.delivery_missions mission
      where mission.order_id = v_order_id
        and mission.assigned_rider_id is not null
      union
      select distinct return_mission.assigned_rider_id
      from dastak_v1.return_missions return_mission
      where return_mission.order_id = v_order_id
        and return_mission.assigned_rider_id is not null;
    return;
  end if;
  if p_audience <> 'MERCHANT' then return; end if;
  v_text := v_event.payload ->> 'branchId';
  if v_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_branch_id := v_text::uuid;
  elsif v_event.aggregate_type = 'FULFILMENT' then
    select fulfilment.branch_id into v_branch_id
    from dastak_v1.fulfilments fulfilment where fulfilment.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'MERCHANT_OPPORTUNITY' then
    select opportunity.branch_id into v_branch_id
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'RECOVERY_OPPORTUNITY' then
    select opportunity.branch_id into v_branch_id
    from dastak_v1.recovery_opportunities opportunity
    where opportunity.id = v_event.aggregate_id;
  end if;
  return query
    with branches as (
      select v_branch_id as branch_id where v_branch_id is not null
      union
      select fulfilment.branch_id
      from dastak_v1.fulfilments fulfilment
      where v_branch_id is null
        and fulfilment.order_id = v_order_id
        and fulfilment.status <> 'RELEASED'
    )
    select distinct merchant_user.account_id
    from branches
    join dastak_v1.merchant_branches branch on branch.id = branches.branch_id
    join dastak_v1.merchant_users merchant_user
      on merchant_user.organization_id = branch.organization_id
      and merchant_user.status = 'ACTIVE'
    where dastak_v1_api.actor_has_merchant_permission(
      merchant_user.account_id,
      branch.organization_id,
      case when v_event.event_type in (
        'MERCHANT_OPPORTUNITY_OFFERED', 'RECOVERY_OPPORTUNITY_OFFERED'
      ) then 'merchant.opportunities.respond' else 'merchant.fulfilment.manage' end,
      branch.id
    );
end;
$$;

create function dastak_v1_api.fanout_pending_outbox_events(
  p_worker_id text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event dastak_v1.domain_events_outbox%rowtype;
  v_route dastak_v1.notification_routes%rowtype;
  v_recipient record;
  v_intent_id uuid;
  v_order_id uuid;
  v_event_count integer := 0;
  v_intent_count integer := 0;
  v_delivery_count integer := 0;
  v_inserted integer;
  v_max_attempts integer;
  v_stale_seconds integer;
  v_error text;
begin
  if nullif(pg_catalog.btrim(p_worker_id), '') is null
    or p_limit not between 1 and 500 then
    raise exception using errcode = '22023', message = 'invalid worker claim';
  end if;
  v_max_attempts := (
    dastak_v1_api.effective_setting_json('notifications.outbox_max_attempts') #>> '{}'
  )::integer;
  v_stale_seconds := (
    dastak_v1_api.effective_setting_json('notifications.claim_stale_seconds') #>> '{}'
  )::integer;
  for v_event in
    select event.*
    from dastak_v1.domain_events_outbox event
    where event.status = 'PENDING'
      and event.available_at <= pg_catalog.clock_timestamp()
      and (
        event.locked_at is null
        or event.locked_at <= pg_catalog.clock_timestamp()
          - pg_catalog.make_interval(secs => v_stale_seconds)
      )
    order by event.available_at, event.occurred_at, event.id
    for update skip locked
    limit p_limit
  loop
    begin
      update dastak_v1.domain_events_outbox event
      set locked_at = pg_catalog.clock_timestamp(), locked_by = p_worker_id,
          attempts = event.attempts + 1, last_error = null
      where event.id = v_event.id;
      v_order_id := dastak_v1_api.event_order_id(v_event.id);
      for v_route in
        select route.* from dastak_v1.notification_routes route
        where route.event_type = v_event.event_type and route.enabled
      loop
        for v_recipient in
          select recipient.account_id
          from dastak_v1_api.notification_recipients(
            v_event.id, v_route.audience
          ) recipient
        loop
          insert into dastak_v1.notification_intents (
            event_id, recipient_account_id, notification_type,
            platform, title, body, payload
          ) values (
            v_event.id, v_recipient.account_id, v_route.notification_type,
            v_route.platform, v_route.title, v_route.body,
            pg_catalog.jsonb_build_object(
              'entityType', 'dastakV1Order',
              'entityId', v_order_id,
              'orderId', v_order_id,
              'eventType', v_event.event_type
            )
          )
          on conflict (event_id, recipient_account_id, notification_type)
          do nothing
          returning id into v_intent_id;
          if v_intent_id is null then
            select intent.id into v_intent_id
            from dastak_v1.notification_intents intent
            where intent.event_id = v_event.id
              and intent.recipient_account_id = v_recipient.account_id
              and intent.notification_type = v_route.notification_type;
          else
            v_intent_count := v_intent_count + 1;
          end if;
          insert into dastak_v1.notification_deliveries (
            intent_id, event_id, recipient_account_id, device_token_id
          )
          select v_intent_id, v_event.id, v_recipient.account_id, token.id
          from public.dastak_device_tokens token
          where token.account_id = v_recipient.account_id
            and token.platform = v_route.platform
            and token.disabled_at is null
          on conflict (intent_id, device_token_id) do nothing;
          get diagnostics v_inserted = row_count;
          v_delivery_count := v_delivery_count + v_inserted;
          v_intent_id := null;
        end loop;
      end loop;
      update dastak_v1.domain_events_outbox event
      set status = 'PUBLISHED', published_at = pg_catalog.clock_timestamp(),
          locked_at = null, locked_by = null, last_error = null
      where event.id = v_event.id;
      v_event_count := v_event_count + 1;
    exception when others then
      get stacked diagnostics v_error = message_text;
      update dastak_v1.domain_events_outbox event
      set status = case
            when event.attempts >= v_max_attempts
              then 'DEAD_LETTER'::dastak_v1.outbox_status
            else 'PENDING'::dastak_v1.outbox_status
          end,
          available_at = pg_catalog.clock_timestamp()
            + pg_catalog.make_interval(secs => least(3600, 15 * (2 ^ least(event.attempts, 8))::integer)),
          locked_at = null, locked_by = null,
          last_error = pg_catalog.left(v_error, 1000)
      where event.id = v_event.id;
    end;
  end loop;
  return pg_catalog.jsonb_build_object(
    'eventsPublished', v_event_count,
    'intentsCreated', v_intent_count,
    'deliveriesCreated', v_delivery_count
  );
end;
$$;

create function dastak_v1_api.claim_notification_deliveries(
  p_worker_id text,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stale_seconds integer;
  v_jobs jsonb;
begin
  if nullif(pg_catalog.btrim(p_worker_id), '') is null
    or p_limit not between 1 and 500 then
    raise exception using errcode = '22023', message = 'invalid delivery claim';
  end if;
  v_stale_seconds := (
    dastak_v1_api.effective_setting_json('notifications.claim_stale_seconds') #>> '{}'
  )::integer;
  update dastak_v1.notification_deliveries delivery
  set status = 'PENDING', locked_at = null, locked_by = null,
      available_at = pg_catalog.clock_timestamp(),
      last_error = 'stale worker claim recovered'
  where delivery.status = 'IN_FLIGHT'
    and delivery.locked_at <= pg_catalog.clock_timestamp()
      - pg_catalog.make_interval(secs => v_stale_seconds);
  update dastak_v1.notification_deliveries delivery
  set status = 'SUPPRESSED', locked_at = null, locked_by = null,
      last_error = 'device token disabled'
  from public.dastak_device_tokens token
  where delivery.device_token_id = token.id
    and delivery.status = 'PENDING'
    and token.disabled_at is not null;
  with candidates as (
    select delivery.id
    from dastak_v1.notification_deliveries delivery
    join public.dastak_device_tokens token on token.id = delivery.device_token_id
    where delivery.status = 'PENDING'
      and delivery.available_at <= pg_catalog.clock_timestamp()
      and token.disabled_at is null
    order by delivery.available_at, delivery.created_at, delivery.id
    for update of delivery skip locked
    limit p_limit
  ), claimed as (
    update dastak_v1.notification_deliveries delivery
    set status = 'IN_FLIGHT', locked_at = pg_catalog.clock_timestamp(),
        locked_by = p_worker_id, attempts = delivery.attempts + 1,
        last_error = null
    from candidates
    where delivery.id = candidates.id
    returning delivery.*
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'deliveryId', claimed.id,
      'eventId', claimed.event_id,
      'notificationType', intent.notification_type,
      'recipientAccountId', claimed.recipient_account_id,
      'deviceToken', token.device_token,
      'platform', token.platform,
      'title', intent.title,
      'body', intent.body,
      'payload', intent.payload,
      'attempt', claimed.attempts
    ) order by claimed.created_at, claimed.id
  ), '[]'::jsonb) into v_jobs
  from claimed
  join dastak_v1.notification_intents intent on intent.id = claimed.intent_id
  join public.dastak_device_tokens token on token.id = claimed.device_token_id;
  return v_jobs;
end;
$$;

create function dastak_v1_api.complete_notification_delivery(
  p_delivery_id uuid,
  p_worker_id text,
  p_succeeded boolean,
  p_permanent_token_failure boolean,
  p_provider_status integer,
  p_provider_response text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery dastak_v1.notification_deliveries%rowtype;
  v_max_attempts integer;
  v_retry_base integer;
  v_delay integer;
begin
  if p_delivery_id is null or nullif(pg_catalog.btrim(p_worker_id), '') is null
    or p_succeeded is null or p_permanent_token_failure is null then
    raise exception using errcode = '22023', message = 'invalid delivery completion';
  end if;
  select delivery.* into v_delivery
  from dastak_v1.notification_deliveries delivery
  where delivery.id = p_delivery_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'delivery not found'; end if;
  if v_delivery.status in ('SENT', 'DEAD_LETTER', 'SUPPRESSED') then
    return pg_catalog.jsonb_build_object(
      'deliveryId', v_delivery.id, 'status', v_delivery.status,
      'idempotentReplay', true
    );
  end if;
  if v_delivery.status <> 'IN_FLIGHT' or v_delivery.locked_by <> p_worker_id then
    raise exception using errcode = '40001', message = 'delivery claim lost';
  end if;
  v_max_attempts := (
    dastak_v1_api.effective_setting_json('notifications.delivery_max_attempts') #>> '{}'
  )::integer;
  v_retry_base := (
    dastak_v1_api.effective_setting_json('notifications.retry_base_seconds') #>> '{}'
  )::integer;
  if p_succeeded then
    update dastak_v1.notification_deliveries delivery
    set status = 'SENT', locked_at = null, locked_by = null,
        provider_status = p_provider_status,
        provider_response = pg_catalog.left(p_provider_response, 1000),
        last_error = null, sent_at = pg_catalog.clock_timestamp()
    where delivery.id = v_delivery.id
    returning * into v_delivery;
  elsif p_permanent_token_failure or v_delivery.attempts >= v_max_attempts then
    update dastak_v1.notification_deliveries delivery
    set status = 'DEAD_LETTER', locked_at = null, locked_by = null,
        provider_status = p_provider_status,
        provider_response = pg_catalog.left(p_provider_response, 1000),
        last_error = case when p_permanent_token_failure
          then 'permanent device token failure'
          else 'delivery retry limit reached' end
    where delivery.id = v_delivery.id
    returning * into v_delivery;
    if p_permanent_token_failure then
      update public.dastak_device_tokens token
      set disabled_at = coalesce(token.disabled_at, pg_catalog.clock_timestamp()),
          disabled_reason = coalesce(token.disabled_reason, 'provider rejected device token'),
          version = case when token.disabled_at is null then token.version + 1 else token.version end
      where token.id = v_delivery.device_token_id;
      update dastak_v1.notification_deliveries delivery
      set status = 'SUPPRESSED', last_error = 'device token disabled'
      where delivery.device_token_id = v_delivery.device_token_id
        and delivery.status = 'PENDING';
    end if;
  else
    v_delay := least(
      3600,
      v_retry_base * (2 ^ least(v_delivery.attempts - 1, 8))::integer
    );
    update dastak_v1.notification_deliveries delivery
    set status = 'PENDING', locked_at = null, locked_by = null,
        available_at = pg_catalog.clock_timestamp()
          + pg_catalog.make_interval(secs => v_delay),
        provider_status = p_provider_status,
        provider_response = pg_catalog.left(p_provider_response, 1000),
        last_error = 'provider delivery failed'
    where delivery.id = v_delivery.id
    returning * into v_delivery;
  end if;
  return pg_catalog.jsonb_build_object(
    'deliveryId', v_delivery.id, 'status', v_delivery.status,
    'attempts', v_delivery.attempts, 'availableAt', v_delivery.available_at
  );
end;
$$;

create type dastak_v1.invariant_incident_status as enum ('OPEN', 'RESOLVED');

create table dastak_v1.invariant_definitions (
  invariant_key text primary key,
  description text not null,
  severity text not null default 'CRITICAL' check (severity = 'CRITICAL'),
  created_at timestamptz not null default pg_catalog.now()
);

create table dastak_v1.invariant_monitor_runs (
  id uuid primary key default gen_random_uuid(),
  worker_id text not null,
  finding_count integer not null check (finding_count >= 0),
  started_at timestamptz not null,
  completed_at timestamptz not null check (completed_at >= started_at),
  created_at timestamptz not null default pg_catalog.now()
);

create table dastak_v1.invariant_incidents (
  id uuid primary key default gen_random_uuid(),
  invariant_key text not null references dastak_v1.invariant_definitions(invariant_key),
  entity_type text not null,
  entity_id uuid not null,
  details jsonb not null check (pg_catalog.jsonb_typeof(details) = 'object'),
  status dastak_v1.invariant_incident_status not null default 'OPEN',
  occurrence_count integer not null default 1 check (occurrence_count >= 1),
  first_detected_at timestamptz not null,
  last_detected_at timestamptz not null,
  resolved_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status = 'OPEN' and resolved_at is null)
    or (status = 'RESOLVED' and resolved_at is not null)
  )
);

create unique index invariant_incidents_open_uidx
  on dastak_v1.invariant_incidents (invariant_key, entity_id)
  where status = 'OPEN';
create index invariant_incidents_definition_idx
  on dastak_v1.invariant_incidents (invariant_key);
create index invariant_incidents_health_idx
  on dastak_v1.invariant_incidents (status, last_detected_at desc, id);

create table dastak_v1.invariant_incident_history (
  id bigint generated always as identity primary key,
  incident_id uuid not null references dastak_v1.invariant_incidents(id),
  action text not null check (action in ('DETECTED', 'REPEATED', 'RESOLVED')),
  incident_snapshot jsonb not null check (
    pg_catalog.jsonb_typeof(incident_snapshot) = 'object'
  ),
  occurred_at timestamptz not null default pg_catalog.now()
);

create index invariant_incident_history_incident_idx
  on dastak_v1.invariant_incident_history (incident_id, occurred_at, id);

insert into dastak_v1.invariant_definitions (invariant_key, description) values
  ('ORDER_MULTIPLE_ACTIVE_MISSIONS', 'Customer order has more than one active delivery mission.'),
  ('RIDER_MULTIPLE_ACTIVE_MISSIONS', 'Rider has more than one active customer-order mission.'),
  ('RETAIL_LINE_MULTIPLE_FINAL_MERCHANTS', 'Retail line has more than one active final merchant fulfilment.'),
  ('RETAIL_HARD_CAPACITY_EXCEEDED', 'Retail branch has more hard capacity slots than its configured limit.'),
  ('PICKED_UP_FULFILMENT_PACKAGE_MISMATCH', 'Picked-up fulfilment does not contain every declared package.'),
  ('DELIVERED_WITHOUT_FINAL_VERIFICATION', 'Delivered order lacks Consumed or Overridden final verification.'),
  ('PAID_WITHOUT_SUCCESSFUL_PAYMENT', 'Paid order has no successful payment truth.'),
  ('PAYMENT_EXPIRED_AFTER_PREPARATION', 'Payment-expired order has preparation timestamps.'),
  ('CONTRADICTORY_PACKAGE_CUSTODY', 'Package lifecycle status contradicts current custody truth.');

create function dastak_v1.record_invariant_incident_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into dastak_v1.invariant_incident_history (
    incident_id, action, incident_snapshot
  ) values (
    new.id,
    case
      when tg_op = 'INSERT' then 'DETECTED'
      when old.status = 'OPEN' and new.status = 'RESOLVED' then 'RESOLVED'
      else 'REPEATED'
    end,
    pg_catalog.to_jsonb(new)
  );
  return new;
end;
$$;

create trigger invariant_incidents_history
after insert or update on dastak_v1.invariant_incidents
for each row execute function dastak_v1.record_invariant_incident_history();
create trigger invariant_definitions_immutable
before update or delete on dastak_v1.invariant_definitions
for each row execute function dastak_v1.reject_mutation();
create trigger invariant_monitor_runs_immutable
before update or delete on dastak_v1.invariant_monitor_runs
for each row execute function dastak_v1.reject_mutation();
create trigger invariant_incidents_no_delete
before delete on dastak_v1.invariant_incidents
for each row execute function dastak_v1.reject_delete();
create trigger invariant_incident_history_immutable
before update or delete on dastak_v1.invariant_incident_history
for each row execute function dastak_v1.reject_mutation();

create function dastak_v1_api.run_invariant_monitors(p_worker_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_id uuid;
  v_started_at timestamptz := pg_catalog.clock_timestamp();
  v_now timestamptz;
  v_finding record;
  v_finding_rows jsonb;
  v_findings integer := 0;
  v_open integer;
begin
  if nullif(pg_catalog.btrim(p_worker_id), '') is null then
    raise exception using errcode = '22023', message = 'worker id required';
  end if;
  with finding_rows (invariant_key, entity_type, entity_id, details) as (
  select 'ORDER_MULTIPLE_ACTIVE_MISSIONS', 'ORDER', mission.order_id,
    pg_catalog.jsonb_build_object('activeMissionCount', pg_catalog.count(*))
  from dastak_v1.delivery_missions mission
  where mission.status not in ('DELIVERED', 'CANCELLED')
  group by mission.order_id having pg_catalog.count(*) > 1

  union all
  select 'RIDER_MULTIPLE_ACTIVE_MISSIONS', 'RIDER', mission.assigned_rider_id,
    pg_catalog.jsonb_build_object('activeMissionCount', pg_catalog.count(*))
  from dastak_v1.delivery_missions mission
  where mission.assigned_rider_id is not null
    and mission.status in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    )
  group by mission.assigned_rider_id having pg_catalog.count(*) > 1

  union all
  select 'RETAIL_LINE_MULTIPLE_FINAL_MERCHANTS', 'ORDER_LINE', line.id,
    pg_catalog.jsonb_build_object(
      'activeMerchantCount', pg_catalog.count(distinct fulfilment.branch_id)
    )
  from dastak_v1.order_lines line
  join dastak_v1.fulfilment_lines fulfilment_line
    on fulfilment_line.order_line_id = line.id
  join dastak_v1.fulfilments fulfilment
    on fulfilment.id = fulfilment_line.fulfilment_id
  where line.line_type = 'RETAIL_SKU'
    and fulfilment.status <> 'RELEASED'
  group by line.id
  having pg_catalog.count(distinct fulfilment.branch_id) > 1

  union all
  select 'RETAIL_HARD_CAPACITY_EXCEEDED', 'MERCHANT_BRANCH', branch.id,
    pg_catalog.jsonb_build_object(
      'activeSlots', pg_catalog.count(slot.id),
      'capacityLimit', branch.capacity_limit
    )
  from dastak_v1.merchant_branches branch
  join dastak_v1.retail_capacity_slots slot
    on slot.branch_id = branch.id and slot.status = 'HELD'
  group by branch.id, branch.capacity_limit
  having pg_catalog.count(slot.id) > branch.capacity_limit

  union all
  select 'PICKED_UP_FULFILMENT_PACKAGE_MISMATCH', 'FULFILMENT', fulfilment.id,
    pg_catalog.jsonb_build_object(
      'declaredPackageCount', fulfilment.package_count,
      'actualPackageCount', pg_catalog.count(package.id),
      'pickedPackageCount', pg_catalog.count(package.id) filter (
        where package.status in ('PICKED_UP', 'IN_TRANSIT', 'DELIVERED', 'RECOVERY', 'RETURN_PENDING', 'RETURNED')
      )
    )
  from dastak_v1.fulfilments fulfilment
  left join dastak_v1.packages package on package.fulfilment_id = fulfilment.id
  where fulfilment.status in ('PICKED_UP', 'COMPLETED')
  group by fulfilment.id, fulfilment.package_count
  having fulfilment.package_count is null
    or pg_catalog.count(package.id) <> fulfilment.package_count
    or pg_catalog.count(package.id) filter (
      where package.status in ('PICKED_UP', 'IN_TRANSIT', 'DELIVERED', 'RECOVERY', 'RETURN_PENDING', 'RETURNED')
    ) <> fulfilment.package_count

  union all
  select 'DELIVERED_WITHOUT_FINAL_VERIFICATION', 'ORDER', customer_order.id,
    pg_catalog.jsonb_build_object('orderStatus', customer_order.status)
  from dastak_v1.orders customer_order
  where customer_order.status = 'DELIVERED'
    and not exists (
      select 1 from dastak_v1.verification_handoffs handoff
      where handoff.order_id = customer_order.id
        and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
        and handoff.status in ('CONSUMED', 'OVERRIDDEN')
    )

  union all
  select 'PAID_WITHOUT_SUCCESSFUL_PAYMENT', 'ORDER', customer_order.id,
    pg_catalog.jsonb_build_object('orderStatus', customer_order.status)
  from dastak_v1.orders customer_order
  where customer_order.paid_at is not null
    and customer_order.status not in ('PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT')
    and not exists (
      select 1 from dastak_v1.payments payment
      where payment.order_id = customer_order.id and payment.status = 'SUCCEEDED'
    )

  union all
  select 'PAYMENT_EXPIRED_AFTER_PREPARATION', 'ORDER', customer_order.id,
    pg_catalog.jsonb_build_object(
      'prepStartedCount', pg_catalog.count(fulfilment.id) filter (
        where fulfilment.prep_started_at is not null
      )
    )
  from dastak_v1.orders customer_order
  join dastak_v1.fulfilments fulfilment on fulfilment.order_id = customer_order.id
  where customer_order.status = 'PAYMENT_EXPIRED'
  group by customer_order.id
  having pg_catalog.count(fulfilment.id) filter (
    where fulfilment.prep_started_at is not null
  ) > 0

  union all
  select 'CONTRADICTORY_PACKAGE_CUSTODY', 'PACKAGE', package.id,
    pg_catalog.jsonb_build_object(
      'packageStatus', package.status,
      'custodyOwnerType', package.current_custody_owner_type
    )
  from dastak_v1.packages package
  where (package.status in ('DECLARED', 'READY')
      and package.current_custody_owner_type <> 'MERCHANT_BRANCH')
    or (package.status in ('PICKED_UP', 'IN_TRANSIT')
      and package.current_custody_owner_type <> 'RIDER')
    or (package.status = 'DELIVERED'
      and package.current_custody_owner_type <> 'CUSTOMER')
  )
  select coalesce(
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(finding)), '[]'::jsonb
  ) into v_finding_rows
  from finding_rows finding;

  v_now := greatest(pg_catalog.clock_timestamp(), v_started_at);
  for v_finding in
    select finding.*
    from pg_catalog.jsonb_to_recordset(v_finding_rows) as finding(
      invariant_key text, entity_type text, entity_id uuid, details jsonb
    )
  loop
    update dastak_v1.invariant_incidents incident
    set details = v_finding.details,
        occurrence_count = incident.occurrence_count + 1,
        last_detected_at = v_now,
        updated_at = v_now,
        version = incident.version + 1
    where incident.invariant_key = v_finding.invariant_key
      and incident.entity_id = v_finding.entity_id
      and incident.status = 'OPEN';
    if not found then
      insert into dastak_v1.invariant_incidents (
        invariant_key, entity_type, entity_id, details,
        first_detected_at, last_detected_at
      ) values (
        v_finding.invariant_key, v_finding.entity_type,
        v_finding.entity_id, v_finding.details, v_now, v_now
      );
    end if;
    v_findings := v_findings + 1;
  end loop;
  update dastak_v1.invariant_incidents incident
  set status = 'RESOLVED', resolved_at = v_now,
      updated_at = v_now, version = incident.version + 1
  where incident.status = 'OPEN'
    and not exists (
      select 1
      from pg_catalog.jsonb_to_recordset(v_finding_rows) as finding(
        invariant_key text, entity_type text, entity_id uuid, details jsonb
      )
      where finding.invariant_key = incident.invariant_key
        and finding.entity_id = incident.entity_id
    );
  insert into dastak_v1.invariant_monitor_runs (
    worker_id, finding_count, started_at, completed_at
  ) values (
    pg_catalog.btrim(p_worker_id), v_findings, v_started_at, v_now
  ) returning id into v_run_id;
  select pg_catalog.count(*) into v_open
  from dastak_v1.invariant_incidents incident where incident.status = 'OPEN';
  return pg_catalog.jsonb_build_object(
    'runId', v_run_id, 'findingCount', v_findings,
    'openCriticalIncidentCount', v_open,
    'healthy', v_open = 0, 'completedAt', v_now
  );
end;
$$;

create function dastak_v1_api.system_health_snapshot(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_open integer;
  v_outbox_pending integer;
  v_outbox_dead integer;
  v_notification_pending integer;
  v_notification_in_flight integer;
  v_notification_dead integer;
  v_reconciliation_open integer;
  v_oldest_outbox_seconds integer;
  v_outbox_stale_threshold integer;
  v_worker_configured boolean;
  v_last_run jsonb;
  v_incidents jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.system_health.read'
  );
  select pg_catalog.count(*) filter (where event.status = 'PENDING'),
    pg_catalog.count(*) filter (where event.status = 'DEAD_LETTER'),
    coalesce(extract(epoch from (
      pg_catalog.clock_timestamp() - (
        pg_catalog.min(event.occurred_at)
          filter (where event.status = 'PENDING')
      )
    ))::integer, 0)
  into v_outbox_pending, v_outbox_dead, v_oldest_outbox_seconds
  from dastak_v1.domain_events_outbox event;
  v_outbox_stale_threshold := (
    dastak_v1_api.effective_setting_json('observability.outbox_stale_seconds') #>> '{}'
  )::integer;
  select pg_catalog.count(*) filter (where delivery.status = 'PENDING'),
    pg_catalog.count(*) filter (where delivery.status = 'IN_FLIGHT'),
    pg_catalog.count(*) filter (where delivery.status = 'DEAD_LETTER')
  into v_notification_pending, v_notification_in_flight, v_notification_dead
  from dastak_v1.notification_deliveries delivery;
  select pg_catalog.count(*) into v_open
  from dastak_v1.invariant_incidents incident where incident.status = 'OPEN';
  select pg_catalog.count(*) into v_reconciliation_open
  from dastak_v1.payment_reconciliation_cases reconciliation
  where reconciliation.status = 'OPEN';
  select pg_catalog.jsonb_build_object(
    'id', run.id, 'findingCount', run.finding_count,
    'startedAt', run.started_at, 'completedAt', run.completed_at
  ) into v_last_run
  from dastak_v1.invariant_monitor_runs run
  order by run.completed_at desc, run.id desc limit 1;
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'id', incident.id, 'invariantKey', incident.invariant_key,
      'entityType', incident.entity_type, 'entityId', incident.entity_id,
      'details', incident.details,
      'firstDetectedAt', incident.first_detected_at,
      'lastDetectedAt', incident.last_detected_at,
      'occurrenceCount', incident.occurrence_count
    ) order by incident.last_detected_at desc, incident.id
  ), '[]'::jsonb) into v_incidents
  from dastak_v1.invariant_incidents incident where incident.status = 'OPEN';
  select coalesce(pg_catalog.bool_or(job.active), false)
  into v_worker_configured
  from cron.job job
  where job.jobname = 'dastak-v1-outbox-worker';
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, metadata
  ) values (
    p_actor_id, 'SYSTEM_HEALTH_READ', 'system_health',
    pg_catalog.jsonb_build_object('openCriticalIncidentCount', v_open)
  );
  return pg_catalog.jsonb_build_object(
    'healthy', v_open = 0 and v_outbox_dead = 0
      and v_notification_dead = 0 and v_worker_configured
      and v_oldest_outbox_seconds <= v_outbox_stale_threshold
      and v_reconciliation_open = 0,
    'workerConfigured', v_worker_configured,
    'openCriticalIncidentCount', v_open,
    'incidents', v_incidents,
    'lastMonitorRun', v_last_run,
    'outbox', pg_catalog.jsonb_build_object(
      'pending', v_outbox_pending, 'deadLetter', v_outbox_dead,
      'oldestPendingSeconds', v_oldest_outbox_seconds,
      'staleThresholdSeconds', v_outbox_stale_threshold
    ),
    'notifications', pg_catalog.jsonb_build_object(
      'pending', v_notification_pending, 'inFlight', v_notification_in_flight,
      'deadLetter', v_notification_dead
    ),
    'paymentReconciliationOpen', v_reconciliation_open,
    'observedAt', pg_catalog.clock_timestamp()
  );
end;
$$;

create function public.dastak_v1_fanout_outbox(
  p_worker_id text,
  p_limit integer default 50
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select dastak_v1_api.fanout_pending_outbox_events(p_worker_id, p_limit);
$$;

create function public.dastak_v1_register_device_token(
  p_account_id uuid,
  p_device_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_account_id is null
    or nullif(pg_catalog.btrim(p_device_token), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_device_token)) > 512
    or p_platform not in ('ios', 'web') then
    raise exception using errcode = '22023', message = 'invalid device token';
  end if;
  insert into public.dastak_device_tokens (
    account_id, device_token, platform, last_seen_at
  ) values (
    p_account_id, pg_catalog.btrim(p_device_token), p_platform,
    pg_catalog.clock_timestamp()
  )
  on conflict (device_token) do update
  set account_id = excluded.account_id,
      platform = excluded.platform,
      last_seen_at = excluded.last_seen_at,
      disabled_at = null,
      disabled_reason = null,
      version = public.dastak_device_tokens.version + 1;
end;
$$;

create function public.dastak_v1_claim_notification_deliveries(
  p_worker_id text,
  p_limit integer default 50
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select dastak_v1_api.claim_notification_deliveries(p_worker_id, p_limit);
$$;

create function public.dastak_v1_complete_notification_delivery(
  p_delivery_id uuid,
  p_worker_id text,
  p_succeeded boolean,
  p_permanent_token_failure boolean,
  p_provider_status integer,
  p_provider_response text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select dastak_v1_api.complete_notification_delivery(
    p_delivery_id, p_worker_id, p_succeeded, p_permanent_token_failure,
    p_provider_status, p_provider_response
  );
$$;

create function public.dastak_v1_run_invariant_monitors(p_worker_id text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select dastak_v1_api.run_invariant_monitors(p_worker_id);
$$;

create function public.dastak_v1_admin_system_health()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select dastak_v1_api.system_health_snapshot(auth.uid());
$$;

alter table dastak_v1.notification_routes enable row level security;
alter table dastak_v1.notification_intents enable row level security;
alter table dastak_v1.notification_deliveries enable row level security;
alter table dastak_v1.invariant_definitions enable row level security;
alter table dastak_v1.invariant_monitor_runs enable row level security;
alter table dastak_v1.invariant_incidents enable row level security;
alter table dastak_v1.invariant_incident_history enable row level security;

revoke all on table dastak_v1.notification_routes,
  dastak_v1.notification_intents,
  dastak_v1.notification_deliveries,
  dastak_v1.invariant_definitions,
  dastak_v1.invariant_monitor_runs,
  dastak_v1.invariant_incidents,
  dastak_v1.invariant_incident_history
from public, anon, authenticated, service_role;
revoke all on sequence dastak_v1.invariant_incident_history_id_seq
from public, anon, authenticated, service_role;
grant select on table dastak_v1.notification_routes,
  dastak_v1.notification_intents,
  dastak_v1.notification_deliveries,
  dastak_v1.invariant_definitions,
  dastak_v1.invariant_monitor_runs,
  dastak_v1.invariant_incidents,
  dastak_v1.invariant_incident_history
to service_role;
grant select on table public.dastak_device_tokens to service_role;

revoke all on function dastak_v1_api.grant_platform_permission_bundle(uuid,uuid,uuid,text,text),
  dastak_v1_api.revoke_platform_permission_grant(uuid,uuid,bigint,text,text),
  dastak_v1_api.event_order_id(uuid),
  dastak_v1_api.notification_recipients(uuid,text),
  dastak_v1_api.fanout_pending_outbox_events(text,integer),
  dastak_v1_api.claim_notification_deliveries(text,integer),
  dastak_v1_api.complete_notification_delivery(uuid,text,boolean,boolean,integer,text),
  dastak_v1_api.run_invariant_monitors(text),
  dastak_v1_api.system_health_snapshot(uuid)
from public, anon, authenticated;

revoke all on function public.dastak_v1_grant_platform_permission_bundle(uuid,uuid,text,text),
  public.dastak_v1_revoke_platform_permission_grant(uuid,bigint,text,text),
  public.dastak_v1_register_device_token(uuid,text,text),
  public.dastak_v1_fanout_outbox(text,integer),
  public.dastak_v1_claim_notification_deliveries(text,integer),
  public.dastak_v1_complete_notification_delivery(uuid,text,boolean,boolean,integer,text),
  public.dastak_v1_run_invariant_monitors(text),
  public.dastak_v1_admin_system_health()
from public, anon, authenticated, service_role;

grant execute on function public.dastak_v1_grant_platform_permission_bundle(uuid,uuid,text,text),
  public.dastak_v1_revoke_platform_permission_grant(uuid,bigint,text,text),
  public.dastak_v1_admin_system_health()
to authenticated;
grant execute on function public.dastak_v1_fanout_outbox(text,integer),
  public.dastak_v1_register_device_token(uuid,text,text),
  public.dastak_v1_claim_notification_deliveries(text,integer),
  public.dastak_v1_complete_notification_delivery(uuid,text,boolean,boolean,integer,text),
  public.dastak_v1_run_invariant_monitors(text)
to service_role;

-- Retire the legacy non-atomic queue schedule. Install the V1 worker only when
-- both runtime endpoint and internal secret exist in Vault; no URL is hard-coded.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select job.jobid from cron.job job
    where job.jobname in (
      'dastak-order-notification-worker', 'dastak-v1-outbox-worker'
    )
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  if (
    select pg_catalog.count(*) = 2
    from vault.decrypted_secrets secret
    where secret.name in ('dastak_project_url', 'dastak_notification_secret')
      and nullif(pg_catalog.btrim(secret.decrypted_secret), '') is not null
  ) then
    perform cron.schedule(
      'dastak-v1-outbox-worker',
      '* * * * *',
      $worker$
        select net.http_post(
          url := (
            select pg_catalog.rtrim(secret.decrypted_secret, '/')
            from vault.decrypted_secrets secret
            where secret.name = 'dastak_project_url'
          ) || '/functions/v1/process-v1-outbox',
          headers := pg_catalog.jsonb_build_object(
            'Content-Type', 'application/json',
            'x-dastak-internal-secret', (
              select secret.decrypted_secret
              from vault.decrypted_secrets secret
              where secret.name = 'dastak_notification_secret'
            )
          ),
          body := '{}'::jsonb,
          timeout_milliseconds := 55000
        );
      $worker$
    );
  end if;
end;
$$;

comment on table dastak_v1.notification_intents is
  'One immutable notification intent per domain event, recipient and notification type.';
comment on table dastak_v1.notification_deliveries is
  'Durable per-device delivery attempts; business state never depends on delivery success.';
comment on table dastak_v1.invariant_incidents is
  'Persistent critical findings from the locked V1 impossible-state monitor set.';
