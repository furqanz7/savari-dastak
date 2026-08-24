-- Recover safely when an Auth credential is removed outside Dastak's
-- history-preserving account-deletion workflow.

-- A revoked provider identity remains immutable history, but it must not
-- prevent the same proven OAuth subject from creating a new account later.
alter table private.customer_auth_identities
  drop constraint customer_auth_identities_provider_provider_subject_digest_key;

create unique index customer_auth_identities_active_provider_subject_uidx
  on private.customer_auth_identities (provider, provider_subject_digest)
  where revoked_at is null;

create function private.reconcile_orphaned_customer_oauth_identity(
  p_provider text,
  p_provider_subject_digest bytea,
  p_replacement_auth_user_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_identity private.customer_auth_identities%rowtype;
  v_account public.accounts%rowtype;
  v_membership_count integer;
  v_customer_membership_count integer;
begin
  if p_provider not in ('apple', 'google')
    or p_provider_subject_digest is null
    or pg_catalog.octet_length(p_provider_subject_digest) <> 32
    or p_replacement_auth_user_id is null then
    raise exception using errcode = '22023', message = 'valid OAuth identity required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_provider || ':' || pg_catalog.encode(p_provider_subject_digest, 'hex'),
      0
    )
  );

  select identity.* into v_identity
  from private.customer_auth_identities identity
  where identity.provider = p_provider
    and identity.provider_subject_digest = p_provider_subject_digest
    and identity.revoked_at is null
  for update;

  if not found or v_identity.account_id = p_replacement_auth_user_id then
    return null;
  end if;

  -- Never merge or transfer an identity away from a live Auth credential.
  if exists (
    select 1 from auth.users auth_user
    where auth_user.id = v_identity.account_id
  ) then
    raise exception using
      errcode = '28000',
      message = 'This OAuth identity is already linked to another Dastak account.';
  end if;

  select account.* into v_account
  from public.accounts account
  where account.id = v_identity.account_id
  for update;

  if not found then
    -- OAuth completed but onboarding never created a business account. There
    -- is no business history to transfer or delete; retain and revoke the link.
    update private.customer_auth_identities identity
    set revoked_at = coalesce(identity.revoked_at, pg_catalog.clock_timestamp())
    where identity.account_id = v_identity.account_id
      and identity.provider = v_identity.provider;
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      null,
      'CUSTOMER_PREONBOARDING_AUTH_ORPHAN_RECONCILED',
      'customer_auth_credential',
      v_identity.account_id,
      pg_catalog.jsonb_build_object(
        'provider', p_provider,
        'replacementAuthUserId', p_replacement_auth_user_id,
        'automaticAccountMerge', false
      )
    );
    return v_identity.account_id;
  end if;

  select
    pg_catalog.count(*),
    pg_catalog.count(*) filter (where membership.role = 'customer')
  into v_membership_count, v_customer_membership_count
  from private.account_memberships membership
  where membership.account_id = v_identity.account_id;

  -- A missing operator credential needs an explicit Operations workflow. It
  -- must never be silently converted into a new ordinary customer account.
  if v_membership_count <> 1 or v_customer_membership_count <> 1 then
    raise exception using
      errcode = '28000',
      message = 'This account requires Dastak Operations recovery.';
  end if;

  if v_account.account_state <> 'DELETED' then
    perform public.prepare_customer_account_deletion(
      v_identity.account_id,
      'orphaned-auth-credential:' || v_identity.account_id::text
    );
    perform public.finalize_customer_account_deletion(v_identity.account_id);
  end if;

  update private.customer_auth_identities identity
  set revoked_at = coalesce(identity.revoked_at, pg_catalog.clock_timestamp())
  where identity.account_id = v_identity.account_id
    and identity.provider = v_identity.provider;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    null,
    'CUSTOMER_AUTH_ORPHAN_RECONCILED',
    'customer_account',
    v_identity.account_id,
    pg_catalog.jsonb_build_object(
      'provider', p_provider,
      'replacementAuthUserId', p_replacement_auth_user_id,
      'historyPreserved', true,
      'automaticAccountMerge', false
    )
  );

  return v_identity.account_id;
end;
$$;

revoke execute on function private.reconcile_orphaned_customer_oauth_identity(text, bytea, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.reconcile_orphaned_customer_oauth_identity(text, bytea, uuid)
  to supabase_auth_admin;

create function private.history_safe_dastak_auth_user_delete()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account public.accounts%rowtype;
  v_membership_count integer;
  v_customer_membership_count integer;
begin
  select account.* into v_account
  from public.accounts account
  where account.id = old.id
  for update;

  if not found then
    -- A customer may abandon OAuth before profile bootstrap. Revoke only the
    -- pre-onboarding provider link so a later login can start cleanly.
    update private.customer_auth_identities identity
    set revoked_at = coalesce(identity.revoked_at, pg_catalog.clock_timestamp())
    where identity.account_id = old.id
      and identity.revoked_at is null;
    return old;
  end if;

  select
    pg_catalog.count(*),
    pg_catalog.count(*) filter (where membership.role = 'customer')
  into v_membership_count, v_customer_membership_count
  from private.account_memberships membership
  where membership.account_id = old.id;

  if v_membership_count <> 1 or v_customer_membership_count <> 1 then
    raise exception using
      errcode = '28000',
      message = 'Dastak operator Auth deletion requires an authorized Operations workflow.';
  end if;

  if v_account.account_state <> 'DELETED' then
    perform public.prepare_customer_account_deletion(
      old.id,
      'direct-auth-credential-delete:' || old.id::text
    );
    perform public.finalize_customer_account_deletion(old.id);
  end if;

  update private.customer_auth_identities identity
  set revoked_at = coalesce(identity.revoked_at, pg_catalog.clock_timestamp())
  where identity.account_id = old.id
    and identity.revoked_at is null;

  return old;
end;
$$;

revoke execute on function private.history_safe_dastak_auth_user_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists dastak_history_safe_auth_user_delete on auth.users;
create trigger dastak_history_safe_auth_user_delete
before delete on auth.users
for each row execute function private.history_safe_dastak_auth_user_delete();

create or replace function public.dastak_custom_access_token(event jsonb)
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

  select pg_catalog.count(*) into v_identity_count
  from auth.identities identity
  where identity.user_id = v_account_id
    and identity.provider in ('apple', 'google');

  if v_identity_count < 1 then
    raise exception using errcode = '28000', message = 'Apple or Google identity required.';
  end if;

  if v_current_provider is not null and v_current_provider not in ('apple', 'google') then
    raise exception using errcode = '28000', message = 'Unsupported Dastak authentication provider.';
  end if;

  select pg_catalog.count(*) into v_registered_count
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
    -- The provider subject, unlike email or phone, proves the same OAuth
    -- identity. If its old Auth credential was manually removed, tombstone the
    -- orphaned customer account before registering a new, separate account.
    perform private.reconcile_orphaned_customer_oauth_identity(
      v_identity.provider,
      v_identity.subject_digest,
      v_account_id
    );

    -- A concurrent token issuance may have completed registration while this
    -- transaction waited on the provider-subject advisory lock.
    if exists (
      select 1
      from private.customer_auth_identities registered
      where registered.account_id = v_account_id
        and registered.provider = v_identity.provider
        and registered.provider_subject_digest = v_identity.subject_digest
        and registered.revoked_at is null
    ) then
      select pg_catalog.count(*) into v_registered_count
      from private.customer_auth_identities registered
      where registered.account_id = v_account_id
        and registered.revoked_at is null;
      continue;
    end if;

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

grant execute on function public.dastak_custom_access_token(jsonb) to supabase_auth_admin;
revoke execute on function public.dastak_custom_access_token(jsonb)
  from public, anon, authenticated, service_role;
