begin;

do $m$
declare
  v_actor uuid;
  v_category_id uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;
  if v_actor is null then raise exception 'approved owner account required'; end if;

  select c.id into v_category_id
  from dastak_v1.categories c
  join dastak_v1.category_types ct on ct.id = c.category_type_id
  where ct.slug = 'fresh-produce' and c.slug = 'fresh-meat-seafood';
  if v_category_id is null then raise exception 'Meat and Seafood category missing'; end if;

  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  values
    (v_category_id,'Fresh Chicken','fresh-chicken','ACTIVE',10,v_actor),
    (v_category_id,'Fresh Seafood','fresh-seafood','ACTIVE',20,v_actor),
    (v_category_id,'Fresh Mutton','fresh-mutton','ACTIVE',30,v_actor),
    (v_category_id,'Frozen Food','frozen-food','ACTIVE',40,v_actor),
    (v_category_id,'Dry Fish','dry-fish','ACTIVE',50,v_actor),
    (v_category_id,'Ready to Cook','ready-to-cook','ACTIVE',60,v_actor)
  on conflict (category_id,slug) do update
    set name = excluded.name,
        status = 'ACTIVE',
        sort_order = excluded.sort_order,
        updated_at = now(),
        version = dastak_v1.subcategories.version + 1;
end $m$;

commit;
