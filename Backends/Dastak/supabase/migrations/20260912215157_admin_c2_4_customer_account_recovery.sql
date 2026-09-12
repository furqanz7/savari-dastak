-- Admin C2.4: governed Customer account recovery. This deliberately reuses
-- Dastak's account-session revocation and phone-claim primitives; privileged
-- Auth tokens and raw Auth metadata never cross the database/Edge boundary.

create or replace function dastak_v1_api.assert_customer_recovery_admin(
  p_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.accounts.recover'
  );
  if dastak_v1_api.admin_role_for_actor(p_actor_id) is null then
    raise exception using
      errcode = '42501',
      message = 'active Admin assignment required';
  end if;
end;
$$;

revoke all on function dastak_v1_api.assert_customer_recovery_admin(uuid)
  from public, anon, authenticated, service_role;

-- A single safe view of active sessions. auth.sessions is authoritative when
-- present; the Dastak registration is retained as a fail-safe for sessions
-- that were registered but are temporarily absent from the Auth projection.
create or replace function private.customer_active_session_projection(
  p_account_id uuid
)
returns table (
  session_id uuid,
  device_name text,
  platform text,
  app_name text,
  created_at timestamptz,
  last_seen_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with candidates as (
    select
      auth_session.id as session_id,
      coalesce(nullif(pg_catalog.btrim(registered.device_name), ''), 'Dastak session') as device_name,
      coalesce(registered.platform, 'web') as platform,
      coalesce(nullif(pg_catalog.btrim(registered.app_name), ''), 'Dastak') as app_name,
      coalesce(registered.created_at, auth_session.created_at, pg_catalog.now()) as created_at,
      greatest(
        coalesce(registered.last_seen_at, '-infinity'::timestamptz),
        coalesce(auth_session.updated_at, '-infinity'::timestamptz),
        coalesce(auth_session.refreshed_at at time zone 'UTC', '-infinity'::timestamptz)
      ) as last_seen_at,
      1 as authority
    from auth.sessions auth_session
    left join private.account_sessions registered
      on registered.session_id = auth_session.id
      and registered.account_id = auth_session.user_id
    where auth_session.user_id = p_account_id
      and (auth_session.not_after is null or auth_session.not_after > pg_catalog.now())
      and not exists (
        select 1
        from private.revoked_account_sessions revoked
        where revoked.session_id = auth_session.id
          and revoked.account_id = p_account_id
      )

    union all

    select
      registered.session_id,
      registered.device_name,
      registered.platform,
      registered.app_name,
      registered.created_at,
      registered.last_seen_at,
      2 as authority
    from private.account_sessions registered
    where registered.account_id = p_account_id
      and registered.ended_at is null
      and not exists (
        select 1 from auth.sessions auth_session
        where auth_session.id = registered.session_id
      )
      and not exists (
        select 1
        from private.revoked_account_sessions revoked
        where revoked.session_id = registered.session_id
          and revoked.account_id = p_account_id
      )
  )
  select distinct on (candidate.session_id)
    candidate.session_id,
    candidate.device_name,
    candidate.platform,
    candidate.app_name,
    candidate.created_at,
    candidate.last_seen_at
  from candidates candidate
  order by candidate.session_id, candidate.authority
$$;

revoke all on function private.customer_active_session_projection(uuid)
  from public, anon, authenticated, service_role;

create or replace function dastak_v1_api.admin_customer_recovery_page(
  p_actor_id uuid,
  p_query text default null,
  p_account_id uuid default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_account_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_customer_recovery_admin(p_actor_id);
  if v_query is not null and pg_catalog.char_length(v_query) > 100 then
    raise exception using errcode = '22023', message = 'Customer recovery search is too long';
  end if;
  if (p_after_updated_at is null) <> (p_after_account_id is null) then
    raise exception using errcode = '22023', message = 'complete Customer recovery cursor required';
  end if;

  with governed as materialized (
    select
      account.id as account_id,
      coalesce(nullif(pg_catalog.btrim(account.display_name), ''), 'Dastak customer') as display_name,
      account.phone_number,
      case
        when pg_catalog.char_length(account.phone_number) <= 4 then account.phone_number
        else pg_catalog.repeat('•', greatest(pg_catalog.char_length(account.phone_number) - 4, 4))
          || ' ' || pg_catalog.right(account.phone_number, 4)
      end as masked_phone_number,
      auth_user.email,
      account.account_state::text as account_state,
      customer.state::text as customer_state,
      coalesce(claim.version, 0) as phone_claim_version,
      coalesce(claim.claim_state::text, 'MISSING') as phone_claim_state,
      coalesce(claim.verification_source, 'UNAVAILABLE') as verification_source,
      account.created_at,
      greatest(
        account.updated_at,
        customer.updated_at,
        coalesce(claim.updated_at, '-infinity'::timestamptz),
        coalesce(session_state.last_seen_at, '-infinity'::timestamptz)
      ) as row_updated_at,
      coalesce(session_state.active_session_count, 0) as active_session_count,
      coalesce(session_state.sessions, '[]'::jsonb) as sessions,
      coalesce(identity_state.providers, '[]'::jsonb) as providers
    from public.accounts account
    join private.account_personas customer
      on customer.account_id = account.id
      and customer.persona = 'CUSTOMER'
    join auth.users auth_user on auth_user.id = account.id
    left join private.account_phone_claims claim on claim.account_id = account.id
    left join lateral (
      select
        pg_catalog.count(*)::integer as active_session_count,
        pg_catalog.max(session.last_seen_at) as last_seen_at,
        coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'sessionId', session.session_id,
          'deviceName', session.device_name,
          'platform', session.platform,
          'appName', session.app_name,
          'createdAt', session.created_at,
          'lastSeenAt', session.last_seen_at
        ) order by session.last_seen_at desc, session.session_id), '[]'::jsonb) as sessions
      from private.customer_active_session_projection(account.id) session
    ) session_state on true
    left join lateral (
      select coalesce(pg_catalog.jsonb_agg(identity.provider order by identity.provider), '[]'::jsonb) as providers
      from private.customer_auth_identities identity
      where identity.account_id = account.id and identity.revoked_at is null
    ) identity_state on true
    where (p_account_id is null or account.id = p_account_id)
      and (
        v_query is null
        or account.id::text = pg_catalog.lower(v_query)
        or account.display_name ilike '%' || v_query || '%'
        or account.phone_number = v_query
        or auth_user.email ilike '%' || v_query || '%'
      )
      and (
        p_after_updated_at is null
        or (greatest(
              account.updated_at,
              customer.updated_at,
              coalesce(claim.updated_at, '-infinity'::timestamptz),
              coalesce(session_state.last_seen_at, '-infinity'::timestamptz)
            ), account.id) < (p_after_updated_at, p_after_account_id)
      )
    order by row_updated_at desc, account_id desc
    limit v_limit + 1
  ), selected as (
    select * from governed
    order by row_updated_at desc, account_id desc
    limit v_limit
  )
  select
    coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'account', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'accountId', row.account_id,
        'displayName', row.display_name,
        'currentPhoneNumber', row.phone_number,
        'maskedPhoneNumber', row.masked_phone_number,
        'email', row.email,
        'accountState', row.account_state,
        'customerState', row.customer_state,
        'createdAt', row.created_at
      )),
      'phoneClaim', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'version', row.phone_claim_version,
        'state', row.phone_claim_state,
        'verificationSource', row.verification_source
      )),
      'identityProviders', row.providers,
      'activeSessionCount', row.active_session_count,
      'sessions', row.sessions,
      'updatedAt', row.row_updated_at
    ) order by row.row_updated_at desc, row.account_id desc) from selected row), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from governed),
    case when (select pg_catalog.count(*) > v_limit from governed) then (
      select pg_catalog.jsonb_build_object('updatedAt', row.row_updated_at, 'accountId', row.account_id)
      from selected row order by row.row_updated_at, row.account_id limit 1
    ) else null end
  into v_rows, v_has_more, v_next_cursor;

  return pg_catalog.jsonb_build_object(
    'customers', v_rows,
    'hasMore', v_has_more,
    'nextCursor', v_next_cursor
  );
end;
$$;

create or replace function dastak_v1_api.admin_revoke_customer_sessions(
  p_actor_id uuid,
  p_account_id uuid,
  p_scope text,
  p_session_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'adminRevokeCustomerSessions';
  v_scope text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_scope, '')));
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_sessions uuid[];
  v_count integer;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_customer_recovery_admin(p_actor_id);
  if p_account_id is null
    or v_scope not in ('SINGLE', 'ALL')
    or (v_scope = 'SINGLE' and p_session_id is null)
    or (v_scope = 'ALL' and p_session_id is not null)
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 200
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid Customer session recovery command required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'accountId', p_account_id,
    'scope', v_scope,
    'sessionId', p_session_id,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak:customer-account-recovery:' || p_account_id::text, 0
  ));
  if not exists (
    select 1 from public.accounts account
    join private.account_personas persona on persona.account_id = account.id
    where account.id = p_account_id
      and account.account_state = 'ACTIVE'
      and persona.persona = 'CUSTOMER'
      and persona.state = 'ACTIVE'
  ) then
    raise exception using errcode = 'P0002', message = 'Customer account not found';
  end if;

  select coalesce(pg_catalog.array_agg(session.session_id order by session.session_id), '{}'::uuid[])
  into v_sessions
  from private.customer_active_session_projection(p_account_id) session
  where v_scope = 'ALL' or session.session_id = p_session_id;
  v_count := coalesce(pg_catalog.cardinality(v_sessions), 0);
  if v_scope = 'SINGLE' and v_count <> 1 then
    raise exception using errcode = 'P0002', message = 'Customer session not found';
  end if;

  insert into private.revoked_account_sessions(
    session_id, account_id, revoked_by, reason
  )
  select session_id, p_account_id, p_actor_id, pg_catalog.btrim(p_reason)
  from pg_catalog.unnest(v_sessions) session_id
  on conflict (session_id) do nothing;

  update private.account_sessions session
  set ended_at = coalesce(session.ended_at, pg_catalog.clock_timestamp())
  where session.account_id = p_account_id
    and session.session_id = any(v_sessions);

  select pg_catalog.count(*)::integer into v_count
  from private.customer_active_session_projection(p_account_id);

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ADMIN_ACCOUNT_SESSIONS_REVOKED',
    'customer_account',
    p_account_id,
    pg_catalog.jsonb_build_object(
      'accountId', p_account_id,
      'scope', v_scope || ':' || pg_catalog.cardinality(v_sessions)::text,
      'outcome', 'revoked ' || pg_catalog.cardinality(v_sessions)::text || ' active session'
        || case when pg_catalog.cardinality(v_sessions) = 1 then '' else 's' end,
      'reason', pg_catalog.btrim(p_reason)
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'accountId', p_account_id,
    'scope', v_scope,
    'revokedSessionCount', pg_catalog.cardinality(v_sessions),
    'revokedSessionId', case when v_scope = 'SINGLE' then p_session_id else null end,
    'activeSessionCount', v_count,
    'updatedAt', pg_catalog.clock_timestamp()
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_account_id
  );
  return v_response;
end;
$$;

create or replace function dastak_v1_api.admin_correct_customer_phone(
  p_actor_id uuid,
  p_account_id uuid,
  p_reviewed_current_phone text,
  p_replacement_phone text,
  p_expected_phone_claim_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'adminCorrectCustomerPhone';
  v_current text := pg_catalog.btrim(coalesce(p_reviewed_current_phone, ''));
  v_replacement text := pg_catalog.btrim(coalesce(p_replacement_phone, ''));
  v_first_lock text;
  v_second_lock text;
  v_claim private.account_phone_claims%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_masked_current text;
  v_masked_replacement text;
begin
  perform dastak_v1_api.assert_customer_recovery_admin(p_actor_id);
  if p_account_id is null
    or v_current !~ '^\+[1-9][0-9]{7,14}$'
    or v_replacement !~ '^\+[1-9][0-9]{7,14}$'
    or v_current = v_replacement
    or p_expected_phone_claim_version is null or p_expected_phone_claim_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid Customer phone correction command required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'accountId', p_account_id,
    'reviewedCurrentPhone', v_current,
    'replacementPhone', v_replacement,
    'expectedPhoneClaimVersion', p_expected_phone_claim_version,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  v_first_lock := least(v_current, v_replacement);
  v_second_lock := greatest(v_current, v_replacement);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dastak-phone:' || v_first_lock, 0));
  if v_second_lock <> v_first_lock then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dastak-phone:' || v_second_lock, 0));
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak:customer-account-recovery:' || p_account_id::text, 0
  ));

  if not exists (
    select 1 from public.accounts account
    join private.account_personas persona on persona.account_id = account.id
    where account.id = p_account_id
      and account.account_state = 'ACTIVE'
      and persona.persona = 'CUSTOMER'
      and persona.state = 'ACTIVE'
  ) then
    raise exception using errcode = 'P0002', message = 'Customer account not found';
  end if;

  select claim.* into v_claim
  from private.account_phone_claims claim
  where claim.account_id = p_account_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Customer phone claim not found';
  end if;
  if v_claim.version <> p_expected_phone_claim_version
    or v_claim.phone_number <> v_current
    or not exists (
      select 1 from public.accounts account
      where account.id = p_account_id and account.phone_number = v_current
    ) then
    raise exception using errcode = '40001', message = 'stale Customer phone claim version';
  end if;
  if exists (
    select 1 from private.account_phone_claims claim
    where claim.phone_number = v_replacement
      and claim.account_id <> p_account_id
  ) then
    raise exception using errcode = '23505', message = 'PHONE_NUMBER_ALREADY_CLAIMED';
  end if;

  update private.account_phone_claims claim
  set phone_number = v_replacement,
      claim_state = 'ACTIVE',
      verified_at = null,
      verification_source = 'PROFILE_ENTRY',
      recovery_eligible_at = null,
      updated_at = pg_catalog.clock_timestamp(),
      version = claim.version + 1
  where claim.account_id = p_account_id
  returning claim.* into v_claim;

  update public.accounts account
  set phone_number = v_replacement,
      phone_verification_state = 'unverified',
      updated_at = pg_catalog.clock_timestamp()
  where account.id = p_account_id;

  v_masked_current := pg_catalog.repeat('•', greatest(pg_catalog.char_length(v_current) - 4, 4))
    || ' ' || pg_catalog.right(v_current, 4);
  v_masked_replacement := pg_catalog.repeat('•', greatest(pg_catalog.char_length(v_replacement) - 4, 4))
    || ' ' || pg_catalog.right(v_replacement, 4);

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'ADMIN_ACCOUNT_PHONE_CORRECTED',
    'customer_account',
    p_account_id,
    pg_catalog.jsonb_build_object(
      'accountId', p_account_id,
      'fromStatus', v_masked_current,
      'toStatus', v_masked_replacement,
      'outcome', 'phone claim version ' || p_expected_phone_claim_version::text
        || ' -> ' || v_claim.version::text,
      'version', v_claim.version,
      'reason', pg_catalog.btrim(p_reason)
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'accountId', p_account_id,
    'maskedPhoneNumber', v_masked_replacement,
    'phoneClaimVersion', v_claim.version,
    'phoneVerificationState', 'unverified',
    'updatedAt', v_claim.updated_at
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_account_id
  );
  return v_response;
end;
$$;

create or replace function public.dastak_v1_admin_customer_recovery_page(
  p_query text default null,
  p_account_id uuid default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_account_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_customer_recovery_page(
    auth.uid(), p_query, p_account_id, p_limit,
    p_after_updated_at, p_after_account_id
  )
$$;

create or replace function public.dastak_v1_admin_revoke_customer_sessions(
  p_account_id uuid,
  p_scope text,
  p_session_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_revoke_customer_sessions(
    auth.uid(), p_account_id, p_scope, p_session_id, p_reason, p_idempotency_key
  )
$$;

create or replace function public.dastak_v1_admin_correct_customer_phone(
  p_account_id uuid,
  p_reviewed_current_phone text,
  p_replacement_phone text,
  p_expected_phone_claim_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_correct_customer_phone(
    auth.uid(), p_account_id, p_reviewed_current_phone, p_replacement_phone,
    p_expected_phone_claim_version, p_reason, p_idempotency_key
  )
$$;

revoke all on function dastak_v1_api.admin_customer_recovery_page(
  uuid,text,uuid,integer,timestamptz,uuid
) from public, anon;
revoke all on function dastak_v1_api.admin_revoke_customer_sessions(
  uuid,uuid,text,uuid,text,text
) from public, anon;
revoke all on function dastak_v1_api.admin_correct_customer_phone(
  uuid,uuid,text,text,bigint,text,text
) from public, anon;
grant execute on function dastak_v1_api.admin_customer_recovery_page(
  uuid,text,uuid,integer,timestamptz,uuid
) to authenticated, service_role;
grant execute on function dastak_v1_api.admin_revoke_customer_sessions(
  uuid,uuid,text,uuid,text,text
) to authenticated, service_role;
grant execute on function dastak_v1_api.admin_correct_customer_phone(
  uuid,uuid,text,text,bigint,text,text
) to authenticated, service_role;

revoke all on function public.dastak_v1_admin_customer_recovery_page(
  text,uuid,integer,timestamptz,uuid
) from public, anon;
revoke all on function public.dastak_v1_admin_revoke_customer_sessions(
  uuid,text,uuid,text,text
) from public, anon;
revoke all on function public.dastak_v1_admin_correct_customer_phone(
  uuid,text,text,bigint,text,text
) from public, anon;
grant execute on function public.dastak_v1_admin_customer_recovery_page(
  text,uuid,integer,timestamptz,uuid
) to authenticated, service_role;
grant execute on function public.dastak_v1_admin_revoke_customer_sessions(
  uuid,text,uuid,text,text
) to authenticated, service_role;
grant execute on function public.dastak_v1_admin_correct_customer_phone(
  uuid,text,text,bigint,text,text
) to authenticated, service_role;

comment on function public.dastak_v1_admin_customer_recovery_page(
  text,uuid,integer,timestamptz,uuid
) is 'Caller-bound, active-Admin Customer recovery projection with safe session labels and bounded keyset pagination.';
comment on function public.dastak_v1_admin_revoke_customer_sessions(
  uuid,text,uuid,text,text
) is 'Governed and idempotent revocation of one reviewed or all authoritative active Customer sessions.';
comment on function public.dastak_v1_admin_correct_customer_phone(
  uuid,text,text,bigint,text,text
) is 'Governed, versioned and idempotent Customer phone-claim correction preserving OAuth identity.';

-- Add only the new invalidation workspace; the private realtime channel sends
-- IDs for invalidation and never sends Customer identity/session payloads.
create or replace function private.send_admin_change(
  p_workspaces text[],
  p_entity_id uuid default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspaces text[];
begin
  select pg_catalog.array_agg(candidate.workspace order by candidate.workspace)
  into v_workspaces
  from (
    select distinct workspace
    from pg_catalog.unnest(p_workspaces) workspace
    where workspace = any (array[
      'operations', 'liveOrders', 'adminAccess', 'commandCenter',
      'merchantApprovals', 'deliveryApprovals', 'systemHealth',
      'operationalSafety', 'royaltyPayouts', 'network', 'catalogue',
      'auditHistory', 'merchantGovernance', 'deliveryPartnerGovernance',
      'customerRecovery'
    ]::text[])
  ) candidate;
  if coalesce(pg_catalog.cardinality(v_workspaces), 0) = 0 then return; end if;
  perform realtime.send(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'workspaces', v_workspaces, 'entityId', p_entity_id
    )),
    'admin_changed', 'admin-control', true
  );
end;
$$;

revoke all on function private.send_admin_change(text[], uuid)
  from public, anon, authenticated, service_role;

drop trigger if exists zzz_admin_customer_recovery_accounts_realtime on public.accounts;
create trigger zzz_admin_customer_recovery_accounts_realtime
after insert or update or delete on public.accounts
for each row execute function private.broadcast_admin_change('customerRecovery');

drop trigger if exists zzz_admin_customer_recovery_personas_realtime on private.account_personas;
create trigger zzz_admin_customer_recovery_personas_realtime
after insert or update or delete on private.account_personas
for each row execute function private.broadcast_admin_change('customerRecovery');

drop trigger if exists zzz_admin_customer_recovery_phone_claims_realtime on private.account_phone_claims;
create trigger zzz_admin_customer_recovery_phone_claims_realtime
after insert or update or delete on private.account_phone_claims
for each row execute function private.broadcast_admin_change('customerRecovery', 'network');

drop trigger if exists zzz_admin_customer_recovery_sessions_realtime on private.account_sessions;
create trigger zzz_admin_customer_recovery_sessions_realtime
after insert or update or delete on private.account_sessions
for each row execute function private.broadcast_admin_change('customerRecovery');

drop trigger if exists zzz_admin_customer_recovery_revocations_realtime on private.revoked_account_sessions;
create trigger zzz_admin_customer_recovery_revocations_realtime
after insert or update or delete on private.revoked_account_sessions
for each row execute function private.broadcast_admin_change('customerRecovery');
