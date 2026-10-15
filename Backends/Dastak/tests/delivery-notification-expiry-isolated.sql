-- New empty LOCAL database only. Minimal fixtures; never run on a linked project.
\set ON_ERROR_STOP on
create role anon;
create role authenticated;
create role service_role;
create schema dastak_v1;
create schema dastak_v1_api;
grant usage on schema dastak_v1_api to service_role;
create table dastak_v1.notification_intents(id uuid primary key, notification_type text);
create table dastak_v1.notification_deliveries(
  id uuid primary key, intent_id uuid, event_id uuid, recipient_account_id uuid,
  status text, locked_at timestamptz, locked_by text, last_error text
);
create table dastak_v1.domain_events_outbox(
  id uuid primary key, aggregate_id uuid, aggregate_type text, event_type text, payload jsonb
);
create table dastak_v1.delivery_missions(
  id uuid primary key, status text, assigned_rider_id uuid, pool_round integer
);
create table dastak_v1.delivery_offers(
  mission_id uuid, rider_id uuid, pool_round integer, status text, respond_by timestamptz
);
\ir ../supabase/migrations/20261015154016_delivery_notification_offer_expiry.sql

create function public.fixture_notification(p_offer_status text default 'OFFERED',
  p_deadline timestamptz default now()+interval '1 minute', p_type text default 'rider.mission_offer')
returns uuid language plpgsql as $$
declare d uuid := gen_random_uuid(); i uuid := gen_random_uuid();
  e uuid := gen_random_uuid(); m uuid := gen_random_uuid();
  r uuid := '11111111-1111-4111-8111-111111111111';
begin
  insert into dastak_v1.delivery_missions values (m,'SEARCHING_RIDER',null,1);
  insert into dastak_v1.delivery_offers values (m,r,1,p_offer_status,p_deadline);
  insert into dastak_v1.domain_events_outbox values
    (e,m,'DELIVERY_MISSION','RIDER_POOL_OPENED','{"poolRound":1}');
  insert into dastak_v1.notification_intents values(i,p_type);
  insert into dastak_v1.notification_deliveries values(d,i,e,r,'IN_FLIGHT',now(),'worker',null);
  return d;
end $$;

do $$
declare d uuid; result jsonb; m uuid; before_offers jsonb;
begin
  if has_function_privilege('anon','public.dastak_v1_prepare_notification_delivery(uuid,text)','execute')
    or has_function_privilege('authenticated','public.dastak_v1_prepare_notification_delivery(uuid,text)','execute')
    or has_function_privilege('authenticated','dastak_v1_api.prepare_notification_delivery(uuid,text)','execute') then
    raise exception 'Notification guard exposed to application clients';
  end if;
  if (select prosecdef from pg_proc where oid='public.dastak_v1_prepare_notification_delivery(uuid,text)'::regprocedure) then
    raise exception 'Exposed wrapper must remain invoker';
  end if;
  d := fixture_notification();
  result := public.dastak_v1_prepare_notification_delivery(d,'worker');
  if result->>'deliver' <> 'true' or (result->>'expiresAt')::timestamptz <= now() then
    raise exception 'Fresh offer did not retain its deadline';
  end if;
  if (select status from dastak_v1.notification_deliveries where id=d) <> 'IN_FLIGHT' then
    raise exception 'Preflight consumed an actionable claim';
  end if;
  begin
    perform public.dastak_v1_prepare_notification_delivery(d,'different-worker');
    raise exception 'Wrong worker used the claim';
  exception when serialization_failure then null; end;

  -- Retry after deadline, even if the dispatch expiry worker has not run yet.
  update dastak_v1.delivery_offers o set respond_by=now()-interval '1 second'
    from dastak_v1.domain_events_outbox e, dastak_v1.notification_deliveries n
    where n.id=d and e.id=n.event_id and o.mission_id=e.aggregate_id;
  result := public.dastak_v1_prepare_notification_delivery(d,'worker');
  if result->>'deliver' <> 'false' or
    (select status from dastak_v1.notification_deliveries where id=d) <> 'SUPPRESSED' or
    (select locked_by from dastak_v1.notification_deliveries where id=d) is not null then
    raise exception 'Expired retry was not durably suppressed';
  end if;
  if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'false' then
    raise exception 'Suppressed claim replay reopened';
  end if;

  foreach result in array array['{"status":"ACCEPTED"}'::jsonb,'{"status":"EXPIRED"}'::jsonb,'{"status":"DECLINED"}'::jsonb] loop
    d := fixture_notification(result->>'status');
    if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'false' then
      raise exception 'Resolved offer was announced';
    end if;
  end loop;

  d := fixture_notification();
  select e.aggregate_id into m from dastak_v1.domain_events_outbox e
    join dastak_v1.notification_deliveries n on n.event_id=e.id where n.id=d;
  update dastak_v1.delivery_missions set status='ASSIGNED',assigned_rider_id=gen_random_uuid() where id=m;
  if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'false' then
    raise exception 'Already assigned mission was reoffered';
  end if;

  d := fixture_notification();
  select e.aggregate_id into m from dastak_v1.domain_events_outbox e
    join dastak_v1.notification_deliveries n on n.event_id=e.id where n.id=d;
  update dastak_v1.delivery_missions set pool_round=2 where id=m;
  insert into dastak_v1.delivery_offers values(m,'11111111-1111-4111-8111-111111111111',2,'OFFERED',now()+interval '2 minutes');
  if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'false' then
    raise exception 'New round revived an old round notification';
  end if;

  d := fixture_notification();
  update dastak_v1.notification_deliveries set recipient_account_id=gen_random_uuid() where id=d;
  if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'false' then
    raise exception 'Another rider inherited the offer deadline';
  end if;

  d := fixture_notification();
  select e.aggregate_id into m from dastak_v1.domain_events_outbox e
    join dastak_v1.notification_deliveries n on n.event_id=e.id where n.id=d;
  -- Matching rider in the matching round wins over a different rider's expiry.
  insert into dastak_v1.delivery_offers values(m,gen_random_uuid(),1,'OFFERED',now()-interval '1 day');
  if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'true' then
    raise exception 'Another rider poisoned a valid notification';
  end if;
  update dastak_v1.notification_deliveries set status='PENDING',locked_at=null,locked_by=null where id=d;
  begin
    perform public.dastak_v1_prepare_notification_delivery(d,'worker');
    raise exception 'Unclaimed notification was authorized';
  exception when serialization_failure then null; end;

  d := fixture_notification('EXPIRED',now()-interval '1 day','rider.assigned');
  if public.dastak_v1_prepare_notification_delivery(d,'worker')->>'deliver' <> 'true' then
    raise exception 'Offer suppression affected unrelated alerts';
  end if;

  -- SQL guard may mutate notification status only, never mission/offer state.
  d := fixture_notification('EXPIRED');
  select jsonb_agg(to_jsonb(o)) into before_offers from dastak_v1.delivery_offers o;
  perform public.dastak_v1_prepare_notification_delivery(d,'worker');
  if before_offers is distinct from (select jsonb_agg(to_jsonb(o)) from dastak_v1.delivery_offers o) then
    raise exception 'Notification preflight mutated an offer';
  end if;
end $$;

-- Exercise real service-role permissions through the invoker wrapper.
select fixture_notification() as allowed_delivery \gset
set role service_role;
select public.dastak_v1_prepare_notification_delivery(:'allowed_delivery'::uuid,'worker')->>'deliver' as service_role_can_preflight;
reset role;
select 'Offer expiry, retries, acceptance, assignment, pool/rider isolation, claim ownership and privileges passed' as result;
