-- Additive, read-only discovery API. Keep the old RPC for existing app versions.
-- Each page is bounded; keyset cursors remove the overall 100-restaurant cap.
create function dastak_v1_api.list_customer_restaurants_page(
  p_actor_id uuid, p_query text default null, p_limit integer default 100,
  p_after_name text default null, p_after_branch_id uuid default null,
  p_branch_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_limit is null or p_limit not between 1 and 100
    or (p_after_name is null) <> (p_after_branch_id is null)
    or (p_after_name is not null and length(p_after_name) not between 1 and 160)
    or (p_query is not null and length(p_query) > 80)
    or (p_branch_id is not null and p_after_branch_id is not null) then
    raise exception using errcode = '22023', message = 'invalid restaurant page';
  end if;
  with eligible as (
    select branch.id, organization.display_name
    from dastak_v1.merchant_branches branch
    join dastak_v1.merchant_organizations organization on organization.id = branch.organization_id
    join dastak_v1.branch_operational_states operating on operating.branch_id = branch.id
    join public.service_zones zone on zone.id = branch.service_zone_id and zone.active
    where organization.merchant_type = 'RESTAURANT_CAFE'
      and organization.status = 'ACTIVE' and branch.status = 'ACTIVE' and operating.is_open
      and (p_branch_id is null or branch.id = p_branch_id)
      and (p_after_branch_id is null or (organization.display_name, branch.id) > (p_after_name, p_after_branch_id))
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
    order by organization.display_name, branch.id limit p_limit + 1
  ), page as (
    select * from eligible order by display_name, id limit p_limit
  )
  select pg_catalog.jsonb_build_object(
    'restaurants', coalesce((select pg_catalog.jsonb_agg(dastak_v1_api.restaurant_menu_json(page.id, false) order by page.display_name, page.id) from page), '[]'::jsonb),
    'nextCursor', case when (select count(*) from eligible) > p_limit then
      (select pg_catalog.jsonb_build_object('name', display_name, 'branchId', id) from page order by display_name desc, id desc limit 1)
      else null end
  ) into result;
  return result;
end;
$$;

create function public.dastak_v1_customer_restaurants_page(
  p_query text default null, p_limit integer default 100,
  p_after_name text default null, p_after_branch_id uuid default null,
  p_branch_id uuid default null
) returns jsonb language sql stable security invoker set search_path = '' as $$
  select dastak_v1_api.list_customer_restaurants_page(auth.uid(), p_query, p_limit, p_after_name, p_after_branch_id, p_branch_id);
$$;
revoke all on function dastak_v1_api.list_customer_restaurants_page(uuid,text,integer,text,uuid,uuid) from public, anon;
revoke all on function public.dastak_v1_customer_restaurants_page(text,integer,text,uuid,uuid) from public, anon;
grant execute on function dastak_v1_api.list_customer_restaurants_page(uuid,text,integer,text,uuid,uuid) to authenticated;
grant execute on function public.dastak_v1_customer_restaurants_page(text,integer,text,uuid,uuid) to authenticated;
