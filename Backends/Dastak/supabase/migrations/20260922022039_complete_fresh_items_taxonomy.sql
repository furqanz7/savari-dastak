-- Complete the Fresh Items / Fresh Produce category set shown in the reference.
do $$
declare
  v_type_id uuid;
  v_actor_id uuid;
begin
  select id into v_type_id from dastak_v1.category_types where slug = 'fresh-produce';
  if v_type_id is null then return; end if;

  select created_by into v_actor_id
  from dastak_v1.categories
  where category_type_id = v_type_id
  order by sort_order
  limit 1;

  update dastak_v1.categories
  set status = 'ACTIVE', updated_at = now(), version = version + 1
  where category_type_id = v_type_id
    and slug in ('fresh-pooja-festive', 'fresh-certified-organics');

  if v_actor_id is not null then
    insert into dastak_v1.categories(category_type_id, name, slug, status, sort_order, created_by)
    values (v_type_id, 'Meat and Seafood', 'fresh-meat-seafood', 'ACTIVE', 5, v_actor_id)
    on conflict (slug) do update
      set category_type_id = excluded.category_type_id,
          name = excluded.name,
          status = excluded.status,
          sort_order = excluded.sort_order,
          updated_at = now(),
          version = dastak_v1.categories.version + 1;
  end if;
end $$;
