begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(50);

select has_table('dastak_v1', 'royalty_payout_provider_contacts',
  'RazorpayX Contacts are mapped without becoming Royalty truth');
select has_table('dastak_v1', 'razorpayx_payouts',
  'one provider payout projection exists per Dastak withdrawal');
select has_table('dastak_v1', 'razorpayx_provider_requests',
  'provider request attempts are durable');
select has_table('dastak_v1', 'razorpayx_provider_events',
  'verified webhook and reconciliation events are durable');
select ok((select bool_and(relation.relrowsecurity)
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='dastak_v1' and relation.relname in (
    'royalty_payout_provider_contacts','razorpayx_payouts',
    'razorpayx_provider_requests','razorpayx_provider_events'
  )), 'every RazorpayX projection enforces RLS');
select is(has_table_privilege('authenticated','dastak_v1.razorpayx_payouts','SELECT'),
  false, 'ordinary clients cannot read provider payout records');
select is(has_function_privilege('authenticated',
  'public.dastak_v1_apply_razorpayx_payout_status(text,text,uuid,uuid,text,text,text,bigint,text,text,text,jsonb,timestamptz,timestamptz,text,jsonb)',
  'EXECUTE'), false, 'ordinary clients cannot forge payout provider events');
select is(has_function_privilege('service_role',
  'public.dastak_v1_apply_razorpayx_payout_status(text,text,uuid,uuid,text,text,text,bigint,text,text,text,jsonb,timestamptz,timestamptz,text,jsonb)',
  'EXECUTE'), true, 'the authenticated payout webhook service can apply verified events');

insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values
('94200000-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'razorpayx-rider@example.test','',now(),now(),now()),
('94200000-0000-4000-8000-000000000002',
 '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'razorpayx-operations@example.test','',now(),now(),now());
insert into public.accounts(id,display_name,phone_number) values
('94200000-0000-4000-8000-000000000001','RazorpayX Rider','+919420000001'),
('94200000-0000-4000-8000-000000000002','RazorpayX Operations','+919420000002');
insert into private.account_memberships(account_id,role,approved_at) values
('94200000-0000-4000-8000-000000000001','dastak_partner',now()),
('94200000-0000-4000-8000-000000000002','owner',now());
insert into private.delivery_partner_applications (
  id,account_id,delivery_method,identity_evidence_object_path,verification_version,
  vehicle_registration_number,vehicle_make_model,vehicle_evidence_object_path,
  status,submitted_at,reviewed_at,reviewed_by
) values (
  '94200000-0000-4000-8000-000000000010',
  '94200000-0000-4000-8000-000000000001','motorbike',
  'test/razorpayx/identity.pdf',2,'TN 01 RX 0001','RazorpayX Test Motorbike',
  'test/razorpayx/vehicle.pdf','approved',now(),now(),
  '94200000-0000-4000-8000-000000000002'
);
insert into private.delivery_partner_profiles(
  account_id,approved_application_id,delivery_method
) values (
  '94200000-0000-4000-8000-000000000001',
  '94200000-0000-4000-8000-000000000010','motorbike'
);
insert into dastak_v1.platform_permission_grants(
  account_id,bundle_id,granted_by,grant_reason
) values (
  '94200000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000009',
  '94200000-0000-4000-8000-000000000002',
  'RazorpayX payout trace test permission.'
);

select lives_ok($$
  select dastak_v1_api.post_balanced_financial_transaction(
    'PGTAP:RAZORPAYX:RIDER:EARNING','RIDER_ROYALTY_EARNING',50000,
    'RIDER_DELIVERY_COST',null,null,
    'RIDER_ROYALTY_PAYABLE','RIDER','94200000-0000-4000-8000-000000000001',
    null,null,null,null,null,null,null,null,
    'Verified delivery available for RazorpayX payout.','{"test":true}'
  )
$$, 'Royalty is funded only through the authoritative Dastak journal');
select is((dastak_v1_api.finalize_razorpayx_payout_destination(
  '94200000-0000-4000-8000-000000000001','RIDER',
  '94200000-0000-4000-8000-000000000001','BANK_ACCOUNT',
  'cont_razorpayx0001','fa_razorpayx0001',
  '94200000-0000-4000-8000-000000000001','RazorpayX Rider',
  'Bank account •••• 0001',repeat('a',64),
  '{"last4":"0001","ifsc":"HDFC0001234"}'
)->>'type')::text, 'BANK_ACCOUNT',
  'an Indian bank payout destination is registered through the provider adapter boundary');
select is((dastak_v1_api.royalty_subject_snapshot(
  '94200000-0000-4000-8000-000000000001','RIDER',
  '94200000-0000-4000-8000-000000000001'
)->'payoutDestination' ? 'provider'), false,
  'Merchant and Rider Royalty projections do not expose Razorpay-specific concepts');
select is((dastak_v1_api.royalty_subject_snapshot(
  '94200000-0000-4000-8000-000000000001','RIDER',
  '94200000-0000-4000-8000-000000000001'
)->'payoutDestination'->>'displayLabel')::text, 'Bank account •••• 0001',
  'ordinary clients receive only a masked destination label');
select is((select count(*) from dastak_v1.royalty_payout_destinations destination
  where destination.details_snapshot::text like '%123456789012%'), 0::bigint,
  'raw bank account details are never persisted in Dastak payout metadata');

create temporary table razorpayx_test_state (
  withdrawal_one uuid,
  attempt_one uuid,
  withdrawal_two uuid,
  attempt_two uuid,
  withdrawal_three uuid,
  attempt_three uuid
);
insert into razorpayx_test_state(withdrawal_one)
select (dastak_v1_api.request_royalty_withdrawal(
  '94200000-0000-4000-8000-000000000001','RIDER',
  '94200000-0000-4000-8000-000000000001',15000,'razorpayx-withdrawal-one'
)->>'withdrawalId')::uuid;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94200000-0000-4000-8000-000000000001'
),35000::bigint,'withdrawal request reserves Royalty before external provider work');
select throws_ok($$
  select dastak_v1_api.start_royalty_withdrawal(
    '94200000-0000-4000-8000-000000000002',state.withdrawal_one,1,'wrong-key'
  ) from razorpayx_test_state state
$$,'42501','RazorpayX attempts must use the provider adapter',
  'the generic withdrawal adapter cannot bypass RazorpayX idempotency enforcement');
update razorpayx_test_state state set attempt_one = (
  dastak_v1_api.claim_razorpayx_withdrawal(
    '94200000-0000-4000-8000-000000000001',state.withdrawal_one,1
  )->>'attemptId'
)::uuid;
select is((select payout.payout_idempotency_key
  from dastak_v1.razorpayx_payouts payout
  join razorpayx_test_state state on state.withdrawal_one=payout.withdrawal_id),
  (select withdrawal_one::text from razorpayx_test_state),
  'the Dastak withdrawal UUID is the mandatory provider payout idempotency key');
select is((select count(*) from dastak_v1.royalty_withdrawal_attempts attempt
  join razorpayx_test_state state on state.withdrawal_one=attempt.withdrawal_id),
  1::bigint,'a Dastak withdrawal has one RazorpayX external payout attempt identity');
select is((select payout.fund_account_reference
  from dastak_v1.razorpayx_payouts payout
  join razorpayx_test_state state on state.withdrawal_one=payout.withdrawal_id),
  'fa_razorpayx0001','the immutable withdrawal snapshots the selected Fund Account');

select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-pending','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.pending','pending',15000,'INR',
  'fa_razorpayx0001',repeat('b',64),'{"safe":true}',
  '2026-08-23T10:00:00Z','2026-08-23T09:59:00Z',null,'{}'
)->>'providerStatus')::text,'PENDING','a verified pending event advances provider state')
from razorpayx_test_state state;
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-pending','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.pending','pending',15000,'INR',
  'fa_razorpayx0001',repeat('b',64),'{"safe":true}',
  '2026-08-23T10:00:00Z','2026-08-23T09:59:00Z',null,'{}'
)->>'replayed')::boolean,true,'duplicate webhook delivery is idempotent')
from razorpayx_test_state state;
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-processing','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.updated','processing',15000,'INR',
  'fa_razorpayx0001',repeat('c',64),'{}',
  '2026-08-23T10:01:00Z','2026-08-23T09:59:00Z',null,'{}'
)->>'providerStatus')::text,'PROCESSING','processing is explicit and remains unpaid')
from razorpayx_test_state state;
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-stale','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.pending','pending',15000,'INR',
  'fa_razorpayx0001',repeat('d',64),'{}',
  '2026-08-23T09:59:30Z','2026-08-23T09:59:00Z',null,'{}'
)->>'applicationResult')::text,'IGNORED_STALE',
  'out-of-order non-terminal provider events cannot regress state')
from razorpayx_test_state state;
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-paid','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.processed','processed',15000,'INR',
  'fa_razorpayx0001',repeat('e',64),'{"utr":"UTR-RX-1"}',
  '2026-08-23T10:02:00Z','2026-08-23T09:59:00Z','UTR-RX-1','{}'
)->>'status')::text,'PAID','Paid is recorded only from authoritative provider confirmation')
from razorpayx_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94200000-0000-4000-8000-000000000001'
),35000::bigint,'provider Paid moves clearing to cash without debiting Royalty twice');
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-paid','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.processed','processed',15000,'INR',
  'fa_razorpayx0001',repeat('e',64),'{"utr":"UTR-RX-1"}',
  '2026-08-23T10:02:00Z','2026-08-23T09:59:00Z','UTR-RX-1','{}'
)->>'replayed')::boolean,true,'duplicate success cannot pay twice')
from razorpayx_test_state state;
select throws_ok($$
  select dastak_v1_api.apply_razorpayx_payout_status(
    'evt-rx-wrong-owner','WEBHOOK',state.withdrawal_one,null,
    'pout_razorpayx0001','payout.processed','processed',15001,'INR',
    'fa_razorpayx0001',repeat('f',64),'{}',
    '2026-08-23T10:03:00Z','2026-08-23T09:59:00Z',null,'{}'
  ) from razorpayx_test_state state
$$,'22023','RAZORPAYX_PAYOUT_OWNERSHIP_MISMATCH',
  'a webhook cannot alter a withdrawal with mismatched authoritative ownership data');
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-reversed','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.reversed','reversed',15000,'INR',
  'fa_razorpayx0001',repeat('1',64),'{}',
  '2026-08-23T10:04:00Z','2026-08-23T09:59:00Z',null,'{}'
)->>'status')::text,'REVERSED','a provider reversal remains distinct from normal Paid')
from razorpayx_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94200000-0000-4000-8000-000000000001'
),50000::bigint,'reversal restores withdrawable Royalty exactly once');
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-reversed','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.reversed','reversed',15000,'INR',
  'fa_razorpayx0001',repeat('1',64),'{}',
  '2026-08-23T10:04:00Z','2026-08-23T09:59:00Z',null,'{}'
)->>'replayed')::boolean,true,'duplicate reversal cannot restore Royalty twice')
from razorpayx_test_state state;
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-late-processing','WEBHOOK',state.withdrawal_one,null,
  'pout_razorpayx0001','payout.updated','processing',15000,'INR',
  'fa_razorpayx0001',repeat('2',64),'{}',
  '2026-08-23T09:58:00Z','2026-08-23T09:59:00Z',null,'{}'
)->>'applicationResult')::text,'IGNORED_TERMINAL',
  'terminal reversed payout cannot regress on late delivery')
from razorpayx_test_state state;
select is((dastak_v1_api.royalty_subject_snapshot(
  '94200000-0000-4000-8000-000000000001','RIDER',
  '94200000-0000-4000-8000-000000000001'
)->'withdrawals'->0->>'status')::text,'REVERSED',
  'Royalty UI receives the effective reversed state');
select is((select withdrawal.status::text
  from dastak_v1.royalty_withdrawals withdrawal
  join razorpayx_test_state state on state.withdrawal_one=withdrawal.id),
  'PAID','historical Paid withdrawal truth is preserved after compensating reversal');

select dastak_v1_api.finalize_razorpayx_payout_destination(
  '94200000-0000-4000-8000-000000000001','RIDER',
  '94200000-0000-4000-8000-000000000001','UPI',
  'cont_razorpayx0001','fa_razorpayx0002',
  '94200000-0000-4000-8000-000000000001','RazorpayX Rider',
  'UPI • ra***@okaxis',repeat('3',64),'{"maskedAddress":"ra***@okaxis"}'
);
select is((select withdrawal.destination_snapshot->>'providerDestinationReference'
  from dastak_v1.royalty_withdrawals withdrawal
  join razorpayx_test_state state on state.withdrawal_one=withdrawal.id),
  'fa_razorpayx0001','changing the default destination cannot rewrite a withdrawal snapshot');
select throws_ok($$
  update dastak_v1.royalty_payout_provider_contacts
  set provider_contact_reference='cont_rewritten'
  where subject_type='RIDER' and subject_id='94200000-0000-4000-8000-000000000001'
$$,'P0001','append-only financial history cannot be changed',
  'provider Contact history cannot be rewritten');
select throws_ok($$
  update dastak_v1.razorpayx_provider_events set provider_status='PENDING'
  where provider_event_id='evt-rx-paid'
$$,'P0001','append-only financial history cannot be changed',
  'verified provider event history cannot be rewritten');

update razorpayx_test_state set withdrawal_two = (
  dastak_v1_api.request_royalty_withdrawal(
    '94200000-0000-4000-8000-000000000001','RIDER',
    '94200000-0000-4000-8000-000000000001',10000,'razorpayx-withdrawal-two'
  )->>'withdrawalId'
)::uuid;
update razorpayx_test_state state set attempt_two = (
  dastak_v1_api.claim_razorpayx_withdrawal(
    '94200000-0000-4000-8000-000000000001',state.withdrawal_two,1
  )->>'attemptId'
)::uuid;
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-failed','WEBHOOK',state.withdrawal_two,null,
  'pout_razorpayx0002','payout.failed','failed',10000,'INR',
  'fa_razorpayx0002',repeat('4',64),'{}',
  '2026-08-23T11:00:00Z','2026-08-23T10:59:00Z',null,
  '{"reason":"beneficiary_bank_failure"}'
)->>'status')::text,'FAILED','provider failure is explicit and retryable as a new withdrawal')
from razorpayx_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94200000-0000-4000-8000-000000000001'
),50000::bigint,'provider failure restores the reserved Royalty exactly once');
select is((dastak_v1_api.apply_razorpayx_payout_status(
  'evt-rx-failed','WEBHOOK',state.withdrawal_two,null,
  'pout_razorpayx0002','payout.failed','failed',10000,'INR',
  'fa_razorpayx0002',repeat('4',64),'{}',
  '2026-08-23T11:00:00Z','2026-08-23T10:59:00Z',null,
  '{"reason":"beneficiary_bank_failure"}'
)->>'replayed')::boolean,true,'duplicate failure cannot restore Royalty twice')
from razorpayx_test_state state;

update razorpayx_test_state set withdrawal_three = (
  dastak_v1_api.request_royalty_withdrawal(
    '94200000-0000-4000-8000-000000000001','RIDER',
    '94200000-0000-4000-8000-000000000001',10000,'razorpayx-withdrawal-three'
  )->>'withdrawalId'
)::uuid;
update razorpayx_test_state state set attempt_three = (
  dastak_v1_api.claim_razorpayx_withdrawal(
    '94200000-0000-4000-8000-000000000001',state.withdrawal_three,1
  )->>'attemptId'
)::uuid;
select is((dastak_v1_api.mark_razorpayx_submission_retryable(
  state.withdrawal_three,state.attempt_three,
  '94200000-0000-4000-8000-000000000099','RAZORPAYX_BAD_REQUEST'
)->>'status')::text,'FAILED_RETRYABLE',
  'known pre-accept provider rejection releases the reservation for safe retry')
from razorpayx_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94200000-0000-4000-8000-000000000001'
),50000::bigint,'known pre-accept rejection cannot lose Royalty');
select is((dastak_v1_api.claim_razorpayx_withdrawal(
  '94200000-0000-4000-8000-000000000001',state.withdrawal_three,3
)->>'attemptId')::uuid,state.attempt_three,
  'retry reuses the same external payout identity rather than creating a second payout')
from razorpayx_test_state state;
select is(dastak_v1_api.royalty_balance_paise(
  'RIDER','94200000-0000-4000-8000-000000000001'
),40000::bigint,'retry transactionally re-reserves the Royalty amount');
select is((select count(*) from dastak_v1.razorpayx_payouts payout
  join razorpayx_test_state state on payout.withdrawal_id=state.withdrawal_three),
  1::bigint,'submission retry cannot create two external payout projections');
select is((dastak_v1_api.mark_razorpayx_reconciliation_required(
  state.withdrawal_three,state.attempt_three,
  '94200000-0000-4000-8000-000000000097','PAYOUT_OWNERSHIP_MISMATCH'
)->>'reconciliationState')::text,'REVIEW_REQUIRED',
  'ownership mismatch remains reserved and is durably escalated for Operations')
from razorpayx_test_state state;

select is((dastak_v1_api.record_razorpayx_provider_request(
  '94200000-0000-4000-8000-000000000098',state.withdrawal_three,
  state.attempt_three,'PAYOUT_CREATE',state.withdrawal_three::text,
  repeat('5',64),'UNKNOWN',null,null,'{}','2026-08-23T12:00:00Z'
)->>'replayed')::boolean,false,'ambiguous provider request is recorded for reconciliation')
from razorpayx_test_state state;
select is((dastak_v1_api.record_razorpayx_provider_request(
  '94200000-0000-4000-8000-000000000098',state.withdrawal_three,
  state.attempt_three,'PAYOUT_CREATE',state.withdrawal_three::text,
  repeat('5',64),'UNKNOWN',null,null,'{}','2026-08-23T12:00:00Z'
)->>'replayed')::boolean,true,'provider request logging is itself idempotent')
from razorpayx_test_state state;
select throws_ok($$
  select dastak_v1_api.record_razorpayx_provider_request(
    '94200000-0000-4000-8000-000000000098',state.withdrawal_three,
    state.attempt_three,'PAYOUT_CREATE',state.withdrawal_three::text,
    repeat('6',64),'UNKNOWN',null,null,'{}','2026-08-23T12:00:00Z'
  ) from razorpayx_test_state state
$$,'22023','RazorpayX request collision',
  'a request identifier cannot conceal changed provider request content');
select is((select response_status from dastak_v1_api.razorpayx_admin_snapshot(
  '94200000-0000-4000-8000-000000000001',100
)),403,'ordinary Riders cannot inspect provider reconciliation data');
select is((select response_status from dastak_v1_api.razorpayx_admin_snapshot(
  '94200000-0000-4000-8000-000000000002',100
)),200,'authorized Operations can inspect provider payout reconciliation');
select is((select count(*) from (
  select transaction.id from dastak_v1.financial_journal_transactions transaction
  join dastak_v1.financial_journal_lines line on line.transaction_id=transaction.id
  group by transaction.id
  having count(*)<>2 or sum(line.amount_paise) filter(where line.direction='DEBIT')
    <> sum(line.amount_paise) filter(where line.direction='CREDIT')
) imbalanced),0::bigint,'RazorpayX events preserve the balanced append-only journal');

select * from finish();
rollback;
