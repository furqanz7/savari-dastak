alter table dastak_v1.skus
  add column product_kind text not null default 'PACKAGED',
  add constraint skus_product_kind_valid check (product_kind in ('PACKAGED','FRESH','WEIGHED','GENERAL'));

create index skus_product_kind_idx on dastak_v1.skus(product_kind,status,qa_status);

create table dastak_v1.catalogue_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('MANUFACTURER','BRAND','DISTRIBUTOR','OWNER_CURATED','PUBLIC_REFERENCE','LEGACY_BACKUP','OTHER')),
  source_name text not null check (char_length(trim(source_name)) between 1 and 160),
  source_reference text,
  status text not null default 'CREATED' check (status in ('CREATED','INGESTING','VALIDATING','READY','COMPLETED','FAILED','CANCELLED')),
  counts jsonb not null default '{}'::jsonb check (jsonb_typeof(counts)='object'),
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  version bigint not null default 1 check (version>0)
);

create index catalogue_import_batches_status_idx
  on dastak_v1.catalogue_import_batches(status,created_at desc,id);

create table dastak_v1.catalogue_import_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references dastak_v1.catalogue_import_batches(id) on delete cascade,
  source_key text not null check (char_length(trim(source_key)) between 1 and 300),
  source_fingerprint text check (source_fingerprint is null or source_fingerprint ~ '^[0-9a-f]{64}$'),
  raw_payload jsonb not null check (jsonb_typeof(raw_payload)='object'),
  normalized_payload jsonb check (normalized_payload is null or jsonb_typeof(normalized_payload)='object'),
  status text not null default 'RAW' check (status in ('RAW','NORMALIZED','MATCHED','READY','IMPORTED','REJECTED')),
  canonical_sku_id uuid references dastak_v1.skus(id) on delete set null,
  issues jsonb not null default '[]'::jsonb check (jsonb_typeof(issues)='array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version bigint not null default 1 check (version>0),
  unique(batch_id,source_key)
);

create index catalogue_import_items_status_idx
  on dastak_v1.catalogue_import_items(batch_id,status,id);
create index catalogue_import_items_fingerprint_idx
  on dastak_v1.catalogue_import_items(source_fingerprint) where source_fingerprint is not null;
create index catalogue_import_items_sku_idx
  on dastak_v1.catalogue_import_items(canonical_sku_id) where canonical_sku_id is not null;

alter table dastak_v1.catalogue_import_batches enable row level security;
alter table dastak_v1.catalogue_import_items enable row level security;

create or replace function dastak_v1.guard_category_activation()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='ACTIVE' then
    if new.category_type_id is null or not exists(
      select 1 from dastak_v1.category_types ct where ct.id=new.category_type_id and ct.status='ACTIVE'
    ) then
      raise exception using errcode='23514',message='active category requires an active category type';
    end if;
  end if;
  if tg_op='UPDATE' then new.updated_at:=now(); end if;
  return new;
end;
$$;

create or replace function dastak_v1.guard_subcategory_activation()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='ACTIVE' and not exists(
    select 1 from dastak_v1.categories c where c.id=new.category_id and c.status='ACTIVE'
  ) then
    raise exception using errcode='23514',message='active subcategory requires an active category';
  end if;
  if tg_op='UPDATE' then new.updated_at:=now(); end if;
  return new;
end;
$$;

create or replace function dastak_v1.guard_sku_activation_quality()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='ACTIVE' then
    if new.qa_status <> 'VERIFIED' then
      raise exception using errcode='23514',message='active SKU requires VERIFIED QA status';
    end if;
    if not exists(
      select 1
      from dastak_v1.subcategories sc
      join dastak_v1.categories c on c.id=sc.category_id
      join dastak_v1.category_types ct on ct.id=c.category_type_id
      where sc.id=new.subcategory_id
        and sc.status='ACTIVE' and c.status='ACTIVE' and ct.status='ACTIVE'
    ) then
      raise exception using errcode='23514',message='active SKU requires active category type/category/subcategory';
    end if;
    if new.brand_id is not null and not exists(
      select 1 from dastak_v1.brands b where b.id=new.brand_id and b.status='ACTIVE'
    ) then
      raise exception using errcode='23514',message='active SKU brand must be active';
    end if;
    if not exists(
      select 1 from dastak_v1.sku_images i
      where i.sku_id=new.id and i.role='PRIMARY' and i.status='VERIFIED'
    ) then
      raise exception using errcode='23514',message='active SKU requires a verified primary image';
    end if;
  end if;
  return new;
end;
$$;

create trigger categories_activation_guard
before insert or update of status,category_type_id on dastak_v1.categories
for each row execute function dastak_v1.guard_category_activation();

create trigger subcategories_activation_guard
before insert or update of status,category_id on dastak_v1.subcategories
for each row execute function dastak_v1.guard_subcategory_activation();

create trigger skus_activation_quality_guard
before insert or update of status,qa_status,subcategory_id,brand_id on dastak_v1.skus
for each row execute function dastak_v1.guard_sku_activation_quality();

create or replace function dastak_v1_api.catalogue_quality_summary(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id,'platform.catalogue.read');
  return jsonb_build_object(
    'taxonomy',jsonb_build_object(
      'categoryTypes',(select count(*) from dastak_v1.category_types),
      'categories',(select count(*) from dastak_v1.categories),
      'subcategories',(select count(*) from dastak_v1.subcategories),
      'activeCategoryTypes',(select count(*) from dastak_v1.category_types where status='ACTIVE'),
      'activeCategories',(select count(*) from dastak_v1.categories where status='ACTIVE'),
      'activeSubcategories',(select count(*) from dastak_v1.subcategories where status='ACTIVE'),
      'orphanCategories',(select count(*) from dastak_v1.categories c left join dastak_v1.category_types ct on ct.id=c.category_type_id where ct.id is null),
      'orphanSubcategories',(select count(*) from dastak_v1.subcategories sc left join dastak_v1.categories c on c.id=sc.category_id where c.id is null)
    ),
    'skus',jsonb_build_object(
      'total',(select count(*) from dastak_v1.skus),
      'active',(select count(*) from dastak_v1.skus where status='ACTIVE'),
      'draft',(select count(*) from dastak_v1.skus where status='DRAFT'),
      'qaVerified',(select count(*) from dastak_v1.skus where qa_status='VERIFIED'),
      'qaPending',(select count(*) from dastak_v1.skus where qa_status in ('PENDING','NEEDS_REVIEW')),
      'missingCategoryType',(select count(*) from dastak_v1.skus s join dastak_v1.subcategories sc on sc.id=s.subcategory_id join dastak_v1.categories c on c.id=sc.category_id where c.category_type_id is null),
      'missingVerifiedPrimaryImage',(select count(*) from dastak_v1.skus s where not exists(select 1 from dastak_v1.sku_images i where i.sku_id=s.id and i.role='PRIMARY' and i.status='VERIFIED')),
      'missingStructuredQuantity',(select count(*) from dastak_v1.skus where product_kind in ('PACKAGED','FRESH','WEIGHED') and (quantity_value is null or quantity_unit is null)),
      'withoutIdentifiers',(select count(*) from dastak_v1.skus s where not exists(select 1 from dastak_v1.sku_identifiers i where i.sku_id=s.id))
    ),
    'assets',jsonb_build_object(
      'images',(select count(*) from dastak_v1.sku_images),
      'verifiedImages',(select count(*) from dastak_v1.sku_images where status='VERIFIED'),
      'aliases',(select count(*) from dastak_v1.sku_search_aliases),
      'identifiers',(select count(*) from dastak_v1.sku_identifiers)
    ),
    'imports',jsonb_build_object(
      'batches',(select count(*) from dastak_v1.catalogue_import_batches),
      'rawItems',(select count(*) from dastak_v1.catalogue_import_items where status='RAW'),
      'readyItems',(select count(*) from dastak_v1.catalogue_import_items where status='READY'),
      'rejectedItems',(select count(*) from dastak_v1.catalogue_import_items where status='REJECTED')
    )
  );
end;
$$;

create or replace function public.dastak_v1_catalogue_quality_summary()
returns jsonb
language sql
security invoker
set search_path=''
as $$ select dastak_v1_api.catalogue_quality_summary(auth.uid()); $$;

revoke all on function public.dastak_v1_catalogue_quality_summary() from public,anon;
grant execute on function public.dastak_v1_catalogue_quality_summary() to authenticated;
grant execute on function dastak_v1_api.catalogue_quality_summary(uuid) to authenticated;

comment on table dastak_v1.catalogue_import_batches is 'Source-level catalogue ingestion batches before canonical SKU publication.';
comment on table dastak_v1.catalogue_import_items is 'Raw/normalized source product records with validation issues and canonical SKU linkage.';
comment on function public.dastak_v1_catalogue_quality_summary() is 'Admin catalogue taxonomy, SKU quality, asset and ingestion readiness summary.';;
