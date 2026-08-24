-- Customer onboarding completion: retry-safe profile bootstrap, durable
-- history-safe account deletion, and Customer Web background notifications.

create or replace function public.bootstrap_account(
  p_account_id uuid,
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
  v_function_name constant text := 'bootstrap_account';
  v_existing private.request_deduplication%rowtype;
  v_account public.accounts%rowtype;
  v_response_body jsonb;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select * into v_existing
  from private.request_deduplication
  where account_id = p_account_id
    and function_name = v_function_name
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_digest = p_request_digest then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
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

  select account.* into v_account
  from public.accounts account
  where account.id = p_account_id;

  v_response_body := pg_catalog.jsonb_build_object(
    'accountId', p_account_id,
    'phoneState', 'unverified'
  );

  if found then
    -- A browser/app restart can lose the original request key after the server
    -- committed. Confirm only the exact same active customer profile; never
    -- treat different profile data or a non-customer account as success.
    if v_account.account_state = 'ACTIVE'
      and v_account.display_name = p_display_name
      and v_account.phone_number = p_phone_number
      and exists (
        select 1 from private.account_memberships membership
        where membership.account_id = p_account_id
          and membership.role = 'customer'
          and (
            membership.suspended_until is null
            or membership.suspended_until <= pg_catalog.now()
          )
      ) then
      insert into private.request_deduplication (
        account_id, function_name, idempotency_key, request_digest,
        response_body, response_status
      ) values (
        p_account_id, v_function_name, p_idempotency_key, p_request_digest,
        v_response_body, 200
      );
      response_body := v_response_body;
      response_status := 200;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'account_already_exists',
        'message', 'An account already exists for this authenticated user.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into public.accounts (id, display_name, phone_number)
  values (p_account_id, p_display_name, p_phone_number);
  insert into private.account_memberships (account_id, role)
  values (p_account_id, 'customer');
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, p_idempotency_key, p_request_digest,
    v_response_body, 200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.bootstrap_account(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.bootstrap_account(uuid, text, text, text, text)
  to service_role;

alter table private.customer_account_deletions
  add column last_idempotency_key text,
  add column request_count integer not null default 1 check (request_count > 0),
  add column attempts integer not null default 0 check (attempts >= 0),
  add column available_at timestamptz not null default pg_catalog.now(),
  add column locked_at timestamptz,
  add column locked_by text,
  add column last_error text,
  add constraint customer_account_deletions_claim_check check (
    (locked_at is null and locked_by is null)
    or (locked_at is not null and nullif(pg_catalog.btrim(locked_by), '') is not null)
  );

update private.customer_account_deletions
set last_idempotency_key = idempotency_key;

alter table private.customer_account_deletions
  alter column last_idempotency_key set not null;

create index customer_account_deletions_claim_idx
  on private.customer_account_deletions (available_at, requested_at, account_id)
  where state = 'DELETION_PENDING';

create or replace function public.prepare_customer_account_deletion(
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
  v_key text := pg_catalog.btrim(p_idempotency_key);
begin
  if p_account_id is null or p_idempotency_key is null
    or pg_catalog.char_length(v_key) not between 1 and 200 then
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
    return pg_catalog.jsonb_build_object(
      'prepared', true, 'alreadyDeleted', true, 'deletionQueued', false
    );
  end if;

  insert into private.customer_account_deletions (
    account_id, idempotency_key, last_idempotency_key, state,
    anonymized_at, available_at
  ) values (
    p_account_id, v_key, v_key, 'DELETION_PENDING', v_now, v_now
  )
  on conflict (account_id) do update
  set last_idempotency_key = excluded.last_idempotency_key,
      request_count = private.customer_account_deletions.request_count + 1,
      available_at = least(private.customer_account_deletions.available_at, excluded.available_at),
      last_error = null;

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
    set label = 'Deleted', address = 'Deleted', details = 'Deleted',
        building = 'Deleted', floor = null, landmark = null,
        delivery_notes = null,
        location = extensions.st_setsrid(extensions.st_makepoint(0, 0), 4326),
        is_default = false, archived_at = coalesce(archived_at, v_now),
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
      p_account_id, 'CUSTOMER_ACCOUNT_ANONYMIZED', 'customer_account', p_account_id,
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

  return pg_catalog.jsonb_build_object(
    'prepared', true, 'alreadyDeleted', false, 'deletionQueued', true
  );
end;
$$;

create function public.claim_customer_account_deletions(
  p_worker_id text,
  p_limit integer default 20
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_jobs jsonb;
begin
  if nullif(pg_catalog.btrim(p_worker_id), '') is null
    or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid deletion worker claim';
  end if;

  update private.customer_account_deletions deletion
  set locked_at = null, locked_by = null,
      available_at = pg_catalog.clock_timestamp(),
      last_error = 'stale deletion worker claim recovered'
  where deletion.state = 'DELETION_PENDING'
    and deletion.locked_at <= pg_catalog.clock_timestamp() - interval '2 minutes';

  with candidates as (
    select deletion.account_id
    from private.customer_account_deletions deletion
    where deletion.state = 'DELETION_PENDING'
      and deletion.available_at <= pg_catalog.clock_timestamp()
      and deletion.locked_at is null
    order by deletion.available_at, deletion.requested_at, deletion.account_id
    for update skip locked
    limit p_limit
  ), claimed as (
    update private.customer_account_deletions deletion
    set locked_at = pg_catalog.clock_timestamp(),
        locked_by = pg_catalog.btrim(p_worker_id),
        attempts = deletion.attempts + 1,
        last_error = null
    from candidates
    where deletion.account_id = candidates.account_id
    returning deletion.account_id, deletion.attempts
  )
  select coalesce(
    pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'accountId', claimed.account_id,
      'attempt', claimed.attempts
    ) order by claimed.account_id),
    '[]'::jsonb
  ) into v_jobs
  from claimed;
  return v_jobs;
end;
$$;

create function public.complete_customer_account_deletion(
  p_account_id uuid,
  p_worker_id text,
  p_succeeded boolean,
  p_error text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_deletion private.customer_account_deletions%rowtype;
  v_delay integer;
begin
  if p_account_id is null or nullif(pg_catalog.btrim(p_worker_id), '') is null
    or p_succeeded is null then
    raise exception using errcode = '22023', message = 'valid deletion completion required';
  end if;
  select deletion.* into v_deletion
  from private.customer_account_deletions deletion
  where deletion.account_id = p_account_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'account deletion not found';
  end if;
  if v_deletion.state = 'DELETED' then
    return pg_catalog.jsonb_build_object('deleted', true, 'idempotentReplay', true);
  end if;
  if v_deletion.locked_by <> pg_catalog.btrim(p_worker_id) then
    raise exception using errcode = '40001', message = 'deletion worker claim lost';
  end if;

  if p_succeeded then
    perform public.finalize_customer_account_deletion(p_account_id);
    return pg_catalog.jsonb_build_object('deleted', true, 'idempotentReplay', false);
  end if;

  v_delay := least(3600, 15 * (2 ^ least(v_deletion.attempts - 1, 8))::integer);
  update private.customer_account_deletions
  set locked_at = null, locked_by = null,
      available_at = pg_catalog.clock_timestamp() + pg_catalog.make_interval(secs => v_delay),
      last_error = pg_catalog.left(coalesce(nullif(p_error, ''), 'Auth deletion failed'), 1000)
  where account_id = p_account_id;
  return pg_catalog.jsonb_build_object(
    'deleted', false,
    'retryAt', pg_catalog.clock_timestamp() + pg_catalog.make_interval(secs => v_delay)
  );
end;
$$;

revoke execute on function public.prepare_customer_account_deletion(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.claim_customer_account_deletions(text, integer)
  from public, anon, authenticated;
revoke execute on function public.complete_customer_account_deletion(uuid, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.prepare_customer_account_deletion(uuid, text) to service_role;
grant execute on function public.claim_customer_account_deletions(text, integer) to service_role;
grant execute on function public.complete_customer_account_deletion(uuid, text, boolean, text)
  to service_role;

alter table public.dastak_device_tokens add column provider_identity bytea;
create unique index dastak_device_tokens_web_provider_identity_uidx
  on public.dastak_device_tokens (platform, provider_identity)
  where platform = 'web' and provider_identity is not null;

alter table dastak_v1.notification_routes
  drop constraint notification_routes_platform_check;
alter table dastak_v1.notification_routes
  add constraint notification_routes_platform_check
  check (platform in ('ios', 'web', 'all'));
alter table dastak_v1.notification_routes alter column platform set default 'all';
-- Platform is protected as route identity during normal operation. This
-- one-time additive expansion is migration-owned and retains version history.
alter table dastak_v1.notification_routes disable trigger notification_routes_guard;
update dastak_v1.notification_routes
set platform = 'all', version = version + 1, updated_at = pg_catalog.now()
where platform = 'ios';
alter table dastak_v1.notification_routes enable trigger notification_routes_guard;

alter table dastak_v1.notification_intents
  drop constraint notification_intents_platform_check;
alter table dastak_v1.notification_intents
  add constraint notification_intents_platform_check check (platform in ('ios', 'web'));

do $$
declare v_constraint record;
begin
  for v_constraint in
    select constraint_row.conname
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid = 'dastak_v1.notification_intents'::regclass
      and constraint_row.contype = 'u'
      and (
        select pg_catalog.array_agg(attribute.attname order by key.ordinality)
        from pg_catalog.unnest(constraint_row.conkey) with ordinality as key(attnum, ordinality)
        join pg_catalog.pg_attribute attribute
          on attribute.attrelid = constraint_row.conrelid
          and attribute.attnum = key.attnum
      ) = array['event_id', 'recipient_account_id', 'notification_type']::name[]
  loop
    execute pg_catalog.format(
      'alter table dastak_v1.notification_intents drop constraint %I',
      v_constraint.conname
    );
  end loop;
end;
$$;

alter table dastak_v1.notification_intents
  add constraint notification_intents_event_recipient_type_platform_key
  unique (event_id, recipient_account_id, notification_type, platform);

create or replace function dastak_v1_api.fanout_pending_outbox_events(
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
  v_platform text;
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
          from dastak_v1_api.notification_recipients(v_event.id, v_route.audience) recipient
        loop
          for v_platform in
            select candidate.platform
            from pg_catalog.unnest(
              case when v_route.platform = 'all'
                then array['ios', 'web']::text[]
                else array[v_route.platform]::text[]
              end
            ) candidate(platform)
          loop
            insert into dastak_v1.notification_intents (
              event_id, recipient_account_id, notification_type,
              platform, title, body, payload
            ) values (
              v_event.id, v_recipient.account_id, v_route.notification_type,
              v_platform, v_route.title, v_route.body,
              pg_catalog.jsonb_build_object(
                'entityType', 'dastakV1Order',
                'entityId', v_order_id,
                'orderId', v_order_id,
                'eventType', v_event.event_type
              )
            )
            on conflict on constraint notification_intents_event_recipient_type_platform_key
            do nothing
            returning id into v_intent_id;
            if v_intent_id is null then
              select intent.id into v_intent_id
              from dastak_v1.notification_intents intent
              where intent.event_id = v_event.id
                and intent.recipient_account_id = v_recipient.account_id
                and intent.notification_type = v_route.notification_type
                and intent.platform = v_platform;
            else
              v_intent_count := v_intent_count + 1;
            end if;
            insert into dastak_v1.notification_deliveries (
              intent_id, event_id, recipient_account_id, device_token_id
            )
            select v_intent_id, v_event.id, v_recipient.account_id, token.id
            from public.dastak_device_tokens token
            where token.account_id = v_recipient.account_id
              and token.platform = v_platform
              and token.disabled_at is null
            on conflict (intent_id, device_token_id) do nothing;
            get diagnostics v_inserted = row_count;
            v_delivery_count := v_delivery_count + v_inserted;
            v_intent_id := null;
          end loop;
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
      set status = case when event.attempts >= v_max_attempts
            then 'DEAD_LETTER'::dastak_v1.outbox_status
            else 'PENDING'::dastak_v1.outbox_status end,
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

create or replace function public.dastak_v1_register_device_token(
  p_account_id uuid,
  p_device_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := pg_catalog.btrim(p_device_token);
  v_subscription jsonb;
  v_endpoint text;
  v_provider_identity bytea;
begin
  if p_account_id is null or nullif(v_token, '') is null
    or p_platform not in ('ios', 'web')
    or (p_platform = 'ios' and pg_catalog.char_length(v_token) > 512)
    or (p_platform = 'web' and pg_catalog.char_length(v_token) > 4096) then
    raise exception using errcode = '22023', message = 'invalid device token';
  end if;

  if p_platform = 'web' then
    begin
      v_subscription := v_token::jsonb;
    exception when others then
      raise exception using errcode = '22023', message = 'invalid web push subscription';
    end;
    v_endpoint := v_subscription ->> 'endpoint';
    if pg_catalog.jsonb_typeof(v_subscription) <> 'object'
      or v_endpoint !~ '^https://[^[:space:]]+$'
      or nullif(v_subscription #>> '{keys,auth}', '') is null
      or nullif(v_subscription #>> '{keys,p256dh}', '') is null
      or pg_catalog.char_length(v_subscription #>> '{keys,auth}') > 512
      or pg_catalog.char_length(v_subscription #>> '{keys,p256dh}') > 512 then
      raise exception using errcode = '22023', message = 'invalid web push subscription';
    end if;
    v_provider_identity := extensions.digest(v_endpoint, 'sha256');
  end if;

  if p_platform = 'web' then
    insert into public.dastak_device_tokens (
      account_id, device_token, platform, provider_identity, last_seen_at
    ) values (
      p_account_id, v_token, p_platform, v_provider_identity,
      pg_catalog.clock_timestamp()
    )
    on conflict (platform, provider_identity)
      where platform = 'web' and provider_identity is not null
    do update
    set account_id = excluded.account_id,
        device_token = excluded.device_token,
        last_seen_at = excluded.last_seen_at,
        disabled_at = null,
        disabled_reason = null,
        version = public.dastak_device_tokens.version + 1;
  else
    insert into public.dastak_device_tokens (
      account_id, device_token, platform, last_seen_at
    ) values (
      p_account_id, v_token, p_platform, pg_catalog.clock_timestamp()
    )
    on conflict (device_token) do update
    set account_id = excluded.account_id,
        platform = excluded.platform,
        last_seen_at = excluded.last_seen_at,
        disabled_at = null,
        disabled_reason = null,
        version = public.dastak_device_tokens.version + 1;
  end if;
end;
$$;

revoke execute on function public.dastak_v1_register_device_token(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.dastak_v1_register_device_token(uuid, text, text)
  to service_role;
