alter table dastak_v1.skus alter column list_price_paise drop not null;
alter table dastak_v1.skus alter column selling_price_paise drop not null;

alter table dastak_v1.skus drop constraint if exists skus_quantity_unit_valid;
alter table dastak_v1.skus add constraint skus_quantity_unit_valid check (
  quantity_unit is null or quantity_unit = any(array[
    'g','kg','ml','l','unit','pack','pair','sheet','roll','tablet','capsule','tea_bag','sachet','cube'
  ]::text[])
);

create or replace function dastak_v1.guard_sku_activation_quality()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status='ACTIVE' then
    if new.list_price_paise is null or new.selling_price_paise is null then
      raise exception using errcode='23514',message='active SKU requires Dastak list and selling prices';
    end if;
    if new.selling_price_paise < 0 or new.list_price_paise < 0 or new.selling_price_paise > new.list_price_paise then
      raise exception using errcode='23514',message='active SKU prices are invalid';
    end if;
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
end $function$;;
