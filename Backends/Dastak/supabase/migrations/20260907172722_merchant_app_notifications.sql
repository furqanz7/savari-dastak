-- Customer/Delivery share com.dastak.app; Merchant is a separate APNs topic.
-- Existing tokens retain a null environment and use the worker's legacy environment.
alter table public.dastak_device_tokens
  add column application_id text not null default 'com.dastak.app',
  add column apns_environment text,
  add constraint dastak_device_tokens_application_check
    check (application_id in ('com.dastak.app', 'com.dastak.merchant')),
  add constraint dastak_device_tokens_environment_check
    check (apns_environment is null or (platform = 'ios' and apns_environment in ('sandbox', 'production')));
alter table public.dastak_device_tokens drop constraint dastak_device_tokens_device_token_key;
create unique index dastak_device_tokens_ios_application_uidx
  on public.dastak_device_tokens (device_token, application_id, (coalesce(apns_environment, 'legacy')))
  where platform = 'ios';
alter table dastak_v1.notification_deliveries add column claimed_token_version bigint;

create or replace function dastak_v1_api.register_app_device_token(
  p_account_id uuid,
  p_device_token text,
  p_platform text,
  p_application_id text,
  p_apns_environment text
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

  if p_application_id not in ('com.dastak.app', 'com.dastak.merchant')
    or p_application_id is null
    or (p_apns_environment is not null and p_apns_environment not in ('sandbox', 'production'))
    or (p_platform = 'web' and (p_application_id <> 'com.dastak.app' or p_apns_environment is not null))
  then raise exception using errcode = '22023', message = 'invalid notification application'; end if;

  -- Serialize re-registration and reject stale deliveries after account changes.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_token, 0));
  if p_platform = 'ios' and p_apns_environment is not null then
    update public.dastak_device_tokens
    set apns_environment = p_apns_environment
    where device_token = v_token and platform = 'ios'
      and application_id = p_application_id and apns_environment is null
      and not exists (
        select 1 from public.dastak_device_tokens existing
        where existing.device_token = v_token and existing.application_id = p_application_id
          and existing.apns_environment = p_apns_environment and existing.platform = 'ios'
      );
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
      account_id, device_token, platform, application_id, apns_environment, last_seen_at
    ) values (
      p_account_id, v_token, p_platform, p_application_id, p_apns_environment, pg_catalog.clock_timestamp()
    )
    on conflict (device_token, application_id, (coalesce(apns_environment, 'legacy')))
      where platform = 'ios' do update
    set account_id = excluded.account_id,
        platform = excluded.platform,
        last_seen_at = excluded.last_seen_at,
        disabled_at = null,
        disabled_reason = null,
        version = public.dastak_device_tokens.version + 1;
  end if;
end;
$$;

create or replace function public.dastak_v1_register_device_token(
  p_account_id uuid, p_device_token text, p_platform text
) returns void language sql security invoker set search_path = '' as $$
  select dastak_v1_api.register_app_device_token(
    p_account_id, p_device_token, p_platform, 'com.dastak.app', null);
$$;

create function public.dastak_v1_register_app_device_token(
  p_account_id uuid, p_device_token text, p_platform text,
  p_application_id text, p_apns_environment text
) returns void language sql security invoker set search_path = '' as $$
  select dastak_v1_api.register_app_device_token(
    p_account_id, p_device_token, p_platform, p_application_id, p_apns_environment);
$$;
revoke all on function dastak_v1_api.register_app_device_token(uuid,text,text,text,text)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_register_app_device_token(uuid,text,text,text,text)
  from public, anon, authenticated;
grant execute on function dastak_v1_api.register_app_device_token(uuid,text,text,text,text),
  public.dastak_v1_register_app_device_token(uuid,text,text,text,text) to service_role;

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
              and (v_platform = 'web' or token.application_id = case
                when v_route.audience = 'MERCHANT' then 'com.dastak.merchant'
                else 'com.dastak.app' end)
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

create or replace function dastak_v1_api.claim_notification_deliveries(
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
      last_error = 'device token disabled, transferred or wrong application'
  from public.dastak_device_tokens token, dastak_v1.notification_intents intent
  where delivery.device_token_id = token.id
    and delivery.status = 'PENDING'
    and intent.id = delivery.intent_id
    and (token.disabled_at is not null or token.account_id <> delivery.recipient_account_id
      or (token.platform = 'ios' and token.application_id <> case
        when intent.notification_type like 'merchant.%' then 'com.dastak.merchant' else 'com.dastak.app' end));
  with candidates as (
    select delivery.id, token.version as token_version
    from dastak_v1.notification_deliveries delivery
    join public.dastak_device_tokens token on token.id = delivery.device_token_id
    join dastak_v1.notification_intents intent on intent.id = delivery.intent_id
    where delivery.status = 'PENDING'
      and delivery.available_at <= pg_catalog.clock_timestamp()
      and token.disabled_at is null
      -- Recheck in the claim statement: registration may commit after suppression.
      and token.account_id = delivery.recipient_account_id
      and (token.platform = 'web' or token.application_id = case
        when intent.notification_type like 'merchant.%' then 'com.dastak.merchant'
        else 'com.dastak.app' end)
    order by delivery.available_at, delivery.created_at, delivery.id
    for update of delivery skip locked
    limit p_limit
  ), claimed as (
    update dastak_v1.notification_deliveries delivery
    set status = 'IN_FLIGHT', locked_at = pg_catalog.clock_timestamp(),
        locked_by = p_worker_id, attempts = delivery.attempts + 1,
        last_error = null, claimed_token_version = candidates.token_version
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
      'applicationId', token.application_id,
      'apnsEnvironment', token.apns_environment,
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

create or replace function dastak_v1_api.complete_notification_delivery(
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
      where token.id = v_delivery.device_token_id
        and token.account_id = v_delivery.recipient_account_id
        and token.version = v_delivery.claimed_token_version;
      update dastak_v1.notification_deliveries delivery
      set status = 'SUPPRESSED', last_error = 'device token disabled'
      where delivery.device_token_id = v_delivery.device_token_id
        and delivery.status = 'PENDING'
        and exists (select 1 from public.dastak_device_tokens token
          where token.id = delivery.device_token_id and token.disabled_at is not null);
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

insert into dastak_v1.notification_routes(event_type, audience, notification_type, title, body)
values ('RESTAURANT_REQUEST_OFFERED', 'MERCHANT', 'merchant.restaurant_request',
  'New food order', 'Review the items and confirm your preparation time.')
on conflict do nothing;

CREATE OR REPLACE FUNCTION dastak_v1_api.notification_recipients(p_event_id uuid, p_audience text)
 RETURNS TABLE(account_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
        and (fulfilment.status <> 'RELEASED'
          or (v_event.event_type = 'ORDER_CANCELLED' and fulfilment.release_reason = 'ADMIN_CANCELLED'))
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
        'MERCHANT_OPPORTUNITY_OFFERED', 'RECOVERY_OPPORTUNITY_OFFERED', 'RESTAURANT_REQUEST_OFFERED'
      ) then 'merchant.opportunities.respond' else 'merchant.fulfilment.manage' end,
      branch.id
    );
end;
$function$;

notify pgrst, 'reload schema';
