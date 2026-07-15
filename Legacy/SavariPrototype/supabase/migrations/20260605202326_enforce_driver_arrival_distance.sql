-- Enforce that a driver can only mark arrival when their latest stored
-- location is close to the ride pickup.

create or replace function public.mark_driver_arrived(
  p_ride_id uuid,
  p_driver_id uuid,
  p_arrival_threshold_m double precision default 100
)
returns boolean
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_pickup_lat double precision;
  v_pickup_lon double precision;
  v_driver_lat double precision;
  v_driver_lon double precision;
  v_distance_m double precision;
  v_updated_count integer := 0;
begin
  if (select auth.uid()) is null or (select auth.uid()) <> p_driver_id then
    return false;
  end if;

  select r.pickup_lat, r.pickup_lon
  into v_pickup_lat, v_pickup_lon
  from public.rides r
  where r.id = p_ride_id
    and (r.driver_id = p_driver_id or r.assigned_driver_id = p_driver_id)
    and r.status in ('assigned', 'accepted', 'driver_en_route');

  if v_pickup_lat is null or v_pickup_lon is null then
    return false;
  end if;

  select dl.latitude, dl.longitude
  into v_driver_lat, v_driver_lon
  from public.driver_locations dl
  where dl.driver_id = p_driver_id;

  if v_driver_lat is null or v_driver_lon is null then
    return false;
  end if;

  v_distance_m :=
    6371000 * 2 * asin(
      sqrt(
        power(sin(radians(v_pickup_lat - v_driver_lat) / 2), 2)
        + cos(radians(v_driver_lat))
          * cos(radians(v_pickup_lat))
          * power(sin(radians(v_pickup_lon - v_driver_lon) / 2), 2)
      )
    );

  if v_distance_m > p_arrival_threshold_m then
    return false;
  end if;

  update public.rides
  set
    status = 'arrived',
    arrived_at = now(),
    driver_id = p_driver_id,
    assigned_driver_id = coalesce(assigned_driver_id, p_driver_id)
  where id = p_ride_id
    and (driver_id = p_driver_id or assigned_driver_id = p_driver_id)
    and status in ('assigned', 'accepted', 'driver_en_route');

  get diagnostics v_updated_count = row_count;
  return v_updated_count = 1;
end;
$$;

revoke all on function public.mark_driver_arrived(uuid, uuid, double precision) from public;
revoke all on function public.mark_driver_arrived(uuid, uuid, double precision) from anon;
revoke all on function public.mark_driver_arrived(uuid, uuid, double precision) from authenticated;
grant execute on function public.mark_driver_arrived(uuid, uuid, double precision) to authenticated;
