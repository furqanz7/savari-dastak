-- Enforce drop-off completion distance and support priced passenger
-- cancellation during an active trip.

alter table if exists public.rides
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by text,
  add column if not exists cancellation_lat double precision,
  add column if not exists cancellation_lon double precision,
  add column if not exists cancellation_distance_m double precision,
  add column if not exists cancellation_fare numeric,
  add column if not exists fare numeric;

alter table if exists public.ride_history
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by text,
  add column if not exists cancellation_lat double precision,
  add column if not exists cancellation_lon double precision,
  add column if not exists cancellation_distance_m double precision,
  add column if not exists cancellation_fare numeric,
  add column if not exists fare numeric;

create or replace function public.distance_meters(
  p_from_lat double precision,
  p_from_lon double precision,
  p_to_lat double precision,
  p_to_lon double precision
)
returns double precision
language sql
immutable
set search_path = public, pg_temp
as $$
  select 6371000 * 2 * asin(
    sqrt(
      power(sin(radians(p_to_lat - p_from_lat) / 2), 2)
      + cos(radians(p_from_lat))
        * cos(radians(p_to_lat))
        * power(sin(radians(p_to_lon - p_from_lon) / 2), 2)
    )
  );
$$;

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
    status = 'completed',
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

create or replace function public.passenger_cancel_mid_trip(
  p_ride_id uuid,
  p_passenger_id uuid,
  p_cancel_lat double precision,
  p_cancel_lon double precision
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_pickup_lat double precision;
  v_pickup_lon double precision;
  v_estimated_distance_m double precision;
  v_estimated_fare numeric;
  v_cancel_distance_m double precision;
  v_cancel_fare numeric;
  v_updated_count integer := 0;
begin
  if (select auth.uid()) is null or (select auth.uid()) <> p_passenger_id then
    return jsonb_build_object('ok', false);
  end if;

  select
    r.pickup_lat,
    r.pickup_lon,
    nullif(r.estimated_distance_m, 0),
    r.estimated_fare
  into
    v_pickup_lat,
    v_pickup_lon,
    v_estimated_distance_m,
    v_estimated_fare
  from public.rides r
  where r.id = p_ride_id
    and r.passenger_id = p_passenger_id
    and r.status = 'in_progress';

  if v_pickup_lat is null or v_pickup_lon is null then
    return jsonb_build_object('ok', false);
  end if;

  v_cancel_distance_m := public.distance_meters(
    v_pickup_lat,
    v_pickup_lon,
    p_cancel_lat,
    p_cancel_lon
  );

  v_cancel_fare := round(
    greatest(
      30::numeric,
      coalesce(
        v_estimated_fare
          * least(1::numeric, (v_cancel_distance_m / nullif(v_estimated_distance_m, 0))::numeric),
        20::numeric + ((v_cancel_distance_m / 1000)::numeric * 12::numeric)
      )
    ),
    2
  );

  update public.rides
  set
    status = 'passenger_cancelled_in_trip',
    cancelled_at = now(),
    cancelled_by = 'passenger',
    cancellation_lat = p_cancel_lat,
    cancellation_lon = p_cancel_lon,
    cancellation_distance_m = v_cancel_distance_m,
    cancellation_fare = v_cancel_fare,
    fare = v_cancel_fare,
    fare_unlocked = true,
    ended_at = now()
  where id = p_ride_id
    and passenger_id = p_passenger_id
    and status = 'in_progress';

  get diagnostics v_updated_count = row_count;

  return jsonb_build_object(
    'ok', v_updated_count = 1,
    'fare', v_cancel_fare,
    'distance_m', v_cancel_distance_m
  );
end;
$$;

revoke all on function public.distance_meters(double precision, double precision, double precision, double precision) from public;
revoke all on function public.distance_meters(double precision, double precision, double precision, double precision) from anon;
revoke all on function public.distance_meters(double precision, double precision, double precision, double precision) from authenticated;
grant execute on function public.distance_meters(double precision, double precision, double precision, double precision) to authenticated;

revoke all on function public.complete_ride(uuid, uuid, double precision) from public;
revoke all on function public.complete_ride(uuid, uuid, double precision) from anon;
revoke all on function public.complete_ride(uuid, uuid, double precision) from authenticated;
grant execute on function public.complete_ride(uuid, uuid, double precision) to authenticated;

revoke all on function public.passenger_cancel_mid_trip(uuid, uuid, double precision, double precision) from public;
revoke all on function public.passenger_cancel_mid_trip(uuid, uuid, double precision, double precision) from anon;
revoke all on function public.passenger_cancel_mid_trip(uuid, uuid, double precision, double precision) from authenticated;
grant execute on function public.passenger_cancel_mid_trip(uuid, uuid, double precision, double precision) to authenticated;
