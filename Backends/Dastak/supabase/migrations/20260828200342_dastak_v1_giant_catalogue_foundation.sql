create table dastak_v1.category_types (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 100),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  image_key text check (image_key is null or char_length(trim(image_key)) between 1 and 500),
  status dastak_v1.catalogue_status not null default 'DRAFT',
  sort_order integer not null default 0 check (sort_order between 0 and 10000),
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version > 0)
);

create index category_types_customer_browse_idx
  on dastak_v1.category_types(status, sort_order, name, id);
create index category_types_created_by_idx
  on dastak_v1.category_types(created_by);

alter table dastak_v1.categories
  add column category_type_id uuid references dastak_v1.category_types(id),
  add constraint categories_active_requires_category_type
    check (status <> 'ACTIVE' or category_type_id is not null);

create index categories_category_type_idx
  on dastak_v1.categories(category_type_id, status, sort_order, name, id);

alter table dastak_v1.skus
  add column quantity_value numeric(12,3),
  add column quantity_unit text,
  add column pack_count integer,
  add column manufacturer_name text,
  add column country_of_origin_code text,
  add column hsn_code text,
  add column diet_type text not null default 'NA',
  add column shelf_life_days integer,
  add column attribute_data jsonb not null default '{}'::jsonb,
  add column qa_status text not null default 'PENDING',
  add column qa_verified_at timestamptz,
  add column qa_verified_by uuid references public.accounts(id),
  add constraint skus_quantity_value_valid check (quantity_value is null or quantity_value > 0),
  add constraint skus_quantity_unit_valid check (
    quantity_unit is null or quantity_unit in ('g','kg','ml','l','unit','pack','pair','sheet','roll','tablet','capsule')
  ),
  add constraint skus_pack_count_valid check (pack_count is null or pack_count between 1 and 10000),
  add constraint skus_manufacturer_name_valid check (
    manufacturer_name is null or char_length(trim(manufacturer_name)) between 1 and 200
  ),
  add constraint skus_country_origin_valid check (
    country_of_origin_code is null or country_of_origin_code ~ '^[A-Z]{2}$'
  ),
  add constraint skus_hsn_code_valid check (
    hsn_code is null or hsn_code ~ '^[0-9]{4,8}$'
  ),
  add constraint skus_diet_type_valid check (diet_type in ('VEG','NON_VEG','EGG','NA')),
  add constraint skus_shelf_life_valid check (shelf_life_days is null or shelf_life_days between 1 and 36500),
  add constraint skus_attribute_data_object check (jsonb_typeof(attribute_data) = 'object'),
  add constraint skus_qa_status_valid check (qa_status in ('PENDING','NEEDS_REVIEW','VERIFIED','REJECTED')),
  add constraint skus_qa_verification_pair check (
    (qa_status = 'VERIFIED' and qa_verified_at is not null and qa_verified_by is not null)
    or qa_status <> 'VERIFIED'
  );

create index skus_qa_status_idx on dastak_v1.skus(qa_status, status, canonical_name, id);
create index skus_country_origin_idx on dastak_v1.skus(country_of_origin_code) where country_of_origin_code is not null;
create index skus_hsn_idx on dastak_v1.skus(hsn_code) where hsn_code is not null;

create table dastak_v1.sku_images (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references dastak_v1.skus(id) on delete cascade,
  image_key text not null unique check (char_length(trim(image_key)) between 1 and 500),
  role text not null check (role in ('PRIMARY','GALLERY')),
  sort_order integer not null default 0 check (sort_order between 0 and 1000),
  source_type text not null check (source_type in (
    'MANUFACTURER','BRAND','AUTHORIZED_RETAILER','DISTRIBUTOR','OWNER_CAPTURE','COMMODITY_STOCK','OTHER'
  )),
  source_reference text,
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$'),
  width_pixels integer check (width_pixels is null or width_pixels between 1 and 20000),
  height_pixels integer check (height_pixels is null or height_pixels between 1 and 20000),
  mime_type text check (mime_type is null or mime_type in ('image/jpeg','image/png','image/webp','image/avif')),
  status text not null default 'PENDING' check (status in ('PENDING','VERIFIED','REJECTED')),
  created_by uuid references public.accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  verified_by uuid references public.accounts(id) on delete set null,
  verified_at timestamptz,
  version bigint not null default 1 check (version > 0),
  constraint sku_images_verification_pair check (
    (status = 'VERIFIED' and verified_at is not null and verified_by is not null)
    or status <> 'VERIFIED'
  )
);

create unique index sku_images_one_primary_uidx
  on dastak_v1.sku_images(sku_id) where role = 'PRIMARY';
create index sku_images_gallery_idx
  on dastak_v1.sku_images(sku_id, role, status, sort_order, id);
create index sku_images_checksum_idx
  on dastak_v1.sku_images(checksum_sha256) where checksum_sha256 is not null;

create table dastak_v1.sku_search_aliases (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references dastak_v1.skus(id) on delete cascade,
  alias text not null check (char_length(trim(alias)) between 1 and 160),
  normalized_alias text generated always as (lower(btrim(alias))) stored,
  locale text not null default 'en-IN' check (char_length(trim(locale)) between 2 and 20),
  alias_type text not null default 'SEARCH' check (alias_type in ('SEARCH','COMMON_NAME','MISSPELLING','REGIONAL','TRANSLITERATION')),
  search_document tsvector generated always as (
    to_tsvector('pg_catalog.simple'::regconfig, coalesce(alias, ''))
  ) stored,
  created_by uuid references public.accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(sku_id, normalized_alias, locale)
);

create index sku_search_aliases_search_gin
  on dastak_v1.sku_search_aliases using gin(search_document);
create index sku_search_aliases_sku_idx
  on dastak_v1.sku_search_aliases(sku_id, alias_type, locale);

create table dastak_v1.sku_identifiers (
  id uuid primary key default gen_random_uuid(),
  sku_id uuid not null references dastak_v1.skus(id) on delete cascade,
  identifier_type text not null check (identifier_type in ('GTIN','EAN','UPC','MANUFACTURER_SKU','DISTRIBUTOR_SKU','OTHER')),
  identifier_value text not null check (char_length(trim(identifier_value)) between 1 and 128),
  normalized_value text generated always as (upper(btrim(identifier_value))) stored,
  is_primary boolean not null default false,
  source_reference text,
  created_by uuid references public.accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(identifier_type, normalized_value)
);

create unique index sku_identifiers_one_primary_uidx
  on dastak_v1.sku_identifiers(sku_id) where is_primary;
create index sku_identifiers_sku_idx
  on dastak_v1.sku_identifiers(sku_id, identifier_type);

alter table dastak_v1.category_types enable row level security;
alter table dastak_v1.sku_images enable row level security;
alter table dastak_v1.sku_search_aliases enable row level security;
alter table dastak_v1.sku_identifiers enable row level security;

create or replace function dastak_v1_api.catalogue_taxonomy_snapshot(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.read');
  return jsonb_build_object(
    'categoryTypes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ct.id, 'name', ct.name, 'slug', ct.slug, 'imageKey', ct.image_key,
        'status', ct.status, 'sortOrder', ct.sort_order, 'version', ct.version
      ) order by ct.sort_order, ct.name, ct.id)
      from dastak_v1.category_types ct
    ), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'categoryTypeId', c.category_type_id, 'name', c.name, 'slug', c.slug,
        'imageKey', c.image_key, 'status', c.status, 'sortOrder', c.sort_order, 'version', c.version
      ) order by ct.sort_order nulls last, c.sort_order, c.name, c.id)
      from dastak_v1.categories c
      left join dastak_v1.category_types ct on ct.id = c.category_type_id
    ), '[]'::jsonb),
    'subcategories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sc.id, 'categoryId', sc.category_id, 'name', sc.name, 'slug', sc.slug,
        'imageKey', sc.image_key, 'status', sc.status, 'sortOrder', sc.sort_order, 'version', sc.version
      ) order by c.sort_order, sc.sort_order, sc.name, sc.id)
      from dastak_v1.subcategories sc
      join dastak_v1.categories c on c.id = sc.category_id
    ), '[]'::jsonb),
    'brands', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name, 'slug', b.slug, 'imageKey', b.image_key,
        'status', b.status, 'version', b.version
      ) order by b.name, b.id)
      from dastak_v1.brands b
    ), '[]'::jsonb)
  );
end;
$$;

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
  select coalesce(jsonb_agg(jsonb_build_object(
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
  ) order by lower(x.canonical_name),x.id),'[]'::jsonb)
  into v_rows from selected x;

  select count(*)>v_limit into v_has_more from matched;
  if v_has_more then
    select jsonb_build_object('name',canonical_name,'skuId',id)
    into v_next_cursor
    from selected order by lower(canonical_name) desc,id desc limit 1;
  else
    v_next_cursor:=null;
  end if;

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
  select coalesce(jsonb_agg(jsonb_build_object(
    'skuId',x.id,'categoryTypeId',x.category_type_id,'categoryId',x.category_id,'subcategoryId',x.subcategory_id,
    'brandName',x.brand_name,'name',x.canonical_name,'variant',x.variant_name,'packSize',x.pack_size,
    'imageKey',coalesce((select i.image_key from dastak_v1.sku_images i where i.sku_id=x.id and i.role='PRIMARY' and i.status='VERIFIED' limit 1),x.image_key),
    'listPricePaise',x.list_price_paise,'sellingPricePaise',x.selling_price_paise,'currencyCode',x.currency_code,
    'selected',coalesce(x.selection_state='SELECTED',false),'selectionState',x.selection_state,
    'selectionVersion',coalesce(x.selection_version,0),'selectionUpdatedAt',x.selection_updated_at,
    'qaStatus',x.qa_status
  ) order by lower(x.canonical_name),x.id),'[]'::jsonb)
  into v_rows from selected x;

  select count(*)>v_limit into v_has_more from matched;
  if v_has_more then
    select jsonb_build_object('name',canonical_name,'skuId',id) into v_next_cursor
    from selected order by lower(canonical_name) desc,id desc limit 1;
  else v_next_cursor:=null; end if;

  return jsonb_build_object('skus',v_rows,'hasMore',v_has_more,'nextCursor',v_next_cursor);
end;
$$;

create or replace function public.dastak_v1_catalogue_taxonomy_snapshot()
returns jsonb language sql security invoker set search_path='' as $$
  select dastak_v1_api.catalogue_taxonomy_snapshot(auth.uid());
$$;

create or replace function public.dastak_v1_admin_catalogue_page(
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
returns jsonb language sql security invoker set search_path='' as $$
  select dastak_v1_api.admin_catalogue_page(auth.uid(),p_query,p_category_type_id,p_category_id,p_subcategory_id,p_status,p_qa_status,p_limit,p_after_name,p_after_sku_id);
$$;

create or replace function public.dastak_v1_merchant_catalogue_page(
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
returns jsonb language sql security invoker set search_path='' as $$
  select dastak_v1_api.merchant_catalogue_page(auth.uid(),p_branch_id,p_query,p_category_type_id,p_category_id,p_subcategory_id,p_selected_only,p_limit,p_after_name,p_after_sku_id);
$$;

revoke all on function public.dastak_v1_catalogue_taxonomy_snapshot() from public,anon;
revoke all on function public.dastak_v1_admin_catalogue_page(text,uuid,uuid,uuid,text,text,integer,text,uuid) from public,anon;
revoke all on function public.dastak_v1_merchant_catalogue_page(uuid,text,uuid,uuid,uuid,boolean,integer,text,uuid) from public,anon;
grant execute on function public.dastak_v1_catalogue_taxonomy_snapshot() to authenticated;
grant execute on function public.dastak_v1_admin_catalogue_page(text,uuid,uuid,uuid,text,text,integer,text,uuid) to authenticated;
grant execute on function public.dastak_v1_merchant_catalogue_page(uuid,text,uuid,uuid,uuid,boolean,integer,text,uuid) to authenticated;

grant execute on function dastak_v1_api.catalogue_taxonomy_snapshot(uuid) to authenticated;
grant execute on function dastak_v1_api.admin_catalogue_page(uuid,text,uuid,uuid,uuid,text,text,integer,text,uuid) to authenticated;
grant execute on function dastak_v1_api.merchant_catalogue_page(uuid,uuid,text,uuid,uuid,uuid,boolean,integer,text,uuid) to authenticated;

comment on table dastak_v1.category_types is 'Top-level Dastak canonical catalogue departments/category types.';
comment on table dastak_v1.sku_images is 'Canonical SKU image assets with provenance and verification state.';
comment on table dastak_v1.sku_search_aliases is 'Search synonyms, misspellings, regional terms and transliterations for exact SKUs.';
comment on table dastak_v1.sku_identifiers is 'Normalized external/internal identifiers associated with an exact canonical SKU.';
comment on function public.dastak_v1_admin_catalogue_page(text,uuid,uuid,uuid,text,text,integer,text,uuid) is 'Cursor-paginated giant-catalogue Admin SKU projection.';
comment on function public.dastak_v1_merchant_catalogue_page(uuid,text,uuid,uuid,uuid,boolean,integer,text,uuid) is 'Cursor-paginated giant-catalogue retail merchant SKU-selection projection.';;
