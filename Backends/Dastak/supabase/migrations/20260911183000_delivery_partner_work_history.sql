-- Rider-safe terminal work history across the existing delivery domains.
-- This is a read-only projection. Assignment, custody and accounting remain
-- owned by their existing domain tables and commands.

create index if not exists delivery_missions_terminal_rider_history_idx
  on dastak_v1.delivery_missions (assigned_rider_id, updated_at desc, id desc)
  where assigned_rider_id is not null and status in ('DELIVERED', 'CANCELLED');

create index if not exists return_missions_terminal_rider_history_idx
  on dastak_v1.return_missions (assigned_rider_id, updated_at desc, id desc)
  where assigned_rider_id is not null and status in ('COMPLETED', 'CANCELLED');

create index if not exists delivery_assignment_partner_history_idx
  on private.delivery_assignment_attempts (partner_account_id, updated_at desc, id desc)
  where status in ('completed', 'cancelled');

create index if not exists parcel_assignment_partner_history_idx
  on private.parcel_assignment_attempts (partner_account_id, updated_at desc, id desc)
  where status in ('completed', 'cancelled');

create or replace function public.dastak_delivery_partner_work_history(
  p_account_id uuid,
  p_limit integer default 30
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with terminal_work as (
    select
      'V1_DELIVERY'::text as kind,
      mission.id as work_id,
      customer_order.display_order_number as reference,
      mission.status::text as status,
      coalesce(mission.assigned_at, mission.created_at) as started_at,
      coalesce(mission.delivered_at, mission.cancelled_at, mission.updated_at) as ended_at,
      (
        select coalesce(pg_catalog.sum(stop.declared_package_count), 0)::integer
        from dastak_v1.delivery_stops as stop
        where stop.mission_id = mission.id
      ) as package_count,
      null::integer as payout_paise,
      case mission.status::text
        when 'DELIVERED' then 'COMPLETED'
        else 'CANCELLED'
      end::text as outcome
    from dastak_v1.delivery_missions as mission
    join dastak_v1.orders as customer_order on customer_order.id = mission.order_id
    where mission.assigned_rider_id = p_account_id
      and mission.status in ('DELIVERED', 'CANCELLED')

    union all

    select
      'RETURN'::text,
      mission.id,
      customer_order.display_order_number,
      mission.status::text,
      coalesce(mission.assigned_at, mission.created_at),
      coalesce(mission.completed_at, mission.updated_at),
      (
        select coalesce(pg_catalog.sum(stop.package_count), 0)::integer
        from dastak_v1.return_stops as stop
        where stop.return_mission_id = mission.id
      ),
      null::integer,
      case mission.status::text
        when 'COMPLETED' then 'RETURNED'
        else 'CANCELLED'
      end::text
    from dastak_v1.return_missions as mission
    join dastak_v1.orders as customer_order on customer_order.id = mission.order_id
    where mission.assigned_rider_id = p_account_id
      and mission.status in ('COMPLETED', 'CANCELLED')

    union all

    select
      'LEGACY_DELIVERY'::text,
      assignment.id,
      'Order ' || pg_catalog.left(merchant_order.id::text, 8),
      merchant_order.status,
      coalesce(assignment.responded_at, assignment.offered_at),
      assignment.updated_at,
      null::integer,
      null::integer,
      case assignment.status
        when 'completed' then 'COMPLETED'
        else 'CANCELLED'
      end::text
    from private.delivery_assignment_attempts as assignment
    join private.merchant_orders as merchant_order on merchant_order.id = assignment.order_id
    where assignment.partner_account_id = p_account_id
      and assignment.status in ('completed', 'cancelled')

    union all

    select
      'PARCEL'::text,
      assignment.id,
      pg_catalog.left(parcel.declared_contents, 80),
      parcel.status,
      coalesce(assignment.responded_at, assignment.offered_at),
      assignment.updated_at,
      1::integer,
      parcel.courier_payout_paise,
      case assignment.status
        when 'completed' then 'COMPLETED'
        else 'CANCELLED'
      end::text
    from private.parcel_assignment_attempts as assignment
    join private.parcel_deliveries as parcel on parcel.id = assignment.parcel_id
    where assignment.partner_account_id = p_account_id
      and assignment.status in ('completed', 'cancelled')
  ), bounded as (
    select *
    from terminal_work
    order by ended_at desc, work_id desc
    limit greatest(1, least(coalesce(p_limit, 30), 50))
  )
  select pg_catalog.jsonb_build_object(
    'items',
    coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'kind', bounded.kind,
          'workId', bounded.work_id,
          'reference', bounded.reference,
          'status', bounded.status,
          'startedAt', bounded.started_at,
          'endedAt', bounded.ended_at,
          'packageCount', bounded.package_count,
          'payoutPaise', bounded.payout_paise,
          'outcome', bounded.outcome
        ) order by bounded.ended_at desc, bounded.work_id desc
      ),
      '[]'::jsonb
    )
  )
  from bounded;
$$;

revoke all on function public.dastak_delivery_partner_work_history(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.dastak_delivery_partner_work_history(uuid, integer)
  to service_role;
