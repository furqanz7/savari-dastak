create or replace function dastak_v1_api.admin_catalogue_page(
  p_actor_id uuid,
  p_query text default null,
  p_category_type_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_status text default null,
  p_qa_status text default null,
  p_limit integer default 100,
  p_after_name text default null,
  p_after_sku_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := nullif(btrim(coalesce(p_query,'')), '');
  v_search tsquery;
  v_limit integer := least(greatest(coalesce(p_limit,100),1),250);
  v_rows jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.read');
  if (p_after_name is null) <> (p_after_sku_id is null) then
    raise exception using errcode='22023', message='complete catalogue cursor required';
  end if;
  if p_status is not null and upper(p_status) not in ('DRAFT','ACTIVE','INACTIVE') then
    raise exception using errcode='22023', message='invalid catalogue status';
  end if;
  if p_qa_status is not null and upper(p_qa_status) not in ('PENDING','NEEDS_REVIEW','VERIFIED','REJECTED') then
    raise exception using errcode='22023', message='invalid QA status';
  end if;
  if v_query is not null then
    if char_length(v_query) > 80 then raise exception using errcode='22023', message='catalogue search is too long'; end if;
    v_search := dastak_v1.catalogue_prefix_query(v_query);
  end if;

  with matched as materialized (
    select s.*, sc.category_id, c.category_type_id, b.name as brand_name,
           coalesce((select count(*) from dastak_v1.merchant_sku_selections ms where ms.sku_id=s.id and ms.state='SELECTED'),0) as selection_count
    from dastak_v1.skus s
    join dastak_v1.subcategories sc on sc.id=s.subcategory_id
    join dastak_v1.categories c on c.id=sc.category_id
    left join dastak_v1.brands b on b.id=s.brand_id
    where (p_category_type_id is null or c.category_type_id=p_category_type_id)
      and (p_category_id is null or sc.category_id=p_category_id)
      and (p_subcategory_id is null or s.subcategory_id=p_subcategory_id)
      and (p_status is null or s.status::text=upper(p_status))
      and (p_qa_status is null or s.qa_status=upper(p_qa_status))
      and (
        v_search is null
        or s.search_document @@ v_search
        or exists(select 1 from dastak_v1.sku_search_aliases a where a.sku_id=s.id and a.search_document @@ v_search)
        or to_tsvector('pg_catalog.simple'::regconfig, coalesce(b.name,'') || ' ' || sc.name || ' ' || c.name) @@ v_search
      )
      and (p_after_name is null or (lower(s.canonical_name),s.id) > (lower(p_after_name),p_after_sku_id))
    order by lower(s.canonical_name),s.id
    limit v_limit+1
  ), selected as (
    select * from matched order by lower(canonical_name),id limit v_limit
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',x.id,'categoryTypeId',x.category_type_id,'categoryId',x.category_id,'subcategoryId',x.subcategory_id,
        'brandId',x.brand_id,'brandName',x.brand_name,'name',x.canonical_name,'slug',x.slug,'variant',x.variant_name,
        'packSize',x.pack_size,'quantityValue',x.quantity_value,'quantityUnit',x.quantity_unit,'packCount',x.pack_count,
        'manufacturerName',x.manufacturer_name,'countryOfOriginCode',x.country_of_origin_code,'hsnCode',x.hsn_code,
        'dietType',x.diet_type,'shelfLifeDays',x.shelf_life_days,'attributes',x.attribute_data,
        'barcode',x.barcode,'listPricePaise',x.list_price_paise,'sellingPricePaise',x.selling_price_paise,
        'currencyCode',x.currency_code,'taxRateBps',x.tax_rate_bps,'logisticsAttributes',x.logistics_attributes,
        'status',x.status,'qaStatus',x.qa_status,'selectionCount',x.selection_count,'version',x.version,'updatedAt',x.updated_at,
        'primaryImage', (select jsonb_build_object('id',i.id,'imageKey',i.image_key,'status',i.status,'sourceType',i.source_type)
                         from dastak_v1.sku_images i where i.sku_id=x.id and i.role='PRIMARY' limit 1),
        'imageCount',(select count(*) from dastak_v1.sku_images i where i.sku_id=x.id and i.status<>'REJECTED'),
        'aliasCount',(select count(*) from dastak_v1.sku_search_aliases a where a.sku_id=x.id),
        'identifierCount',(select count(*) from dastak_v1.sku_identifiers si where si.sku_id=x.id)
      ) order by lower(x.canonical_name),x.id)
      from selected x
    ),'[]'::jsonb),
    (select count(*)>v_limit from matched),
    case when (select count(*)>v_limit from matched) then (
      select jsonb_build_object('name',x.canonical_name,'skuId',x.id)
      from selected x order by lower(x.canonical_name) desc,x.id desc limit 1
    ) else null end
  into v_rows,v_has_more,v_next_cursor;

  return jsonb_build_object('skus',v_rows,'hasMore',v_has_more,'nextCursor',v_next_cursor);
end;
$$;

create or replace function dastak_v1_api.merchant_catalogue_page(
  p_actor_id uuid,
  p_branch_id uuid,
  p_query text default null,
  p_category_type_id uuid default null,
  p_category_id uuid default null,
  p_subcategory_id uuid default null,
  p_selected_only boolean default false,
  p_limit integer default 100,
  p_after_name text default null,
  p_after_sku_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_query text := nullif(btrim(coalesce(p_query,'')), '');
  v_search tsquery;
  v_limit integer := least(greatest(coalesce(p_limit,100),1),250);
  v_rows jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  select * into v_branch from dastak_v1.merchant_branches where id=p_branch_id;
  if not found then raise exception using errcode='P0002',message='merchant branch not found'; end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,v_branch.organization_id,'merchant.catalogue.selection.manage',v_branch.id) then
    raise exception using errcode='42501',message='permission denied';
  end if;
  if (p_after_name is null) <> (p_after_sku_id is null) then
    raise exception using errcode='22023',message='complete catalogue cursor required';
  end if;
  if v_query is not null then
    if char_length(v_query)>80 then raise exception using errcode='22023',message='catalogue search is too long'; end if;
    v_search:=dastak_v1.catalogue_prefix_query(v_query);
  end if;

  with matched as materialized (
    select s.*,sc.category_id,c.category_type_id,b.name as brand_name,ms.state as selection_state,ms.version as selection_version,ms.updated_at as selection_updated_at
    from dastak_v1.skus s
    join dastak_v1.subcategories sc on sc.id=s.subcategory_id
    join dastak_v1.categories c on c.id=sc.category_id
    left join dastak_v1.brands b on b.id=s.brand_id
    left join dastak_v1.merchant_sku_selections ms on ms.branch_id=p_branch_id and ms.sku_id=s.id
    where (s.status='ACTIVE' or ms.sku_id is not null)
      and (p_selected_only=false or ms.state='SELECTED')
      and (p_category_type_id is null or c.category_type_id=p_category_type_id)
      and (p_category_id is null or sc.category_id=p_category_id)
      and (p_subcategory_id is null or s.subcategory_id=p_subcategory_id)
      and (v_search is null or s.search_document @@ v_search or exists(select 1 from dastak_v1.sku_search_aliases a where a.sku_id=s.id and a.search_document @@ v_search))
      and (p_after_name is null or (lower(s.canonical_name),s.id)>(lower(p_after_name),p_after_sku_id))
    order by lower(s.canonical_name),s.id
    limit v_limit+1
  ), selected as (
    select * from matched order by lower(canonical_name),id limit v_limit
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'skuId',x.id,'categoryTypeId',x.category_type_id,'categoryId',x.category_id,'subcategoryId',x.subcategory_id,
        'brandName',x.brand_name,'name',x.canonical_name,'variant',x.variant_name,'packSize',x.pack_size,
        'imageKey',coalesce((select i.image_key from dastak_v1.sku_images i where i.sku_id=x.id and i.role='PRIMARY' and i.status='VERIFIED' limit 1),x.image_key),
        'listPricePaise',x.list_price_paise,'sellingPricePaise',x.selling_price_paise,'currencyCode',x.currency_code,
        'selected',coalesce(x.selection_state='SELECTED',false),'selectionState',x.selection_state,
        'selectionVersion',coalesce(x.selection_version,0),'selectionUpdatedAt',x.selection_updated_at,
        'qaStatus',x.qa_status
      ) order by lower(x.canonical_name),x.id)
      from selected x
    ),'[]'::jsonb),
    (select count(*)>v_limit from matched),
    case when (select count(*)>v_limit from matched) then (
      select jsonb_build_object('name',x.canonical_name,'skuId',x.id)
      from selected x order by lower(x.canonical_name) desc,x.id desc limit 1
    ) else null end
  into v_rows,v_has_more,v_next_cursor;

  return jsonb_build_object('skus',v_rows,'hasMore',v_has_more,'nextCursor',v_next_cursor);
end;
$$;;
