begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid)',
    'EXECUTE'
  ),
  true,
  'authenticated customers retain the safe canonical catalogue wrapper'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid)',
    'EXECUTE'
  ),
  false,
  'anonymous users cannot read the canonical customer catalogue'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.customer_catalogue(uuid,text,uuid,uuid,integer,text,uuid)'::regprocedure
  ),
  'previewImageKeys',
  'customer taxonomy includes safe image-rich previews'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.customer_catalogue(uuid,text,uuid,uuid,integer,text,uuid)'::regprocedure
  ),
  'sku_search_aliases[\s\S]*sku_identifiers',
  'customer search includes aliases and identifiers'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.customer_catalogue(uuid,text,uuid,uuid,integer,text,uuid)'::regprocedure
  ),
  'categoryTypes',
  'customer projection includes the department hierarchy'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer)'::regprocedure
  ),
  'merchant\.catalogue\.selection\.manage[\s\S]*galleryImageKeys[\s\S]*quantityValue[\s\S]*searchTerms',
  'Merchant catalogue stays permission-bound and exposes safe selection details'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.update_catalogue_sku(uuid,uuid,text,bigint,jsonb)'::regprocedure
  ),
  'platform\.catalogue\.manage[\s\S]*quantityValue[\s\S]*packCount[\s\S]*CATALOGUE_SKU_UPDATED',
  'Admin SKU quantity mutation remains permission-bound, versioned and audited'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.skus', 'UPDATE'),
  false,
  'clients cannot bypass the audited Admin SKU mutation'
);

select * from finish();
rollback;
