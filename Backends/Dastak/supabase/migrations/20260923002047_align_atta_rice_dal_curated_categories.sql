-- Give the Atta, Rice & Dal rail real catalogue destinations.
-- Existing SKU identities are preserved; only their subcategory bucket moves.
with actor as (
  select g.account_id
  from dastak_v1.platform_permission_grants g
  join dastak_v1.permission_bundles b on b.id = g.bundle_id
  where b.bundle_key = 'platform_super_admin' and g.revoked_at is null
  order by g.granted_at
  limit 1
), curated(category_slug, name, slug, sort_order) as (
  values
    ('atta-flours', 'High Protein Atta', 'high-protein-atta', 5),
    ('atta-flours', 'Top Deals', 'top-deals', 6),
    ('atta-flours', 'Besan, Sooji and Maida', 'besan-sooji-maida', 7),
    ('atta-flours', 'Premium Brands', 'premium-brands', 8),
    ('atta-flours', 'Other Flours', 'other-flours', 9),
    ('atta-flours', 'Ready to Cook Flour Mix', 'ready-to-cook-flour-mix', 10),
    ('rice', 'Poha & Puffed Rice', 'poha-puffed-rice', 55),
    ('dals-pulses', 'Rajma, Chola and Others', 'rajma-chola-others', 75),
    ('dals-pulses', 'Soya Chunk & Badi', 'soya-chunk-badi', 76),
    ('millets-grains', 'Millets & Daliya', 'millets-daliya', 5)
)
insert into dastak_v1.subcategories(category_id, name, slug, status, sort_order, created_by)
select c.id, x.name, x.slug, 'ACTIVE', x.sort_order, a.account_id
from curated x
join dastak_v1.categories c on c.slug = x.category_slug
join dastak_v1.category_types ct on ct.id = c.category_type_id and ct.slug = 'staples-pantry'
cross join actor a
on conflict (category_id, slug) do update
set name = excluded.name,
    sort_order = excluded.sort_order,
    updated_at = now(),
    version = dastak_v1.subcategories.version + 1;

-- Move existing flour SKUs into the matching curated destinations.
update dastak_v1.skus s
set subcategory_id = target.id,
    updated_at = now(),
    version = s.version + 1
from dastak_v1.subcategories old_sc
join dastak_v1.categories old_c on old_c.id = old_sc.category_id
join dastak_v1.category_types old_ct on old_ct.id = old_c.category_type_id
join dastak_v1.subcategories target on target.category_id = old_c.id
where s.subcategory_id = old_sc.id
  and old_ct.slug = 'staples-pantry'
  and target.slug = case
    when old_sc.slug in ('multigrain-atta') then 'high-protein-atta'
    when old_sc.slug in ('besan', 'sooji-rava', 'maida') then 'besan-sooji-maida'
    when old_sc.slug in ('rice-flour', 'ragi-flour', 'corn-flour', 'bajra-flour', 'jowar-flour', 'idiyappam-flour', 'puttu-flour') then 'other-flours'
    else null
  end;

-- Move pulse varieties into the dedicated Rajma/Chola destination.
update dastak_v1.skus s
set subcategory_id = target.id,
    updated_at = now(),
    version = s.version + 1
from dastak_v1.subcategories old_sc
join dastak_v1.categories old_c on old_c.id = old_sc.category_id
join dastak_v1.category_types old_ct on old_ct.id = old_c.category_type_id
join dastak_v1.subcategories target on target.category_id = old_c.id and target.slug = 'rajma-chola-others'
where s.subcategory_id = old_sc.id
  and old_ct.slug = 'staples-pantry'
  and old_sc.slug in ('rajma', 'kabuli-chana', 'black-chana', 'lobia');

-- Move millet SKUs into the exact curated rail destination.
update dastak_v1.skus s
set subcategory_id = target.id,
    updated_at = now(),
    version = s.version + 1
from dastak_v1.subcategories old_sc
join dastak_v1.categories old_c on old_c.id = old_sc.category_id
join dastak_v1.category_types old_ct on old_ct.id = old_c.category_type_id
join dastak_v1.subcategories target on target.category_id = old_c.id and target.slug = 'millets-daliya'
where s.subcategory_id = old_sc.id
  and old_ct.slug = 'staples-pantry'
  and old_sc.slug in ('ragi', 'kambu-pearl-millet', 'thinai-foxtail-millet', 'samai-little-millet', 'kuthiraivali-barnyard-millet', 'varagu-kodo-millet', 'quinoa', 'barley', 'broken-wheat');
