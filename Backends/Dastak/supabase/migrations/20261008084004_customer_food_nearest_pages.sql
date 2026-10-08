-- Additive read-only endpoint; older alphabetical clients remain unchanged.
-- Distances are straight-line metres, not routing/ETA or checkout eligibility.
create function dastak_v1_api.list_customer_restaurants_nearest_page(
  p_actor_id uuid, p_address_id uuid, p_address_version timestamptz,
  p_query text default null, p_limit integer default 100,
  p_after_name text default null, p_after_branch_id uuid default null,
  p_after_distance_meters integer default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_location extensions.geometry;
  v_address_version timestamptz;
  result jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_address_id is null or p_address_version is null or p_limit is null or p_limit not between 1 and 100
    or (p_after_name is null) <> (p_after_branch_id is null)
    or (p_after_name is not null and length(p_after_name) not between 1 and 160)
    or (p_after_distance_meters is not null and (p_after_branch_id is null or p_after_distance_meters not between 0 and 41000000))
    or (p_query is not null and length(p_query) > 80) then
    raise exception using errcode = '22023', message = 'invalid nearest restaurant page';
  end if;
  select address.location, address.updated_at into v_location, v_address_version
    from private.customer_delivery_addresses address
    where address.id = p_address_id and address.account_id = p_actor_id;
  if not found then
    raise exception using errcode = '42501', message = 'delivery address unavailable';
  end if;
  if v_address_version <> p_address_version then
    raise exception using errcode = '22023', message = 'delivery address changed; refresh your location';
  end if;
  with distances as (
    select branch.id, organization.display_name,
      case when branch.location is null then null else
        pg_catalog.round(extensions.st_distance(branch.location::extensions.geography, v_location::extensions.geography))::integer
      end as distance_meters
    from dastak_v1.merchant_branches branch
    join dastak_v1.merchant_organizations organization on organization.id = branch.organization_id
    join dastak_v1.branch_operational_states operating on operating.branch_id = branch.id
    join public.service_zones zone on zone.id = branch.service_zone_id and zone.active
    where organization.merchant_type = 'RESTAURANT_CAFE'
      and organization.status = 'ACTIVE' and branch.status = 'ACTIVE' and operating.is_open
      and (p_query is null or organization.display_name ilike '%' || p_query || '%'
        or branch.display_name ilike '%' || p_query || '%'
        or exists (select 1 from dastak_v1.restaurant_menu_items item
          join dastak_v1.restaurant_menu_categories category on category.id = item.category_id and category.status = 'ACTIVE'
          where item.branch_id = branch.id and item.status = 'ACTIVE' and item.name ilike '%' || p_query || '%'))
      and not exists (select 1 from dastak_v1.operational_pause_controls control
        where control.active and ((control.scope = 'MERCHANT_BRANCH' and control.branch_id = branch.id)
          or (control.scope = 'ZONE_FOOD' and control.service_zone_id = branch.service_zone_id)))
      and exists (select 1 from dastak_v1.restaurant_menu_items item
        join dastak_v1.restaurant_menu_categories category on category.id = item.category_id and category.status = 'ACTIVE'
        where item.branch_id = branch.id and item.status = 'ACTIVE')
  ), eligible as (
    select * from distances
    where p_after_branch_id is null or
      (coalesce(distance_meters, 2147483647), display_name, id) >
      (coalesce(p_after_distance_meters, 2147483647), p_after_name, p_after_branch_id)
    order by distance_meters nulls last, display_name, id limit p_limit + 1
  ), page as (
    select * from eligible order by distance_meters nulls last, display_name, id limit p_limit
  )
  select pg_catalog.jsonb_build_object(
    'restaurants', coalesce((select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_set(dastak_v1_api.restaurant_menu_json(page.id, false), '{restaurant,distanceMeters}',
        coalesce(pg_catalog.to_jsonb(page.distance_meters), 'null'::jsonb))
      order by page.distance_meters nulls last, page.display_name, page.id) from page), '[]'::jsonb),
    'ordering', 'NEAREST', 'addressId', p_address_id, 'addressVersion', v_address_version,
    'nextCursor', case when (select count(*) from eligible) > p_limit then
      (select pg_catalog.jsonb_build_object('name', display_name, 'branchId', id,
        'distanceMeters', distance_meters, 'addressId', p_address_id, 'addressVersion', v_address_version)
        from page order by distance_meters desc nulls first, display_name desc, id desc limit 1)
      else null end
  ) into result;
  return result;
end;
$$;

create function public.dastak_v1_customer_restaurants_nearest_page(
  p_address_id uuid, p_address_version timestamptz, p_query text default null, p_limit integer default 100,
  p_after_name text default null, p_after_branch_id uuid default null, p_after_distance_meters integer default null
) returns jsonb language sql stable security invoker set search_path = '' as $$
  select dastak_v1_api.list_customer_restaurants_nearest_page(auth.uid(), p_address_id, p_address_version,
    p_query, p_limit, p_after_name, p_after_branch_id, p_after_distance_meters);
$$;
revoke all on function dastak_v1_api.list_customer_restaurants_nearest_page(uuid,uuid,timestamptz,text,integer,text,uuid,integer) from public, anon;
revoke all on function public.dastak_v1_customer_restaurants_nearest_page(uuid,timestamptz,text,integer,text,uuid,integer) from public, anon;
grant execute on function dastak_v1_api.list_customer_restaurants_nearest_page(uuid,uuid,timestamptz,text,integer,text,uuid,integer) to authenticated;
grant execute on function public.dastak_v1_customer_restaurants_nearest_page(uuid,timestamptz,text,integer,text,uuid,integer) to authenticated;
