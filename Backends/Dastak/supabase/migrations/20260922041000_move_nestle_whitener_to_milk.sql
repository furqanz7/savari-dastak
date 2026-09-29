-- Keep Nestle Everyday Dairy Whitener available under the Milk category.
do $m$
declare
  v_actor uuid;
  v_milk_category uuid;
  v_milk_subcategory uuid;
  v_old_subcategory uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;
  if v_actor is null then raise exception 'approved owner account required'; end if;

  select id into v_milk_category from dastak_v1.categories where slug = 'milk';
  if v_milk_category is null then raise exception 'milk category missing'; end if;

  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values(v_milk_category,'Dairy Whitener','dairy-whitener','ACTIVE',90,v_actor)
  on conflict (category_id,slug) do update
    set name = excluded.name, status = 'ACTIVE', updated_at = now(), version = dastak_v1.subcategories.version + 1
  returning id into v_milk_subcategory;

  select sc.id into v_old_subcategory
  from dastak_v1.subcategories sc
  join dastak_v1.categories c on c.id = sc.category_id
  where c.slug = 'milk-powders-creamers' and sc.slug = 'milk-powder';

  update dastak_v1.skus s
  set subcategory_id = v_milk_subcategory,
      status = 'ACTIVE',
      updated_at = now(),
      version = version + 1
  where s.subcategory_id = v_old_subcategory
    and lower(s.canonical_name) like 'nestle%'
    and lower(s.canonical_name) like '%whitener%';
end $m$;
