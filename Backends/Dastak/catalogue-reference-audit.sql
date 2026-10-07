-- Read-only production audit. Run with `supabase db query --linked --file`.
-- Do not treat the reference screenshots as a product import source.

-- Active SKU identity and the parent path currently used by every client.
select s.id as sku_id, s.slug as sku_slug, s.canonical_name,
       ct.slug as type_slug, c.slug as category_slug, sc.slug as subcategory_slug
from dastak_v1.skus s
join dastak_v1.subcategories sc on sc.id = s.subcategory_id
join dastak_v1.categories c on c.id = sc.category_id
join dastak_v1.category_types ct on ct.id = c.category_type_id
where s.status = 'ACTIVE'
order by ct.slug, c.slug, sc.slug, s.slug;

-- Existing product distribution. A zero-product reference rail must remain
-- empty; it must not fall back to another category's SKUs.
select ct.slug as type_slug, c.slug as category_slug,
       count(s.id) filter (where s.status = 'ACTIVE') as active_skus
from dastak_v1.categories c
join dastak_v1.category_types ct on ct.id = c.category_type_id
left join dastak_v1.subcategories sc on sc.category_id = c.id
left join dastak_v1.skus s on s.subcategory_id = sc.id
group by ct.slug, c.slug
order by ct.slug, c.slug;

-- Reference rails whose old canonical parents caused cross-department opens.
select c.slug, c.name, c.status, ct.slug as actual_parent,
       count(s.id) filter (where s.status = 'ACTIVE') as active_skus
from dastak_v1.categories c
join dastak_v1.category_types ct on ct.id = c.category_type_id
left join dastak_v1.subcategories sc on sc.category_id = c.id
left join dastak_v1.skus s on s.subcategory_id = sc.id
where c.slug in ('sugar-sweeteners', 'salt', 'papad-fryums',
                 'cooking-oils', 'ghee', 'blended-masalas',
                 'sauces-condiments', 'spreads', 'rice')
group by c.id, c.slug, c.name, c.status, ct.slug
order by c.slug;

-- Check the specific overlap that requires one browse destination to read
-- multiple canonical sources without copying SKU rows.
select count(distinct s.id) filter (where c.slug = 'spreads') as spread_skus,
       count(distinct s.id) filter (where c.slug = 'sauces-condiments') as sauce_skus,
       count(distinct s.id) as unique_sauce_and_spread_skus
from dastak_v1.skus s
join dastak_v1.subcategories sc on sc.id = s.subcategory_id
join dastak_v1.categories c on c.id = sc.category_id
where s.status = 'ACTIVE' and c.slug in ('spreads', 'sauces-condiments');

-- Cardinality and active-parent safety gates.
select count(*) as active_sku_rows, count(distinct s.id) as unique_active_sku_ids,
       count(*) filter (where ct.status <> 'ACTIVE' or c.status <> 'ACTIVE'
                        or sc.status <> 'ACTIVE') as active_skus_under_inactive_path
from dastak_v1.skus s
join dastak_v1.subcategories sc on sc.id = s.subcategory_id
join dastak_v1.categories c on c.id = sc.category_id
join dastak_v1.category_types ct on ct.id = c.category_type_id
where s.status = 'ACTIVE';
