create or replace function dastak_v1.guard_active_sku_primary_image_integrity()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_old_active boolean := false;
  v_old_qualifying boolean := false;
  v_new_qualifying boolean := false;
  v_other_exists boolean := false;
begin
  if tg_op in ('UPDATE','DELETE') then
    select exists(select 1 from dastak_v1.skus s where s.id=old.sku_id and s.status='ACTIVE') into v_old_active;
    v_old_qualifying := old.role='PRIMARY' and old.status='VERIFIED' and old.rights_status='CLEARED';

    if tg_op='UPDATE' then
      v_new_qualifying := new.sku_id=old.sku_id and new.role='PRIMARY' and new.status='VERIFIED' and new.rights_status='CLEARED';
    end if;

    if v_old_active and v_old_qualifying and not v_new_qualifying then
      select exists(
        select 1 from dastak_v1.sku_images im
        where im.sku_id=old.sku_id
          and im.id<>old.id
          and im.role='PRIMARY'
          and im.status='VERIFIED'
          and im.rights_status='CLEARED'
      ) into v_other_exists;
      if not v_other_exists then
        raise exception using errcode='23514',message='active SKU cannot lose its last verified primary image with cleared usage rights';
      end if;
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $function$;

drop trigger if exists sku_images_active_integrity_guard on dastak_v1.sku_images;
create trigger sku_images_active_integrity_guard
before update of sku_id,role,status,rights_status or delete on dastak_v1.sku_images
for each row execute function dastak_v1.guard_active_sku_primary_image_integrity();

drop trigger if exists skus_activation_quality_guard on dastak_v1.skus;
create trigger skus_activation_quality_guard
before insert or update of status,qa_status,subcategory_id,brand_id,list_price_paise,selling_price_paise on dastak_v1.skus
for each row execute function dastak_v1.guard_sku_activation_quality();

create or replace function dastak_v1.guard_catalogue_parent_deactivation()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare v_dep boolean := false;
begin
  if tg_op='UPDATE' and old.status='ACTIVE' and new.status<>'ACTIVE' then
    if tg_table_name='brands' then
      select exists(select 1 from dastak_v1.skus s where s.brand_id=old.id and s.status='ACTIVE') into v_dep;
    elsif tg_table_name='subcategories' then
      select exists(select 1 from dastak_v1.skus s where s.subcategory_id=old.id and s.status='ACTIVE') into v_dep;
    elsif tg_table_name='categories' then
      select exists(select 1 from dastak_v1.skus s join dastak_v1.subcategories sc on sc.id=s.subcategory_id where sc.category_id=old.id and s.status='ACTIVE') into v_dep;
    elsif tg_table_name='category_types' then
      select exists(select 1 from dastak_v1.skus s join dastak_v1.subcategories sc on sc.id=s.subcategory_id join dastak_v1.categories c on c.id=sc.category_id where c.category_type_id=old.id and s.status='ACTIVE') into v_dep;
    end if;
    if v_dep then
      raise exception using errcode='23514',message='catalogue parent cannot be deactivated while ACTIVE SKUs depend on it';
    end if;
  end if;
  return new;
end $function$;

drop trigger if exists brands_deactivation_guard on dastak_v1.brands;
create trigger brands_deactivation_guard before update of status on dastak_v1.brands for each row execute function dastak_v1.guard_catalogue_parent_deactivation();
drop trigger if exists subcategories_deactivation_guard on dastak_v1.subcategories;
create trigger subcategories_deactivation_guard before update of status on dastak_v1.subcategories for each row execute function dastak_v1.guard_catalogue_parent_deactivation();
drop trigger if exists categories_deactivation_guard on dastak_v1.categories;
create trigger categories_deactivation_guard before update of status on dastak_v1.categories for each row execute function dastak_v1.guard_catalogue_parent_deactivation();
drop trigger if exists category_types_deactivation_guard on dastak_v1.category_types;
create trigger category_types_deactivation_guard before update of status on dastak_v1.category_types for each row execute function dastak_v1.guard_catalogue_parent_deactivation();;
