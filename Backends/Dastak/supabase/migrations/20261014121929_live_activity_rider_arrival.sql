-- Activity presentation only: ARRIVED is a delivery mission phase, not a new
-- order enum value. Keep the order lifecycle and the existing lease contract.
create or replace function dastak_v1_api.claim_order_live_activities() returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;
revoke all on function dastak_v1_api.claim_order_live_activities() from public, anon, authenticated;
grant execute on function dastak_v1_api.claim_order_live_activities() to service_role;
