-- Customer-account completion: revocable device sessions and a privacy-safe,
-- customer-owned data export. This migration is additive and preserves all
-- historical account, order, payment, custody, settlement and audit records.

create table private.revoked_account_sessions (
  session_id uuid primary key,
  account_id uuid not null references public.accounts(id),
  revoked_by uuid not null references public.accounts(id),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 200
  ),
  revoked_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index revoked_account_sessions_account_idx
  on private.revoked_account_sessions (account_id, revoked_at desc);

alter table private.revoked_account_sessions enable row level security;
revoke all on table private.revoked_account_sessions
  from public, anon, authenticated, service_role, supabase_auth_admin;
grant select, insert on table private.revoked_account_sessions to service_role;

create function private.assert_dastak_session_active(
  p_account_id uuid,
  p_session_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_session_id is not null and exists (
    select 1
    from private.revoked_account_sessions revoked
    where revoked.session_id = p_session_id
      and revoked.account_id = p_account_id
  ) then
    raise exception using
      errcode = '28000',
      message = 'This Dastak session has been revoked.';
  end if;
end;
$$;

revoke execute on function private.assert_dastak_session_active(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.assert_dastak_session_active(uuid, uuid)
  to supabase_auth_admin;

create function public.is_account_session_revoked(
  p_account_id uuid,
  p_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.revoked_account_sessions revoked
    where revoked.account_id = p_account_id
      and revoked.session_id = p_session_id
  );
$$;

revoke execute on function public.is_account_session_revoked(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.is_account_session_revoked(uuid, uuid)
  to service_role;

create function public.revoke_account_session(
  p_account_id uuid,
  p_current_session_id uuid,
  p_target_session_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_inserted integer;
begin
  if p_account_id is null or p_current_session_id is null or p_target_session_id is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A valid session is required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if p_current_session_id = p_target_session_id then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'current_session_forbidden',
        'message', 'Use Sign out to close this device.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_target_session_id::text || ':revoke-session', 0)
  );

  if not exists (
    select 1
    from private.account_sessions session
    where session.account_id = p_account_id
      and session.session_id = p_target_session_id
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'session_not_found',
        'message', 'That session is no longer active.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  insert into private.revoked_account_sessions (
    session_id, account_id, revoked_by, reason
  ) values (
    p_target_session_id, p_account_id, p_account_id, 'Customer removed signed-in device'
  ) on conflict (session_id) do nothing;
  get diagnostics v_inserted = row_count;

  update private.account_sessions session
  set ended_at = coalesce(session.ended_at, pg_catalog.clock_timestamp())
  where session.account_id = p_account_id
    and session.session_id = p_target_session_id;

  if v_inserted = 1 then
    insert into audit.events (actor_id, action, entity_type, entity_id, after_state)
    values (
      p_account_id,
      'account_session_revoked',
      'account_session',
      p_target_session_id,
      pg_catalog.jsonb_build_object('accountId', p_account_id)
    );
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_account_id,
      'ACCOUNT_SESSION_REVOKED',
      'account_session',
      p_target_session_id,
      pg_catalog.jsonb_build_object('accountId', p_account_id)
    );
  end if;

  select snapshot.response_body, snapshot.response_status
  into response_body, response_status
  from public.get_account_sessions(p_account_id, p_current_session_id) snapshot;
  return next;
end;
$$;

revoke execute on function public.revoke_account_session(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.revoke_account_session(uuid, uuid, uuid)
  to service_role;

-- Keep the existing Auth refresh-token revocation, and also deny every known
-- access-token session at Dastak's server boundary without writing Supabase's
-- managed auth.sessions table directly.
create or replace function public.end_other_account_sessions(
  p_account_id uuid,
  p_current_session_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_revoked integer;
begin
  insert into private.revoked_account_sessions (
    session_id, account_id, revoked_by, reason
  )
  select session.session_id, p_account_id, p_account_id,
         'Customer signed out all other devices'
  from private.account_sessions session
  where session.account_id = p_account_id
    and session.session_id <> p_current_session_id
    and session.ended_at is null
  on conflict (session_id) do nothing;
  get diagnostics v_revoked = row_count;

  update private.account_sessions session
  set ended_at = coalesce(session.ended_at, pg_catalog.clock_timestamp())
  where session.account_id = p_account_id
    and session.session_id <> p_current_session_id
    and session.ended_at is null;

  if v_revoked > 0 then
    insert into audit.events (actor_id, action, entity_type, entity_id, after_state)
    values (
      p_account_id,
      'other_account_sessions_ended',
      'account',
      p_account_id,
      pg_catalog.jsonb_build_object('revokedSessionCount', v_revoked)
    );
    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_account_id,
      'OTHER_ACCOUNT_SESSIONS_REVOKED',
      'customer_account',
      p_account_id,
      pg_catalog.jsonb_build_object('revokedSessionCount', v_revoked)
    );
  end if;

  response_body := pg_catalog.jsonb_build_object('ended', true);
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.end_other_account_sessions(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.end_other_account_sessions(uuid, uuid)
  to service_role;

create function private.revoke_sessions_when_customer_account_closes()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.account_state = 'ACTIVE' and new.account_state <> 'ACTIVE' then
    insert into private.revoked_account_sessions (
      session_id, account_id, revoked_by, reason
    )
    select session.session_id, new.id, new.id, 'Customer account access disabled'
    from private.account_sessions session
    where session.account_id = new.id
      and session.ended_at is null
    on conflict (session_id) do nothing;
  end if;
  return new;
end;
$$;

revoke execute on function private.revoke_sessions_when_customer_account_closes()
  from public, anon, authenticated, service_role;

create trigger customer_account_session_revocation
before update of account_state on public.accounts
for each row
when (old.account_state is distinct from new.account_state)
execute function private.revoke_sessions_when_customer_account_closes();

create function public.export_customer_account_data(p_account_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_profile jsonb;
  v_identities jsonb;
  v_addresses jsonb;
  v_sessions jsonb;
  v_legacy_orders jsonb;
  v_parcels jsonb;
  v_v1_orders jsonb;
  v_issues jsonb;
begin
  select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'accountId', account.id,
    'displayName', account.display_name,
    'phoneNumber', account.phone_number,
    'email', auth_user.email,
    'accountState', account.account_state,
    'createdAt', account.created_at,
    'updatedAt', account.updated_at
  )) into v_profile
  from public.accounts account
  left join auth.users auth_user on auth_user.id = account.id
  where account.id = p_account_id;

  if v_profile is null then
    raise exception using errcode = 'P0002', message = 'customer account not found';
  end if;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'provider', identity.provider,
    'linkKind', identity.link_kind,
    'linkedAt', identity.linked_at,
    'revokedAt', identity.revoked_at
  ) order by identity.linked_at, identity.provider), '[]'::jsonb)
  into v_identities
  from private.customer_auth_identities identity
  where identity.account_id = p_account_id;

  select coalesce(pg_catalog.jsonb_agg(
    private.customer_delivery_address_json(address_row)
      || pg_catalog.jsonb_build_object(
        'createdAt', address_row.created_at,
        'archivedAt', address_row.archived_at
      )
    order by address_row.created_at, address_row.id
  ), '[]'::jsonb)
  into v_addresses
  from private.customer_delivery_addresses address_row
  where address_row.account_id = p_account_id;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'sessionId', session.session_id,
    'deviceName', session.device_name,
    'platform', session.platform,
    'appName', session.app_name,
    'createdAt', session.created_at,
    'lastSeenAt', session.last_seen_at,
    'endedAt', session.ended_at,
    'revokedAt', revoked.revoked_at
  ) order by session.created_at, session.session_id), '[]'::jsonb)
  into v_sessions
  from private.account_sessions session
  left join private.revoked_account_sessions revoked
    on revoked.session_id = session.session_id
  where session.account_id = p_account_id;

  select coalesce(pg_catalog.jsonb_agg(
    private.customer_merchant_order_json(merchant_order, p_account_id)
    order by merchant_order.created_at, merchant_order.id
  ), '[]'::jsonb)
  into v_legacy_orders
  from private.merchant_orders merchant_order
  where merchant_order.customer_account_id = p_account_id;

  select coalesce(pg_catalog.jsonb_agg(
    private.customer_parcel_delivery_json(
      parcel,
      case when parcel.customer_account_id = p_account_id then 'customer' else 'recipient' end,
      p_account_id
    ) || pg_catalog.jsonb_build_object(
      'audience', case when parcel.customer_account_id = p_account_id then 'sender' else 'recipient' end
    )
    order by parcel.created_at, parcel.id
  ), '[]'::jsonb)
  into v_parcels
  from private.parcel_deliveries parcel
  where parcel.customer_account_id = p_account_id
     or parcel.recipient_account_id = p_account_id;

  select coalesce(pg_catalog.jsonb_agg(
    dastak_v1_api.order_json(customer_order.id, p_account_id)
    order by customer_order.created_at, customer_order.id
  ), '[]'::jsonb)
  into v_v1_orders
  from dastak_v1.orders customer_order
  where customer_order.customer_id = p_account_id;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'id', issue.id,
      'orderId', issue.order_id,
      'orderLineId', issue.order_line_id,
      'category', issue.category,
      'status', issue.status,
      'description', issue.description,
      'reportedAt', issue.reported_at,
      'reviewedAt', issue.reviewed_at,
      'resolution', issue.resolution,
      'resolvedAt', issue.resolved_at,
      'updatedAt', issue.updated_at
    )
  ) order by issue.reported_at, issue.id), '[]'::jsonb)
  into v_issues
  from dastak_v1.customer_issues issue
  where issue.customer_id = p_account_id;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_account_id,
    'CUSTOMER_ACCOUNT_DATA_EXPORTED',
    'customer_account',
    p_account_id,
    pg_catalog.jsonb_build_object('formatVersion', 1)
  );

  return pg_catalog.jsonb_build_object(
    'formatVersion', 1,
    'exportedAt', pg_catalog.clock_timestamp(),
    'profile', v_profile,
    'signInIdentities', v_identities,
    'savedAddresses', v_addresses,
    'accountSessions', v_sessions,
    'orders', pg_catalog.jsonb_build_object(
      'dastakV1', v_v1_orders,
      'legacy', v_legacy_orders,
      'parcelDeliveries', v_parcels
    ),
    'customerIssues', v_issues
  );
end;
$$;

revoke execute on function public.export_customer_account_data(uuid)
  from public, anon, authenticated;
grant execute on function public.export_customer_account_data(uuid)
  to service_role;

-- Preserve the existing OAuth-only identity and explicit-linking rules while
-- also denying refresh for a customer-removed session.
create or replace function public.dastak_custom_access_token(event jsonb)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_account_id uuid;
  v_session_id uuid;
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
  if coalesce(event -> 'claims' ->> 'session_id', '')
    ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  then
    v_session_id := (event -> 'claims' ->> 'session_id')::uuid;
  end if;
  perform private.assert_dastak_session_active(v_account_id, v_session_id);

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
    perform private.reconcile_orphaned_customer_oauth_identity(
      v_identity.provider,
      v_identity.subject_digest,
      v_account_id
    );

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

notify pgrst, 'reload schema';
