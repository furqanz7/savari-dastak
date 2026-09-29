-- Align Fresh Produce's customer-facing category list with the requested
-- reference while retaining existing category IDs, SKUs, and subcategory links.
do $$
declare
  v_type_id uuid;
  v_actor_id uuid;
begin
  select id into v_type_id from dastak_v1.category_types where slug = 'fresh-produce';
  if v_type_id is null then
    return;
  end if;

  update dastak_v1.category_types
  set status = 'ACTIVE', updated_at = now(), version = version + 1
  where id = v_type_id;

  select created_by into v_actor_id
  from dastak_v1.categories
  where category_type_id = v_type_id
  order by sort_order
  limit 1;

  update dastak_v1.categories
  set name = case slug
      when 'leafy-greens-herbs' then 'Leafy and Seasonings'
      when 'seasonal-fruits' then 'Premium Produce'
      when 'fresh-cuts-sprouts' then 'Cuts and sprouts'
      when 'exotic-premium-produce' then 'Exotic Vegetables'
      when 'flowers-leaves' then 'Bouquet & Plants'
      else name
    end,
    updated_at = now(), version = version + 1
  where category_type_id = v_type_id
    and slug in ('leafy-greens-herbs','seasonal-fruits','fresh-cuts-sprouts',
                 'exotic-premium-produce','flowers-leaves');

  if v_actor_id is not null then
    insert into dastak_v1.categories(category_type_id, name, slug, status, sort_order, created_by)
    values
      (v_type_id, 'Pooja & Festive', 'fresh-pooja-festive', 'ACTIVE', 70, v_actor_id),
      (v_type_id, 'Certified Organics', 'fresh-certified-organics', 'ACTIVE', 80, v_actor_id),
      (v_type_id, 'Frozen Vegetables', 'fresh-frozen-vegetables', 'ACTIVE', 90, v_actor_id)
    on conflict (slug) do update
      set category_type_id = excluded.category_type_id,
          name = excluded.name,
          status = excluded.status,
          sort_order = excluded.sort_order,
          updated_at = now(),
          version = dastak_v1.categories.version + 1;
  end if;
end $$;
