-- Keep open restaurants discoverable even when the merchant pauses new orders.
-- Customer discovery exposes the branch with acceptingOrders=false so the UI
-- can label it Store closed; order/checkout RPCs remain authoritative guards.
create or replace function dastak_v1_api.list_customer_restaurants(
  p_actor_id uuid,
  p_query text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid restaurant limit';
  end if;
  return pg_catalog.jsonb_build_object(
    'restaurants', coalesce((
      select pg_catalog.jsonb_agg(
        dastak_v1_api.restaurant_menu_json(visible.id, false)
        order by visible.display_name, visible.id
      )
      from (
        select branch.id, organization.display_name
        from dastak_v1.merchant_branches branch
        join dastak_v1.merchant_organizations organization
          on organization.id = branch.organization_id
        join dastak_v1.branch_operational_states operating
          on operating.branch_id = branch.id
        join public.service_zones zone
          on zone.id = branch.service_zone_id and zone.active
        where organization.merchant_type = 'RESTAURANT_CAFE'
          and organization.status = 'ACTIVE'
          and branch.status = 'ACTIVE'
          and operating.is_open
          and (
            p_query is null
            or organization.display_name ilike '%' || p_query || '%'
            or branch.display_name ilike '%' || p_query || '%'
            or exists (
              select 1 from dastak_v1.restaurant_menu_items item
              where item.branch_id = branch.id and item.status = 'ACTIVE'
                and item.name ilike '%' || p_query || '%'
            )
          )
          and not exists (
            select 1 from dastak_v1.operational_pause_controls control
            where control.active and (
              (control.scope = 'MERCHANT_BRANCH' and control.branch_id = branch.id)
              or (control.scope = 'ZONE_FOOD' and control.service_zone_id = branch.service_zone_id)
            )
          )
          and exists (
            select 1 from dastak_v1.restaurant_menu_items item
            join dastak_v1.restaurant_menu_categories category
              on category.id = item.category_id and category.status = 'ACTIVE'
            where item.branch_id = branch.id and item.status = 'ACTIVE'
          )
        order by organization.display_name, branch.id
        limit p_limit
      ) visible
    ), '[]'::jsonb)
  );
end;
$$;
