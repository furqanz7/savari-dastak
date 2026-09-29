begin;

do $m$
declare
  v_actor uuid;
  v_type_id uuid;
begin
  select m.account_id
    into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;

  if v_actor is null then
    raise exception 'approved owner account required';
  end if;

  select id
    into v_type_id
  from dastak_v1.category_types
  where slug = 'dairy-bread-eggs';

  if v_type_id is null then
    raise exception 'dairy-bread-eggs category type missing';
  end if;

  insert into dastak_v1.categories
    (category_type_id, name, slug, status, sort_order, created_by)
  values
    (v_type_id, 'Batters and Chutneys', 'batters-chutneys', 'ACTIVE', 100, v_actor),
    (v_type_id, 'Lassi and Buttermilk', 'lassi-buttermilk', 'ACTIVE', 110, v_actor),
    (v_type_id, 'Indian Breads', 'indian-breads', 'ACTIVE', 120, v_actor),
    (v_type_id, 'Cream and Condensed Milk', 'cream-condensed-milk', 'ACTIVE', 130, v_actor),
    (v_type_id, 'Milkshakes and More', 'milkshakes-more', 'ACTIVE', 140, v_actor)
  on conflict (slug) do update
    set category_type_id = excluded.category_type_id,
        name = excluded.name,
        status = 'ACTIVE',
        sort_order = excluded.sort_order,
        updated_at = now(),
        version = dastak_v1.categories.version + 1;
end $m$;

commit;
