-- Keep normally completed rides observable until the driver collects payment.
-- The mobile app moves ride_finished -> payment_collected after cash collection.

alter table if exists public.rides
  add column if not exists payment_collected_at timestamptz;

alter table if exists public.ride_history
  add column if not exists payment_collected_at timestamptz;

create or replace function public.complete_ride(
  p_ride_id uuid,
  p_driver_id uuid,
  p_dropoff_threshold_m double precision default 100
)
returns boolean
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_drop_lat double precision;
  v_drop_lon double precision;
  v_driver_lat double precision;
  v_driver_lon double precision;
  v_distance_m double precision;
  v_updated_count integer := 0;
begin
  if (select auth.uid()) is null or (select auth.uid()) <> p_driver_id then
    return false;
  end if;

  select r.drop_lat, r.drop_lon
  into v_drop_lat, v_drop_lon
  from public.rides r
  where r.id = p_ride_id
    and (r.driver_id = p_driver_id or r.assigned_driver_id = p_driver_id)
    and r.status = 'in_progress';

  if v_drop_lat is null or v_drop_lon is null then
    return false;
  end if;

  select dl.latitude, dl.longitude
  into v_driver_lat, v_driver_lon
  from public.driver_locations dl
  where dl.driver_id = p_driver_id;

  if v_driver_lat is null or v_driver_lon is null then
    return false;
  end if;

  v_distance_m := public.distance_meters(v_driver_lat, v_driver_lon, v_drop_lat, v_drop_lon);

  if v_distance_m > p_dropoff_threshold_m then
    return false;
  end if;

  update public.rides
  set
    status = 'ride_finished',
    ended_at = now(),
    fare = coalesce(fare, estimated_fare),
    fare_unlocked = true
  where id = p_ride_id
    and (driver_id = p_driver_id or assigned_driver_id = p_driver_id)
    and status = 'in_progress';

  get diagnostics v_updated_count = row_count;
  return v_updated_count = 1;
end;
$$;

revoke all on function public.complete_ride(uuid, uuid, double precision) from public;
revoke all on function public.complete_ride(uuid, uuid, double precision) from anon;
revoke all on function public.complete_ride(uuid, uuid, double precision) from authenticated;
grant execute on function public.complete_ride(uuid, uuid, double precision) to authenticated;
