-- Refine Dairy, Bread & Eggs taxonomy without deleting historical SKU records.
do $m$
declare
  v_actor uuid;
  v_paneer_category uuid;
  v_bakery_category uuid;
  v_milk_powders_category uuid;
  v_milk_subcategory uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;
  if v_actor is null then
    raise exception 'approved owner account required';
  end if;

  update dastak_v1.categories
  set name = 'Paneer & Tofu', updated_at = now(), version = version + 1
  where slug = 'paneer-cream';

  select id into v_milk_powders_category
  from dastak_v1.categories
  where slug = 'milk-powders-creamers';

  select sc.id into v_milk_subcategory
  from dastak_v1.subcategories sc
  join dastak_v1.categories c on c.id = sc.category_id
  where c.slug = 'milk'
    and sc.slug = 'milk';

  if v_milk_powders_category is not null and v_milk_subcategory is not null then
    update dastak_v1.skus s
    set subcategory_id = v_milk_subcategory,
        updated_at = now(),
        version = version + 1
    where s.subcategory_id in (
      select sc.id
      from dastak_v1.subcategories sc
      where sc.category_id = v_milk_powders_category
        and sc.slug = 'dairy-whitener'
    )
    and lower(s.canonical_name) like 'nestle%'
    and lower(s.canonical_name) like '%whitener%';
  end if;

  -- Deactivate remaining SKUs before retiring their parent categories; the
  -- catalogue guard intentionally rejects orphaning ACTIVE inventory.
  update dastak_v1.skus s
  set status = 'INACTIVE', updated_at = now(), version = version + 1
  where s.subcategory_id in (
    select sc.id
    from dastak_v1.subcategories sc
    join dastak_v1.categories c on c.id = sc.category_id
    where c.slug in ('milk-powders-creamers', 'bakery-essentials')
  );

  update dastak_v1.categories
  set status = 'INACTIVE', updated_at = now(), version = version + 1
  where slug = 'bakery-essentials';

  update dastak_v1.categories
  set status = 'INACTIVE', updated_at = now(), version = version + 1
  where slug = 'milk-powders-creamers';
end $m$;
