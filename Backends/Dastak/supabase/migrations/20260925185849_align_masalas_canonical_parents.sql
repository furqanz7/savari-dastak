-- Keep one canonical parent for every Masalas rail in customer, merchant and
-- admin. Reparenting the existing category IDs preserves SKU IDs, merchant
-- selections, carts and order history; it neither creates nor deletes SKUs.
do $$
declare
  v_masalas_id uuid;
  v_staples_id uuid;
  v_snacks_id uuid;
  v_ready_curries_id uuid;
begin
  select id into strict v_masalas_id
  from dastak_v1.category_types where slug = 'masala-cooking';
  select id into strict v_staples_id
  from dastak_v1.category_types where slug = 'staples-pantry';
  select id into strict v_snacks_id
  from dastak_v1.category_types where slug = 'snacks-munchies';

  -- The API snapshot must use the same names as all three storefronts.
  update dastak_v1.category_types
  set name = 'Atta, Flour & Dal', updated_at = now(), version = version + 1
  where id = v_staples_id and name is distinct from 'Atta, Flour & Dal';
  update dastak_v1.category_types
  set name = 'Masalas', updated_at = now(), version = version + 1
  where id = v_masalas_id and name is distinct from 'Masalas';

  if (select count(*) from dastak_v1.categories
      where slug in ('sugar-sweeteners', 'salt', 'papad-fryums')) <> 3 then
    raise exception 'Expected exactly three existing Masalas cross-parent categories';
  end if;
  if exists (
    select 1 from dastak_v1.categories
    where (slug in ('sugar-sweeteners', 'salt')
           and category_type_id not in (v_staples_id, v_masalas_id))
       or (slug = 'papad-fryums'
           and category_type_id not in (v_snacks_id, v_masalas_id))
  ) then
    raise exception 'A Masalas cross-parent category has an unexpected current parent';
  end if;

  update dastak_v1.categories
  set category_type_id = v_masalas_id,
      name = case slug
        when 'sugar-sweeteners' then 'Sugar and Jaggery'
        when 'papad-fryums' then 'Papad & Fryums'
        else 'Salt'
      end,
      sort_order = case slug
        when 'sugar-sweeteners' then 40
        when 'papad-fryums' then 50
        else 70
      end,
      updated_at = now(),
      version = version + 1
  where slug in ('sugar-sweeteners', 'salt', 'papad-fryums')
    and (category_type_id is distinct from v_masalas_id
      or name is distinct from case slug
        when 'sugar-sweeteners' then 'Sugar and Jaggery'
        when 'papad-fryums' then 'Papad & Fryums'
        else 'Salt'
      end
      or sort_order is distinct from case slug
        when 'sugar-sweeteners' then 40
        when 'papad-fryums' then 50
        else 70
      end);

  -- Store the visible reference labels in canonical taxonomy as well, so
  -- administrative selectors and catalogue snapshots do not retain old names.
  update dastak_v1.categories
  set name = case slug
        when 'blended-masalas' then 'Ready Masala'
        when 'cooking-pastes' then 'Paste and Puree'
        when 'pickles-chutneys' then 'Pickles & Chutney'
        else 'Coconut Milk & Powder'
      end,
      status = case when slug = 'coconut-products' then 'ACTIVE'::dastak_v1.catalogue_status else status end,
      updated_at = now(),
      version = version + 1
  where category_type_id = v_masalas_id
    and slug in ('blended-masalas', 'cooking-pastes', 'pickles-chutneys', 'coconut-products')
    and (name is distinct from case slug
           when 'blended-masalas' then 'Ready Masala'
           when 'cooking-pastes' then 'Paste and Puree'
           when 'pickles-chutneys' then 'Pickles & Chutney'
           else 'Coconut Milk & Powder'
         end
         or (slug = 'coconut-products' and status <> 'ACTIVE'));

  update dastak_v1.categories
  set sort_order = case slug
        when 'powdered-spices' then 10
        when 'whole-spices' then 20
        when 'cold-grind' then 30
        when 'sugar-sweeteners' then 40
        when 'papad-fryums' then 50
        when 'blended-masalas' then 60
        when 'salt' then 70
        when 'cooking-pastes' then 80
        when 'pickles-chutneys' then 90
        when 'herbs-seasoning' then 100
        else 110
      end,
      updated_at = now(),
      version = version + 1
  where category_type_id = v_masalas_id
    and slug in ('powdered-spices', 'whole-spices', 'cold-grind',
                 'sugar-sweeteners', 'papad-fryums', 'blended-masalas',
                 'salt', 'cooking-pastes', 'pickles-chutneys',
                 'herbs-seasoning', 'coconut-products')
    and sort_order is distinct from case slug
      when 'powdered-spices' then 10
      when 'whole-spices' then 20
      when 'cold-grind' then 30
      when 'sugar-sweeteners' then 40
      when 'papad-fryums' then 50
      when 'blended-masalas' then 60
      when 'salt' then 70
      when 'cooking-pastes' then 80
      when 'pickles-chutneys' then 90
      when 'herbs-seasoning' then 100
      else 110
    end;

  -- These are prepared meals, not dry ready masala powders. Keep their SKU IDs
  -- and existing merchant selections while correcting the canonical leaf.
  select sub.id into strict v_ready_curries_id
  from dastak_v1.subcategories sub
  join dastak_v1.categories c on c.id = sub.category_id
  join dastak_v1.category_types t on t.id = c.category_type_id
  where t.slug = 'instant-ready-frozen-food'
    and c.slug = 'ready-to-eat'
    and sub.slug = 'curries'
    and sub.status = 'ACTIVE';

  if (select count(*) from dastak_v1.skus
      where slug in (
        'mtr-ready-to-eat-chana-masala-300-g-da35287d',
        'mtr-ready-to-eat-pav-bhaji-300-g-6be1feee'
      )) <> 2 then
    raise exception 'Expected both existing MTR ready-to-eat SKUs';
  end if;

  update dastak_v1.skus
  set subcategory_id = v_ready_curries_id,
      updated_at = now(),
      version = version + 1
  where slug in (
    'mtr-ready-to-eat-chana-masala-300-g-da35287d',
    'mtr-ready-to-eat-pav-bhaji-300-g-6be1feee'
  )
    and subcategory_id is distinct from v_ready_curries_id;
end;
$$;
