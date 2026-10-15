-- Notification-only preflight. Never changes an offer, mission, order or token.
-- Run immediately before each provider attempt, including reclaimed/retried work.
create or replace function dastak_v1_api.prepare_notification_delivery(
  p_delivery_id uuid, p_worker_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery dastak_v1.notification_deliveries%rowtype;
  v_type text;
  v_deadline timestamptz;
begin
  if p_delivery_id is null or nullif(pg_catalog.btrim(p_worker_id), '') is null then
    raise exception using errcode = '22023', message = 'invalid notification preflight';
  end if;
  select d.* into v_delivery from dastak_v1.notification_deliveries d
  where d.id = p_delivery_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'notification not found'; end if;
  if v_delivery.status in ('SENT', 'SUPPRESSED', 'DEAD_LETTER') then
    return pg_catalog.jsonb_build_object('deliver', false);
  end if;
  if v_delivery.status <> 'IN_FLIGHT' or v_delivery.locked_by is distinct from p_worker_id then
    raise exception using errcode = '40001', message = 'notification claim lost';
  end if;
  select i.notification_type into v_type from dastak_v1.notification_intents i
  where i.id = v_delivery.intent_id;
  if v_type is distinct from 'rider.mission_offer' then
    return pg_catalog.jsonb_build_object('deliver', true);
  end if;

  -- A pool event can contain several riders. Resolve this exact recipient and
  -- pool round, not another rider's or a later round's acceptance deadline.
  select o.respond_by into v_deadline
  from dastak_v1.domain_events_outbox e
  join dastak_v1.delivery_missions m on m.id = e.aggregate_id
  join dastak_v1.delivery_offers o on o.mission_id = m.id
    and o.rider_id = v_delivery.recipient_account_id
    and o.pool_round::text = e.payload ->> 'poolRound'
  where e.id = v_delivery.event_id and e.event_type = 'RIDER_POOL_OPENED'
    and e.aggregate_type = 'DELIVERY_MISSION'
    and o.status = 'OFFERED'
    and pg_catalog.date_trunc('second', o.respond_by) > pg_catalog.clock_timestamp()
    and m.status = 'SEARCHING_RIDER' and m.assigned_rider_id is null
    and m.pool_round = o.pool_round;
  if v_deadline is null then
    update dastak_v1.notification_deliveries
    set status = 'SUPPRESSED', locked_at = null, locked_by = null,
        last_error = 'delivery offer expired or no longer actionable'
    where id = v_delivery.id;
    return pg_catalog.jsonb_build_object('deliver', false);
  end if;
  return pg_catalog.jsonb_build_object('deliver', true, 'expiresAt', v_deadline);
end;
$$;

revoke all on function dastak_v1_api.prepare_notification_delivery(uuid,text) from public,anon,authenticated;
grant execute on function dastak_v1_api.prepare_notification_delivery(uuid,text) to service_role;

create or replace function public.dastak_v1_prepare_notification_delivery(
  p_delivery_id uuid, p_worker_id text
)
returns jsonb language sql security invoker set search_path = ''
as $$ select dastak_v1_api.prepare_notification_delivery(p_delivery_id,p_worker_id); $$;
revoke all on function public.dastak_v1_prepare_notification_delivery(uuid,text) from public,anon,authenticated;
grant execute on function public.dastak_v1_prepare_notification_delivery(uuid,text) to service_role;
