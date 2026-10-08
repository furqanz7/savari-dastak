-- New-order policy only. Existing reservations keep their original recovery semantics.
alter table dastak_v1.orders add column availability_policy_version smallint not null default 0
  check (availability_policy_version in (0,1));
alter table dastak_v1.orders alter column availability_policy_version set default 1;

create function private.customer_area_delivery_available(p_location extensions.geometry)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from private.delivery_partner_availability availability
    join private.delivery_partner_profiles profile on profile.account_id=availability.account_id
    join private.delivery_partner_applications application on application.id=profile.approved_application_id
      and application.account_id=profile.account_id and application.status='approved'
    join private.account_memberships membership on membership.account_id=profile.account_id
      and membership.role='dastak_partner' and membership.approved_at is not null
      and (membership.suspended_until is null or membership.suspended_until<=now())
    join public.accounts account on account.id=profile.account_id and account.account_state='ACTIVE'
    join public.service_zones zone on zone.id=availability.service_zone_id and zone.active
    where profile.governance_status='ACTIVE' and availability.status='online'
      and availability.available_until>now() and availability.location is not null
      and extensions.st_covers(zone.boundary,p_location)
      and extensions.st_covers(zone.boundary,availability.location)
      and not exists (select 1 from private.account_personas persona where persona.account_id=profile.account_id
        and persona.persona='DELIVERY' and persona.state='DELETED')
      and not exists (select 1 from dastak_v1.operational_pause_controls control where control.active
        and control.scope='RIDER_ASSIGNMENTS' and (control.service_zone_id is null or control.service_zone_id=zone.id))
  );
$$;

create function private.customer_area_stock(p_location extensions.geometry,p_sku_id uuid default null)
returns table(sku_id uuid, available_quantity integer) language sql stable security definer set search_path='' as $$
  select selection.sku_id, max(selection.stock_quantity)::integer
  from dastak_v1.merchant_sku_selections selection
  join dastak_v1.merchant_branches branch on branch.id=selection.branch_id and branch.status='ACTIVE'
  join dastak_v1.merchant_organizations organization on organization.id=branch.organization_id
    and organization.status='ACTIVE' and organization.merchant_type in ('RETAIL','DASTAK_CONVENIENCE_STORE')
  join dastak_v1.branch_operational_states operating on operating.branch_id=branch.id
    and operating.is_open and operating.accepting_orders
  join public.service_zones zone on zone.id=branch.service_zone_id and zone.active
  join dastak_v1.skus sku on sku.id=selection.sku_id and sku.status='ACTIVE'
  where selection.state='SELECTED' and selection.stock_quantity>0 and (p_sku_id is null or selection.sku_id=p_sku_id)
    and branch.location is not null and extensions.st_covers(zone.boundary,p_location)
    and extensions.st_covers(zone.boundary,branch.location)
    and extensions.st_distance(branch.location::extensions.geography,p_location::extensions.geography)
      <= (dastak_v1_api.wave1_branch_configuration(branch.id,organization.id,zone.id)->>'retailRadiusMeters')::integer
    and not exists (select 1 from dastak_v1.operational_pause_controls control where control.active
      and ((control.scope='MERCHANT_BRANCH' and control.branch_id=branch.id)
        or (control.scope='ZONE_RETAIL' and control.service_zone_id=zone.id)))
  group by selection.sku_id;
$$;

create function private.customer_owned_area(p_actor_id uuid,p_address_id uuid,p_address_version timestamptz)
returns extensions.geometry language plpgsql stable security definer set search_path='' as $$
declare address private.customer_delivery_addresses%rowtype;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_actor_id is distinct from auth.uid() then
    raise exception using errcode='42501',message='customer required';
  end if;
  select * into address from private.customer_delivery_addresses
    where id=p_address_id and account_id=p_actor_id;
  if not found then raise exception using errcode='42501',message='delivery address unavailable'; end if;
  if p_address_version is null or address.updated_at<>p_address_version then
    raise exception using errcode='22023',message='delivery address changed; refresh your location';
  end if;
  return address.location;
end;
$$;

create function private.customer_restaurant_accepting(p_branch_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce((select o.status='ACTIVE' and b.status='ACTIVE' and z.active and s.is_open and s.accepting_orders
    and exists(select 1 from dastak_v1.restaurant_menu_items i
      join dastak_v1.restaurant_menu_categories c on c.id=i.category_id and c.status='ACTIVE'
      where i.branch_id=b.id and i.status='ACTIVE')
    and not exists(select 1 from dastak_v1.operational_pause_controls p where p.active
      and ((p.scope='MERCHANT_BRANCH' and p.branch_id=b.id) or (p.scope='ZONE_FOOD' and p.service_zone_id=z.id)))
    from dastak_v1.merchant_branches b join dastak_v1.merchant_organizations o on o.id=b.organization_id
    join public.service_zones z on z.id=b.service_zone_id
    left join dastak_v1.branch_operational_states s on s.branch_id=b.id where b.id=p_branch_id),false);
$$;
create function dastak_v1_api.customer_area_availability(p_actor_id uuid,p_address_id uuid,p_address_version timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare origin extensions.geometry; result jsonb;
begin
  origin:=private.customer_owned_area(p_actor_id,p_address_id,p_address_version);
  select jsonb_build_object(
    'addressId',p_address_id,'addressVersion',p_address_version,
    'checkedAt',statement_timestamp(),
    'groceryServiceable',exists(select 1 from dastak_v1.merchant_branches b
      join dastak_v1.merchant_organizations o on o.id=b.organization_id
      join public.service_zones z on z.id=b.service_zone_id and z.active
      where b.status='ACTIVE' and o.status='ACTIVE' and o.merchant_type in ('RETAIL','DASTAK_CONVENIENCE_STORE')
        and extensions.st_covers(z.boundary,origin)),
    'foodServiceable',exists(select 1 from dastak_v1.merchant_branches b
      join dastak_v1.merchant_organizations o on o.id=b.organization_id
      join public.service_zones z on z.id=b.service_zone_id
      where b.status<>'PENDING_REVIEW' and o.status<>'PENDING_REVIEW' and o.merchant_type='RESTAURANT_CAFE'
        and extensions.st_covers(z.boundary,origin)),
    'deliveryAvailable',private.customer_area_delivery_available(origin),
    'restaurants',coalesce((select jsonb_object_agg(b.id::text,private.customer_restaurant_accepting(b.id))
      from dastak_v1.merchant_branches b join dastak_v1.merchant_organizations o on o.id=b.organization_id
      join public.service_zones z on z.id=b.service_zone_id where b.status<>'PENDING_REVIEW' and o.status<>'PENDING_REVIEW'
        and o.merchant_type='RESTAURANT_CAFE' and extensions.st_covers(z.boundary,origin)),'{}'::jsonb),
    -- Sparse, batched inventory: absent/NULL/zero stock is unavailable. Never sum different merchants' stock.
    'stock',coalesce((select jsonb_object_agg(s.sku_id::text,s.available_quantity)
      from private.customer_area_stock(origin) s),'{}'::jsonb)
  ) into result;
  return result;
end;
$$;
create function public.dastak_v1_customer_area_availability(p_address_id uuid,p_address_version timestamptz)
returns jsonb language sql stable security invoker set search_path='' as $$
  select dastak_v1_api.customer_area_availability(auth.uid(),p_address_id,p_address_version);
$$;

-- Closing, pausing, suspending or an empty menu never removes an onboarded store.
-- PENDING_REVIEW is not onboarded. No deletion/removal workflow is invented here.
create function private.customer_visible_restaurant_menu(p_branch_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_set(dastak_v1_api.restaurant_menu_json(p_branch_id,false),'{restaurant,acceptingOrders}',
    to_jsonb(private.customer_restaurant_accepting(p_branch_id)));
$$;

create function dastak_v1_api.customer_restaurants_area_page(
  p_actor_id uuid,p_address_id uuid,p_address_version timestamptz,p_query text default null,
  p_limit integer default 100,p_after_name text default null,p_after_branch_id uuid default null,
  p_after_distance_meters integer default null,p_branch_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare origin extensions.geometry; result jsonb;
begin
  origin:=private.customer_owned_area(p_actor_id,p_address_id,p_address_version);
  if p_limit is null or p_limit not between 1 and 100 or (p_query is not null and length(p_query)>80)
    or (p_after_name is null)<>(p_after_branch_id is null)
    or (p_after_name is not null and length(p_after_name) not between 1 and 160)
    or (p_after_distance_meters is not null and (p_after_branch_id is null or p_after_distance_meters not between 0 and 41000000))
    or (p_branch_id is not null and p_after_branch_id is not null) then
    raise exception using errcode='22023',message='invalid restaurant area page';
  end if;
  with distances as (
    select b.id,o.display_name,case when b.location is null then null else
      round(extensions.st_distance(b.location::extensions.geography,origin::extensions.geography))::integer end distance_meters
    from dastak_v1.merchant_branches b join dastak_v1.merchant_organizations o on o.id=b.organization_id
    join public.service_zones z on z.id=b.service_zone_id
    where o.merchant_type='RESTAURANT_CAFE' and o.status<>'PENDING_REVIEW' and b.status<>'PENDING_REVIEW'
      and extensions.st_covers(z.boundary,origin) and (p_branch_id is null or b.id=p_branch_id)
      and (p_query is null or o.display_name ilike '%'||p_query||'%' or b.display_name ilike '%'||p_query||'%'
        or exists(select 1 from dastak_v1.restaurant_menu_items i where i.branch_id=b.id and i.status='ACTIVE' and i.name ilike '%'||p_query||'%'))
  ), eligible as (
    select * from distances where p_after_branch_id is null or
      (coalesce(distance_meters,2147483647),display_name,id)>(coalesce(p_after_distance_meters,2147483647),p_after_name,p_after_branch_id)
    order by distance_meters nulls last,display_name,id limit p_limit+1
  ), page as (select * from eligible order by distance_meters nulls last,display_name,id limit p_limit)
  select jsonb_build_object('restaurants',coalesce((select jsonb_agg(
    jsonb_set(private.customer_visible_restaurant_menu(page.id),'{restaurant,distanceMeters}',coalesce(to_jsonb(page.distance_meters),'null'::jsonb))
    order by page.distance_meters nulls last,page.display_name,page.id) from page),'[]'::jsonb),
    'ordering','NEAREST','addressId',p_address_id,'addressVersion',p_address_version,
    'nextCursor',case when (select count(*) from eligible)>p_limit then
      (select jsonb_build_object('name',display_name,'branchId',id,'distanceMeters',distance_meters,
        'addressId',p_address_id,'addressVersion',p_address_version) from page
        order by distance_meters desc nulls first,display_name desc,id desc limit 1) else null end) into result;
  return result;
end;
$$;
create function public.dastak_v1_customer_restaurants_area_page(
  p_address_id uuid,p_address_version timestamptz,p_query text default null,p_limit integer default 100,
  p_after_name text default null,p_after_branch_id uuid default null,p_after_distance_meters integer default null,p_branch_id uuid default null
) returns jsonb language sql stable security invoker set search_path='' as $$
  select dastak_v1_api.customer_restaurants_area_page(auth.uid(),p_address_id,p_address_version,p_query,
    p_limit,p_after_name,p_after_branch_id,p_after_distance_meters,p_branch_id);
$$;
create or replace function dastak_v1_api.list_customer_restaurants_nearest_page(
  p_actor_id uuid,p_address_id uuid,p_address_version timestamptz,p_query text default null,p_limit integer default 100,
  p_after_name text default null,p_after_branch_id uuid default null,p_after_distance_meters integer default null
) returns jsonb language sql stable security definer set search_path='' as $$
  select dastak_v1_api.customer_restaurants_area_page(p_actor_id,p_address_id,p_address_version,p_query,
    p_limit,p_after_name,p_after_branch_id,p_after_distance_meters,null);
$$;

-- Older alphabetical/existing-interface callers use their owned default location.
-- A missing address is NOT permission to browse another city's restaurants.
create or replace function dastak_v1_api.list_customer_restaurants_page(
  p_actor_id uuid,p_query text default null,p_limit integer default 100,
  p_after_name text default null,p_after_branch_id uuid default null,p_branch_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare origin extensions.geometry; result jsonb;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_actor_id is distinct from auth.uid() then raise exception using errcode='42501',message='customer required'; end if;
  if p_limit is null or p_limit not between 1 and 100 or (p_query is not null and length(p_query)>80)
    or (p_after_name is null)<>(p_after_branch_id is null)
    or (p_after_name is not null and length(p_after_name) not between 1 and 160)
    or (p_branch_id is not null and p_after_branch_id is not null) then
    raise exception using errcode='22023',message='invalid restaurant page';
  end if;
  select location into origin from private.customer_delivery_addresses where account_id=p_actor_id
    order by is_default desc,updated_at desc,id limit 1;
  with eligible as (
    select b.id,o.display_name from dastak_v1.merchant_branches b
    join dastak_v1.merchant_organizations o on o.id=b.organization_id
    join public.service_zones z on z.id=b.service_zone_id
    where o.merchant_type='RESTAURANT_CAFE' and o.status<>'PENDING_REVIEW' and b.status<>'PENDING_REVIEW'
      and extensions.st_covers(z.boundary,origin) and (p_branch_id is null or b.id=p_branch_id)
      and (p_after_branch_id is null or (o.display_name,b.id)>(p_after_name,p_after_branch_id))
      and (p_query is null or o.display_name ilike '%'||p_query||'%' or b.display_name ilike '%'||p_query||'%'
        or exists(select 1 from dastak_v1.restaurant_menu_items i where i.branch_id=b.id and i.status='ACTIVE' and i.name ilike '%'||p_query||'%'))
    order by o.display_name,b.id limit p_limit+1
  ), page as (select * from eligible order by display_name,id limit p_limit)
  select jsonb_build_object('restaurants',coalesce((select jsonb_agg(private.customer_visible_restaurant_menu(page.id)
    order by page.display_name,page.id) from page),'[]'::jsonb),
    'nextCursor',case when (select count(*) from eligible)>p_limit then
      (select jsonb_build_object('name',display_name,'branchId',id) from page order by display_name desc,id desc limit 1) else null end) into result;
  return result;
end;
$$;
create or replace function dastak_v1_api.list_customer_restaurants(p_actor_id uuid,p_query text default null,p_limit integer default 50)
returns jsonb language sql stable security definer set search_path='' as $$
  select dastak_v1_api.list_customer_restaurants_page(p_actor_id,p_query,p_limit,null,null,null)-'nextCursor';
$$;

-- These triggers run inside the canonical submission/commit transaction, AFTER idempotency replay.
create function private.enforce_customer_area_order()
returns trigger language plpgsql security definer set search_path='' as $$
declare customer_order dastak_v1.orders%rowtype; address jsonb; origin extensions.geometry; stock integer;
begin
  if tg_table_name='order_context_snapshots' then
    select * into customer_order from dastak_v1.orders where id=new.order_id;
    address:=new.delivery_address;
  elsif tg_table_name='order_lines' then
    select * into customer_order from dastak_v1.orders where id=new.order_id;
    select delivery_address into address from dastak_v1.order_context_snapshots where order_id=new.order_id;
  else
    if new.status<>'PAID' or old.status='PAID' then return new; end if;
    customer_order:=new;
    select delivery_address into address from dastak_v1.order_context_snapshots where order_id=new.id;
  end if;
  if customer_order.availability_policy_version=0 then return new; end if;
  if address is null or jsonb_typeof(address->'latitude')<>'number' or jsonb_typeof(address->'longitude')<>'number'
    or (address->>'latitude')::numeric not between -90 and 90 or (address->>'longitude')::numeric not between -180 and 180 then
    raise exception using errcode='22023',message='valid delivery location required';
  end if;
  origin:=extensions.st_setsrid(extensions.st_makepoint((address->>'longitude')::double precision,(address->>'latitude')::double precision),4326);
  if not private.customer_area_delivery_available(origin) then
    raise exception using errcode='55000',message='No delivery partners are available in your area right now. Your cart is saved; please try again later.';
  end if;
  if tg_table_name='order_lines' then
    if new.line_type='RETAIL_SKU' then
      select s.available_quantity into stock from private.customer_area_stock(origin,new.sku_id) s;
      if stock is null or stock<new.quantity then
        raise exception using errcode='55000',message='This pack is out of stock in your area. Review your saved cart.';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger customer_area_order_context before insert on dastak_v1.order_context_snapshots
  for each row execute function private.enforce_customer_area_order();
create trigger customer_area_order_line before insert on dastak_v1.order_lines
  for each row execute function private.enforce_customer_area_order();
create trigger customer_area_order_commit before update of status on dastak_v1.orders
  for each row execute function private.enforce_customer_area_order();

-- Patch the five existing matching/reservation stock predicates without copying their
-- audited lifecycle implementations. Abort on source drift; do not weaken old grants.
do $$
declare signature text; definition text; replacement text;
begin
  foreach signature in array array[
    'dastak_v1_api.evaluate_wave1_candidate(uuid,uuid)',
    'dastak_v1_api.start_wave2(uuid,uuid)',
    'dastak_v1_api.lock_best_wave2_plan(uuid,uuid,boolean)',
    'dastak_v1_api.accept_wave2_opportunity(uuid,uuid,text,bigint,integer)',
    'dastak_v1_api.recovery_branch_eligibility(uuid,uuid)'
  ] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    if (length(definition)-length(replace(definition,'selection.stock_quantity is null','')))/length('selection.stock_quantity is null')<>1 then
      raise exception 'stock predicate drift in %',signature;
    end if;
    replacement:=case when signature like '%recovery_branch_eligibility%' then
      '(selection.stock_quantity is null and exists(select 1 from dastak_v1.orders legacy where legacy.id=v_case.order_id and legacy.availability_policy_version=0))'
      else '(selection.stock_quantity is null and v_order.availability_policy_version=0)' end;
    execute replace(definition,'selection.stock_quantity is null',replacement);
  end loop;
  -- Recheck unknown stock inside the existing branch/selection row locks. Keep
  -- release, consume, idempotent replay and historical untracked holds unchanged.
  signature:='dastak_v1_api.apply_order_stock(uuid,text)';
  definition:=pg_get_functiondef(signature::regprocedure);
  if (length(definition)-length(replace(definition,'if v_selection.stock_quantity is null then return; end if;','')))
    /length('if v_selection.stock_quantity is null then return; end if;')<>1 then
    raise exception 'locked stock guard drift in %',signature;
  end if;
  execute replace(definition,'if v_selection.stock_quantity is null then return; end if;',
    'if v_selection.stock_quantity is null then
      if exists(select 1 from dastak_v1.orders policy where policy.id=v_line.order_id and policy.availability_policy_version=1) then
        raise exception using errcode=''55000'',message=''This pack is out of stock. Refresh merchant inventory before reserving it.'';
      end if;
      return;
    end if;');
end;
$$;
revoke all on function private.customer_area_delivery_available(extensions.geometry),private.customer_area_stock(extensions.geometry,uuid),
  private.customer_owned_area(uuid,uuid,timestamptz),private.customer_restaurant_accepting(uuid),private.customer_visible_restaurant_menu(uuid),private.enforce_customer_area_order()
  from public,anon,authenticated,service_role;
revoke all on function dastak_v1_api.customer_area_availability(uuid,uuid,timestamptz),
  dastak_v1_api.customer_restaurants_area_page(uuid,uuid,timestamptz,text,integer,text,uuid,integer,uuid),
  public.dastak_v1_customer_area_availability(uuid,timestamptz),
  public.dastak_v1_customer_restaurants_area_page(uuid,timestamptz,text,integer,text,uuid,integer,uuid) from public,anon;
grant execute on function dastak_v1_api.customer_area_availability(uuid,uuid,timestamptz),
  dastak_v1_api.customer_restaurants_area_page(uuid,uuid,timestamptz,text,integer,text,uuid,integer,uuid),
  public.dastak_v1_customer_area_availability(uuid,timestamptz),
  public.dastak_v1_customer_restaurants_area_page(uuid,timestamptz,text,integer,text,uuid,integer,uuid) to authenticated;
