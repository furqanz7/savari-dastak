begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table('private', 'merchant_stores', 'private.merchant_stores exists');
select has_table('private', 'catalogue_categories', 'private.catalogue_categories exists');
select has_table('private', 'catalogue_products', 'private.catalogue_products exists');
select has_column('private', 'merchant_stores', 'location', 'stores retain a server-checked point');
select has_column('private', 'catalogue_products', 'price_paise', 'products use integer paise');
select has_column(
  'private',
  'catalogue_products',
  'restricted_approval_state',
  'controlled products have an approval state'
);

select has_function(
  'public',
  'upsert_merchant_store',
  array[
    'uuid', 'text', 'text', 'double precision', 'double precision',
    'boolean', 'boolean', 'text', 'text'
  ]
);
select has_function(
  'public',
  'upsert_catalogue_category',
  array['uuid', 'uuid', 'text', 'integer', 'boolean', 'text', 'text']
);
select has_function(
  'public',
  'upsert_catalogue_product',
  array[
    'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'integer',
    'text', 'text', 'text', 'boolean', 'text', 'text'
  ]
);
select has_function('public', 'get_merchant_catalogue', array['uuid']);
select has_function(
  'public',
  'browse_catalogue',
  array['uuid', 'double precision', 'double precision']
);

select is(
  has_table_privilege('authenticated', 'private.merchant_stores', 'SELECT'),
  false,
  'authenticated cannot read private stores directly'
);
select is(
  has_table_privilege('authenticated', 'private.catalogue_categories', 'SELECT'),
  false,
  'authenticated cannot read private categories directly'
);
select is(
  has_table_privilege('authenticated', 'private.catalogue_products', 'SELECT'),
  false,
  'authenticated cannot read private products directly'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.upsert_merchant_store(uuid,text,text,double precision,double precision,boolean,boolean,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass the store Edge Function'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.upsert_catalogue_category(uuid,uuid,text,integer,boolean,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass the category Edge Function'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.upsert_catalogue_product(uuid,uuid,uuid,text,text,text,integer,text,text,text,boolean,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass the product Edge Function'
);
select is(
  has_function_privilege('authenticated', 'public.get_merchant_catalogue(uuid)', 'EXECUTE'),
  false,
  'authenticated cannot bypass the merchant snapshot Edge Function'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.browse_catalogue(uuid,double precision,double precision)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass the customer catalogue Edge Function'
);

select is(
  has_function_privilege(
    'service_role',
    'public.upsert_merchant_store(uuid,text,text,double precision,double precision,boolean,boolean,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can upsert a verified merchant store'
);
select is(
  has_function_privilege(
    'service_role',
    'public.upsert_catalogue_category(uuid,uuid,text,integer,boolean,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can upsert a verified merchant category'
);
select is(
  has_function_privilege(
    'service_role',
    'public.upsert_catalogue_product(uuid,uuid,uuid,text,text,text,integer,text,text,text,boolean,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can upsert a verified merchant product'
);
select is(
  has_function_privilege('service_role', 'public.get_merchant_catalogue(uuid)', 'EXECUTE'),
  true,
  'service role can retrieve an authorized merchant snapshot'
);
select is(
  has_function_privilege(
    'service_role',
    'public.browse_catalogue(uuid,double precision,double precision)',
    'EXECUTE'
  ),
  true,
  'service role can retrieve an authorized customer snapshot'
);

select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_catalogue_image_insert_own'
  ),
  true,
  'catalogue images have a self-owned insert policy'
);
select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_catalogue_image_select_own'
  ),
  true,
  'catalogue images have a self-owned select policy'
);
select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_catalogue_image_update_own'
  ),
  true,
  'catalogue images have a self-owned update policy'
);
select is(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'dastak_catalogue_image_delete_own'
  ),
  false,
  'catalogue images cannot be deleted while products may reference them'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '11111111-1111-4111-8111-111111111115',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalogue-merchant-a@example.test', '',
  now(), now(), now()
),
(
  '22222222-2222-4222-8222-222222222225',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalogue-merchant-b@example.test', '',
  now(), now(), now()
),
(
  '33333333-3333-4333-8333-333333333335',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalogue-customer@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number)
values
  ('11111111-1111-4111-8111-111111111115', 'Catalogue Merchant A', '+14155552701'),
  ('22222222-2222-4222-8222-222222222225', 'Catalogue Merchant B', '+14155552702'),
  ('33333333-3333-4333-8333-333333333335', 'Catalogue Customer', '+14155552703');

insert into private.account_memberships (account_id, role, approved_at)
values
  ('11111111-1111-4111-8111-111111111115', 'customer', null),
  ('11111111-1111-4111-8111-111111111115', 'merchant', now()),
  ('22222222-2222-4222-8222-222222222225', 'customer', null),
  ('22222222-2222-4222-8222-222222222225', 'merchant', now()),
  ('33333333-3333-4333-8333-333333333335', 'customer', null);

insert into public.service_zones (id, name, boundary, active)
values (
  '44444444-4444-4444-8444-444444444445',
  'tap catalogue Vaniyambadi',
  extensions.st_geomfromtext(
    'POLYGON((78.50 12.50, 78.80 12.50, 78.80 12.80, 78.50 12.80, 78.50 12.50))',
    4326
  ),
  true
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111115',
  true
);

select lives_ok(
  $$insert into storage.objects (bucket_id, name) values (
    'dastak-catalogue',
    'merchant/11111111-1111-4111-8111-111111111115/product.jpg'
  )$$,
  'merchant uploads an image only under its own catalogue path'
);
select throws_like(
  $$insert into storage.objects (bucket_id, name) values (
    'dastak-catalogue',
    'merchant/22222222-2222-4222-8222-222222222225/foreign.jpg'
  )$$,
  '%row-level security%',
  'merchant cannot upload under another merchant path'
);
select results_eq(
  $$update storage.objects
    set metadata = '{"contentType":"image/jpeg"}'::jsonb
    where name = 'merchant/11111111-1111-4111-8111-111111111115/product.jpg'
    returning name$$,
  array['merchant/11111111-1111-4111-8111-111111111115/product.jpg']::text[],
  'merchant can replace its own catalogue image'
);
select throws_matching(
  $$delete from storage.objects
    where name = 'merchant/11111111-1111-4111-8111-111111111115/product.jpg'$$,
  '(permission denied|row-level security|Direct deletion from storage tables is not allowed)',
  'merchant cannot directly delete a referenced catalogue image'
);

reset role;
set local role service_role;

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_merchant_store(
      '33333333-3333-4333-8333-333333333335',
      'Not A Merchant', '12 Main Road', 12.6819, 78.6201,
      false, false, 'nonmerchant-store-key', 'nonmerchant-store-digest'
    )
  ),
  'access_denied',
  'customer cannot create a merchant store'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_merchant_store(
      '11111111-1111-4111-8111-111111111115',
      'Corner Store', '12 Main Road', 13.5000, 79.5000,
      false, false, 'outside-store-key', 'outside-store-digest'
    )
  ),
  'outside_service_area',
  'store location must be inside an active service zone'
);

select is(
  (
    select response_body ->> 'name'
    from public.upsert_merchant_store(
      '11111111-1111-4111-8111-111111111115',
      'Corner Store', '12 Main Road', 12.6819, 78.6201,
      true, true, 'store-key', 'store-digest'
    )
  ),
  'Corner Store',
  'approved merchant creates a published store in its service zone'
);

select is(
  (
    select response_body ->> 'storeId'
    from public.upsert_merchant_store(
      '11111111-1111-4111-8111-111111111115',
      'Corner Store', '12 Main Road', 12.6819, 78.6201,
      true, true, 'store-key', 'store-digest'
    )
  ),
  (
    select id::text from private.merchant_stores
    where merchant_account_id = '11111111-1111-4111-8111-111111111115'
  ),
  'identical store request replays the original response'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_merchant_store(
      '11111111-1111-4111-8111-111111111115',
      'Changed Store', '12 Main Road', 12.6819, 78.6201,
      true, true, 'store-key', 'changed-store-digest'
    )
  ),
  'idempotency_conflict',
  'store request cannot reuse an idempotency key with changed input'
);

select lives_ok(
  $$select * from public.upsert_merchant_store(
    '22222222-2222-4222-8222-222222222225',
    'Second Store', '14 Main Road', 12.6900, 78.6300,
    true, true, 'store-b-key', 'store-b-digest'
  )$$,
  'second approved merchant creates its own store'
);

select is(
  (
    select response_body ->> 'name'
    from public.upsert_catalogue_category(
      '11111111-1111-4111-8111-111111111115',
      null, 'Snacks and Drinks', 4, true,
      'category-key', 'category-digest'
    )
  ),
  'Snacks and Drinks',
  'merchant creates a category in its own store'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_catalogue_category(
      '22222222-2222-4222-8222-222222222225',
      (
        select category.id
        from private.catalogue_categories category
        join private.merchant_stores store on store.id = category.store_id
        where store.merchant_account_id = '11111111-1111-4111-8111-111111111115'
      ),
      'Hijacked Category', 1, true,
      'cross-category-key', 'cross-category-digest'
    )
  ),
  'catalogue_category_not_found',
  'merchant cannot update another store category'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_catalogue_product(
      '11111111-1111-4111-8111-111111111115',
      null,
      (select id from private.catalogue_categories where name = 'Snacks and Drinks'),
      'Missing Image Product', null, '1 pc', 1000,
      'merchant/11111111-1111-4111-8111-111111111115/missing.jpg',
      'in_stock', 'general', true,
      'missing-image-key', 'missing-image-digest'
    )
  ),
  'catalogue_image_not_found',
  'product image must already exist in the public catalogue bucket'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.upsert_catalogue_product(
      '11111111-1111-4111-8111-111111111115',
      null,
      (select id from private.catalogue_categories where name = 'Snacks and Drinks'),
      'Foreign Image Product', null, '1 pc', 1000,
      'merchant/22222222-2222-4222-8222-222222222225/foreign.jpg',
      'in_stock', 'general', true,
      'foreign-image-key', 'foreign-image-digest'
    )
  ),
  'validation_failed',
  'product cannot reference another merchant image path'
);

select is(
  (
    select (response_body #>> '{price,paise}')::integer
    from public.upsert_catalogue_product(
      '11111111-1111-4111-8111-111111111115',
      null,
      (select id from private.catalogue_categories where name = 'Snacks and Drinks'),
      'Lime Soda', 'Freshly bottled', '750 ml', 12500,
      'merchant/11111111-1111-4111-8111-111111111115/product.jpg',
      'in_stock', 'general', true,
      'product-key', 'product-digest'
    )
  ),
  12500,
  'merchant product keeps an integer-paise server value'
);

select is(
  (
    select (response_body #>> '{price,paise}')::integer
    from public.upsert_catalogue_product(
      '11111111-1111-4111-8111-111111111115',
      (select id from private.catalogue_products where name = 'Lime Soda'),
      (select id from private.catalogue_categories where name = 'Snacks and Drinks'),
      'Lime Soda', 'Freshly bottled', '750 ml', 13000,
      'merchant/11111111-1111-4111-8111-111111111115/product.jpg',
      'in_stock', 'general', true,
      'product-update-key', 'product-update-digest'
    )
  ),
  13000,
  'merchant can update its own product price'
);

select is(
  (
    select response_body ->> 'restrictedApprovalState'
    from public.upsert_catalogue_product(
      '11111111-1111-4111-8111-111111111115',
      null,
      (select id from private.catalogue_categories where name = 'Snacks and Drinks'),
      'Restricted Tobacco', null, '20 pcs', 40000,
      null, 'in_stock', 'paan_corner', true,
      'restricted-product-key', 'restricted-product-digest'
    )
  ),
  'pending',
  'controlled product is server-marked pending rather than self-approved'
);

select is(
  (
    select pg_catalog.jsonb_array_length(response_body -> 'products')
    from public.get_merchant_catalogue(
      '11111111-1111-4111-8111-111111111115'
    )
  ),
  2,
  'merchant snapshot includes ordinary and controlled products owned by the merchant'
);

select is(
  (
    select response_body ->> 'serviceZoneId'
    from public.browse_catalogue(
      '33333333-3333-4333-8333-333333333335',
      12.6819,
      78.6201
    )
  ),
  '44444444-4444-4444-8444-444444444445',
  'customer browse resolves the service zone on the server'
);

select is(
  (
    select pg_catalog.jsonb_array_length(response_body -> 'products')
    from public.browse_catalogue(
      '33333333-3333-4333-8333-333333333335',
      12.6819,
      78.6201
    )
  ),
  1,
  'ordinary browse excludes controlled products'
);

select is(
  (
    select (response_body #>> '{products,0,price,paise}')::integer
    from public.browse_catalogue(
      '33333333-3333-4333-8333-333333333335',
      12.6819,
      78.6201
    )
  ),
  13000,
  'customer receives the current server product price'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.browse_catalogue(
      '33333333-3333-4333-8333-333333333335',
      13.5000,
      79.5000
    )
  ),
  'outside_service_area',
  'customer cannot browse outside an active service zone'
);

update private.account_memberships
set suspended_until = now() + interval '1 hour'
where account_id = '11111111-1111-4111-8111-111111111115'
  and role = 'merchant';

select is(
  (
    select pg_catalog.jsonb_array_length(response_body -> 'stores')
    from public.browse_catalogue(
      '33333333-3333-4333-8333-333333333335',
      12.6819,
      78.6201
    )
  ),
  1,
  'customer browse hides a suspended merchant while retaining other active stores'
);

select is(
  (
    select response_body #>> '{error,code}'
    from public.get_merchant_catalogue(
      '11111111-1111-4111-8111-111111111115'
    )
  ),
  'access_denied',
  'suspended merchant cannot manage its catalogue'
);

reset role;

select is(
  (
    select count(*)::integer from audit.events
    where action = 'merchant_store_upserted'
      and actor_id = '11111111-1111-4111-8111-111111111115'
  ),
  1,
  'store mutation is audited once despite idempotent replay'
);
select is(
  (
    select count(*)::integer from audit.events
    where action = 'catalogue_category_upserted'
      and actor_id = '11111111-1111-4111-8111-111111111115'
  ),
  1,
  'category mutation is audited'
);
select is(
  (
    select count(*)::integer from audit.events
    where action = 'catalogue_product_upserted'
      and actor_id = '11111111-1111-4111-8111-111111111115'
  ),
  3,
  'each successful product mutation is audited'
);

select * from finish();
rollback;
