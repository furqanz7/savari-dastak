-- PREPARATION_STARTED is emitted once for the fulfilment workflow and once for
-- the parent order. Both events remain part of the audit trail, but only the
-- canonical order event may fan out customer and merchant notifications.
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
        select route.*
        from dastak_v1.notification_routes route
        where route.event_type = v_event.event_type
          and route.enabled
          and (
            v_event.event_type <> 'PREPARATION_STARTED'
            or v_event.aggregate_type = 'ORDER'
          )
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
