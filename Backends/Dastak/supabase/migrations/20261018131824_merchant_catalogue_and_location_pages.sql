-- Additive authenticated reads. Existing snapshots and older page contracts
-- remain intact for distributed clients. No stock or permission mutation.
create function dastak_v1_api.merchant_inventory_page(
  p_actor_id uuid,p_branch_id uuid,p_query text default null,p_selected_only boolean default false,
  p_limit integer default 100,p_after_name text default null,p_after_sku_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_search tsquery;
  v_limit integer := coalesce(p_limit,100);
  v_result jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  select * into v_branch from dastak_v1.merchant_branches where id=p_branch_id;
  if not found or not dastak_v1_api.actor_has_wave1_merchant_permission(
      p_actor_id,v_branch.organization_id,'merchant.catalogue.selection.manage',p_branch_id) then
    raise exception using errcode='42501',message='Merchant catalogue is unavailable';
  end if;
  if not exists(select 1 from dastak_v1.merchant_organizations o where o.id=v_branch.organization_id
      and o.merchant_type in ('RETAIL','DASTAK_CONVENIENCE_STORE')) then
    raise exception using errcode='22023',message='Catalogue selection is retail-only';
  end if;
  if v_limit not between 1 and 250 or (p_after_name is null) <> (p_after_sku_id is null)
      or char_length(coalesce(p_after_name,''))>300 or char_length(coalesce(p_query,''))>80 then
    raise exception using errcode='22023',message='Invalid catalogue page';
  end if;
  if nullif(btrim(p_query),'') is not null then
    v_search := dastak_v1.catalogue_prefix_query(p_query);
    if v_search is null then raise exception using errcode='22023',message='Enter a product search'; end if;
  end if;
  with matched as materialized (
    select s.id,s.canonical_name
    from dastak_v1.skus s
    join dastak_v1.subcategories sc on sc.id=s.subcategory_id
    join dastak_v1.categories c on c.id=sc.category_id
    left join dastak_v1.category_types ct on ct.id=c.category_type_id
    left join dastak_v1.brands b on b.id=s.brand_id
    left join dastak_v1.merchant_sku_selections ms on ms.branch_id=p_branch_id and ms.sku_id=s.id
    where (s.status='ACTIVE' or ms.sku_id is not null)
      and (not coalesce(p_selected_only,false) or ms.state='SELECTED')
      and (p_after_name is null or (pg_catalog.lower(s.canonical_name),s.id)>(pg_catalog.lower(p_after_name),p_after_sku_id))
      and (v_search is null or s.search_document @@ v_search
        or exists(select 1 from dastak_v1.sku_search_aliases a where a.sku_id=s.id and a.search_document @@ v_search)
        or pg_catalog.to_tsvector('pg_catalog.simple'::regconfig,pg_catalog.concat_ws(' ',
          s.canonical_name,s.variant_name,s.pack_size,s.description,b.name,ct.name,c.name,sc.name,
          (select pg_catalog.string_agg(a.alias,' ') from dastak_v1.sku_search_aliases a where a.sku_id=s.id))) @@ v_search)
    order by pg_catalog.lower(s.canonical_name),s.id limit v_limit+1
  ), selected as materialized (
    select * from matched order by pg_catalog.lower(canonical_name),id limit v_limit
  ), projected as (
    select s.canonical_name,s.id,pg_catalog.jsonb_build_object(
      'skuId',s.id,'categoryTypeId',c.category_type_id,'categoryId',sc.category_id,'subcategoryId',s.subcategory_id,
      'brandName',b.name,'name',s.canonical_name,'variant',s.variant_name,'packSize',s.pack_size,'description',s.description,
      'imageKey',(select i.image_key from dastak_v1.sku_images i where i.sku_id=s.id
        and i.role='PRIMARY' and i.status='VERIFIED' and i.rights_status='CLEARED' order by i.sort_order,i.id limit 1),
      'galleryImageKeys',coalesce((select pg_catalog.jsonb_agg(i.image_key order by i.sort_order,i.id)
        from dastak_v1.sku_images i where i.sku_id=s.id and i.role='GALLERY' and i.status='VERIFIED' and i.rights_status='CLEARED'),'[]'::jsonb),
      'quantityValue',s.quantity_value,'quantityUnit',s.quantity_unit,'packCount',s.pack_count,'dietType',s.diet_type,
      'searchTerms',coalesce((select pg_catalog.jsonb_agg(a.alias order by a.alias) from dastak_v1.sku_search_aliases a where a.sku_id=s.id),'[]'::jsonb),
      'listPricePaise',s.list_price_paise,'sellingPricePaise',s.selling_price_paise,'currencyCode',s.currency_code,
      'catalogueStatus',s.status,'selected',coalesce(ms.state='SELECTED',false),'selectionState',ms.state,
      'selectionVersion',coalesce(ms.version,0),'selectionUpdatedAt',ms.updated_at,
      'stockQuantity',ms.stock_quantity,'stockReservedQuantity',ms.stock_reserved_quantity
    ) value
    from selected x join dastak_v1.skus s on s.id=x.id
    join dastak_v1.subcategories sc on sc.id=s.subcategory_id
    join dastak_v1.categories c on c.id=sc.category_id
    left join dastak_v1.brands b on b.id=s.brand_id
    left join dastak_v1.merchant_sku_selections ms on ms.branch_id=p_branch_id and ms.sku_id=s.id
  )
  select pg_catalog.jsonb_build_object('branchId',p_branch_id,
    'skus',coalesce((select pg_catalog.jsonb_agg(value order by pg_catalog.lower(canonical_name),id) from projected),'[]'::jsonb),
    'nextCursor',case when (select count(*) from matched)>v_limit then
      (select pg_catalog.jsonb_build_object('name',canonical_name,'skuId',id) from selected order by pg_catalog.lower(canonical_name) desc,id desc limit 1)
      else null end) into v_result;
  return v_result;
end;
$$;

create function dastak_v1_api.merchant_locations_page(
  p_actor_id uuid,p_limit integer default 100,p_after_id uuid default null,p_focus_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode='22023',message='Invalid location page';
  end if;
  with permitted as materialized (
    select b.id,b.display_name,o.merchant_type,
      dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,b.organization_id,'merchant.catalogue.selection.manage',b.id) catalogue,
      dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,b.organization_id,'merchant.restaurant.menu.manage',b.id) menu,
      dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,b.organization_id,'merchant.fulfilment.manage',b.id) fulfilment,
      dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,b.organization_id,'merchant.opportunities.respond',b.id) opportunities
    from dastak_v1.merchant_branches b join dastak_v1.merchant_organizations o on o.id=b.organization_id
    -- Bound permission probes to the caller's active organizations, rather
    -- than running four probes for every store in the whole marketplace.
    -- The existing permission helper remains authoritative for each branch.
    where o.status='ACTIVE' and exists (
      select 1 from dastak_v1.merchant_users u where u.account_id=p_actor_id
        and u.organization_id=o.id and u.status='ACTIVE'
    )
  ), authorized as materialized (
    select id,pg_catalog.jsonb_build_object('id',id,'displayName',display_name,'merchantType',merchant_type,
      'canManageStore',case when merchant_type in ('RETAIL','DASTAK_CONVENIENCE_STORE') then catalogue
        when merchant_type='RESTAURANT_CAFE' then menu else false end) value
    from permitted where catalogue or menu or fulfilment or opportunities
  ), page as materialized (
    select * from authorized where p_after_id is null or id>p_after_id order by id limit p_limit+1
  ), selected as (select * from page order by id limit p_limit)
  select pg_catalog.jsonb_build_object(
    'locations',coalesce((select pg_catalog.jsonb_agg(value order by id) from selected),'[]'::jsonb),
    'focusedLocation',(select value from authorized where id=p_focus_id),
    'nextCursor',case when (select count(*) from page)>p_limit then (select id from selected order by id desc limit 1) else null end
  ) into v_result;
  return v_result;
end;
$$;

create function public.dastak_v1_merchant_inventory_page(p_branch_id uuid,p_query text default null,
  p_selected_only boolean default false,p_limit integer default 100,p_after_name text default null,p_after_sku_id uuid default null)
returns jsonb language sql stable security invoker set search_path='' as $$
  select dastak_v1_api.merchant_inventory_page(auth.uid(),p_branch_id,p_query,p_selected_only,p_limit,p_after_name,p_after_sku_id);
$$;
create function public.dastak_v1_merchant_locations_page(p_limit integer default 100,p_after_id uuid default null,p_focus_id uuid default null)
returns jsonb language sql stable security invoker set search_path='' as $$
  select dastak_v1_api.merchant_locations_page(auth.uid(),p_limit,p_after_id,p_focus_id);
$$;
revoke all on function dastak_v1_api.merchant_inventory_page(uuid,uuid,text,boolean,integer,text,uuid),
  dastak_v1_api.merchant_locations_page(uuid,integer,uuid,uuid),
  public.dastak_v1_merchant_inventory_page(uuid,text,boolean,integer,text,uuid),
  public.dastak_v1_merchant_locations_page(integer,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function dastak_v1_api.merchant_inventory_page(uuid,uuid,text,boolean,integer,text,uuid),
  dastak_v1_api.merchant_locations_page(uuid,integer,uuid,uuid),
  public.dastak_v1_merchant_inventory_page(uuid,text,boolean,integer,text,uuid),
  public.dastak_v1_merchant_locations_page(integer,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
