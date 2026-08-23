-- Dastak V1 customer identity integrity and canonical merchant controls.
-- Additive except for decoupling historical account rows from auth.users deletion.

create type public.account_lifecycle_state as enum (
  'ACTIVE', 'DELETION_PENDING', 'DELETED'
);

alter table public.accounts
  add column account_state public.account_lifecycle_state not null default 'ACTIVE',
  add column deletion_requested_at timestamptz,
  add column anonymized_at timestamptz,
  add column deleted_at timestamptz,
  add constraint accounts_lifecycle_timestamps_check check (
    (account_state = 'ACTIVE'
      and deletion_requested_at is null
      and anonymized_at is null
      and deleted_at is null)
    or (account_state = 'DELETION_PENDING'
      and deletion_requested_at is not null
      and anonymized_at is not null
      and deleted_at is null)
    or (account_state = 'DELETED'
      and deletion_requested_at is not null
      and anonymized_at is not null
      and deleted_at is not null)
  );

-- auth.users is an access credential, not the historical business-account row.
-- Removing the FK lets Auth deletion revoke access without cascading immutable V1 history.
alter table public.accounts drop constraint accounts_id_fkey;

create index accounts_active_idx on public.accounts (id)
  where account_state = 'ACTIVE';

drop policy accounts_select_self on public.accounts;
create policy accounts_select_self on public.accounts
for select to authenticated
using (id = (select auth.uid()) and account_state = 'ACTIVE');

create type private.customer_identity_link_kind as enum ('ORIGIN', 'EXPLICIT');
create type private.customer_identity_link_intent_status as enum (
  'PENDING', 'COMPLETED', 'EXPIRED', 'CANCELLED'
);

create table private.customer_auth_identities (
  account_id uuid not null,
  provider text not null check (provider in ('apple', 'google')),
  provider_subject_digest bytea not null,
  link_kind private.customer_identity_link_kind not null,
  linked_at timestamptz not null default pg_catalog.now(),
  revoked_at timestamptz,
  primary key (account_id, provider),
  unique (provider, provider_subject_digest),
  check (pg_catalog.octet_length(provider_subject_digest) = 32)
);

create index customer_auth_identities_active_account_idx
  on private.customer_auth_identities (account_id, provider)
  where revoked_at is null;

create table private.customer_identity_link_intents (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  target_provider text not null check (target_provider in ('apple', 'google')),
  requested_by uuid not null references public.accounts(id),
  status private.customer_identity_link_intent_status not null default 'PENDING',
  requested_at timestamptz not null default pg_catalog.now(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  cancelled_at timestamptz,
  check (expires_at > requested_at),
  check (
    (status = 'PENDING' and completed_at is null and cancelled_at is null)
    or (status = 'COMPLETED' and completed_at is not null and cancelled_at is null)
    or (status in ('EXPIRED', 'CANCELLED') and completed_at is null and cancelled_at is not null)
  )
);

create unique index customer_identity_link_intents_pending_uidx
  on private.customer_identity_link_intents (account_id, target_provider)
  where status = 'PENDING';
create index customer_identity_link_intents_expiry_idx
  on private.customer_identity_link_intents (expires_at)
  where status = 'PENDING';

alter table private.customer_auth_identities enable row level security;
alter table private.customer_identity_link_intents enable row level security;
revoke all on table private.customer_auth_identities
  from public, anon, authenticated, service_role;
revoke all on table private.customer_identity_link_intents
  from public, anon, authenticated, service_role;
grant select, insert, update on table private.customer_auth_identities
  to service_role, supabase_auth_admin;
grant select, insert, update on table private.customer_identity_link_intents
  to service_role, supabase_auth_admin;

create policy customer_auth_identities_auth_hook_access
on private.customer_auth_identities for all to supabase_auth_admin
using (true) with check (true);
create policy customer_identity_link_intents_auth_hook_access
on private.customer_identity_link_intents for all to supabase_auth_admin
using (true) with check (true);

-- Existing single-provider OAuth users are safe to register without inferring
-- identity from email or phone. Multi-provider existing users require explicit review.
insert into private.customer_auth_identities (
  account_id, provider, provider_subject_digest, link_kind
)
select identity.user_id,
       identity.provider,
       extensions.digest(identity.provider_id, 'sha256'),
       'ORIGIN'::private.customer_identity_link_kind
from auth.identities identity
where identity.provider in ('apple', 'google')
  and (
    select count(*)
    from auth.identities candidate
    where candidate.user_id = identity.user_id
  ) = 1
on conflict do nothing;

create function public.dastak_before_user_created(event jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_provider text := event -> 'user' -> 'app_metadata' ->> 'provider';
  v_is_anonymous boolean := coalesce(
    (event -> 'user' ->> 'is_anonymous')::boolean,
    false
  );
begin
  if v_is_anonymous or v_provider is null or v_provider not in ('apple', 'google') then
    return pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'http_code', 403,
        'message', 'Dastak customer accounts require Apple or Google sign-in.'
      )
    );
  end if;

  return '{}'::jsonb;
exception
  when invalid_text_representation then
    return pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'http_code', 403,
        'message', 'Dastak customer accounts require Apple or Google sign-in.'
      )
    );
end;
$$;

create function public.dastak_custom_access_token(event jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_account_id uuid;
  v_method text := event ->> 'authentication_method';
  v_current_provider text := event -> 'claims' -> 'app_metadata' ->> 'provider';
  v_identity record;
  v_identity_count integer;
  v_registered_count integer;
  v_intent_id uuid;
  v_account_state public.account_lifecycle_state;
begin
  if v_method not in ('oauth', 'oauth_provider/authorization_code', 'token_refresh') then
    raise exception using
      errcode = '28000',
      message = 'Dastak sessions require Apple or Google OAuth.';
  end if;

  v_account_id := (event ->> 'user_id')::uuid;

  select account.account_state into v_account_state
  from public.accounts account
  where account.id = v_account_id;

  if found and v_account_state <> 'ACTIVE' then
    raise exception using errcode = '28000', message = 'This Dastak account is unavailable.';
  end if;

  if exists (
    select 1 from auth.identities identity
    where identity.user_id = v_account_id
      and identity.provider not in ('apple', 'google')
  ) then
    raise exception using errcode = '28000', message = 'Unsupported Dastak authentication identity.';
  end if;

  select count(*) into v_identity_count
  from auth.identities identity
  where identity.user_id = v_account_id
    and identity.provider in ('apple', 'google');

  if v_identity_count < 1 then
    raise exception using errcode = '28000', message = 'Apple or Google identity required.';
  end if;

  if v_current_provider is not null and v_current_provider not in ('apple', 'google') then
    raise exception using errcode = '28000', message = 'Unsupported Dastak authentication provider.';
  end if;

  select count(*) into v_registered_count
  from private.customer_auth_identities registered
  where registered.account_id = v_account_id
    and registered.revoked_at is null;

  for v_identity in
    select identity.provider,
           extensions.digest(identity.provider_id, 'sha256') as subject_digest
    from auth.identities identity
    where identity.user_id = v_account_id
      and identity.provider in ('apple', 'google')
      and not exists (
        select 1
        from private.customer_auth_identities registered
        where registered.account_id = v_account_id
          and registered.provider = identity.provider
          and registered.provider_subject_digest = extensions.digest(identity.provider_id, 'sha256')
          and registered.revoked_at is null
      )
    order by identity.created_at, identity.id
  loop
    if v_registered_count = 0 and v_identity_count = 1 then
      insert into private.customer_auth_identities (
        account_id, provider, provider_subject_digest, link_kind
      ) values (
        v_account_id, v_identity.provider, v_identity.subject_digest, 'ORIGIN'
      );
      v_registered_count := 1;
      continue;
    end if;

    select intent.id into v_intent_id
    from private.customer_identity_link_intents intent
    where intent.account_id = v_account_id
      and intent.target_provider = v_identity.provider
      and intent.status = 'PENDING'
      and intent.expires_at > pg_catalog.now()
    order by intent.requested_at desc
    limit 1
    for update;

    if not found then
      raise exception using
        errcode = '28000',
        message = 'A second identity must be linked from the signed-in Dastak account.';
    end if;

    insert into private.customer_auth_identities (
      account_id, provider, provider_subject_digest, link_kind
    ) values (
      v_account_id, v_identity.provider, v_identity.subject_digest, 'EXPLICIT'
    );

    update private.customer_identity_link_intents
    set status = 'COMPLETED', completed_at = pg_catalog.now()
    where id = v_intent_id;

    v_registered_count := v_registered_count + 1;
  end loop;

  if v_registered_count <> v_identity_count then
    raise exception using errcode = '28000', message = 'Dastak identity registration is inconsistent.';
  end if;

  return pg_catalog.jsonb_build_object('claims', event -> 'claims');
end;
$$;

grant usage on schema private to supabase_auth_admin;
grant select on table public.accounts to supabase_auth_admin;
grant select on table auth.identities to supabase_auth_admin;
grant execute on function public.dastak_before_user_created(jsonb) to supabase_auth_admin;
grant execute on function public.dastak_custom_access_token(jsonb) to supabase_auth_admin;
revoke execute on function public.dastak_before_user_created(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function public.dastak_custom_access_token(jsonb)
  from public, anon, authenticated, service_role;

create function public.dastak_customer_identity_snapshot()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'providers', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'provider', identity.provider,
            'linkKind', identity.link_kind,
            'linkedAt', identity.linked_at
          ) order by identity.provider
        )
        from private.customer_auth_identities identity
        where identity.account_id = auth.uid()
          and identity.revoked_at is null
      ),
      '[]'::jsonb
    )
  )
  where exists (
    select 1 from public.accounts account
    join private.account_memberships membership
      on membership.account_id = account.id
      and membership.role = 'customer'
      and membership.approved_at is null
      and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
    where account.id = auth.uid()
      and account.account_state = 'ACTIVE'
  );
$$;

create function public.dastak_begin_customer_identity_link(
  p_target_provider text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_intent private.customer_identity_link_intents%rowtype;
begin
  if v_actor_id is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if p_target_provider not in ('apple', 'google')
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid provider and idempotency key required';
  end if;
  if not exists (
    select 1 from public.accounts account
    join private.account_memberships membership
      on membership.account_id = account.id
      and membership.role = 'customer'
      and membership.approved_at is null
      and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
    where account.id = v_actor_id and account.account_state = 'ACTIVE'
  ) then
    raise exception using errcode = '42501', message = 'active customer account required';
  end if;
  if exists (
    select 1 from private.customer_auth_identities identity
    where identity.account_id = v_actor_id
      and identity.provider = p_target_provider
      and identity.revoked_at is null
  ) then
    raise exception using errcode = '22023', message = 'provider is already linked';
  end if;

  update private.customer_identity_link_intents intent
  set status = 'EXPIRED', cancelled_at = pg_catalog.now()
  where intent.account_id = v_actor_id
    and intent.target_provider = p_target_provider
    and intent.status = 'PENDING'
    and intent.expires_at <= pg_catalog.now();

  insert into private.customer_identity_link_intents (
    account_id, target_provider, requested_by, expires_at
  ) values (
    v_actor_id, p_target_provider, v_actor_id, pg_catalog.now() + interval '10 minutes'
  )
  on conflict (account_id, target_provider) where status = 'PENDING'
  do update set expires_at = greatest(
    private.customer_identity_link_intents.expires_at,
    pg_catalog.now() + interval '10 minutes'
  )
  returning * into v_intent;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    v_actor_id,
    'CUSTOMER_IDENTITY_LINK_REQUESTED',
    'customer_account',
    v_actor_id,
    pg_catalog.jsonb_build_object(
      'provider', p_target_provider,
      'intentId', v_intent.id,
      'expiresAt', v_intent.expires_at,
      'idempotencyKey', p_idempotency_key
    )
  );

  return pg_catalog.jsonb_build_object(
    'provider', v_intent.target_provider,
    'intentId', v_intent.id,
    'expiresAt', v_intent.expires_at
  );
end;
$$;

revoke execute on function public.dastak_customer_identity_snapshot()
  from public, anon;
revoke execute on function public.dastak_begin_customer_identity_link(text, text)
  from public, anon;
grant execute on function public.dastak_customer_identity_snapshot() to authenticated;
grant execute on function public.dastak_begin_customer_identity_link(text, text) to authenticated;

create table private.customer_account_deletions (
  account_id uuid primary key references public.accounts(id),
  idempotency_key text not null,
  state public.account_lifecycle_state not null check (state in ('DELETION_PENDING', 'DELETED')),
  requested_at timestamptz not null default pg_catalog.now(),
  anonymized_at timestamptz not null,
  auth_deleted_at timestamptz,
  completed_at timestamptz,
  unique (account_id, idempotency_key)
);

alter table private.customer_account_deletions enable row level security;
revoke all on table private.customer_account_deletions from public, anon, authenticated;
grant select, insert, update on table private.customer_account_deletions to service_role;

create function public.prepare_customer_account_deletion(
  p_account_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account public.accounts%rowtype;
  v_now timestamptz := pg_catalog.now();
begin
  if p_account_id is null or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'account and idempotency key required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':customer-account-deletion', 0)
  );

  select account.* into v_account
  from public.accounts account
  where account.id = p_account_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'account not found';
  end if;

  if v_account.account_state = 'DELETED' then
    return pg_catalog.jsonb_build_object('prepared', true, 'alreadyDeleted', true);
  end if;

  insert into private.customer_account_deletions (
    account_id, idempotency_key, state, anonymized_at
  ) values (
    p_account_id, pg_catalog.btrim(p_idempotency_key), 'DELETION_PENDING', v_now
  )
  on conflict (account_id) do nothing;

  if not exists (
    select 1 from private.customer_account_deletions deletion
    where deletion.account_id = p_account_id
      and deletion.idempotency_key = pg_catalog.btrim(p_idempotency_key)
  ) then
    raise exception using errcode = '22023', message = 'account deletion is already in progress';
  end if;

  if v_account.account_state = 'ACTIVE' then
    update public.accounts
    set display_name = 'Deleted customer',
        phone_number = '+999000000000000',
        account_state = 'DELETION_PENDING',
        deletion_requested_at = v_now,
        anonymized_at = v_now,
        updated_at = v_now
    where id = p_account_id;

    update private.account_memberships
    set suspended_until = 'infinity'::timestamptz
    where account_id = p_account_id;

    update private.account_sessions
    set ended_at = coalesce(ended_at, v_now)
    where account_id = p_account_id and ended_at is null;

    update public.dastak_device_tokens
    set disabled_at = coalesce(disabled_at, v_now),
        disabled_reason = coalesce(disabled_reason, 'Customer account deletion'),
        version = case when disabled_at is null then version + 1 else version end
    where account_id = p_account_id;

    update private.customer_delivery_addresses
    set label = 'Deleted',
        address = 'Deleted',
        details = 'Deleted',
        building = 'Deleted',
        floor = null,
        landmark = null,
        delivery_notes = null,
        location = extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326),
        is_default = false,
        archived_at = coalesce(archived_at, v_now),
        updated_at = v_now
    where account_id = p_account_id;

    update private.customer_auth_identities
    set revoked_at = coalesce(revoked_at, v_now)
    where account_id = p_account_id and revoked_at is null;

    update private.customer_identity_link_intents
    set status = 'CANCELLED', cancelled_at = v_now
    where account_id = p_account_id and status = 'PENDING';

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_account_id,
      'CUSTOMER_ACCOUNT_ANONYMIZED',
      'customer_account',
      p_account_id,
      pg_catalog.jsonb_build_object('historyPreserved', true)
    );

    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      p_account_id::text || ':CUSTOMER_ACCOUNT_ANONYMIZED:1',
      'CUSTOMER_ACCOUNT', p_account_id, 1,
      'CUSTOMER_ACCOUNT_ANONYMIZED', p_account_id,
      pg_catalog.jsonb_build_object('accountId', p_account_id, 'historyPreserved', true)
    ) on conflict (event_key) do nothing;
  end if;

  return pg_catalog.jsonb_build_object('prepared', true, 'alreadyDeleted', false);
end;
$$;

create function public.finalize_customer_account_deletion(p_account_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := pg_catalog.now();
  v_changed boolean;
begin
  update public.accounts
  set account_state = 'DELETED',
      deleted_at = coalesce(deleted_at, v_now),
      updated_at = v_now
  where id = p_account_id
    and account_state = 'DELETION_PENDING';
  v_changed := found;

  update private.customer_account_deletions
  set state = 'DELETED',
      auth_deleted_at = coalesce(auth_deleted_at, v_now),
      completed_at = coalesce(completed_at, v_now)
  where account_id = p_account_id;

  if v_changed then
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_account_id,
      'CUSTOMER_ACCOUNT_DELETED',
      'customer_account',
      p_account_id,
      pg_catalog.jsonb_build_object('authCredentialDeleted', true, 'historyPreserved', true)
    );
  end if;

  return pg_catalog.jsonb_build_object('deleted', true, 'changed', v_changed);
end;
$$;

revoke execute on function public.prepare_customer_account_deletion(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.finalize_customer_account_deletion(uuid)
  from public, anon, authenticated;
grant execute on function public.prepare_customer_account_deletion(uuid, text) to service_role;
grant execute on function public.finalize_customer_account_deletion(uuid) to service_role;

create function dastak_v1_api.merchant_canonical_catalogue_snapshot(
  p_actor_id uuid,
  p_branch_id uuid default null,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_state dastak_v1.branch_operational_states%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 1000);
  v_capacity_held integer;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  if p_branch_id is null then
    select branch.* into v_branch
    from dastak_v1.merchant_branches branch
    where branch.status not in ('CLOSED', 'SUSPENDED')
      and dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id,
        branch.organization_id,
        'merchant.catalogue.selection.manage',
        branch.id
      )
    order by branch.created_at, branch.id
    limit 1;
  else
    select branch.* into v_branch
    from dastak_v1.merchant_branches branch
    where branch.id = p_branch_id;
  end if;

  if not found then
    raise exception using errcode = 'P0002', message = 'merchant branch not found';
  end if;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_branch.organization_id,
    'merchant.catalogue.selection.manage',
    v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select organization.* into strict v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;

  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception using errcode = '22023', message = 'canonical SKU selection is retail-only';
  end if;

  select state.* into v_state
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id;

  select count(*) into v_capacity_held
  from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id and slot.status = 'HELD';

  return pg_catalog.jsonb_build_object(
    'branch', pg_catalog.jsonb_build_object(
      'branchId', v_branch.id,
      'branchName', v_branch.display_name,
      'branchStatus', v_branch.status,
      'branchVersion', v_branch.version,
      'organizationId', v_organization.id,
      'organizationName', v_organization.display_name,
      'merchantType', v_organization.merchant_type,
      'operationalState', pg_catalog.jsonb_build_object(
        'isOpen', coalesce(v_state.is_open, false),
        'acceptingOrders', coalesce(v_state.accepting_orders, false),
        'version', coalesce(v_state.version, 0),
        'updatedAt', v_state.updated_at
      ),
      'capacity', pg_catalog.jsonb_build_object(
        'limit', v_branch.capacity_limit,
        'held', v_capacity_held,
        'available', greatest(v_branch.capacity_limit - v_capacity_held, 0)
      )
    ),
    'categories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'categoryId', category.id,
          'name', category.name,
          'slug', category.slug,
          'imageKey', category.image_key,
          'sortOrder', category.sort_order
        ) order by category.sort_order, category.name, category.id
      )
      from dastak_v1.categories category
      where category.status = 'ACTIVE'
    ), '[]'::jsonb),
    'subcategories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'subcategoryId', subcategory.id,
          'categoryId', subcategory.category_id,
          'name', subcategory.name,
          'slug', subcategory.slug,
          'imageKey', subcategory.image_key,
          'sortOrder', subcategory.sort_order
        ) order by category.sort_order, subcategory.sort_order, subcategory.name, subcategory.id
      )
      from dastak_v1.subcategories subcategory
      join dastak_v1.categories category on category.id = subcategory.category_id
      where subcategory.status = 'ACTIVE' and category.status = 'ACTIVE'
    ), '[]'::jsonb),
    'skus', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'skuId', sku.id,
          'categoryId', subcategory.category_id,
          'subcategoryId', sku.subcategory_id,
          'brandName', brand.name,
          'name', sku.canonical_name,
          'variant', sku.variant_name,
          'packSize', sku.pack_size,
          'description', sku.description,
          'imageKey', sku.image_key,
          'listPricePaise', sku.list_price_paise,
          'sellingPricePaise', sku.selling_price_paise,
          'currencyCode', sku.currency_code,
          'catalogueStatus', sku.status,
          'selected', coalesce(selection.state = 'SELECTED', false),
          'selectionState', selection.state,
          'selectionVersion', coalesce(selection.version, 0),
          'selectionUpdatedAt', selection.updated_at
        ) order by category.sort_order, subcategory.sort_order,
                   pg_catalog.lower(sku.canonical_name), sku.id
      )
      from (
        select source.*
        from dastak_v1.skus source
        where source.status = 'ACTIVE'
          or exists (
            select 1 from dastak_v1.merchant_sku_selections existing
            where existing.branch_id = v_branch.id and existing.sku_id = source.id
          )
        order by pg_catalog.lower(source.canonical_name), source.id
        limit v_limit
      ) sku
      join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
      join dastak_v1.categories category on category.id = subcategory.category_id
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      left join dastak_v1.merchant_sku_selections selection
        on selection.branch_id = v_branch.id and selection.sku_id = sku.id
    ), '[]'::jsonb),
    'truncated', (
      select count(*) > v_limit
      from dastak_v1.skus sku
      where sku.status = 'ACTIVE'
        or exists (
          select 1 from dastak_v1.merchant_sku_selections existing
          where existing.branch_id = v_branch.id and existing.sku_id = sku.id
        )
    )
  );
end;
$$;

create function dastak_v1_api.update_merchant_sku_selection(
  p_actor_id uuid,
  p_branch_id uuid,
  p_sku_id uuid,
  p_selected boolean,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'updateMerchantSkuSelection';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_sku dastak_v1.skus%rowtype;
  v_selection dastak_v1.merchant_sku_selections%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_branch_id is null or p_sku_id is null or p_selected is null
    or p_expected_version is null or p_expected_version < 0
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid selection command required';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id,
    'skuId', p_sku_id,
    'selected', p_selected,
    'expectedVersion', p_expected_version
  ));

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key),
      0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_request_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  -- Stable lock order: branch, SKU, then selection.
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'branch not found'; end if;

  select organization.* into strict v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception using errcode = '22023', message = 'canonical SKU selection is retail-only';
  end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_branch.organization_id,
    'merchant.catalogue.selection.manage', v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select sku.* into v_sku
  from dastak_v1.skus sku where sku.id = p_sku_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'canonical SKU not found'; end if;
  if p_selected and v_sku.status <> 'ACTIVE' then
    raise exception using errcode = '22023', message = 'inactive canonical SKU cannot be selected';
  end if;

  select selection.* into v_selection
  from dastak_v1.merchant_sku_selections selection
  where selection.branch_id = p_branch_id and selection.sku_id = p_sku_id
  for update;

  if found then
    if v_selection.version is distinct from p_expected_version then
      raise exception using errcode = '40001', message = 'stale merchant SKU selection version';
    end if;
    update dastak_v1.merchant_sku_selections
    set state = (
          case when p_selected then 'SELECTED' else 'UNAVAILABLE' end
        )::dastak_v1.merchant_sku_state,
        selected_by = p_actor_id,
        updated_at = pg_catalog.now(),
        version = version + 1
    where branch_id = p_branch_id and sku_id = p_sku_id
    returning * into v_selection;
  else
    if p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'new merchant SKU selection expectedVersion must be 0';
    end if;
    insert into dastak_v1.merchant_sku_selections (
      branch_id, sku_id, state, selected_by
    ) values (
      p_branch_id, p_sku_id,
      (
        case when p_selected then 'SELECTED' else 'UNAVAILABLE' end
      )::dastak_v1.merchant_sku_state,
      p_actor_id
    ) returning * into v_selection;
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'branchId', v_selection.branch_id,
    'skuId', v_selection.sku_id,
    'selected', v_selection.state = 'SELECTED',
    'state', v_selection.state,
    'version', v_selection.version,
    'updatedAt', v_selection.updated_at
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED',
    'merchant_branch', p_branch_id,
    v_response || pg_catalog.jsonb_build_object('idempotencyKey', p_idempotency_key)
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    p_branch_id::text || ':MERCHANT_CANONICAL_SKU_SELECTION_CHANGED:' ||
      p_sku_id::text || ':' || v_selection.version::text,
    'MERCHANT_BRANCH', p_branch_id, v_selection.version,
    'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED', p_actor_id, v_response
  );

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_request_hash,
    v_response, 200, p_branch_id
  );

  return v_response;
end;
$$;

create function public.dastak_v1_merchant_canonical_catalogue_snapshot(
  p_branch_id uuid default null,
  p_limit integer default 1000
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.merchant_canonical_catalogue_snapshot(
    auth.uid(), p_branch_id, p_limit
  );
$$;

create function public.dastak_v1_update_merchant_sku_selection(
  p_branch_id uuid,
  p_sku_id uuid,
  p_selected boolean,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.update_merchant_sku_selection(
    auth.uid(), p_branch_id, p_sku_id, p_selected,
    p_expected_version, p_idempotency_key
  );
$$;

revoke execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid, uuid, integer)
  from public, anon;
revoke execute on function dastak_v1_api.update_merchant_sku_selection(uuid, uuid, uuid, boolean, bigint, text)
  from public, anon;
revoke execute on function public.dastak_v1_merchant_canonical_catalogue_snapshot(uuid, integer)
  from public, anon;
revoke execute on function public.dastak_v1_update_merchant_sku_selection(uuid, uuid, boolean, bigint, text)
  from public, anon;
grant execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid, uuid, integer)
  to authenticated;
grant execute on function dastak_v1_api.update_merchant_sku_selection(uuid, uuid, uuid, boolean, bigint, text)
  to authenticated;
grant execute on function public.dastak_v1_merchant_canonical_catalogue_snapshot(uuid, integer)
  to authenticated;
grant execute on function public.dastak_v1_update_merchant_sku_selection(uuid, uuid, boolean, bigint, text)
  to authenticated;

comment on function public.dastak_v1_merchant_canonical_catalogue_snapshot(uuid, integer) is
  'Merchant branch view of Dastak-owned canonical retail SKUs plus branch operational/capacity state.';
comment on function public.dastak_v1_update_merchant_sku_selection(uuid, uuid, boolean, bigint, text) is
  'Audited, version-checked branch selection of an immutable canonical Dastak SKU.';
