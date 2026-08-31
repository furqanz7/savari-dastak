begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_column('dastak_v1', 'skus', 'barcode', 'canonical SKUs support barcodes');
select has_column(
  'dastak_v1',
  'skus',
  'logistics_attributes',
  'canonical SKUs include validated logistics attributes'
);
select has_index('dastak_v1', 'skus', 'skus_search_gin', 'canonical SKU search is indexed');
select has_table(
  'dastak_v1',
  'platform_permission_grants',
  'catalogue admin uses explicit platform permission grants'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.skus', 'SELECT'),
  false,
  'authenticated clients cannot read private canonical SKU rows'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.skus', 'UPDATE'),
  false,
  'retail merchants and customers cannot mutate canonical SKU truth'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot browse the V1 catalogue'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid)',
    'EXECUTE'
  ),
  true,
  'authenticated customers can browse the canonical catalogue'
);
select is(
  (
    select procedure.prosecdef
    from pg_catalog.pg_proc procedure
    where procedure.oid =
      'public.dastak_v1_customer_catalogue(text,uuid,uuid,integer,text,uuid)'::regprocedure
  ),
  false,
  'the public customer catalogue wrapper is a security invoker'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '97000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalogue-owner@example.test', '',
  now(), now(), now()
),
(
  '97000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalogue-customer@example.test', '',
  now(), now(), now()
),
(
  '97000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalogue-outsider@example.test', '',
  now(), now(), now()
);

insert into public.accounts (id, display_name, phone_number) values
  ('97000000-0000-4000-8000-000000000001', 'Catalogue Owner', '+919700000001'),
  ('97000000-0000-4000-8000-000000000002', 'Catalogue Customer', '+919700000002'),
  ('97000000-0000-4000-8000-000000000003', 'Catalogue Outsider', '+919700000003');

insert into private.account_memberships (account_id, role, approved_at) values
  ('97000000-0000-4000-8000-000000000001', 'owner', now()),
  ('97000000-0000-4000-8000-000000000002', 'customer', null),
  ('97000000-0000-4000-8000-000000000003', 'customer', null);

insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
) values (
  '97000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-00000000000c',
  '97000000-0000-4000-8000-000000000001',
  'Canonical catalogue explicit platform administration fixture.'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);

create temp table tap_catalogue_import on commit drop as
select public.dastak_v1_import_catalogue(
  'tap-catalogue-import-1',
  '{
    "categories":[{
      "slug":"groceries",
      "name":"Groceries",
      "status":"DRAFT",
      "sortOrder":1
    }],
    "subcategories":[{
      "categorySlug":"groceries",
      "slug":"dairy",
      "name":"Dairy",
      "status":"DRAFT",
      "sortOrder":1
    }],
    "brands":[{
      "slug":"dastak-daily",
      "name":"Dastak Daily",
      "status":"DRAFT"
    }],
    "skus":[{
      "categorySlug":"groceries",
      "subcategorySlug":"dairy",
      "brandSlug":"dastak-daily",
      "slug":"whole-milk-1-litre",
      "canonicalName":"Whole Milk",
      "variant":"Full cream",
      "packSize":"1 litre",
      "description":"Fresh full-cream milk",
      "barcode":"8901000000001",
      "listPricePaise":7200,
      "sellingPricePaise":6900,
      "currencyCode":"INR",
      "taxRateBps":0,
      "logisticsAttributes":{
        "weightGrams":1030,
        "temperatureClass":"CHILLED",
        "fragile":false,
        "bulky":false
      },
      "status":"DRAFT"
    }]
  }'::jsonb
) as body;

select is(
  (select body #>> '{counts,skus}' from tap_catalogue_import),
  '1',
  'catalogue admin atomically imports canonical SKUs'
);
select is(
  (
    select public.dastak_v1_import_catalogue(
      'tap-catalogue-import-1',
      '{
        "categories":[{"slug":"groceries","name":"Groceries","status":"DRAFT","sortOrder":1}],
        "subcategories":[{"categorySlug":"groceries","slug":"dairy","name":"Dairy","status":"DRAFT","sortOrder":1}],
        "brands":[{"slug":"dastak-daily","name":"Dastak Daily","status":"DRAFT"}],
        "skus":[{
          "categorySlug":"groceries","subcategorySlug":"dairy","brandSlug":"dastak-daily",
          "slug":"whole-milk-1-litre","canonicalName":"Whole Milk","variant":"Full cream",
          "packSize":"1 litre","description":"Fresh full-cream milk","barcode":"8901000000001",
          "listPricePaise":7200,"sellingPricePaise":6900,"currencyCode":"INR","taxRateBps":0,
          "logisticsAttributes":{"weightGrams":1030,"temperatureClass":"CHILLED","fragile":false,"bulky":false},
          "status":"DRAFT"
        }]
      }'::jsonb
    ) ->> 'importId'
  ),
  (select body ->> 'importId' from tap_catalogue_import),
  'catalogue import replay returns the original result'
);

-- Imported products enter the governed DRAFT workflow. Catalogue activation
-- requires explicit taxonomy, QA, and cleared primary-image evidence.
reset role;

insert into dastak_v1.category_types (
  id, name, slug, status, created_by
) values (
  '97000000-0000-4000-8000-000000000010',
  'Catalogue Test Type', 'catalogue-test-type', 'ACTIVE',
  '97000000-0000-4000-8000-000000000001'
);

update dastak_v1.categories
set category_type_id = '97000000-0000-4000-8000-000000000010',
    status = 'ACTIVE'
where slug = 'groceries';

update dastak_v1.subcategories
set status = 'ACTIVE'
where slug = 'dairy'
  and category_id = (
    select id from dastak_v1.categories where slug = 'groceries'
  );

update dastak_v1.brands
set status = 'ACTIVE'
where slug = 'dastak-daily';

update dastak_v1.skus
set qa_status = 'VERIFIED',
    qa_verified_at = now(),
    qa_verified_by = '97000000-0000-4000-8000-000000000001'
where slug = 'whole-milk-1-litre';

insert into dastak_v1.sku_images (
  id, sku_id, image_key, role, source_type, status,
  verified_by, verified_at, rights_status, rights_reference,
  rights_verified_by, rights_verified_at
)
select
  '97000000-0000-4000-8000-000000000011', id,
  'test/whole-milk-primary.webp', 'PRIMARY', 'OTHER', 'VERIFIED',
  '97000000-0000-4000-8000-000000000001', now(),
  'CLEARED', 'PGTAP fixture',
  '97000000-0000-4000-8000-000000000001', now()
from dastak_v1.skus
where slug = 'whole-milk-1-litre';

update dastak_v1.skus
set status = 'ACTIVE'
where slug = 'whole-milk-1-litre';

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);

create temp table tap_admin_catalogue on commit drop as
select public.dastak_v1_admin_catalogue_snapshot(1000) as body;
create temp table tap_admin_catalogue_sku on commit drop as
select sku
from tap_admin_catalogue,
  lateral pg_catalog.jsonb_array_elements(body -> 'skus') as sku
where sku ->> 'slug' = 'whole-milk-1-litre';
select is(
  (select pg_catalog.count(*) from tap_admin_catalogue_sku),
  1::bigint,
  'catalogue admin sees imported SKU activation and pricing state'
);
select ok(
  (select body ? 'configuration' from tap_admin_catalogue),
  'catalogue admin sees launch configuration readiness data'
);

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000002',
  true
);
create temp table tap_customer_catalogue on commit drop as
select public.dastak_v1_customer_catalogue(null, null, null, 100, null, null) as body;
create temp table tap_customer_catalogue_sku on commit drop as
select sku
from tap_customer_catalogue,
  lateral pg_catalog.jsonb_array_elements(body -> 'skus') as sku
where sku ->> 'slug' = 'whole-milk-1-litre';

select is(
  (
    select pg_catalog.count(*)
    from tap_customer_catalogue,
      lateral pg_catalog.jsonb_array_elements(body -> 'categories') as category
    where category ->> 'slug' = 'groceries'
  ),
  1::bigint,
  'customer sees canonical categories'
);
select is(
  (select sku ->> 'sellingPricePaise' from tap_customer_catalogue_sku),
  '6900',
  'customer sees the server-authoritative standardized selling price'
);
select ok(
  (select body::text from tap_customer_catalogue)
    !~* '(merchant|organizationName|branchId|storeId)',
  'customer catalogue projection contains no retail merchant identity'
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_customer_catalogue(
      'whole mi', null, null, 100, null, null
    ) -> 'skus'
  ),
  1,
  'indexed canonical search supports safe word-prefix matching'
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_customer_catalogue(
      'unrelated', null, null, 100, null, null
    ) -> 'skus'
  ),
  0,
  'canonical search excludes unrelated products'
);

create temp table tap_v1_catalogue_order on commit drop as
select public.dastak_v1_submit_order(
  'tap-catalogue-order-1',
  0,
  pg_catalog.jsonb_build_object(
    'deliveryAddress', pg_catalog.jsonb_build_object(
      'line1', '1 Launch Road',
      'city', 'Vaniyambadi',
      'countryCode', 'IN',
      'latitude', 12.6819,
      'longitude', 78.6201
    ),
    'recipient', pg_catalog.jsonb_build_object(
      'name', 'Catalogue Customer',
      'phoneNumber', '+919700000002'
    ),
    'lines', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'lineType', 'RETAIL_SKU',
        'skuId', (
          select (sku ->> 'id')::uuid from tap_admin_catalogue_sku
        ),
        'quantity', 2
      )
    )
  )
) as body;

select is(
  (select body #>> '{price,totalPaise}' from tap_v1_catalogue_order),
  '13800',
  'V1 order submission consumes canonical SKU identity and authoritative price'
);
select is(
  (select body ->> 'status' from tap_v1_catalogue_order),
  'MATCHING',
  'placing the order starts matching without charging the customer'
);

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);
create temp table tap_sku_update on commit drop as
select public.dastak_v1_update_catalogue_sku(
  (select (sku ->> 'id')::uuid from tap_admin_catalogue_sku),
  'tap-sku-price-1',
  1,
  '{"sellingPricePaise":6500}'::jsonb
) as body;

select is(
  (select body ->> 'version' from tap_sku_update),
  '2',
  'catalogue SKU updates use optimistic versioning'
);
select throws_ok(
  format(
    'select public.dastak_v1_update_catalogue_sku(%L::uuid, %L, 1, %L::jsonb)',
    (select (sku ->> 'id')::uuid from tap_admin_catalogue_sku),
    'tap-sku-stale',
    '{"sellingPricePaise":6400}'
  ),
  '40001',
  'stale SKU version',
  'stale catalogue writes are rejected'
);

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000002',
  true
);
select is(
  public.dastak_v1_get_order(
    (select (body ->> 'id')::uuid from tap_v1_catalogue_order)
  ) #>> '{price,totalPaise}',
  '13800',
  'catalogue price changes never rewrite historical order price snapshots'
);

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000001',
  true
);
select lives_ok(
  format(
    'select public.dastak_v1_update_catalogue_sku(%L::uuid, %L, 2, %L::jsonb)',
    (select (sku ->> 'id')::uuid from tap_admin_catalogue_sku),
    'tap-sku-inactive',
    '{"status":"INACTIVE"}'
  ),
  'catalogue admin can deactivate an SKU without deleting product history'
);

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000002',
  true
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.jsonb_array_elements(
      public.dastak_v1_customer_catalogue(null, null, null, 100, null, null) -> 'skus'
    ) as sku
    where sku ->> 'slug' = 'whole-milk-1-litre'
  ),
  0::bigint,
  'inactive SKUs disappear from customer projections'
);

select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000003',
  true
);
select throws_ok(
  $$
    select public.dastak_v1_import_catalogue(
      'tap-unauthorized-import',
      '{"categories":[]}'::jsonb
    )
  $$,
  '42501',
  'platform permission required',
  'ordinary customers cannot manage the canonical catalogue'
);

reset role;

select is(
  (
    select count(*)
    from dastak_v1.audit_events
    where action in ('CATALOGUE_IMPORTED', 'CATALOGUE_SKU_UPDATED')
      and actor_id = '97000000-0000-4000-8000-000000000001'
  ),
  3::bigint,
  'every catalogue write is attributed in the audit trail'
);
select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox
    where event_type = 'CATALOGUE_IMPORTED'
      and actor_id = '97000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'idempotent import creates one transactional catalogue event'
);
select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox
    where event_type = 'CATALOGUE_SKU_UPDATED'
      and actor_id = '97000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'each successful catalogue SKU update creates one transactional event'
);

select * from finish();
rollback;
