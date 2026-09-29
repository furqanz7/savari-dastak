-- Add the two reference Masalas rails that have no canonical destination.
-- They start empty: this migration does not create or infer any SKU.
do $$
declare
  v_actor uuid;
  v_type_id uuid;
begin
  select m.account_id into v_actor
  from private.account_memberships m
  where m.role = 'owner'
    and m.approved_at is not null
    and (m.suspended_until is null or m.suspended_until <= now())
  order by m.approved_at desc
  limit 1;
  if v_actor is null then
    raise exception 'approved owner account required for Masalas taxonomy';
  end if;

  select id into v_type_id
  from dastak_v1.category_types
  where slug = 'masala-cooking';
  if v_type_id is null then
    raise exception 'Masalas category type is missing';
  end if;

  if exists (
    select 1 from dastak_v1.categories c
    where c.slug in ('cold-grind', 'herbs-seasoning')
      and c.category_type_id is distinct from v_type_id
  ) then
    raise exception 'A Masalas category slug belongs to another department';
  end if;

  insert into dastak_v1.categories
    (category_type_id, name, slug, status, sort_order, created_by)
  values
    (v_type_id, 'Cold Grind', 'cold-grind', 'ACTIVE', 35, v_actor),
    (v_type_id, 'Herbs & Seasoning', 'herbs-seasoning', 'ACTIVE', 95, v_actor)
  on conflict (slug) do update
  set name = excluded.name,
      status = 'ACTIVE',
      sort_order = excluded.sort_order,
      updated_at = now(),
      version = dastak_v1.categories.version + 1;
end;
$$;
