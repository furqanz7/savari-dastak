-- Customer Orders completion: retain immutable order context, expose an
-- authoritative preparation estimate, and expose only customer-safe live
-- delivery tracking. Retail fulfilment identities and pickup routing remain
-- private.

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_pre_customer_orders_completion;

create function dastak_v1_api.order_json(
  p_order_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_status text;
  v_estimated_ready_at timestamptz;
  v_running_late boolean := false;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_destination jsonb;
  v_rider_location jsonb;
  v_rider_location_updated_at timestamptz;
  v_distance_to_destination_meters bigint;
begin
  v_result := dastak_v1_api.order_json_pre_customer_orders_completion(
    p_order_id,
    p_customer_id
  );
  if v_result is null then
    return null;
  end if;

  v_status := v_result ->> 'status';

  if v_status in ('PAID', 'PREPARING') then
    select
      max(fulfilment.estimated_ready_at),
      coalesce(
        bool_or(
          fulfilment.status = 'PREPARING'
          and fulfilment.estimated_ready_at < pg_catalog.clock_timestamp()
        ),
        false
      )
    into v_estimated_ready_at, v_running_late
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = p_order_id
      and fulfilment.status in ('PREPARING', 'READY', 'PICKED_UP');

    v_result := pg_catalog.jsonb_set(
      v_result,
      '{fulfilmentProgress}',
      coalesce(v_result -> 'fulfilmentProgress', '{}'::jsonb)
        || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'estimatedReadyAt', v_estimated_ready_at,
          'runningLate', v_running_late
        )),
      true
    );
  end if;

  if v_status in ('OUT_FOR_DELIVERY', 'DELIVERED') then
    select mission.*
    into v_mission
    from dastak_v1.delivery_missions mission
    where mission.order_id = p_order_id
    order by mission.created_at desc, mission.id desc
    limit 1;

    v_destination := v_result -> 'deliveryAddress';

    if v_status = 'OUT_FOR_DELIVERY'
      and v_mission.assigned_rider_id is not null then
      select
        pg_catalog.jsonb_build_object(
          'latitude', extensions.st_y(availability.location),
          'longitude', extensions.st_x(availability.location)
        ),
        availability.last_seen_at
      into v_rider_location, v_rider_location_updated_at
      from private.delivery_partner_availability availability
      where availability.account_id = v_mission.assigned_rider_id
        and availability.status = 'online'
        and availability.available_until > pg_catalog.clock_timestamp()
        and availability.location is not null;

      if v_rider_location is not null
        and pg_catalog.jsonb_typeof(v_destination -> 'latitude') = 'number'
        and pg_catalog.jsonb_typeof(v_destination -> 'longitude') = 'number' then
        v_distance_to_destination_meters := pg_catalog.round(
          extensions.st_distance(
            extensions.st_setsrid(extensions.st_makepoint(
              (v_rider_location ->> 'longitude')::double precision,
              (v_rider_location ->> 'latitude')::double precision
            ), 4326)::extensions.geography,
            extensions.st_setsrid(extensions.st_makepoint(
              (v_destination ->> 'longitude')::double precision,
              (v_destination ->> 'latitude')::double precision
            ), 4326)::extensions.geography
          )
        )::bigint;
      end if;
    end if;

    v_result := pg_catalog.jsonb_set(
      v_result,
      '{delivery}',
      coalesce(v_result -> 'delivery', '{}'::jsonb)
        || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'outForDeliveryAt', v_mission.out_for_delivery_at,
          'riderLocation', v_rider_location,
          'riderLocationUpdatedAt', v_rider_location_updated_at,
          'distanceToDestinationMeters', v_distance_to_destination_meters
        )),
      true
    );
  end if;

  return v_result;
end;
$$;

revoke all on function
  dastak_v1_api.order_json_pre_customer_orders_completion(uuid, uuid)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.order_json(uuid, uuid)
  from public, anon, authenticated;
grant execute on function dastak_v1_api.order_json(uuid, uuid)
  to authenticated;

comment on function dastak_v1_api.order_json(uuid, uuid) is
  'Customer-safe V1 order projection with immutable destination/recipient context, preparation ETA and active final-mile rider location; no retail merchant identity or pickup route is exposed.';
