-- Customer discovery and new-order merchant eligibility use a 30 km geodesic
-- radius. Rider eligibility, fees, account approval and old-order recovery stay
-- unchanged. Retain Admin removal, pauses, ownership and idempotency guards.
-- One millimetre tolerance keeps the inclusive boundary stable under PostGIS
-- projection/geodesic floating-point round trips; displayed/configured radius
-- remains 30,000 metres, never rounded kilometres for eligibility.
create index if not exists merchant_branches_customer_distance_idx
  on dastak_v1.merchant_branches using gist ((location::extensions.geography));

do $$
declare signature text; definition text; before_text text; after_text text; expected integer;
begin
  foreach signature in array array[
    'dastak_v1_api.customer_area_availability(uuid,uuid,timestamptz)',
    'dastak_v1_api.customer_restaurants_area_page(uuid,uuid,timestamptz,text,integer,text,uuid,integer,uuid)',
    'dastak_v1_api.list_customer_restaurants_page(uuid,text,integer,text,uuid,uuid)'
  ] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    before_text:='extensions.st_covers(z.boundary,origin)';
    after_text:='extensions.st_dwithin(b.location::extensions.geography,origin::extensions.geography,30000.001)';
    expected:=case when signature like '%customer_area_availability%' then 3 else 1 end;
    if (length(definition)-length(replace(definition,before_text,'')))/length(before_text)<>expected then
      raise exception '30 km discovery source drift in %',signature;
    end if;
    if position('b.customer_listing_visible' in definition)=0 then
      raise exception 'Admin removal guard missing in %',signature;
    end if;
    execute replace(definition,before_text,after_text);
  end loop;

  -- Inventory cannot be available beyond the same customer discovery radius.
  signature:='private.customer_area_stock(extensions.geometry,uuid)';
  definition:=pg_get_functiondef(signature::regprocedure);
  before_text:=$old$and branch.location is not null and extensions.st_covers(zone.boundary,p_location)
    and extensions.st_covers(zone.boundary,branch.location)
    and extensions.st_distance(branch.location::extensions.geography,p_location::extensions.geography)
      <= (dastak_v1_api.wave1_branch_configuration(branch.id,organization.id,zone.id)->>'retailRadiusMeters')::integer$old$;
  after_text:=$new$and branch.location is not null and extensions.st_covers(zone.boundary,branch.location)
    and extensions.st_dwithin(branch.location::extensions.geography,p_location::extensions.geography,30000.001)$new$;
  if position(before_text in definition)=0 then raise exception '30 km stock source drift'; end if;
  execute replace(definition,before_text,after_text);

  signature:='private.checkout_pickup_branches(extensions.geometry,jsonb,uuid)';
  definition:=pg_get_functiondef(signature::regprocedure);
  before_text:='extensions.st_covers(z.boundary,p_origin)';
  if (length(definition)-length(replace(definition,before_text,'')))/length(before_text)<>2 then
    raise exception '30 km quote source drift';
  end if;
  definition:=replace(definition,before_text,
    'extensions.st_dwithin(b.location::extensions.geography,p_origin::extensions.geography,30000.001)');
  before_text:=$old$and extensions.st_distance(b.location::extensions.geography,p_origin::extensions.geography)
        <= (dastak_v1_api.wave1_branch_configuration(b.id,o.id,z.id)->>'retailRadiusMeters')::integer$old$;
  if position(before_text in definition)=0 then raise exception '30 km quote radius source drift'; end if;
  execute replace(definition,before_text,'');

  -- Wave 2 delegates merchant geography to this canonical Wave 1 evaluator.
  -- Preserve old orders' original zone/radius checks and all stock/capacity locks.
  signature:='dastak_v1_api.evaluate_wave1_candidate(uuid,uuid)';
  definition:=pg_get_functiondef(signature::regprocedure);
  before_text:=$old$v_radius_meters := (v_configuration ->> 'retailRadiusMeters')::integer;$old$;
  after_text:=$new$v_radius_meters := case when v_order.availability_policy_version=1 then 30000
      else (v_configuration ->> 'retailRadiusMeters')::integer end;$new$;
  if position(before_text in definition)=0 then raise exception '30 km matching radius source drift'; end if;
  definition:=replace(definition,before_text,after_text);
  before_text:='and not extensions.st_covers(v_zone.boundary, v_customer_location) then';
  if position(before_text in definition)=0 then raise exception '30 km matching zone source drift'; end if;
  definition:=replace(definition,before_text,
    'and v_order.availability_policy_version=0 and not extensions.st_covers(v_zone.boundary, v_customer_location) then');
  before_text:='v_distance_meters > v_radius_meters then';
  if position(before_text in definition)=0 then raise exception '30 km matching distance source drift'; end if;
  execute replace(definition,before_text,
    'v_distance_meters > v_radius_meters + (case when v_order.availability_policy_version=1 then 0.001 else 0 end) then');

  signature:='dastak_v1_api.submit_order(uuid,text,bigint,jsonb)';
  definition:=pg_get_functiondef(signature::regprocedure);
  before_text:=$old$and extensions.st_covers(
          zone.boundary,
          extensions.st_setsrid(extensions.st_makepoint(
            v_longitude::double precision, v_latitude::double precision
          ), 4326)
        )$old$;
  after_text:=$new$and extensions.st_dwithin(
          v_restaurant_branch.location::extensions.geography,
          extensions.st_setsrid(extensions.st_makepoint(
            v_longitude::double precision, v_latitude::double precision
          ), 4326)::extensions.geography,30000.001
        )$new$;
  if position(before_text in definition)=0 then raise exception '30 km Food submission source drift'; end if;
  execute replace(definition,before_text,after_text);

  signature:='dastak_v1_api.recovery_branch_eligibility(uuid,uuid)';
  definition:=pg_get_functiondef(signature::regprocedure);
  before_text:=$old$v_radius := dastak_v1_api.required_setting_integer(
    'recovery.radius_meters', v_branch.id, v_branch.organization_id,
    v_branch.service_zone_id
  );$old$;
  after_text:=$new$v_radius := case when exists(select 1 from dastak_v1.orders policy
    where policy.id=v_case.order_id and policy.availability_policy_version=1) then 30000
    else dastak_v1_api.required_setting_integer(
      'recovery.radius_meters', v_branch.id, v_branch.organization_id,
      v_branch.service_zone_id) end;$new$;
  if position(before_text in definition)=0 then raise exception '30 km recovery source drift'; end if;
  definition:=replace(definition,before_text,after_text);
  before_text:='v_distance > v_radius then';
  if position(before_text in definition)=0 then raise exception '30 km recovery distance source drift'; end if;
  execute replace(definition,before_text,
    'v_distance > v_radius + (case when exists(select 1 from dastak_v1.orders policy where policy.id=v_case.order_id and policy.availability_policy_version=1) then 0.001 else 0 end) then');
end;
$$;
