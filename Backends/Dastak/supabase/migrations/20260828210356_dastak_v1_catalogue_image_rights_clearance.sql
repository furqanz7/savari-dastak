alter table dastak_v1.catalogue_import_item_assets
  add column if not exists rights_status text not null default 'UNKNOWN'
    check (rights_status in ('UNKNOWN','CLEARED','RESTRICTED','REJECTED')),
  add column if not exists rights_reference text,
  add column if not exists rights_verified_by uuid references public.accounts(id),
  add column if not exists rights_verified_at timestamptz;

alter table dastak_v1.sku_images
  add column if not exists rights_status text not null default 'UNKNOWN'
    check (rights_status in ('UNKNOWN','CLEARED','RESTRICTED','REJECTED')),
  add column if not exists rights_reference text,
  add column if not exists rights_verified_by uuid references public.accounts(id),
  add column if not exists rights_verified_at timestamptz;

create or replace function dastak_v1.guard_sku_activation_quality()
returns trigger language plpgsql security definer set search_path='' as $$
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
      where i.sku_id=new.id and i.role='PRIMARY' and i.status='VERIFIED' and i.rights_status='CLEARED'
    ) then
      raise exception using errcode='23514',message='active SKU requires a verified primary image with cleared usage rights';
    end if;
  end if;
  return new;
end $$;;
