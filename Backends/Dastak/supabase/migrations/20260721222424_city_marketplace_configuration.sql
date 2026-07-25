alter table public.service_zones
  add column center extensions.geometry(Point, 4326),
  add column coverage_radius_m integer default 10000,
  add column version bigint not null default 1,
  add column updated_at timestamptz not null default pg_catalog.now();

update public.service_zones as zone
set center = extensions.st_pointonsurface(zone.boundary),
    coverage_radius_m = coalesce(zone.coverage_radius_m, 10000);

alter table public.service_zones
  alter column center set not null,
  alter column coverage_radius_m set not null,
  add constraint service_zones_coverage_radius_check check (
    coverage_radius_m between 10000 and 30000
  ),
  add constraint service_zones_version_check check (version > 0),
  add constraint service_zones_center_covered_check check (
    extensions.st_covers(boundary, center)
  );

create index service_zones_center_gix
  on public.service_zones using gist (center);

create function private.prepare_service_zone_insert()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if new.center is null then
    new.center := extensions.st_pointonsurface(new.boundary);
  end if;
  if new.coverage_radius_m is null then
    new.coverage_radius_m := 10000;
  end if;
  return new;
end;
$$;

create trigger service_zones_prepare_insert
before insert on public.service_zones
for each row execute function private.prepare_service_zone_insert();

alter table private.merchant_order_rate_cards
  add column included_distance_m integer not null default 3000,
  add column base_delivery_fee_paise integer not null default 3500,
  add column delivery_fee_per_started_km_paise integer not null default 800,
  add column base_courier_payout_paise integer not null default 3000,
  add column courier_payout_per_started_km_paise integer not null default 700;

update private.merchant_order_rate_cards as rate
set base_delivery_fee_paise = rate.delivery_fee_paise,
    base_courier_payout_paise = rate.courier_payout_paise;

alter table private.merchant_order_rate_cards
  alter column merchant_commission_bps set default 1000,
  add constraint merchant_order_rate_cards_included_distance_check check (
    included_distance_m between 1000 and 30000
  ),
  add constraint merchant_order_rate_cards_base_delivery_fee_check check (
    base_delivery_fee_paise between 0 and 100000000
  ),
  add constraint merchant_order_rate_cards_delivery_per_km_check check (
    delivery_fee_per_started_km_paise between 0 and 100000000
  ),
  add constraint merchant_order_rate_cards_base_payout_check check (
    base_courier_payout_paise between 0 and base_delivery_fee_paise
  ),
  add constraint merchant_order_rate_cards_payout_per_km_check check (
    courier_payout_per_started_km_paise
      between 0 and delivery_fee_per_started_km_paise
  );

create function private.city_service_zone_json(
  zone_row public.service_zones
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'serviceZoneId', (zone_row).id,
    'cityName', (zone_row).name,
    'center', pg_catalog.jsonb_build_object(
      'latitude', extensions.st_y((zone_row).center),
      'longitude', extensions.st_x((zone_row).center)
    ),
    'coverageRadiusMeters', (zone_row).coverage_radius_m,
    'active', (zone_row).active,
    'version', (zone_row).version,
    'updatedAt', (zone_row).updated_at
  );
$$;

create function private.merchant_order_distance_rate_card_json(
  rate_row private.merchant_order_rate_cards
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'rateCardId', (rate_row).id,
    'serviceZoneId', (rate_row).service_zone_id,
    'includedDistanceMeters', (rate_row).included_distance_m,
    'baseDeliveryFee', pg_catalog.jsonb_build_object(
      'paise', (rate_row).base_delivery_fee_paise
    ),
    'deliveryFeePerStartedKilometre', pg_catalog.jsonb_build_object(
      'paise', (rate_row).delivery_fee_per_started_km_paise
    ),
    'baseCourierPayout', pg_catalog.jsonb_build_object(
      'paise', (rate_row).base_courier_payout_paise
    ),
    'courierPayoutPerStartedKilometre', pg_catalog.jsonb_build_object(
      'paise', (rate_row).courier_payout_per_started_km_paise
    ),
    'merchantCommissionBps', (rate_row).merchant_commission_bps,
    'active', (rate_row).active,
    'version', (rate_row).version,
    'updatedAt', (rate_row).updated_at
  );
$$;

create function private.calculate_merchant_order_distance_terms(
  rate_row private.merchant_order_rate_cards,
  p_route_distance_m integer
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_extra_started_km bigint;
  v_delivery_fee_paise bigint;
  v_courier_payout_paise bigint;
begin
  if p_route_distance_m is null or p_route_distance_m not between 0 and 1000000 then
    raise exception using
      errcode = '22023',
      message = 'merchant_order_route_distance_invalid';
  end if;

  v_extra_started_km := pg_catalog.ceil(
    greatest(
      0,
      p_route_distance_m - (rate_row).included_distance_m
    )::numeric / 1000
  )::bigint;
  v_delivery_fee_paise := (rate_row).base_delivery_fee_paise::bigint
    + v_extra_started_km * (rate_row).delivery_fee_per_started_km_paise::bigint;
  v_courier_payout_paise := (rate_row).base_courier_payout_paise::bigint
    + v_extra_started_km * (rate_row).courier_payout_per_started_km_paise::bigint;

  return pg_catalog.jsonb_build_object(
    'rateCardId', (rate_row).id,
    'rateCardVersion', (rate_row).version,
    'routeDistanceMeters', p_route_distance_m,
    'includedDistanceMeters', (rate_row).included_distance_m,
    'extraStartedKilometres', v_extra_started_km,
    'deliveryFee', pg_catalog.jsonb_build_object(
      'paise', v_delivery_fee_paise
    ),
    'courierPayout', pg_catalog.jsonb_build_object(
      'paise', v_courier_payout_paise
    ),
    'platformDeliveryMargin', pg_catalog.jsonb_build_object(
      'paise', v_delivery_fee_paise - v_courier_payout_paise
    ),
    'merchantCommissionBps', (rate_row).merchant_commission_bps
  );
end;
$$;

create function public.upsert_city_service_zone(
  p_account_id uuid,
  p_service_zone_id uuid,
  p_city_name text,
  p_latitude double precision,
  p_longitude double precision,
  p_coverage_radius_m integer,
  p_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_city_service_zone';
  v_existing private.request_deduplication%rowtype;
  v_zone public.service_zones%rowtype;
  v_center extensions.geometry(Point, 4326);
  v_boundary extensions.geometry(Polygon, 4326);
  v_before_state jsonb;
  v_response_body jsonb;
  v_response_status integer;
  v_changed boolean := false;
begin
  if not private.has_active_membership(p_account_id, 'owner') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if nullif(pg_catalog.btrim(p_city_name), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_city_name)) > 120
    or p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or p_coverage_radius_m is null
    or p_coverage_radius_m not between 10000 and 30000
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The city service-zone configuration is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  v_center := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude),
    4326
  );
  v_boundary := extensions.st_buffer(
    v_center::extensions.geography,
    p_coverage_radius_m
  )::extensions.geometry;

  if p_service_zone_id is null then
    select zone.*
    into v_zone
    from public.service_zones as zone
    where zone.name = pg_catalog.btrim(p_city_name)
    for update;
  else
    select zone.*
    into v_zone
    from public.service_zones as zone
    where zone.id = p_service_zone_id
    for update;
  end if;

  if found then
    perform 1
    from public.service_zones as zone
    where zone.name = pg_catalog.btrim(p_city_name)
      and zone.id <> v_zone.id;

    if found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'city_name_conflict',
          'message', 'Another service zone already uses this city name.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    v_before_state := private.city_service_zone_json(v_zone);
    if v_zone.name <> pg_catalog.btrim(p_city_name)
      or not extensions.st_equals(v_zone.center, v_center)
      or v_zone.coverage_radius_m <> p_coverage_radius_m
      or v_zone.active <> p_active
    then
      update public.service_zones as zone
      set name = pg_catalog.btrim(p_city_name),
          center = v_center,
          boundary = v_boundary,
          coverage_radius_m = p_coverage_radius_m,
          active = p_active,
          version = zone.version + 1,
          updated_at = pg_catalog.now()
      where zone.id = v_zone.id
      returning zone.* into v_zone;
      v_changed := true;
    end if;
    v_response_status := 200;
  else
    perform 1
    from public.service_zones as zone
    where zone.name = pg_catalog.btrim(p_city_name);

    if found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'city_name_conflict',
          'message', 'Another service zone already uses this city name.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    insert into public.service_zones (
      id, name, center, boundary, coverage_radius_m, active
    ) values (
      coalesce(p_service_zone_id, pg_catalog.gen_random_uuid()),
      pg_catalog.btrim(p_city_name),
      v_center,
      v_boundary,
      p_coverage_radius_m,
      p_active
    )
    returning * into v_zone;
    v_changed := true;
    v_response_status := 201;
  end if;

  v_response_body := private.city_service_zone_json(v_zone);

  if v_changed then
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id,
      'city_service_zone_upserted',
      'service_zone',
      v_zone.id,
      v_before_state,
      v_response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id,
    v_function_name,
    pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest),
    v_response_body,
    v_response_status
  );

  response_body := v_response_body;
  response_status := v_response_status;
  return next;
end;
$$;

create function public.upsert_merchant_order_distance_rate_card(
  p_account_id uuid,
  p_service_zone_id uuid,
  p_included_distance_m integer,
  p_base_delivery_fee_paise integer,
  p_delivery_fee_per_started_km_paise integer,
  p_base_courier_payout_paise integer,
  p_courier_payout_per_started_km_paise integer,
  p_merchant_commission_bps integer,
  p_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_merchant_order_distance_rate_card';
  v_existing private.request_deduplication%rowtype;
  v_rate private.merchant_order_rate_cards%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_response_status integer;
  v_changed boolean := false;
begin
  if not private.has_active_membership(p_account_id, 'owner') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_service_zone_id is null
    or p_included_distance_m is null
    or p_included_distance_m not between 1000 and 30000
    or p_base_delivery_fee_paise is null
    or p_base_delivery_fee_paise not between 0 and 100000000
    or p_delivery_fee_per_started_km_paise is null
    or p_delivery_fee_per_started_km_paise not between 0 and 100000000
    or p_base_courier_payout_paise is null
    or p_base_courier_payout_paise not between 0 and p_base_delivery_fee_paise
    or p_courier_payout_per_started_km_paise is null
    or p_courier_payout_per_started_km_paise
      not between 0 and p_delivery_fee_per_started_km_paise
    or p_merchant_commission_bps is null
    or p_merchant_commission_bps not between 0 and 10000
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant-order distance rate card is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  perform 1
  from public.service_zones as zone
  where zone.id = p_service_zone_id
    and zone.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'service_zone_unavailable',
        'message', 'An active Dastak service zone is required.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_service_zone_id::text || ':merchant_order_distance_rate',
      0
    )
  );

  select rate.*
  into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.service_zone_id = p_service_zone_id
  for update;

  if found then
    v_before_state := private.merchant_order_distance_rate_card_json(v_rate);
    if v_rate.included_distance_m <> p_included_distance_m
      or v_rate.base_delivery_fee_paise <> p_base_delivery_fee_paise
      or v_rate.delivery_fee_per_started_km_paise
        <> p_delivery_fee_per_started_km_paise
      or v_rate.base_courier_payout_paise <> p_base_courier_payout_paise
      or v_rate.courier_payout_per_started_km_paise
        <> p_courier_payout_per_started_km_paise
      or v_rate.merchant_commission_bps <> p_merchant_commission_bps
      or v_rate.active <> p_active
    then
      update private.merchant_order_rate_cards as rate
      set included_distance_m = p_included_distance_m,
          base_delivery_fee_paise = p_base_delivery_fee_paise,
          delivery_fee_per_started_km_paise = p_delivery_fee_per_started_km_paise,
          base_courier_payout_paise = p_base_courier_payout_paise,
          courier_payout_per_started_km_paise = p_courier_payout_per_started_km_paise,
          merchant_commission_bps = p_merchant_commission_bps,
          delivery_fee_paise = p_base_delivery_fee_paise,
          courier_payout_paise = p_base_courier_payout_paise,
          active = p_active,
          version = rate.version + 1,
          updated_at = pg_catalog.now()
      where rate.id = v_rate.id
      returning rate.* into v_rate;
      v_changed := true;
    end if;
    v_response_status := 200;
  else
    insert into private.merchant_order_rate_cards (
      service_zone_id,
      included_distance_m,
      base_delivery_fee_paise,
      delivery_fee_per_started_km_paise,
      base_courier_payout_paise,
      courier_payout_per_started_km_paise,
      merchant_commission_bps,
      delivery_fee_paise,
      courier_payout_paise,
      active
    ) values (
      p_service_zone_id,
      p_included_distance_m,
      p_base_delivery_fee_paise,
      p_delivery_fee_per_started_km_paise,
      p_base_courier_payout_paise,
      p_courier_payout_per_started_km_paise,
      p_merchant_commission_bps,
      p_base_delivery_fee_paise,
      p_base_courier_payout_paise,
      p_active
    )
    returning * into v_rate;
    v_changed := true;
    v_response_status := 201;
  end if;

  v_response_body := private.merchant_order_distance_rate_card_json(v_rate);

  if v_changed then
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id,
      'merchant_order_distance_rate_card_upserted',
      'merchant_order_rate_card',
      v_rate.id,
      v_before_state,
      v_response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id,
    v_function_name,
    pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest),
    v_response_body,
    v_response_status
  );

  response_body := v_response_body;
  response_status := v_response_status;
  return next;
end;
$$;

create function public.browse_catalogue(
  p_account_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_discovery_radius_m integer
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_zone_id uuid;
  v_location extensions.geometry(Point, 4326);
  v_stores jsonb;
  v_categories jsonb;
  v_products jsonb;
begin
  if not private.has_active_membership(p_account_id, 'customer') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or p_discovery_radius_m is null
    or p_discovery_radius_m not between 10000 and 30000
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The catalogue location or discovery range is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude),
    4326
  );

  select zone.id
  into v_zone_id
  from public.service_zones as zone
  where zone.active = true
    and extensions.st_covers(zone.boundary, v_location)
  order by zone.created_at, zone.id
  limit 1;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'Dastak is not available at this location.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_store_json(store)
      order by store.name, store.id
    ),
    '[]'::jsonb
  )
  into v_stores
  from private.merchant_stores as store
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and extensions.st_dwithin(
      store.location::extensions.geography,
      v_location::extensions.geography,
      p_discovery_radius_m
    );

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_category_json(category)
      order by store.name, category.display_order, category.id
    ),
    '[]'::jsonb
  )
  into v_categories
  from private.catalogue_categories as category
  join private.merchant_stores as store on store.id = category.store_id
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and category.is_active = true
    and extensions.st_dwithin(
      store.location::extensions.geography,
      v_location::extensions.geography,
      p_discovery_radius_m
    );

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_product_json(product)
      order by store.name, category.display_order, product.name, product.id
    ),
    '[]'::jsonb
  )
  into v_products
  from private.catalogue_products as product
  join private.catalogue_categories as category
    on category.id = product.category_id
    and category.store_id = product.store_id
  join private.merchant_stores as store on store.id = product.store_id
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
    and membership.role = 'merchant'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and category.is_active = true
    and product.is_active = true
    and product.catalogue_kind = 'general'
    and product.restricted_approval_state = 'not_applicable'
    and extensions.st_dwithin(
      store.location::extensions.geography,
      v_location::extensions.geography,
      p_discovery_radius_m
    );

  response_body := pg_catalog.jsonb_build_object(
    'serviceZoneId', v_zone_id,
    'discoveryRadiusMeters', p_discovery_radius_m,
    'stores', v_stores,
    'categories', v_categories,
    'products', v_products
  );
  response_status := 200;
  return next;
end;
$$;

create or replace function public.browse_catalogue(
  p_account_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns table (response_body jsonb, response_status integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from public.browse_catalogue(
    p_account_id,
    p_latitude,
    p_longitude,
    10000
  );
$$;

revoke execute on function private.prepare_service_zone_insert()
  from public, anon, authenticated;
revoke execute on function private.city_service_zone_json(public.service_zones)
  from public, anon, authenticated;
revoke execute on function private.merchant_order_distance_rate_card_json(
  private.merchant_order_rate_cards
) from public, anon, authenticated;
revoke execute on function private.calculate_merchant_order_distance_terms(
  private.merchant_order_rate_cards, integer
) from public, anon, authenticated;

grant execute on function private.prepare_service_zone_insert() to service_role;
grant execute on function private.city_service_zone_json(public.service_zones)
  to service_role;
grant execute on function private.merchant_order_distance_rate_card_json(
  private.merchant_order_rate_cards
) to service_role;
grant execute on function private.calculate_merchant_order_distance_terms(
  private.merchant_order_rate_cards, integer
) to service_role;

revoke execute on function public.upsert_city_service_zone(
  uuid, uuid, text, double precision, double precision, integer, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_city_service_zone(
  uuid, uuid, text, double precision, double precision, integer, boolean, text, text
) to service_role;

revoke execute on function public.upsert_merchant_order_distance_rate_card(
  uuid, uuid, integer, integer, integer, integer, integer, integer, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_merchant_order_distance_rate_card(
  uuid, uuid, integer, integer, integer, integer, integer, integer, boolean, text, text
) to service_role;

revoke execute on function public.browse_catalogue(
  uuid, double precision, double precision, integer
) from public, anon, authenticated;
grant execute on function public.browse_catalogue(
  uuid, double precision, double precision, integer
) to service_role;

revoke execute on function public.browse_catalogue(
  uuid, double precision, double precision
) from public, anon, authenticated;
grant execute on function public.browse_catalogue(
  uuid, double precision, double precision
) to service_role;
