begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_column('public', 'accounts', 'account_state', 'accounts expose a history-safe lifecycle state');
select has_table('private', 'customer_auth_identities', 'OAuth identity links are registered privately');
select has_table('private', 'customer_identity_link_intents', 'explicit identity-link intent exists');
select has_table('private', 'customer_account_deletions', 'account deletion is recoverable and audited');
select is(
  has_function_privilege('anon', 'public.dastak_before_user_created(jsonb)', 'EXECUTE'),
  false,
  'anonymous callers cannot invoke the Auth creation hook'
);
select is(
  has_function_privilege('supabase_auth_admin', 'public.dastak_custom_access_token(jsonb)', 'EXECUTE'),
  true,
  'only Supabase Auth can invoke the token hook'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.merchant_sku_selections', 'UPDATE'),
  false,
  'merchant clients cannot mutate canonical selections as table DML'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_update_merchant_sku_selections(uuid,jsonb,text)',
    'EXECUTE'
  ),
  true,
  'authenticated merchants can atomically save staged canonical selections'
);
select is(
  has_function_privilege(
    'anon',
    'public.dastak_v1_update_merchant_sku_selections(uuid,jsonb,text)',
    'EXECUTE'
  ),
  false,
  'anonymous callers cannot save merchant catalogue selections'
);

select is(
  public.dastak_before_user_created(
    '{"user":{"app_metadata":{"provider":"apple"},"is_anonymous":false}}'::jsonb
  ),
  '{}'::jsonb,
  'Apple OAuth account creation is allowed'
);
select is(
  public.dastak_before_user_created(
    '{"user":{"app_metadata":{"provider":"google"},"is_anonymous":false}}'::jsonb
  ),
  '{}'::jsonb,
  'Google OAuth account creation is allowed'
);
select is(
  public.dastak_before_user_created(
    '{"user":{"app_metadata":{"provider":"email"},"is_anonymous":false}}'::jsonb
  ) #>> '{error,http_code}',
  '403',
  'email/password and email OTP account creation are rejected'
);
select is(
  public.dastak_before_user_created(
    '{"user":{"app_metadata":{"provider":"phone"},"is_anonymous":false}}'::jsonb
  ) #>> '{error,http_code}',
  '403',
  'phone OTP account creation is rejected'
);
select is(
  public.dastak_before_user_created(
    '{"user":{"app_metadata":{"provider":"apple"},"is_anonymous":true}}'::jsonb
  ) #>> '{error,http_code}',
  '403',
  'anonymous account creation is rejected'
);
select throws_ok(
  $$select public.dastak_custom_access_token('{"user_id":"a5000000-0000-4000-8000-000000000001","authentication_method":"password","claims":{}}'::jsonb)$$,
  '28000',
  'Dastak sessions require Apple or Google OAuth.',
  'password token issuance is rejected'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('a5000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'identity-owner@example.test', '', now(), now(), now()),
  ('a5000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'identity-unlinked@example.test', '', now(), now(), now()),
  ('a5000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'merchant-control@example.test', '', now(), now(), now()),
  ('a5000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'merchant-outsider@example.test', '', now(), now(), now());

insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, created_at, updated_at
) values
  ('a5100000-0000-4000-8000-000000000001', 'apple-subject-owner', 'a5000000-0000-4000-8000-000000000001', '{"email":"identity-owner@example.test"}', 'apple', now(), now()),
  ('a5100000-0000-4000-8000-000000000002', 'apple-subject-unlinked', 'a5000000-0000-4000-8000-000000000002', '{"email":"identity-unlinked@example.test"}', 'apple', now(), now());

insert into public.accounts (id, display_name, phone_number) values
  ('a5000000-0000-4000-8000-000000000001', 'Identity Owner', '+919500000001'),
  ('a5000000-0000-4000-8000-000000000002', 'Identity Unlinked', '+919500000002'),
  ('a5000000-0000-4000-8000-000000000003', 'Merchant Control', '+919500000003'),
  ('a5000000-0000-4000-8000-000000000004', 'Merchant Outsider', '+919500000004');

insert into private.account_memberships (account_id, role) values
  ('a5000000-0000-4000-8000-000000000001', 'customer'),
  ('a5000000-0000-4000-8000-000000000002', 'customer'),
  ('a5000000-0000-4000-8000-000000000003', 'customer'),
  ('a5000000-0000-4000-8000-000000000004', 'customer');

select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"a5000000-0000-4000-8000-000000000001","authentication_method":"oauth","claims":{"app_metadata":{"provider":"apple"}}}'::jsonb)$$,
  'first Apple OAuth session registers its origin identity'
);
select is(
  (select count(*) from private.customer_auth_identities where account_id = 'a5000000-0000-4000-8000-000000000001' and link_kind = 'ORIGIN'),
  1::bigint,
  'origin registration never uses email or phone matching'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-4000-8000-000000000001', true);
select is(
  public.dastak_begin_customer_identity_link('google', 'link-google-1') ->> 'provider',
  'google',
  'signed-in customer explicitly starts second-provider linking'
);
reset role;

insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, created_at, updated_at
) values (
  'a5100000-0000-4000-8000-000000000003', 'google-subject-owner',
  'a5000000-0000-4000-8000-000000000001',
  '{"email":"different-google@example.test"}', 'google', now(), now()
);

select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"a5000000-0000-4000-8000-000000000001","authentication_method":"oauth","claims":{"app_metadata":{"provider":"google"}}}'::jsonb)$$,
  'second identity is accepted only with its explicit intent'
);
select is(
  (select count(*) from private.customer_auth_identities where account_id = 'a5000000-0000-4000-8000-000000000001' and revoked_at is null),
  2::bigint,
  'explicitly linked Apple and Google identities restore one account'
);
select is(
  (select status::text from private.customer_identity_link_intents where account_id = 'a5000000-0000-4000-8000-000000000001' and target_provider = 'google'),
  'COMPLETED',
  'successful proof consumes the linking intent'
);

select lives_ok(
  $$select public.dastak_custom_access_token('{"user_id":"a5000000-0000-4000-8000-000000000002","authentication_method":"oauth","claims":{"app_metadata":{"provider":"apple"}}}'::jsonb)$$,
  'a separate OAuth identity remains a separate account'
);
reset role;

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, paid_at, delivered_at
) values
  ('a5200000-0000-4000-8000-000000000001', 'DASTAK-DELETE-ACTIVE', 'a5000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'PREPARING', now() - interval '1 hour', now() - interval '50 minutes', null),
  ('a5200000-0000-4000-8000-000000000002', 'DASTAK-DELETE-DONE', 'a5000000-0000-4000-8000-000000000001', 'RETAIL_ONLY', 'DELIVERED', now() - interval '2 days', now() - interval '2 days' + interval '10 minutes', now() - interval '1 day');

set local role service_role;
select is(
  public.prepare_customer_account_deletion('a5000000-0000-4000-8000-000000000001', 'delete-history-safe-1') ->> 'prepared',
  'true',
  'deletion first blocks access and anonymises permitted PII'
);
select is(
  (select account_state::text from public.accounts where id = 'a5000000-0000-4000-8000-000000000001'),
  'DELETION_PENDING',
  'deletion enters fail-closed pending state before Auth deletion'
);
select is(
  (select count(*) from dastak_v1.orders where customer_id = 'a5000000-0000-4000-8000-000000000001'),
  2::bigint,
  'active and completed V1 order history survives anonymisation'
);

reset role;
delete from auth.users where id = 'a5000000-0000-4000-8000-000000000001';
set local role service_role;
select is(
  public.finalize_customer_account_deletion('a5000000-0000-4000-8000-000000000001') ->> 'deleted',
  'true',
  'credential deletion finalises the retained account tombstone'
);
reset role;
select is(
  (select account_state::text from public.accounts where id = 'a5000000-0000-4000-8000-000000000001'),
  'DELETED',
  'historical account row remains as an anonymised tombstone'
);
select is(
  (select count(*) from dastak_v1.orders where customer_id = 'a5000000-0000-4000-8000-000000000001'),
  2::bigint,
  'Auth deletion cannot cascade active or completed V1 orders'
);

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  'a5300000-0000-4000-8000-000000000001', 'Control Retail Private Limited',
  'Control Retail', 'RETAIL', 'ACTIVE', 'a5000000-0000-4000-8000-000000000003'
);
insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, capacity_limit, status, created_by
) values (
  'a5400000-0000-4000-8000-000000000001', 'a5300000-0000-4000-8000-000000000001',
  'Control Branch', 5, 'ACTIVE', 'a5000000-0000-4000-8000-000000000003'
);
insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values (
  'a5500000-0000-4000-8000-000000000001', 'a5300000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000003', 'ACTIVE', 'a5000000-0000-4000-8000-000000000003'
);
insert into dastak_v1.merchant_permission_grants (
  merchant_user_id, organization_id, bundle_id, branch_id, granted_by, grant_reason
) values (
  'a5500000-0000-4000-8000-000000000001', 'a5300000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002', 'a5400000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000003', 'Merchant canonical control test fixture.'
);
insert into dastak_v1.category_types (id, name, slug, status, created_by)
values ('a5f00000-0000-4000-8000-000000000001', 'Control Retail', 'control-retail', 'ACTIVE', 'a5000000-0000-4000-8000-000000000003');
insert into dastak_v1.categories (id, category_type_id, name, slug, status, created_by)
values ('a5600000-0000-4000-8000-000000000001', 'a5f00000-0000-4000-8000-000000000001', 'Groceries', 'control-groceries', 'ACTIVE', 'a5000000-0000-4000-8000-000000000003');
insert into dastak_v1.subcategories (id, category_id, name, slug, status, created_by)
values ('a5700000-0000-4000-8000-000000000001', 'a5600000-0000-4000-8000-000000000001', 'Daily', 'control-daily', 'ACTIVE', 'a5000000-0000-4000-8000-000000000003');
insert into dastak_v1.skus (
  id, subcategory_id, canonical_name, slug, pack_size,
  list_price_paise, selling_price_paise, status,
  qa_status, qa_verified_at, qa_verified_by, created_by
) values (
  'a5800000-0000-4000-8000-000000000001', 'a5700000-0000-4000-8000-000000000001',
  'Canonical Milk', 'control-canonical-milk', '1 litre', 7000, 6500, 'DRAFT',
  'VERIFIED', now(), 'a5000000-0000-4000-8000-000000000003',
  'a5000000-0000-4000-8000-000000000003'
), (
  'a5800000-0000-4000-8000-000000000002', 'a5700000-0000-4000-8000-000000000001',
  'Canonical Bread', 'control-canonical-bread', '400 g', 5000, 4500, 'DRAFT',
  'VERIFIED', now(), 'a5000000-0000-4000-8000-000000000003',
  'a5000000-0000-4000-8000-000000000003'
);

insert into dastak_v1.sku_images (
  id, sku_id, image_key, role, source_type, status,
  verified_by, verified_at, rights_status, rights_reference,
  rights_verified_by, rights_verified_at
) values
(
  'a5f00000-0000-4000-8000-000000000002',
  'a5800000-0000-4000-8000-000000000001',
  'test/control-canonical-milk-primary.webp',
  'PRIMARY', 'OTHER', 'VERIFIED',
  'a5000000-0000-4000-8000-000000000003', now(),
  'CLEARED', 'PGTAP fixture',
  'a5000000-0000-4000-8000-000000000003', now()
),
(
  'a5f00000-0000-4000-8000-000000000003',
  'a5800000-0000-4000-8000-000000000002',
  'test/control-canonical-bread-primary.webp',
  'PRIMARY', 'OTHER', 'VERIFIED',
  'a5000000-0000-4000-8000-000000000003', now(),
  'CLEARED', 'PGTAP fixture',
  'a5000000-0000-4000-8000-000000000003', now()
);

update dastak_v1.skus
set status = 'ACTIVE'
where id in (
  'a5800000-0000-4000-8000-000000000001',
  'a5800000-0000-4000-8000-000000000002'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-4000-8000-000000000003', true);
select is(
  pg_catalog.jsonb_path_exists(
    public.dastak_v1_merchant_canonical_catalogue_snapshot(
      'a5400000-0000-4000-8000-000000000001', 100
    ),
    '$.skus[*] ? (@.name == "Canonical Milk")'
  ),
  true,
  'merchant sees Dastak-owned SKU/category context and pricing'
);
select is(
  public.dastak_v1_update_merchant_sku_selection(
    'a5400000-0000-4000-8000-000000000001',
    'a5800000-0000-4000-8000-000000000001', true, 0, 'select-control-milk-1'
  ) ->> 'version',
  '1',
  'merchant can select a canonical SKU with expected version zero'
);
select is(
  public.dastak_v1_update_merchant_sku_selection(
    'a5400000-0000-4000-8000-000000000001',
    'a5800000-0000-4000-8000-000000000002', true, 0, 'select-control-bread-1'
  ) ->> 'version',
  '1',
  'independent SKUs may each begin their outbox stream at version one'
);
select throws_ok(
  $$select public.dastak_v1_update_merchant_sku_selection('a5400000-0000-4000-8000-000000000001','a5800000-0000-4000-8000-000000000001',false,0,'select-control-stale')$$,
  '40001',
  'stale merchant SKU selection version',
  'stale merchant selection is rejected'
);
select is(
  public.dastak_v1_update_merchant_sku_selections(
    'a5400000-0000-4000-8000-000000000001',
    '[
      {"skuId":"a5800000-0000-4000-8000-000000000001","selected":false,"expectedVersion":1},
      {"skuId":"a5800000-0000-4000-8000-000000000002","selected":false,"expectedVersion":1}
    ]'::jsonb,
    'save-control-catalogue-1'
  ) ->> 'updatedCount',
  '2',
  'merchant saves several staged SKU selections in one command'
);
select is(
  public.dastak_v1_update_merchant_sku_selections(
    'a5400000-0000-4000-8000-000000000001',
    '[
      {"skuId":"a5800000-0000-4000-8000-000000000001","selected":false,"expectedVersion":1},
      {"skuId":"a5800000-0000-4000-8000-000000000002","selected":false,"expectedVersion":1}
    ]'::jsonb,
    'save-control-catalogue-1'
  ) #>> '{selections,0,version}',
  '2',
  'replaying a batch returns its first committed response without another write'
);
select is(
  public.dastak_v1_set_branch_operational_state(
    'a5400000-0000-4000-8000-000000000001', 'branch-control-open-1', 0, true, true
  ) ->> 'acceptingOrders',
  'true',
  'merchant can explicitly enable branch order acceptance'
);
select is(
  public.dastak_v1_merchant_canonical_catalogue_snapshot('a5400000-0000-4000-8000-000000000001', 100) #>> '{branch,capacity,limit}',
  '5',
  'merchant sees branch capacity without gaining generic branch mutation'
);

select set_config('request.jwt.claim.sub', 'a5000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$select public.dastak_v1_update_merchant_sku_selection('a5400000-0000-4000-8000-000000000001','a5800000-0000-4000-8000-000000000001',false,1,'outsider-selection')$$,
  '42501',
  'permission denied',
  'merchant isolation rejects another account'
);
reset role;

select is(
  (
    select count(*)
    from dastak_v1.domain_events_outbox event
    where event.event_type = 'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED'
      and event.aggregate_type = 'MERCHANT_SKU_SELECTION'
      and event.aggregate_id in (
        'a5800000-0000-4000-8000-000000000001',
        'a5800000-0000-4000-8000-000000000002'
      )
  ),
  4::bigint,
  'each branch/SKU selection has an independent outbox aggregate'
);
select ok(
  exists (
    select 1 from dastak_v1.audit_events event
    where event.action = 'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED'
      and event.resource_id = 'a5400000-0000-4000-8000-000000000001'
  ),
  'canonical SKU selection is audited'
);

select set_config('request.jwt.claim.sub', 'a5000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select is(public.dastak_v1_update_merchant_sku_selections(
  'a5400000-0000-4000-8000-000000000001',
  '[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":true,"expectedVersion":2,"stockQuantity":24}]', 'stock-24'
) #>> '{selections,0,stockQuantity}', '24', 'merchant saves the stock count inside the versioned selection command');
select is(public.dastak_v1_update_merchant_sku_selections(
  'a5400000-0000-4000-8000-000000000001',
  '[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":true,"expectedVersion":2,"stockQuantity":24}]', 'stock-24'
) #>> '{selections,0,version}', '3', 'stock command replay does not increment twice');
select ok(pg_catalog.jsonb_path_exists(public.dastak_v1_merchant_canonical_catalogue_snapshot(
  'a5400000-0000-4000-8000-000000000001',100), '$.skus[*] ? (@.stockQuantity == 24)'), 'saved stock is returned in the merchant card snapshot');
select throws_ok($$select public.dastak_v1_update_merchant_sku_selections('a5400000-0000-4000-8000-000000000001', '[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":true,"expectedVersion":2,"stockQuantity":9}]', 'stock-stale')$$,
  '40001', 'stale merchant SKU selection version', 'stale counts cannot overwrite a newer count');
select is(public.dastak_v1_update_merchant_sku_selections(
  'a5400000-0000-4000-8000-000000000001',
  '[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":false,"expectedVersion":3,"stockQuantity":0}]', 'stock-zero'
) #>> '{selections,0,selected}', 'false', 'zero stock removes branch availability');
select throws_ok($$select public.dastak_v1_update_merchant_sku_selection('a5400000-0000-4000-8000-000000000001','a5800000-0000-4000-8000-000000000001',true,4,'stock-zero-old-client')$$,
  '22023', 'update stock count before selecting this product', 'old clients cannot make zero-stock products available');
select is(public.dastak_v1_update_merchant_sku_selections(
  'a5400000-0000-4000-8000-000000000001',
  '[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":true,"expectedVersion":4,"stockQuantity":12}]', 'stock-restock'
) #>> '{selections,0,stockQuantity}', '12', 'restocking restores availability with a fresh count');
select throws_ok($$select public.dastak_v1_update_merchant_sku_selections('a5400000-0000-4000-8000-000000000001','[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":true,"expectedVersion":5,"stockQuantity":-1}]','stock-negative')$$,
  '22023', 'stock quantity must be a whole number from 0 to 1000000; zero stock must be unavailable', 'negative counts rejected');
select set_config('request.jwt.claim.sub', 'a5000000-0000-4000-8000-000000000004', true);
select throws_ok($$select public.dastak_v1_update_merchant_sku_selections('a5400000-0000-4000-8000-000000000001','[{"skuId":"a5800000-0000-4000-8000-000000000001","selected":true,"expectedVersion":5,"stockQuantity":10}]','stock-outsider')$$,
  '42501', 'permission denied', 'other accounts cannot edit branch stock');
reset role;
select is((select stock_quantity from dastak_v1.merchant_sku_selections where branch_id='a5400000-0000-4000-8000-000000000001' and sku_id='a5800000-0000-4000-8000-000000000001'),12,'failed edits leave saved stock intact');
select is(has_function_privilege('anon','dastak_v1_api.update_merchant_stock_selection(uuid,uuid,uuid,boolean,bigint,text,integer)','EXECUTE'),false,'anonymous stock mutation denied');
select * from finish();
rollback;
