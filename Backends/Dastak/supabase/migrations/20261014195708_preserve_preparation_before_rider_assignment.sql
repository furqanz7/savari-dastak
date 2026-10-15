-- Preserve preparation until every active fulfilment is genuinely Ready.
create function dastak_v1_api.order_waiting_for_rider(p_order_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from dastak_v1.orders o where o.id=p_order_id and o.status::text in ('PAID','PREPARING'))
    and exists(select 1 from dastak_v1.fulfilments f where f.order_id=p_order_id and f.status::text <> 'RELEASED')
    and not exists(select 1 from dastak_v1.fulfilments f where f.order_id=p_order_id and f.status::text not in ('READY','RELEASED'))
    and not exists(select 1 from dastak_v1.delivery_missions d where d.order_id=p_order_id
      and d.assigned_rider_id is not null and d.status::text in
        ('ASSIGNED','EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS','ALL_PACKAGES_PICKED_UP','OUT_FOR_DELIVERY','ARRIVED','DELIVERY_RECOVERY'));
$$;
revoke all on function dastak_v1_api.order_waiting_for_rider(uuid) from public, anon, authenticated;
grant execute on function dastak_v1_api.order_waiting_for_rider(uuid) to service_role;

CREATE OR REPLACE FUNCTION dastak_v1_api.claim_order_live_activities()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_jobs jsonb;
begin
  delete from dastak_v1.order_live_activities
    where ended_at < now() - interval '1 day' or expires_at < now() - interval '1 day';
  with states as materialized (
    select a.id,
      case when a.expires_at <= now() or s.id is null
        or exists(select 1 from private.revoked_account_sessions r where r.session_id = a.session_id and r.account_id = a.account_id)
        or not exists(select 1 from private.account_memberships m where m.account_id = a.account_id and m.role = 'customer'
          and (m.suspended_until is null or m.suspended_until <= now()))
        then 'ENDED'
        when o.status::text = 'OUT_FOR_DELIVERY' and mission.status::text = 'ARRIVED' then 'RIDER_ARRIVED'
        when dastak_v1_api.order_waiting_for_rider(o.id) then 'ASSIGNING_RIDER'
        else o.status::text end as status,
      o.version, greatest(o.updated_at, mission.updated_at) as updated_at
    from dastak_v1.order_live_activities a join dastak_v1.orders o on o.id = a.order_id
    left join auth.sessions s on s.id = a.session_id and s.user_id = a.account_id
    left join lateral (
      select d.status, d.updated_at from dastak_v1.delivery_missions d
      where d.order_id = o.id and d.assigned_rider_id is not null
        and d.status::text in ('ASSIGNED','EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS',
          'ALL_PACKAGES_PICKED_UP','OUT_FOR_DELIVERY','ARRIVED','DELIVERY_RECOVERY')
      order by d.created_at desc limit 1
    ) mission on true
    where a.ended_at is null
  ), candidates as (
    select a.id from dastak_v1.order_live_activities a join states s on s.id = a.id
    where a.ended_at is null and (a.lease_until is null or a.lease_until < now())
      and (a.last_sent_at is null or a.last_sent_at < now() - interval '90 seconds'
           or a.last_status is distinct from s.status or a.expires_at <= now())
    order by a.last_sent_at nulls first limit 20 for update of a skip locked
  ), claimed as (
    update dastak_v1.order_live_activities a set lease_id = gen_random_uuid(), lease_until = now() + interval '60 seconds'
    from candidates c where a.id = c.id returning a.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'leaseId', a.lease_id, 'tokenVersion', a.token_version,
    'token', a.push_token, 'environment', a.environment,
    'status', s.status, 'version', s.version,
    'updatedAt', extract(epoch from s.updated_at), 'timestamp', floor(extract(epoch from now()))
  )), '[]'::jsonb) into v_jobs from claimed a join states s on s.id = a.id;
  return v_jobs;
end $function$
;

CREATE OR REPLACE FUNCTION dastak_v1_api.order_json(p_order_id uuid, p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; h dastak_v1.verification_handoffs%rowtype;
begin
  result := dastak_v1_api.order_json_pre_tracking(p_order_id,p_customer_id);
  if auth.role()='authenticated' or pg_catalog.current_setting('role',true)='authenticated' then
    perform dastak_v1_api.assert_authenticated_actor(p_customer_id);
  end if;
  if result is null then return null; end if;
  -- Explicit check even when an underlying projection's behavior changes.
  if not exists(select 1 from dastak_v1.orders where id=p_order_id and customer_id=p_customer_id) then
    raise exception using errcode='42501',message='order not found';
  end if;
  result := result || pg_catalog.jsonb_build_object('tracking',dastak_v1_api.delivery_tracking_json(p_order_id));
  select * into h from dastak_v1.verification_handoffs where order_id=p_order_id and handoff_type='RIDER_TO_CUSTOMER'
    order by created_at desc limit 1;
  if result->'delivery' is not null and result->'delivery' <> 'null'::jsonb then
    result := pg_catalog.jsonb_set(result,'{delivery}',(result->'delivery')
      || pg_catalog.jsonb_build_object('pinVerified',h.pin_verified_at is not null));
  end if;
  if dastak_v1_api.order_waiting_for_rider(p_order_id) then
    result := result || pg_catalog.jsonb_build_object('customerState','ASSIGNING_RIDER',
      'fulfilmentProgress',coalesce(nullif(result->'fulfilmentProgress','null'::jsonb),'{}'::jsonb)
        || pg_catalog.jsonb_build_object('state','ASSIGNING_RIDER','title','Assigning your rider'));
  end if;
  return result;
end;
$function$
;


-- Alert at actual preparation completion, not at early mission creation.
update dastak_v1.notification_routes set enabled=false, version=version+1
where event_type='DELIVERY_MISSION_CREATED' and audience='CUSTOMER'
  and notification_type='customer.assigning_rider' and enabled;

insert into dastak_v1.notification_routes(event_type,audience,notification_type,platform,title,body)
values ('RIDER_ASSIGNMENT_PENDING','CUSTOMER','customer.assigning_rider','all',
  'Assigning your rider','Your order is ready. We’re finding a delivery partner to collect it.')
on conflict(event_type,audience,notification_type) do nothing;

create function dastak_v1_api.notify_rider_assignment_after_ready() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_version bigint;
begin
  if new.status::text <> 'READY' then return new; end if;
  if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
  -- Serialize the final Ready checks for merchants preparing the same order.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('dastak-v1-assignment:'||new.order_id::text,0));
  if not dastak_v1_api.order_waiting_for_rider(new.order_id) then return new; end if;
  select o.version into v_version from dastak_v1.orders o where o.id=new.order_id;
  insert into dastak_v1.domain_events_outbox(event_key,aggregate_type,aggregate_id,aggregate_version,event_type,payload)
  values(new.order_id::text||':RIDER_ASSIGNMENT_PENDING','ORDER',new.order_id,v_version,
    'RIDER_ASSIGNMENT_PENDING',pg_catalog.jsonb_build_object('orderId',new.order_id))
  on conflict(event_key) do nothing;
  return new;
end $$;
revoke all on function dastak_v1_api.notify_rider_assignment_after_ready() from public, anon, authenticated;
create constraint trigger fulfilment_ready_assignment_notification
after insert or update on dastak_v1.fulfilments
deferrable initially deferred for each row
execute function dastak_v1_api.notify_rider_assignment_after_ready();
