begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'dastak_v1_api', 'catalogue_navigation_section', array['text'],
  'curated catalogue navigation mapper exists'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1_api.catalogue_navigation_section(text)',
    'EXECUTE'
  ),
  false,
  'navigation mapper is not a directly callable client API'
);
select is(
  dastak_v1_api.catalogue_navigation_section('pharmacy') ->> 'name',
  'Beauty & Wellness',
  'Pharmacy is visible in the correct curated storefront section'
);
select is(
  dastak_v1_api.catalogue_navigation_section('paan-corner') ->> 'name',
  'Snacks & Drinks',
  'Paan Corner is visible in the correct curated storefront section'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.browse_catalogue_taxonomy(uuid)'::regprocedure
  ),
  'rights_status = ''CLEARED''[\s\S]*previewImageKeys[\s\S]*navigationSection',
  'shared Customer and Merchant taxonomy exposes curated sections and safe artwork previews'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.catalogue_taxonomy_snapshot(uuid)'::regprocedure
  ),
  'browse_catalogue_taxonomy[\s\S]*navigationSection[\s\S]*previewImageKeys',
  'Admin keeps the same artwork and navigation metadata while retaining the full hierarchy'
);

select * from finish();
rollback;
