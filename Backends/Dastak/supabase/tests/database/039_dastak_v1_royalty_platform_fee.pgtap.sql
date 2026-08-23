begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(43);

select has_table('dastak_v1', 'financial_journal_transactions',
  'financial journal transactions exist');
select has_table('dastak_v1', 'financial_journal_lines',
  'balanced financial journal lines exist');
select has_table('dastak_v1', 'royalty_payout_destinations',
  'Royalty payout destinations exist');
select has_table('dastak_v1', 'royalty_withdrawals',
  'provider-independent Royalty withdrawals exist');
select has_table('dastak_v1', 'royalty_withdrawal_attempts',
  'withdrawal attempts are durable');
select has_table('dastak_v1', 'royalty_withdrawal_provider_events',
  'provider callbacks are durable and deduplicated');
select ok((select bool_and(relation.relrowsecurity)
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='dastak_v1' and relation.relname in (
    'financial_journal_transactions','financial_journal_lines',
    'royalty_payout_destinations','royalty_withdrawals',
    'royalty_withdrawal_attempts','royalty_withdrawal_provider_events'
  )), 'Royalty and journal tables enforce RLS');
select is(has_table_privilege('authenticated',
  'dastak_v1.financial_journal_transactions','SELECT'), false,
  'ordinary clients cannot read the private financial journal');
select is(has_function_privilege('authenticated',
  'public.dastak_v1_request_royalty_withdrawal(uuid,text,uuid,bigint,text)',
  'EXECUTE'), false, 'clients cannot spoof the authenticated account through service RPC');
select is(has_function_privilege('service_role',
  'public.dastak_v1_request_royalty_withdrawal(uuid,text,uuid,bigint,text)',
  'EXECUTE'), true, 'authenticated Edge handler can invoke withdrawal service RPC');
select has_function('dastak_v1_api', 'royalty_earning_milestone_proven',
  array['uuid'], 'Royalty earning milestone proof is explicit');
select is(has_function_privilege('service_role',
  'dastak_v1_api.royalty_earning_milestone_proven(uuid)', 'EXECUTE'), false,
  'service callers cannot bypass the custody-gated Royalty coordinator');

select is(dastak_v1_api.calculate_platform_fee(1), 0::bigint,
  'sub-paise 2 percent rounds deterministically to zero');
select is(dastak_v1_api.calculate_platform_fee(24), 0::bigint,
  'platform fee rounds down below half a paise');
select is(dastak_v1_api.calculate_platform_fee(25), 1::bigint,
  'platform fee rounds half-up at half a paise');
select is(dastak_v1_api.calculate_platform_fee(10000), 200::bigint,
  'platform fee is exactly 2 percent of paid total');
select throws_ok($$select dastak_v1_api.calculate_platform_fee(0)$$,
  '22023','invalid paid total','non-positive paid totals are rejected');

insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values
('94000000-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'royalty-rider@example.test','',now(),now(),now()),
('94000000-0000-4000-8000-000000000002',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'royalty-operations@example.test','',now(),now(),now());
insert into public.accounts(id,display_name,phone_number) values
('94000000-0000-4000-8000-000000000001','Royalty Rider','+919400000001'),
('94000000-0000-4000-8000-000000000002','Royalty Operations','+919400000002');
insert into private.account_memberships(account_id,role,approved_at) values
('94000000-0000-4000-8000-000000000001','dastak_partner',now()),
('94000000-0000-4000-8000-000000000002','owner',now());
insert into private.delivery_partner_applications (
  id,account_id,delivery_method,identity_evidence_object_path,verification_version,
  vehicle_registration_number,vehicle_make_model,vehicle_evidence_object_path,
  status,submitted_at,reviewed_at,reviewed_by
) values (
  '94000000-0000-4000-8000-000000000010',
  '94000000-0000-4000-8000-000000000001','motorbike',
  'test/royalty/identity.pdf',2,'TN 01 RT 0001','Royalty Test Motorbike',
  'test/royalty/vehicle.pdf','approved',now(),now(),
  '94000000-0000-4000-8000-000000000002'
);
insert into private.delivery_partner_profiles (
  account_id,approved_application_id,delivery_method
) values (
  '94000000-0000-4000-8000-000000000001',
  '94000000-0000-4000-8000-000000000010','motorbike'
);
insert into dastak_v1.platform_permission_grants (
  account_id,bundle_id,granted_by,grant_reason
) values (
  '94000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000009',
  '94000000-0000-4000-8000-000000000002',
  'Royalty withdrawal runtime test permission.'
);

select ok(dastak_v1_api.actor_can_manage_royalty_subject(
  '94000000-0000-4000-8000-000000000001','RIDER',
  '94000000-0000-4000-8000-000000000001',true
), 'approved Rider can manage only their own Royalty');
select is(dastak_v1_api.actor_can_manage_royalty_subject(
  '94000000-0000-4000-8000-000000000002','RIDER',
  '94000000-0000-4000-8000-000000000001',true
), false, 'another account cannot withdraw Rider Royalty');

select lives_ok($$
  select dastak_v1_api.post_balanced_financial_transaction(
    'PGTAP:RIDER:EARNING:1','RIDER_ROYALTY_EARNING',50000,
    'RIDER_DELIVERY_COST',null,null,
    'RIDER_ROYALTY_PAYABLE','RIDER','94000000-0000-4000-8000-000000000001',
    null,null,null,null,null,null,null,null,
    'Verified delivery test earning.','{"test":true}'
  )
$$, 'verified Rider earning posts as a balanced transaction');
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), 50000::bigint, 'Royalty derives from journal credits');
select throws_ok($$
  select dastak_v1_api.post_balanced_financial_transaction(
    'PGTAP:RIDER:EARNING:1','RIDER_ROYALTY_EARNING',50000,
    'RIDER_DELIVERY_COST',null,null,
    'RIDER_ROYALTY_PAYABLE','RIDER','94000000-0000-4000-8000-000000000001',
    null,null,null,null,null,null,null,null,
    'Verified delivery test earning.','{"test":false}'
  )
$$, 'P0001','financial transaction key collision',
  'an idempotency key cannot conceal changed journal metadata');
select throws_ok($$
  select dastak_v1_api.post_balanced_financial_transaction(
    'PGTAP:RIDER:EARNING:1','RIDER_ROYALTY_EARNING',50000,
    'FAULT_RECOVERY',null,null,
    'RIDER_ROYALTY_PAYABLE','RIDER','94000000-0000-4000-8000-000000000001',
    null,null,null,null,null,null,null,null,
    'Verified delivery test earning.','{"test":true}'
  )
$$, 'P0001','financial transaction key collision',
  'an idempotency key cannot conceal changed debit or credit lines');

select lives_ok($$
  select dastak_v1_api.post_balanced_financial_transaction(
    'PGTAP:RIDER:FAULT:1','ROYALTY_FAULT_ADJUSTMENT',65000,
    'RIDER_ROYALTY_PAYABLE','RIDER','94000000-0000-4000-8000-000000000001',
    'FAULT_RECOVERY',null,null,
    null,null,null,null,null,null,null,null,
    'Authorized fault adjustment test.','{"test":true}'
  )
$$, 'fault adjustment can exceed positive balance');
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), -15000::bigint, 'fault adjustment creates a negative Royalty balance');
select lives_ok($$
  select dastak_v1_api.post_balanced_financial_transaction(
    'PGTAP:RIDER:EARNING:2','RIDER_ROYALTY_EARNING',15000,
    'RIDER_DELIVERY_COST',null,null,
    'RIDER_ROYALTY_PAYABLE','RIDER','94000000-0000-4000-8000-000000000001',
    null,null,null,null,null,null,null,null,
    'Later verified earning offsets debt.','{"test":true}'
  )
$$, 'later earning offsets negative Royalty automatically');
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), 0::bigint, 'later earnings first return a negative balance to zero');
select throws_ok($$
  select dastak_v1_api.request_royalty_withdrawal(
    '94000000-0000-4000-8000-000000000001','RIDER',
    '94000000-0000-4000-8000-000000000001',1,'zero-balance'
  )
$$, '23514','POSITIVE_ROYALTY_BALANCE_REQUIRED',
  'zero Royalty cannot be withdrawn');

select dastak_v1_api.post_balanced_financial_transaction(
  'PGTAP:RIDER:EARNING:3','RIDER_ROYALTY_EARNING',50000,
  'RIDER_DELIVERY_COST',null,null,
  'RIDER_ROYALTY_PAYABLE','RIDER','94000000-0000-4000-8000-000000000001',
  null,null,null,null,null,null,null,null,
  'Verified earning available for withdrawal.','{"test":true}'
);
select dastak_v1_api.register_royalty_payout_destination(
  '94000000-0000-4000-8000-000000000001','RIDER',
  '94000000-0000-4000-8000-000000000001','PROVIDER_DESTINATION',
  'TEST_PAYOUT','destination-token-1','Test payout • 0001','{"test":true}'
);
select is((dastak_v1_api.royalty_subject_snapshot(
  '94000000-0000-4000-8000-000000000001','RIDER',
  '94000000-0000-4000-8000-000000000001'
)->>'canWithdraw')::boolean, true,
  'the approved Rider sees withdrawal enabled for their own positive Royalty');
select is((dastak_v1_api.royalty_subject_snapshot(
  '94000000-0000-4000-8000-000000000002','RIDER',
  '94000000-0000-4000-8000-000000000001'
)->>'canWithdraw')::boolean, false,
  'a different actor never sees another Rider withdrawal as enabled');
create temporary table royalty_test_state (
  withdrawal_id uuid, attempt_id uuid
);
insert into royalty_test_state(withdrawal_id)
select (dastak_v1_api.request_royalty_withdrawal(
  '94000000-0000-4000-8000-000000000001','RIDER',
  '94000000-0000-4000-8000-000000000001',30000,'withdrawal-1'
)->>'withdrawalId')::uuid;

select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), 20000::bigint, 'withdrawal request reserves availability transactionally');
select throws_ok($$
  select dastak_v1_api.request_royalty_withdrawal(
    '94000000-0000-4000-8000-000000000001','RIDER',
    '94000000-0000-4000-8000-000000000001',20001,'withdrawal-too-large'
  )
$$, '23514','WITHDRAWAL_EXCEEDS_AVAILABLE_ROYALTY',
  'withdrawal cannot exceed positive available Royalty');
select is((
  dastak_v1_api.request_royalty_withdrawal(
    '94000000-0000-4000-8000-000000000001','RIDER',
    '94000000-0000-4000-8000-000000000001',30000,'withdrawal-1'
  )->>'replayed'
)::boolean, true, 'withdrawal request replay is idempotent');

update royalty_test_state state set attempt_id = (
  dastak_v1_api.start_royalty_withdrawal(
    '94000000-0000-4000-8000-000000000002',state.withdrawal_id,1,
    'provider-request-1'
  )->>'attemptId'
)::uuid;
select is((
  dastak_v1_api.record_royalty_withdrawal_result(
    state.withdrawal_id,state.attempt_id,'TEST_PAYOUT','provider-event-failed-1',
    'FAILED',null,'TEMPORARY_PROVIDER_FAILURE',repeat('a',64),
    '{"test":true}',now()
  )->>'status'
)::text,'FAILED_RETRYABLE','failed payout is explicitly retryable')
from royalty_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), 50000::bigint, 'failed payout restores all reserved availability');
select is((
  dastak_v1_api.record_royalty_withdrawal_result(
    state.withdrawal_id,state.attempt_id,'TEST_PAYOUT','provider-event-failed-1',
    'FAILED',null,'TEMPORARY_PROVIDER_FAILURE',repeat('a',64),
    '{"test":true}',now()
  )->>'replayed'
)::boolean,true,'duplicate payout callback is idempotent')
from royalty_test_state state;

update royalty_test_state state set attempt_id = (
  dastak_v1_api.start_royalty_withdrawal(
    '94000000-0000-4000-8000-000000000002',state.withdrawal_id,3,
    'provider-request-2'
  )->>'attemptId'
)::uuid;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), 20000::bigint, 'retry re-reserves the same Royalty amount');
select is((
  dastak_v1_api.record_royalty_withdrawal_result(
    state.withdrawal_id,state.attempt_id,'TEST_PAYOUT','provider-event-paid-2',
    'PAID','payout-reference-2',null,repeat('b',64),
    '{"test":true}',now()
  )->>'status'
)::text,'PAID','provider confirmation alone records withdrawal Paid')
from royalty_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94000000-0000-4000-8000-000000000001'
), 20000::bigint, 'paid withdrawal remains debited exactly once');
select is((select destination_snapshot->>'providerDestinationReference'
  from dastak_v1.royalty_withdrawals withdrawal
  join royalty_test_state state on state.withdrawal_id=withdrawal.id),
  'destination-token-1','withdrawal destination is immutably snapshotted');
select throws_ok($$
  update dastak_v1.financial_journal_transactions
  set reason='rewrite forbidden' where transaction_key='PGTAP:RIDER:EARNING:1'
$$, 'P0001','append-only financial history cannot be changed',
  'historical financial transactions cannot be rewritten');
select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000002',
  true
);
select throws_ok($$
  select dastak_v1_api.settle_entry(
    '94000000-0000-4000-8000-000000000002',
    '94000000-0000-4000-8000-000000000099','legacy-bank-reference',1,'legacy'
  )
$$, '55000','ROYALTY_WITHDRAWAL_REQUIRED',
  'legacy manual settlement path cannot bypass Royalty withdrawal');
select is((select count(*) from (
  select transaction.id from dastak_v1.financial_journal_transactions transaction
  join dastak_v1.financial_journal_lines line on line.transaction_id=transaction.id
  group by transaction.id
  having count(*)<>2 or sum(line.amount_paise) filter(where line.direction='DEBIT')
    <> sum(line.amount_paise) filter(where line.direction='CREDIT')
) imbalanced), 0::bigint,
  'every financial transaction remains double-entry balanced');

select * from finish();
rollback;
