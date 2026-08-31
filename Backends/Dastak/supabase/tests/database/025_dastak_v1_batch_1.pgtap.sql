begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_schema('dastak_v1', 'Dastak V1 domain schema exists');
select has_schema('dastak_v1_api', 'Dastak V1 command schema exists');
select has_table('dastak_v1', 'orders', 'canonical V1 orders exist');
select has_table('dastak_v1', 'domain_events_outbox', 'transactional outbox exists');
select has_table('dastak_v1', 'idempotency_records', 'idempotency records exist');
select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relkind in ('r', 'p')
      and not relation.relrowsecurity
  ),
  0::bigint,
  'every Dastak V1 table has row level security enabled'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_constraint constraint_record
    join pg_catalog.pg_namespace namespace
      on namespace.oid = constraint_record.connamespace
    where namespace.nspname = 'dastak_v1'
      and constraint_record.contype = 'f'
      and not exists (
        select 1
        from pg_catalog.pg_index index_record
        where index_record.indrelid = constraint_record.conrelid
          and index_record.indisvalid
          and index_record.indisready
          and index_record.indpred is null
          and index_record.indexprs is null
          and constraint_record.conkey <@ (index_record.indkey::smallint[])
      )
  ),
  0::bigint,
  'every Dastak V1 foreign key has a supporting index'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('dastak_v1', 'dastak_v1_api')
      and procedure.prosecdef
      and not (
        coalesce(procedure.proconfig, '{}'::text[])
          @> array['search_path=""']::text[]
      )
  ),
  0::bigint,
  'every privileged Dastak V1 function pins an empty search path'
);
select has_trigger(
  'dastak_v1',
  'order_context_snapshots',
  'order_context_snapshots_immutable',
  'delivery and recipient snapshots are immutable'
);
select has_trigger(
  'dastak_v1',
  'order_price_snapshots',
  'order_price_snapshots_immutable',
  'price snapshots are immutable'
);

select is(
  has_schema_privilege('authenticated', 'dastak_v1', 'USAGE'),
  false,
  'authenticated clients cannot address V1 tables'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.orders', 'SELECT'),
  false,
  'authenticated clients cannot select canonical orders directly'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.orders', 'INSERT'),
  false,
  'authenticated clients cannot create canonical orders directly'
);
select is(
  has_table_privilege('service_role', 'dastak_v1.orders', 'INSERT'),
  false,
  'service role must use privileged commands for writes'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_submit_order(text,bigint,jsonb)',
    'EXECUTE'
  ),
  false,
  'anonymous clients cannot submit V1 orders'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_submit_order(text,bigint,jsonb)',
    'EXECUTE'
  ),
  true,
  'authenticated customers can execute submitOrder'
);
select is(
  (
    select p.prosecdef
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where p.oid = 'public.dastak_v1_submit_order(text,bigint,jsonb)'::regprocedure
  ),
  false,
  'public submitOrder wrapper is security invoker'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '98000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'v1-customer-one@example.test', '',
  now(), now(), now()
),
(
  '98000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'v1-customer-two@example.test', '',
  now(), now(), now()
),
(
  '98000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'v1-owner@example.test', '',
  now(), now(), now()
),
(
  '98000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'v1-merchant@example.test', '',
  now(), now(), now()
);

insert into public.accounts (id, display_name, phone_number) values
  ('98000000-0000-4000-8000-000000000001', 'V1 Customer One', '+919800000001'),
  ('98000000-0000-4000-8000-000000000002', 'V1 Customer Two', '+919800000002'),
  ('98000000-0000-4000-8000-000000000003', 'V1 Owner', '+919800000003'),
  ('98000000-0000-4000-8000-000000000004', 'V1 Merchant', '+919800000004');

insert into private.account_memberships (account_id, role, approved_at) values
  ('98000000-0000-4000-8000-000000000001', 'customer', null),
  ('98000000-0000-4000-8000-000000000002', 'customer', null),
  ('98000000-0000-4000-8000-000000000003', 'owner', now()),
  ('98000000-0000-4000-8000-000000000004', 'merchant', now());

insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
) values (
  '98000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-00000000000c',
  '98000000-0000-4000-8000-000000000003',
  'Batch 1 explicit platform administration fixture.'
);

insert into dastak_v1.category_types (
  id, name, slug, status, created_by
) values (
  '98000000-0000-4000-8000-000000000009',
  'Batch One Type',
  'batch-one-type',
  'ACTIVE',
  '98000000-0000-4000-8000-000000000003'
);

insert into dastak_v1.categories (
  id, category_type_id, name, slug, status, created_by
) values (
  '98000000-0000-4000-8000-000000000010',
  '98000000-0000-4000-8000-000000000009',
  'Batch One Category',
  'batch-one-category',
  'ACTIVE',
  '98000000-0000-4000-8000-000000000003'
);

insert into dastak_v1.subcategories (
  id, category_id, name, slug, status, created_by
) values (
  '98000000-0000-4000-8000-000000000011',
  '98000000-0000-4000-8000-000000000010',
  'Batch One Subcategory',
  'batch-one-subcategory',
  'ACTIVE',
  '98000000-0000-4000-8000-000000000003'
);

insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, status,
  qa_status, qa_verified_at, qa_verified_by, created_by
) values (
  '98000000-0000-4000-8000-000000000012',
  '98000000-0000-4000-8000-000000000011',
  'Batch One Product',
  'batch-one-product',
  '1 unit',
  1000,
  900,
  'DRAFT',
  'VERIFIED',
  now(),
  '98000000-0000-4000-8000-000000000003',
  '98000000-0000-4000-8000-000000000003'
);

insert into dastak_v1.sku_images (
  id, sku_id, image_key, role, source_type, status,
  verified_by, verified_at, rights_status, rights_reference,
  rights_verified_by, rights_verified_at
) values (
  '98000000-0000-4000-8000-000000000014',
  '98000000-0000-4000-8000-000000000012',
  'test/batch-one-product-primary.webp',
  'PRIMARY', 'OTHER', 'VERIFIED',
  '98000000-0000-4000-8000-000000000003', now(),
  'CLEARED', 'PGTAP fixture',
  '98000000-0000-4000-8000-000000000003', now()
);

update dastak_v1.skus
set status = 'ACTIVE'
where id = '98000000-0000-4000-8000-000000000012';

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  '98000000-0000-4000-8000-000000000020',
  'Batch One Merchant Private Limited',
  'Batch One Merchant',
  'RETAIL',
  'ACTIVE',
  '98000000-0000-4000-8000-000000000003'
);

insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values (
  '98000000-0000-4000-8000-000000000021',
  '98000000-0000-4000-8000-000000000020',
  '98000000-0000-4000-8000-000000000004',
  'ACTIVE',
  '98000000-0000-4000-8000-000000000003'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-4000-8000-000000000001',
  true
);

create temp table tap_v1_submit on commit drop as
select public.dastak_v1_submit_order(
  'tap-submit-1',
  0,
  pg_catalog.jsonb_build_object(
    'deliveryAddress', pg_catalog.jsonb_build_object(
      'line1', '1 Batch One Road',
      'city', 'Vaniyambadi',
      'countryCode', 'IN'
    ),
    'recipient', pg_catalog.jsonb_build_object(
      'name', 'V1 Customer One',
      'phoneNumber', '+919800000001'
    ),
    'lines', pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'lineType', 'RETAIL_SKU',
        'skuId', '98000000-0000-4000-8000-000000000012',
        'quantity', 2
      )
    )
  )
) as body;

select throws_ok(
  $$
    select public.dastak_v1_submit_order(
      'tap-null-version',
      null,
      '{
        "deliveryAddress":{"line1":"1 Batch One Road","countryCode":"IN"},
        "lines":[{
          "lineType":"RETAIL_SKU",
          "skuId":"98000000-0000-4000-8000-000000000012",
          "quantity":1
        }]
      }'::jsonb
    )
  $$,
  '40001',
  'new order expectedVersion must be 0',
  'submitOrder rejects a null expected version'
);

select is(
  (
    select public.dastak_v1_submit_order(
      'tap-submit-1',
      0,
      pg_catalog.jsonb_build_object(
        'deliveryAddress', pg_catalog.jsonb_build_object(
          'line1', '1 Batch One Road',
          'city', 'Vaniyambadi',
          'countryCode', 'IN'
        ),
        'recipient', pg_catalog.jsonb_build_object(
          'name', 'V1 Customer One',
          'phoneNumber', '+919800000001'
        ),
        'lines', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'lineType', 'RETAIL_SKU',
            'skuId', '98000000-0000-4000-8000-000000000012',
            'quantity', 2
          )
        )
      )
    ) ->> 'id'
  ),
  (select body ->> 'id' from tap_v1_submit),
  'same idempotency key and payload returns the original order'
);

select throws_ok(
  $$
    select public.dastak_v1_submit_order(
      'tap-submit-1',
      0,
      '{
        "deliveryAddress":{"line1":"Changed Road","countryCode":"IN"},
        "lines":[{
          "lineType":"RETAIL_SKU",
          "skuId":"98000000-0000-4000-8000-000000000012",
          "quantity":1
        }]
      }'::jsonb
    )
  $$,
  '22023',
  'idempotency key was already used with a different request',
  'same idempotency key with a changed request is rejected'
);

select is(
  (select body #>> '{price,totalPaise}' from tap_v1_submit),
  '1800',
  'submitOrder snapshots the authoritative canonical SKU price'
);
select ok(
  not (
    (select body #> '{lines,0}' from tap_v1_submit)
      ?| array['merchantId', 'merchantBranchId', 'branchId', 'storeId']
  ),
  'retail order DTO does not expose merchant or branch identity'
);

reset role;

select is(
  (
    select count(*)
    from dastak_v1.orders
    where customer_id = '98000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'idempotent replay creates exactly one order'
);
select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox
    where event_type = 'ORDER_SUBMITTED'
      and actor_id = '98000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'idempotent replay creates exactly one submission event'
);

select throws_ok(
  $$
    update dastak_v1.order_context_snapshots
    set delivery_address = '{"line1":"rewritten"}'::jsonb
    where order_id = (
      select id from dastak_v1.orders
      where customer_id = '98000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'dastak_v1.order_context_snapshots is append-only',
  'delivery snapshot cannot be rewritten'
);
select throws_ok(
  $$
    update dastak_v1.order_lines
    set unit_price_paise = unit_price_paise + 1,
        version = version + 1
    where order_id = (
      select id from dastak_v1.orders
      where customer_id = '98000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'order line commercial snapshot cannot change',
  'order line price snapshot cannot be rewritten'
);
select throws_ok(
  $$
    update dastak_v1.order_price_snapshots
    set calculation_details = '{"rewritten":true}'::jsonb
    where order_id = (
      select id from dastak_v1.orders
      where customer_id = '98000000-0000-4000-8000-000000000001'
    )
  $$,
  'P0001',
  'dastak_v1.order_price_snapshots is append-only',
  'order price snapshot cannot be rewritten'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-4000-8000-000000000002',
  true
);
select throws_ok(
  format(
    'select public.dastak_v1_get_order(%L::uuid)',
    (select body ->> 'id' from tap_v1_submit)
  ),
  'P0002',
  'order not found',
  'a customer cannot read another customer order'
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_list_customer_orders() -> 'orders'
  ),
  0,
  'customer list contains only its own orders'
);

select set_config(
  'request.jwt.claim.sub',
  '98000000-0000-4000-8000-000000000001',
  true
);
select throws_ok(
  format(
    'select public.dastak_v1_cancel_prepayment_order(%L::uuid, %L, null)',
    (select body ->> 'id' from tap_v1_submit),
    'tap-null-cancel-version'
  ),
  '40001',
  'stale order version',
  'cancellation rejects a null expected version'
);
select is(
  public.dastak_v1_cancel_prepayment_order(
    (select (body ->> 'id')::uuid from tap_v1_submit),
    'tap-cancel-1',
    2
  ) ->> 'status',
  'CANCELLED_PREPAYMENT',
  'customer can cancel before payment'
);
select is(
  public.dastak_v1_cancel_prepayment_order(
    (select (body ->> 'id')::uuid from tap_v1_submit),
    'tap-cancel-1',
    2
  ) ->> 'status',
  'CANCELLED_PREPAYMENT',
  'prepayment cancellation replay is idempotent'
);
reset role;

select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox
    where event_type = 'ORDER_CANCELLED_PREPAYMENT'
      and actor_id = '98000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'cancellation replay creates exactly one cancellation event'
);
select ok(
  not dastak_v1.is_valid_order_transition('PAID', 'CANCELLED_PREPAYMENT'),
  'postpayment customer cancellation is structurally invalid'
);

set local role service_role;
select throws_ok(
  $$
    select dastak_v1_api.grant_merchant_permission_bundle(
      '98000000-0000-4000-8000-000000000001',
      '98000000-0000-4000-8000-000000000021',
      '10000000-0000-4000-8000-000000000002',
      null,
      'Unauthorized permission test.'
    )
  $$,
  '42501',
  'permission denied',
  'non-owner without permission cannot grant a merchant bundle'
);
select lives_ok(
  $$
    select dastak_v1_api.grant_merchant_permission_bundle(
      '98000000-0000-4000-8000-000000000003',
      '98000000-0000-4000-8000-000000000021',
      '10000000-0000-4000-8000-000000000002',
      null,
      'Batch 1 audited permission test.'
    )
  $$,
  'owner grants a server-enforced merchant permission bundle'
);
select is(
  dastak_v1_api.actor_has_merchant_permission(
    '98000000-0000-4000-8000-000000000004',
    '98000000-0000-4000-8000-000000000020',
    'merchant.branch.manage',
    null
  ),
  true,
  'an active granted merchant bundle authorizes its permission'
);
reset role;

update dastak_v1.permission_bundles
set active = false,
    version = version + 1
where id = '10000000-0000-4000-8000-000000000002';

set local role service_role;
select is(
  dastak_v1_api.actor_has_merchant_permission(
    '98000000-0000-4000-8000-000000000004',
    '98000000-0000-4000-8000-000000000020',
    'merchant.branch.manage',
    null
  ),
  false,
  'a disabled merchant bundle stops authorizing immediately'
);
reset role;

select is(
  (
    select count(*)
    from dastak_v1.merchant_permission_grant_history
    where actor_id = '98000000-0000-4000-8000-000000000003'
      and action = 'GRANTED'
  ),
  1::bigint,
  'permission grant history is recorded'
);
select is(
  (
    select count(*)
    from dastak_v1.audit_events
    where actor_id = '98000000-0000-4000-8000-000000000003'
      and action = 'MERCHANT_PERMISSION_GRANTED'
  ),
  1::bigint,
  'permission grant audit event is recorded'
);

select * from finish();
rollback;
