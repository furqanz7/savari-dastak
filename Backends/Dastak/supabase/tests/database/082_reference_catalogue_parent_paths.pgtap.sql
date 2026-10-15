begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(12);

-- Operational imports are not migration seeds. Recreate the two source SKUs
-- as rollback-only DRAFT fixtures, then exercise the exact historical correction.
update dastak_v1.category_types set status='ACTIVE',version=version+1
where slug='instant-ready-frozen-food' and status<>'ACTIVE';
update dastak_v1.categories set status='ACTIVE',version=version+1
where slug='ready-to-eat' and status<>'ACTIVE';
update dastak_v1.subcategories set status='ACTIVE',version=version+1
where slug='curries' and category_id=(select id from dastak_v1.categories where slug='ready-to-eat')
  and status<>'ACTIVE';
insert into dastak_v1.skus(id,subcategory_id,canonical_name,slug,pack_size,
  list_price_paise,selling_price_paise,status,created_by)
select x.id,sub.id,x.name,x.slug,'300 g',10000,10000,'DRAFT',sub.created_by
from dastak_v1.subcategories sub join dastak_v1.categories c on c.id=sub.category_id
cross join (values
 ('a8200000-0000-4000-8000-000000000001'::uuid,'MTR Chana Masala','mtr-ready-to-eat-chana-masala-300-g-da35287d'),
 ('a8200000-0000-4000-8000-000000000002'::uuid,'MTR Pav Bhaji','mtr-ready-to-eat-pav-bhaji-300-g-6be1feee')
) x(id,name,slug)
where c.slug='blended-masalas' and sub.id=(select min(s.id::text)::uuid from dastak_v1.subcategories s where s.category_id=c.id)
on conflict(slug) do nothing;
create temporary table mtr_identity_before as select id,slug from dastak_v1.skus
where slug in ('mtr-ready-to-eat-chana-masala-300-g-da35287d','mtr-ready-to-eat-pav-bhaji-300-g-6be1feee');
\ir ../../migrations/20260925185849_align_masalas_canonical_parents.sql
select is((select jsonb_agg(jsonb_build_object('id',id,'slug',slug) order by slug) from dastak_v1.skus
 where slug in ('mtr-ready-to-eat-chana-masala-300-g-da35287d','mtr-ready-to-eat-pav-bhaji-300-g-6be1feee')),
 (select jsonb_agg(to_jsonb(b) order by slug) from mtr_identity_before b),
 'the exact correction preserves both source SKU UUIDs and slugs');

select is((select name from dastak_v1.category_types where slug = 'staples-pantry'),
  'Atta, Flour & Dal', 'canonical Atta department has the reference name');
select is((select name from dastak_v1.category_types where slug = 'masala-cooking'),
  'Masalas', 'canonical Masalas department has the reference name');
select is((select name from dastak_v1.categories where slug = 'blended-masalas'),
  'Ready Masala', 'Ready Masala is the canonical category name');
select is((select status::text from dastak_v1.categories where slug = 'coconut-products'),
  'ACTIVE', 'empty Coconut Milk and Powder rail remains visible');
select is((select count(*)::integer from dastak_v1.categories c
  join dastak_v1.category_types t on t.id = c.category_type_id
  where c.slug in ('sugar-sweeteners', 'salt', 'papad-fryums')
    and t.slug = 'masala-cooking'), 3,
  'Sugar and Jaggery, Salt and Papad all have Masalas as their canonical parent');
select is((select count(*)::integer from dastak_v1.categories
  where (slug = 'sugar-sweeteners' and name = 'Sugar and Jaggery')
     or (slug = 'salt' and name = 'Salt')
     or (slug = 'papad-fryums' and name = 'Papad & Fryums')), 3,
  'Masalas rail labels match the canonical names even when already reparented');
select is((select count(*)::integer from dastak_v1.categories c
  join dastak_v1.category_types t on t.id = c.category_type_id
  where c.slug in ('cooking-oils', 'ghee') and t.slug = 'oils-ghee'), 2,
  'Cooking Oils and Ghee share the Oils and Ghee department');
select is((select count(*)::integer from dastak_v1.skus s
  join dastak_v1.subcategories sub on sub.id = s.subcategory_id
  join dastak_v1.categories c on c.id = sub.category_id
  where s.slug in ('mtr-ready-to-eat-chana-masala-300-g-da35287d',
                   'mtr-ready-to-eat-pav-bhaji-300-g-6be1feee')
    and c.slug = 'ready-to-eat' and sub.slug = 'curries'), 2,
  'prepared MTR meals do not appear under Ready Masala');
select is((select count(*)::integer from dastak_v1.categories
  where slug in ('sugar-sweeteners', 'salt', 'papad-fryums', 'cooking-oils', 'ghee')),
  5, 'existing category identities were preserved');
select is((select count(*)::integer from dastak_v1.skus
  where slug in ('mtr-ready-to-eat-chana-masala-300-g-da35287d',
                 'mtr-ready-to-eat-pav-bhaji-300-g-6be1feee')),
  2, 'existing prepared-meal SKU identities were preserved');
select is((select count(*)::integer from dastak_v1.subcategories
  where slug = 'high-protein-atta' and status = 'ACTIVE'),
  0, 'High Protein Atta remains removed');

select * from finish();
rollback;
