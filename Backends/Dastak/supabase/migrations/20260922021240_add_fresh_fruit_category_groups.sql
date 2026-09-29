-- Add the Fresh Fruits sibling groups shown in the requested catalogue layout.
-- Existing IDs are retained; empty groups are created without inventing SKUs.
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
  if v_actor_id is null then return; end if;

  update dastak_v1.categories
  set name = 'Seasonal Fruits', updated_at = now(), version = version + 1
  where category_type_id = v_type_id and slug = 'seasonal-fruits';

  insert into dastak_v1.categories(category_type_id, name, slug, status, sort_order, created_by)
  values
    (v_type_id, 'Premium Produce', 'fresh-premium-produce', 'ACTIVE', 60, v_actor_id),
    (v_type_id, 'Exotic Fruits', 'fresh-exotic-fruits', 'ACTIVE', 65, v_actor_id),
    (v_type_id, 'Cut Fruits and Juices', 'fresh-cut-fruits-juices', 'ACTIVE', 75, v_actor_id),
    (v_type_id, 'Frozen Fruits', 'fresh-frozen-fruits', 'ACTIVE', 85, v_actor_id)
  on conflict (slug) do update
    set category_type_id = excluded.category_type_id,
        name = excluded.name,
        status = excluded.status,
        sort_order = excluded.sort_order,
        updated_at = now(),
        version = dastak_v1.categories.version + 1;
end $$;
