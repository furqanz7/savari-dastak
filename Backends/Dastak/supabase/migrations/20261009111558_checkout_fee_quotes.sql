-- Approved 2026-10-09: a CUSTOMER surcharge of 2% of items + delivery,
-- and the Food started-kilometre tariff for both services. No history backfill.
alter table dastak_v1.orders add column checkout_pricing_version smallint not null default 0
  check (checkout_pricing_version in (0,1));
alter table dastak_v1.orders alter column checkout_pricing_version set default 1;

create function dastak_v1.preserve_checkout_pricing_version()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if new.checkout_pricing_version is distinct from old.checkout_pricing_version then
    raise exception using errcode='22023',message='order checkout pricing version is immutable';
  end if;
  return new;
end;
$$;
create trigger orders_preserve_checkout_pricing_version before update on dastak_v1.orders
  for each row execute function dastak_v1.preserve_checkout_pricing_version();

create function private.checkout_customer_platform_fee(p_base bigint)
returns bigint language plpgsql immutable security invoker set search_path='' as $$
begin
  if p_base is null or p_base < 0 then
    raise exception using errcode='22023',message='invalid checkout fee base';
  end if;
  return floor((p_base::numeric*200+5000)/10000)::bigint;
end;
$$;

-- An estimate, not a stock reservation. Prefer one full-cart merchant; otherwise
-- greedily cover remaining exact SKUs, bounded to four stops including Food.
create function private.checkout_pickup_branches(
  p_origin extensions.geometry,p_retail_lines jsonb,p_restaurant uuid default null
) returns uuid[] language plpgsql stable security definer set search_path='' as $$
declare branches uuid[]:='{}'; remaining uuid[]; selected_branch uuid;
begin
  if p_origin is null then raise exception using errcode='22023',message='delivery location unavailable'; end if;
  if p_restaurant is not null then
    if not private.customer_restaurant_accepting(p_restaurant) or not exists (
      select 1 from dastak_v1.merchant_branches b join public.service_zones z on z.id=b.service_zone_id
      where b.id=p_restaurant and b.location is not null and z.active
        and extensions.st_covers(z.boundary,p_origin)
    ) then raise exception using errcode='55000',message='Restaurant is not accepting orders in this area'; end if;
    branches:=array[p_restaurant];
  end if;
  select coalesce(array_agg((value->>'skuId')::uuid),'{}') into remaining
    from jsonb_array_elements(p_retail_lines);
  while cardinality(remaining)>0 loop
    if cardinality(branches)>=4 then
      raise exception using errcode='55000',message='A complete delivery estimate is unavailable for this basket';
    end if;
    select b.id into selected_branch
    from dastak_v1.merchant_branches b
    join dastak_v1.merchant_organizations o on o.id=b.organization_id
    join dastak_v1.branch_operational_states operating on operating.branch_id=b.id
    join public.service_zones z on z.id=b.service_zone_id
    join dastak_v1.merchant_sku_selections s on s.branch_id=b.id
    join jsonb_array_elements(p_retail_lines) line on (line->>'skuId')::uuid=s.sku_id
    where b.status='ACTIVE' and o.status='ACTIVE' and o.merchant_type in ('RETAIL','DASTAK_CONVENIENCE_STORE')
      and operating.is_open and operating.accepting_orders and z.active and b.location is not null
      and extensions.st_covers(z.boundary,p_origin) and extensions.st_covers(z.boundary,b.location)
      and extensions.st_distance(b.location::extensions.geography,p_origin::extensions.geography)
        <= (dastak_v1_api.wave1_branch_configuration(b.id,o.id,z.id)->>'retailRadiusMeters')::integer
      and s.state='SELECTED' and s.stock_quantity>=(line->>'quantity')::integer
      and s.sku_id=any(remaining) and not b.id=any(branches)
      and not exists(select 1 from dastak_v1.operational_pause_controls c where c.active
        and ((c.scope='MERCHANT_BRANCH' and c.branch_id=b.id) or (c.scope='ZONE_RETAIL' and c.service_zone_id=z.id)))
    group by b.id
    order by count(distinct s.sku_id) desc,
      extensions.st_distance(b.location::extensions.geography,p_origin::extensions.geography),b.id limit 1;
    if selected_branch is null then raise exception using errcode='55000',message='Some items are out of stock in your area'; end if;
    branches:=array_append(branches,selected_branch);
    select coalesce(array_agg(id),'{}') into remaining from unnest(remaining) id
    where not exists(select 1 from dastak_v1.merchant_sku_selections s
      join jsonb_array_elements(p_retail_lines) line on (line->>'skuId')::uuid=s.sku_id
      where s.branch_id=selected_branch and s.sku_id=id and s.state='SELECTED'
        and s.stock_quantity>=(line->>'quantity')::integer);
  end loop;
  if cardinality(branches)=0 then raise exception using errcode='22023',message='empty checkout basket'; end if;
  return branches;
end;
$$;

-- Same geodesic distance authority as pickup_route_distance_meters; not road ETA.
create function private.checkout_route_distance(p_origin extensions.geometry,p_branches uuid[])
returns bigint language plpgsql stable security definer set search_path='' as $$
declare distance_meters bigint;
begin
  if p_origin is null or cardinality(p_branches) not between 1 and 4
    or array_position(p_branches,null) is not null then
    raise exception using errcode='22023',message='invalid checkout pickup route';
  end if;
  with recursive routes as (
    select array[id] visited,id last_id,0::numeric distance
      from unnest(p_branches) id
    union all
    select r.visited||id,id,r.distance+dastak_v1_api.branch_distance_meters(r.last_id,id)
      from routes r cross join unnest(p_branches) id where not id=any(r.visited)
  ) select round(min(r.distance+extensions.st_distance(b.location::extensions.geography,p_origin::extensions.geography)::numeric))::bigint
    into distance_meters from routes r join dastak_v1.merchant_branches b on b.id=r.last_id
    where cardinality(r.visited)=cardinality(p_branches);
  if distance_meters is null then raise exception using errcode='55000',message='delivery distance unavailable'; end if;
  return distance_meters;
end;
$$;

create function dastak_v1_api.customer_checkout_quote(
  p_actor_id uuid,p_address_id uuid,p_address_version timestamptz,p_lines jsonb,p_restaurant_branch_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare origin extensions.geometry; line jsonb; identity text; identities text[]:='{}'; retail jsonb:='[]';
  unit_price bigint; quantity integer; subtotal bigint:=0; delivery bigint; platform bigint; distance_meters bigint;
  food boolean:=false; grocery boolean:=false;
begin
  origin:=private.customer_owned_area(p_actor_id,p_address_id,p_address_version);
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then
    raise exception using errcode='22023',message='invalid checkout basket';
  end if;
  if jsonb_array_length(p_lines) not between 1 and 80 then
    raise exception using errcode='22023',message='invalid checkout basket';
  end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(line->'quantity')<>'number' or coalesce(line->>'quantity','') !~ '^[0-9]{1,2}$'
      or (line->>'quantity')::integer not between 1 and 99 then
      raise exception using errcode='22023',message='invalid checkout quantity';
    end if;
    quantity:=(line->>'quantity')::integer;
    if line->>'lineType'='RETAIL_SKU' then
      grocery:=true; identity:=(line->>'skuId')::uuid::text;
      select s.selling_price_paise into unit_price from dastak_v1.skus s
        join dastak_v1.subcategories sc on sc.id=s.subcategory_id and sc.status='ACTIVE'
        join dastak_v1.categories c on c.id=sc.category_id and c.status='ACTIVE'
        left join dastak_v1.brands b on b.id=s.brand_id
        where s.id=(line->>'skuId')::uuid and s.status='ACTIVE' and s.currency_code='INR'
          and (b.id is null or b.status='ACTIVE');
      if unit_price is null then raise exception using errcode='22023',message='A saved product is unavailable'; end if;
      retail:=retail||jsonb_build_array(line);
    elsif line->>'lineType'='FOOD_MENU_ITEM' and p_restaurant_branch_id is not null then
      food:=true;
      line:=line||jsonb_build_object('selection',dastak_v1_api.restaurant_selection_snapshot(
        p_restaurant_branch_id,(line->>'menuItemId')::uuid,coalesce(line->'optionIds','[]')));
      identity:=line->'selection'->>'selectionKey'; unit_price:=(line->'selection'->>'unitPricePaise')::bigint;
    else raise exception using errcode='22023',message='invalid checkout selection'; end if;
    if identity is null or identity=any(identities) then raise exception using errcode='22023',message='invalid duplicate checkout selection'; end if;
    identities:=array_append(identities,identity); subtotal:=subtotal+unit_price*quantity;
  end loop;
  if (food and grocery) or (not food and p_restaurant_branch_id is not null) then
    raise exception using errcode='22023',message='Grocery and Food require separate checkouts';
  end if;
  distance_meters:=private.checkout_route_distance(origin,private.checkout_pickup_branches(origin,retail,p_restaurant_branch_id));
  delivery:=dastak_v1_api.calculate_delivery_fee_paise(distance_meters);
  platform:=private.checkout_customer_platform_fee(subtotal+delivery);
  return jsonb_build_object('addressId',p_address_id,'addressVersion',p_address_version,
    'lines',p_lines,'restaurantBranchId',p_restaurant_branch_id,'kind','ESTIMATE','currencyCode','INR',
    'checkedAt',statement_timestamp(),'validUntil',statement_timestamp()+interval '45 seconds',
    'subtotalPaise',subtotal,'deliveryFeePaise',delivery,'platformFeePaise',platform,
    'taxPaise',0,'discountPaise',0,'totalPaise',subtotal+delivery+platform,
    'deliveryDistanceMeters',distance_meters,'deliveryAvailable',private.customer_area_delivery_available(origin),
    'pricingVersion',1,'taxIncludedInUnitPrice',true);
end;
$$;
create function public.dastak_v1_customer_checkout_quote(
  p_address_id uuid,p_address_version timestamptz,p_lines jsonb,p_restaurant_branch_id uuid default null
) returns jsonb language sql stable security invoker set search_path='' as $$
  select dastak_v1_api.customer_checkout_quote(auth.uid(),p_address_id,p_address_version,p_lines,p_restaurant_branch_id);
$$;

create or replace function dastak_v1.apply_authoritative_delivery_fee()
returns trigger language plpgsql security definer set search_path='' as $$
declare pricing_version smallint; restaurant uuid; origin extensions.geometry; branches uuid[]; retail jsonb; distance_meters bigint;
begin
  -- PAID must COPY the immutable amount already committed/collected. Never reprice it.
  if new.snapshot_kind not in ('SUBMITTED','FULLY_SECURED') then return new; end if;
  select checkout_pricing_version,restaurant_branch_id into pricing_version,restaurant
    from dastak_v1.orders where id=new.order_id;
  if pricing_version is distinct from 1 then return new; end if;
  if new.snapshot_kind='FULLY_SECURED' then
    select array_agg(distinct branch_id) into branches from dastak_v1.fulfilments
      where order_id=new.order_id and status='RESERVED_PREPAYMENT';
    if coalesce(cardinality(branches),0) not between 1 and 4 then
      raise exception using errcode='55000',message='secured delivery pickup route unavailable';
    end if;
    distance_meters:=dastak_v1_api.pickup_route_distance_meters(new.order_id,branches);
  else
    select extensions.st_setsrid(extensions.st_makepoint((delivery_address->>'longitude')::double precision,
      (delivery_address->>'latitude')::double precision),4326) into origin
      from dastak_v1.order_context_snapshots where order_id=new.order_id;
    select coalesce(jsonb_agg(jsonb_build_object('skuId',sku_id,'quantity',quantity)),'[]') into retail
      from dastak_v1.order_lines where order_id=new.order_id and line_type='RETAIL_SKU';
    branches:=private.checkout_pickup_branches(origin,retail,restaurant);
    distance_meters:=private.checkout_route_distance(origin,branches);
  end if;
  if distance_meters is null then raise exception using errcode='55000',message='delivery distance unavailable'; end if;
  new.delivery_fee_paise:=dastak_v1_api.calculate_delivery_fee_paise(distance_meters);
  new.platform_fee_paise:=private.checkout_customer_platform_fee(new.subtotal_paise+new.delivery_fee_paise);
  new.total_paise:=new.subtotal_paise+new.delivery_fee_paise+new.platform_fee_paise+new.tax_paise-new.discount_paise;
  new.calculation_details:=coalesce(new.calculation_details,'{}')||jsonb_build_object(
    'checkoutPricingVersion',1,'deliveryDistanceMeters',distance_meters,
    'deliveryFeeAuthority','DASTAK_STARTED_KILOMETRE_BANDS','platformFeeAuthority','CUSTOMER_SURCHARGE_200_BPS',
    'platformFeeBase','ITEMS_PLUS_DELIVERY','rounding','HALF_UP_TO_PAISE',
    'pickupRouteAuthority',case when new.snapshot_kind='FULLY_SECURED' then 'SECURED_FULFILMENTS' else 'ESTIMATED_MERCHANT_COVERAGE' end);
  return new;
end;
$$;

revoke all on function private.checkout_customer_platform_fee(bigint),
  private.checkout_pickup_branches(extensions.geometry,jsonb,uuid),
  private.checkout_route_distance(extensions.geometry,uuid[]),
  dastak_v1_api.customer_checkout_quote(uuid,uuid,timestamptz,jsonb,uuid),
  public.dastak_v1_customer_checkout_quote(uuid,timestamptz,jsonb,uuid) from public,anon,authenticated,service_role;
grant execute on function dastak_v1_api.customer_checkout_quote(uuid,uuid,timestamptz,jsonb,uuid),
  public.dastak_v1_customer_checkout_quote(uuid,timestamptz,jsonb,uuid) to authenticated;
