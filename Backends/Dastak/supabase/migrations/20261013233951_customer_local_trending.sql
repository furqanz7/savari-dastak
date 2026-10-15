-- Only aggregate popularity leaves the private order tables. Addresses, customers,
-- quantities and order identifiers are never returned to the browsing client.
create function private.trending_delivery_point(p_address jsonb)
returns extensions.geometry language plpgsql immutable strict security invoker set search_path='' as $$
begin
  if jsonb_typeof(p_address->'latitude')<>'number' or jsonb_typeof(p_address->'longitude')<>'number'
    or not (p_address->>'latitude')::numeric between -90 and 90
    or not (p_address->>'longitude')::numeric between -180 and 180 then return null; end if;
  return extensions.st_setsrid(extensions.st_makepoint(
    (p_address->>'longitude')::double precision,(p_address->>'latitude')::double precision),4326);
end;
$$;

create index orders_local_trending_delivered_idx on dastak_v1.orders(delivered_at desc,id)
  where status='DELIVERED';
create index order_context_local_trending_location_idx on dastak_v1.order_context_snapshots
  using gist ((private.trending_delivery_point(delivery_address)::extensions.geography));

create function private.customer_area_trending(p_location extensions.geometry)
returns jsonb language sql stable security definer set search_path='' as $$
  with products as materialized (
    select sku.*, category.id category_id,category.category_type_id,brand.name brand_name,brand.slug brand_slug,
      image.image_key primary_image_key,
      case when brand.id is null then jsonb_build_array(sku.id)
        else jsonb_build_array(category.id,subcategory.id,brand.id,sku.variant_name,
          btrim(regexp_replace(replace(lower(sku.canonical_name),lower(sku.pack_size),''),'\s+',' ','g')))
        end family_key
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory on subcategory.id=sku.subcategory_id and subcategory.status='ACTIVE'
    join dastak_v1.categories category on category.id=subcategory.category_id and category.status='ACTIVE'
    join dastak_v1.category_types kind on kind.id=category.category_type_id and kind.status='ACTIVE'
    left join dastak_v1.brands brand on brand.id=sku.brand_id
    join lateral (select asset.image_key from dastak_v1.sku_images asset
      where asset.sku_id=sku.id and asset.role='PRIMARY' and asset.status='VERIFIED' and asset.rights_status='CLEARED'
      order by asset.sort_order,asset.id limit 1) image on true
    where sku.status='ACTIVE' and (brand.id is null or brand.status='ACTIVE')
      and kind.slug not in ('pharmacy','paan-corner')
  ), stock as materialized (
    select * from private.customer_area_stock(p_location)
  ), local_orders as materialized (
    select customer_order.id,customer_order.delivered_at
    from dastak_v1.orders customer_order
    join dastak_v1.order_context_snapshots context on context.order_id=customer_order.id
    where customer_order.status='DELIVERED' and customer_order.delivered_at>=statement_timestamp()-interval '30 days'
      and customer_order.delivered_at<=statement_timestamp()
      and extensions.st_dwithin(private.trending_delivery_point(context.delivery_address)::extensions.geography,
        p_location::extensions.geography,30000.001)
  ), ranked as (
    select product.family_key,count(distinct local_order.id) popularity,max(local_order.delivered_at) latest
    from local_orders local_order
    join dastak_v1.order_lines line on line.order_id=local_order.id
      and line.line_type='RETAIL_SKU' and line.status='FULFILLED'
    join products product on product.id=line.sku_id
    where exists(select 1 from products available join stock on stock.sku_id=available.id
      where available.family_key=product.family_key)
    group by product.family_key
    order by popularity desc,latest desc,product.family_key limit 12
  ), packs as (
    select product.*,ranked.popularity,ranked.latest,stock.available_quantity
    from ranked join products product on product.family_key=ranked.family_key
    left join stock on stock.sku_id=product.id
    -- Keep the available pack first, but retain other exact sizes for the picker.
    order by ranked.popularity desc,ranked.latest desc,product.family_key,
      (stock.available_quantity is not null) desc,product.pack_size,product.id limit 250
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',pack.id,'categoryTypeId',pack.category_type_id,'categoryId',pack.category_id,'subcategoryId',pack.subcategory_id,
    'brand',case when pack.brand_id is null then null else jsonb_build_object('id',pack.brand_id,'name',pack.brand_name,'slug',pack.brand_slug) end,
    'name',pack.canonical_name,'slug',pack.slug,'variant',pack.variant_name,'packSize',pack.pack_size,
    'description',pack.description,'imageKey',pack.primary_image_key,
    'galleryImageKeys',coalesce((select jsonb_agg(asset.image_key order by asset.sort_order,asset.id)
      from dastak_v1.sku_images asset where asset.sku_id=pack.id and asset.role='GALLERY'
        and asset.status='VERIFIED' and asset.rights_status='CLEARED'),'[]'::jsonb),
    'barcode',pack.barcode,'quantityValue',pack.quantity_value,'quantityUnit',pack.quantity_unit,'packCount',pack.pack_count,
    'manufacturerName',pack.manufacturer_name,'countryOfOriginCode',pack.country_of_origin_code,
    'dietType',pack.diet_type,'shelfLifeDays',pack.shelf_life_days,'attributes',pack.attribute_data,
    'listPricePaise',pack.list_price_paise,'sellingPricePaise',pack.selling_price_paise,
    'currencyCode',pack.currency_code,'logisticsAttributes',pack.logistics_attributes
  )) order by pack.popularity desc,pack.latest desc,pack.family_key,
    (pack.available_quantity is not null) desc,pack.pack_size,pack.id),'[]'::jsonb) from packs pack;
$$;

revoke all on function private.trending_delivery_point(jsonb),private.customer_area_trending(extensions.geometry)
  from public,anon,authenticated,service_role;

-- Preserve the deployed location ownership/version checks, radius, stock, rider,
-- Admin-removal and pause rules. Abort on drift instead of copying stale code.
do $$
declare definition text; before_text text:='return result;';
begin
  definition:=pg_get_functiondef('dastak_v1_api.customer_area_availability(uuid,uuid,timestamptz)'::regprocedure);
  if position('private.customer_owned_area(p_actor_id,p_address_id,p_address_version)' in definition)=0
    or (length(definition)-length(replace(definition,before_text,'')))/length(before_text)<>1 then
    raise exception 'trending availability source drift';
  end if;
  execute replace(definition,before_text,
    $new$return result || jsonb_build_object('trendingSkus',private.customer_area_trending(origin));$new$);
end;
$$;
