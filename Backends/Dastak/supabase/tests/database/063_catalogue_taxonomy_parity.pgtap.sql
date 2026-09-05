begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_function(
  'dastak_v1_api', 'browse_catalogue_taxonomy', array['uuid'],
  'shared browse taxonomy projection exists'
);
select is(
  has_function_privilege(
    'anon', 'dastak_v1_api.browse_catalogue_taxonomy(uuid)', 'EXECUTE'
  ),
  false,
  'anonymous callers cannot read canonical taxonomy'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.browse_catalogue_taxonomy(uuid)'::regprocedure
  ),
  'status <> ''INACTIVE''[\s\S]*requiresControlledFlow',
  'browse taxonomy includes every non-inactive node and marks controlled sections'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid)'::regprocedure
  ),
  'browse_catalogue_taxonomy',
  'Customer receives the shared complete hierarchy'
);
select matches(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer)'::regprocedure
  ),
  '5000[\s\S]*browse_catalogue_taxonomy',
  'Merchant can receive the complete active SKU library and shared hierarchy'
);

select is(
  (select status::text from dastak_v1.category_types where slug = 'pharmacy'),
  'DRAFT',
  'Pharmacy exists as a safely unpublished department'
);
select is(
  (select status::text from dastak_v1.categories where slug = 'medicines'),
  'DRAFT',
  'Medicines exists as a safely unpublished category'
);
select is(
  (select status::text from dastak_v1.category_types where slug = 'paan-corner'),
  'DRAFT',
  'Paan Corner exists as a safely unpublished department'
);
select is(
  (
    select pg_catalog.count(*)
    from dastak_v1.subcategories subcategory
    join dastak_v1.categories category on category.id = subcategory.category_id
    join dastak_v1.category_types category_type on category_type.id = category.category_type_id
    where category_type.slug in ('pharmacy', 'paan-corner')
  ),
  14::bigint,
  'controlled departments have their complete initial subcategory hierarchy'
);
select is(
  (
    select pg_catalog.count(*)
    from dastak_v1.skus sku
    join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
    join dastak_v1.categories category on category.id = subcategory.category_id
    join dastak_v1.category_types category_type on category_type.id = category.category_type_id
    where category_type.slug in ('pharmacy', 'paan-corner')
  ),
  0::bigint,
  'controlled shells do not leak ordinary retail SKUs into checkout'
);

select * from finish();
rollback;
