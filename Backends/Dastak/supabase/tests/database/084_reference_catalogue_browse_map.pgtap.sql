begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(25);

select is((select state from dastak_v1.catalogue_browse_versions where version = 1),
  'ACTIVE', 'reconciled reference browse map is the active release');
select is((select count(*)::integer from dastak_v1.catalogue_browse_nodes
  where version = 1 and kind = 'SECTION'), 5, 'five reference home sections');
select is((select count(*)::integer from dastak_v1.catalogue_browse_nodes
  where version = 1 and kind = 'DESTINATION'), 36, 'all reference home destinations');
select is((select count(*)::integer from dastak_v1.catalogue_browse_nodes
  where version = 1 and kind = 'RAIL'), 71, 'confirmed reference rails are explicit');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'dairy-alternatives'
    and type_slug = 'dairy-bread-eggs' and category_slug = 'dairy-alternatives'),
  1, 'Dairy Alternatives has its exact canonical source path');
select is((select count(*)::integer from dastak_v1.catalogue_browse_nodes
  where version = 1 and label = 'High Protein Atta'), 0,
  'removed High Protein Atta is not browsable');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'sauces-spreads'), 3,
  'Sauces and Spreads includes spreads, condiments, and honey');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'rice'
    and excluded_subcategory_slugs @> array['basmati-rice','poha-puffed-rice']), 1,
  'broad Rice excludes dedicated Basmati and Poha shelves');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'atta'
    and excluded_subcategory_slugs @> array['besan-sooji-maida','premium-brands','other-flours','ready-to-cook-flour-mix']), 1,
  'broad Atta excludes dedicated flour shelves');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'ready-masala'
    and type_slug = 'masala-cooking' and category_slug = 'blended-masalas'), 1,
  'Ready Masala cannot resolve to prepared meals');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key in ('fashion','sports-fitness','sexual-wellness')), 0,
  'unstocked destinations never borrow an unrelated SKU source');
select is((select count(*)::integer from dastak_v1.catalogue_browse_nodes
  where version = 1 and parent_key = 'grocery-kitchen'
    and label in ('Atta, Flour & Dal','Masalas','Oils and Ghee','Cereals and Breakfast')),
  4, 'grocery labels match the user''s final naming');
select is((select count(*)::integer from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'dastak_v1_api' and p.proname = 'catalogue_browse_sku_ids'
    and p.pronargs = 3), 0,
  'authenticated callers cannot select a draft browse version');
select is((select count(*)::integer from dastak_v1.catalogue_browse_versions
  where state = 'ACTIVE'), 1,
  'exactly one reference browse version is active after reconciliation');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'atta-flour-dal'
    and type_slug = 'staples-pantry' and category_slug is null
    and excluded_category_slugs @> array['dry-fruits-nuts','seeds']), 1,
  'staples does not borrow Dry Fruits and Seeds Mix products');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'masalas'
    and excluded_category_slugs @> array['sauces-condiments']), 1,
  'Masalas does not duplicate Sauces and Spreads');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'cereals-breakfast'
    and type_slug = 'breakfast-spreads' and category_slug is null
    and excluded_category_slugs @> array['spreads','pancake-baking-mixes']), 1,
  'Breakfast does not duplicate Sauces or Dessert Mixes');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'noodles-pasta-vermicelli'
    and category_slug in ('ready-to-eat','soups')), 2,
  'Noodles destination includes its reference Ready to eat and Soups rails');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key in ('ready-to-eat','soups')), 2,
  'Ready to eat and Soups each resolve to their own canonical category');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'ready-cook-flour-mix'
    and category_slug = 'ready-to-cook'
    and subcategory_slug in ('adhirasam-mix','bajji-bonda-mix','murukku-mix')), 3,
  'flour-based ready-to-cook products have the reference flour mix rail');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'atta-flour-dal'
    and category_slug = 'ready-to-cook'
    and subcategory_slug = 'pani-puri-kit'), 0,
  'pani-puri kits are not misclassified as flour');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'rice'
    and type_slug = 'instant-ready-frozen-food'
    and category_slug = 'ready-to-cook' and subcategory_slug = 'biryani-kits'), 1,
  'biryani kits appear in Rice as requested');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'basmati-rice'
    and category_slug = 'ready-to-cook' and subcategory_slug = 'biryani-kits'), 0,
  'biryani kits do not duplicate into Basmati Rice');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'instant-noodles'
    and type_slug = 'instant-ready-frozen-food'
    and category_slug = 'noodles' and subcategory_slug = 'shirataki-noodles'), 1,
  'approved Shirataki Noodles placement uses Instant Noodles');
select is((select count(*)::integer from dastak_v1.catalogue_browse_sources
  where version = 1 and node_key = 'chips-nuts'
    and type_slug = 'snacks-munchies'
    and category_slug = 'nuts-trail-mixes' and subcategory_slug = 'flavoured-nuts'), 1,
  'approved flavoured-nut placement uses the Chips and Namkeens Nuts rail');

select * from finish();
rollback;
