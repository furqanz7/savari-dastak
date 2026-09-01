begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_trigger(
  'dastak_v1',
  'merchant_users',
  'merchant_users_close_unstaffed_branches_on_status',
  'Merchant suspension fail-closes unstaffed branches'
);
select has_trigger(
  'dastak_v1',
  'merchant_users',
  'merchant_users_close_unstaffed_branches_on_delete',
  'Merchant removal fail-closes unstaffed branches'
);
select is(
  has_function_privilege(
    'authenticated',
    'dastak_v1.close_unstaffed_merchant_branches_after_membership_change()',
    'EXECUTE'
  ),
  false,
  'clients cannot invoke the branch-closure trigger directly'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    'bc000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'branch-owner-one@example.test', '',
    now(), now(), now()
  ),
  (
    'bc000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'branch-owner-two@example.test', '',
    now(), now(), now()
  );

insert into public.accounts (id, display_name, phone_number) values
  ('bc000000-0000-4000-8000-000000000001', 'Branch Owner One', '+919300000001'),
  ('bc000000-0000-4000-8000-000000000002', 'Branch Owner Two', '+919300000002');

insert into dastak_v1.merchant_organizations (
  id, legal_name, display_name, merchant_type, status, created_by
) values (
  'bc000000-0000-4000-8000-000000000010',
  'Unstaffed Branch Test Private Limited',
  'Unstaffed Branch Test',
  'RETAIL',
  'ACTIVE',
  'bc000000-0000-4000-8000-000000000001'
);

insert into dastak_v1.merchant_branches (
  id, organization_id, display_name, status, created_by
) values (
  'bc000000-0000-4000-8000-000000000011',
  'bc000000-0000-4000-8000-000000000010',
  'Unstaffed Branch',
  'ACTIVE',
  'bc000000-0000-4000-8000-000000000001'
);

insert into dastak_v1.merchant_users (
  id, organization_id, account_id, status, created_by
) values
  (
    'bc000000-0000-4000-8000-000000000021',
    'bc000000-0000-4000-8000-000000000010',
    'bc000000-0000-4000-8000-000000000001',
    'ACTIVE',
    'bc000000-0000-4000-8000-000000000001'
  ),
  (
    'bc000000-0000-4000-8000-000000000022',
    'bc000000-0000-4000-8000-000000000010',
    'bc000000-0000-4000-8000-000000000002',
    'ACTIVE',
    'bc000000-0000-4000-8000-000000000001'
  );

insert into dastak_v1.branch_operational_states (
  branch_id, is_open, accepting_orders, updated_by
) values (
  'bc000000-0000-4000-8000-000000000011',
  true,
  true,
  'bc000000-0000-4000-8000-000000000001'
);

update dastak_v1.merchant_users
set status = 'SUSPENDED', updated_at = now(), version = version + 1
where id = 'bc000000-0000-4000-8000-000000000021';

select is(
  (
    select is_open and accepting_orders
    from dastak_v1.branch_operational_states
    where branch_id = 'bc000000-0000-4000-8000-000000000011'
  ),
  true,
  'a branch stays open while another active Merchant operator remains'
);

update dastak_v1.merchant_users
set status = 'SUSPENDED', updated_at = now(), version = version + 1
where id = 'bc000000-0000-4000-8000-000000000022';

select is(
  (
    select is_open or accepting_orders
    from dastak_v1.branch_operational_states
    where branch_id = 'bc000000-0000-4000-8000-000000000011'
  ),
  false,
  'the final active Merchant suspension closes and disables the branch'
);
select is(
  (
    select version
    from dastak_v1.branch_operational_states
    where branch_id = 'bc000000-0000-4000-8000-000000000011'
  ),
  2::bigint,
  'automatic closure follows the branch optimistic-lock version contract'
);

select * from finish();
rollback;
