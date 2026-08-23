begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(25);

select has_table('dastak_v1', 'merchant_branch_reachability',
  'merchant reachability has authoritative runtime state');
select ok((select relrowsecurity from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='dastak_v1' and relation.relname='merchant_branch_reachability'),
  'merchant reachability enforces RLS');
select is(has_table_privilege('authenticated','dastak_v1.merchant_branch_reachability','SELECT'),
  false, 'clients cannot inspect merchant reachability telemetry directly');
select has_column('dastak_v1','delivery_problem_reports','problem_code',
  'delivery problems carry a structured operational code');
select has_column('dastak_v1','delivery_problem_reports','operational_policy_snapshot',
  'customer-unreachable policy is snapshotted');
select has_column('dastak_v1','recovery_cases','next_action_at',
  'customer-unreachable escalation deadline is durable');
select has_column('dastak_v1','settlement_entries','payout_cadence_snapshot',
  'settled entries retain payout cadence truth');

select is((select count(*) from dastak_v1.setting_definitions definition
  where definition.setting_key in (
    'merchant.reachability_stale_seconds','delivery.customer_unreachable_policy',
    'observability.alert_thresholds','observability.outbox_stale_seconds',
    'settlement.payout_cadence'
  ) and definition.requires_explicit_value and definition.default_value is null),
  5::bigint, 'business-owned operational settings require explicit values');
select is((select count(*) from pg_catalog.pg_trigger trigger_row
  join pg_catalog.pg_class relation on relation.oid=trigger_row.tgrelid
  join pg_catalog.pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='dastak_v1' and not trigger_row.tgisinternal
    and trigger_row.tgname in (
      'branch_operational_state_records_heartbeat',
      'aa_merchant_opportunities_reachability',
      'aa_restaurant_requests_reachability',
      'aa_delivery_problem_policy'
    )), 4::bigint, 'reachability and unreachable-policy gates are structural');
select is(has_function_privilege('authenticated',
  'public.dastak_v1_list_merchant_opportunities(integer)','EXECUTE'), true,
  'merchant polling may record an authenticated heartbeat');
select is(has_function_privilege('anon',
  'public.dastak_v1_list_merchant_opportunities(integer)','EXECUTE'), false,
  'anonymous callers cannot record merchant heartbeats');

select throws_ok($$select dastak_v1_api.customer_unreachable_policy()$$,
  '55000','SYSTEM_CONFIGURATION_ERROR',
  'missing customer-unreachable policy fails as configuration error');
select throws_ok($$select dastak_v1_api.operational_alert_thresholds()$$,
  '55000','SYSTEM_CONFIGURATION_ERROR',
  'missing alert thresholds fail as configuration error');
select throws_ok($$select dastak_v1_api.payout_cadence_policy()$$,
  '55000','SYSTEM_CONFIGURATION_ERROR',
  'missing payout cadence fails as configuration error');

insert into auth.users (
  id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at
) values (
  '93900000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'acceptance-closure-owner@example.test','',now(),now(),now()
);
insert into public.accounts(id,display_name,phone_number) values (
  '93900000-0000-4000-8000-000000000001','Acceptance Closure Owner','+919390000001'
);
insert into public.service_zones(id,name,boundary,active) values (
  '93900000-0000-4000-8000-000000000020','Acceptance Closure Zone',
  extensions.st_geomfromtext('POLYGON((78 12,79 12,79 13,78 13,78 12))',4326),true
);
insert into dastak_v1.merchant_organizations(
  id,legal_name,display_name,merchant_type,status,created_by
) values (
  '93900000-0000-4000-8000-000000000021','Acceptance Closure Retail Private Limited',
  'Acceptance Closure Retail','RETAIL','ACTIVE','93900000-0000-4000-8000-000000000001'
);
insert into dastak_v1.merchant_branches(
  id,organization_id,display_name,service_zone_id,address_snapshot,location,
  capacity_limit,status,created_by
) values
(
  '93900000-0000-4000-8000-000000000022','93900000-0000-4000-8000-000000000021',
  'Reachable Branch','93900000-0000-4000-8000-000000000020','{}',
  extensions.st_setsrid(extensions.st_makepoint(78.5,12.5),4326),2,'ACTIVE',
  '93900000-0000-4000-8000-000000000001'
),(
  '93900000-0000-4000-8000-000000000023','93900000-0000-4000-8000-000000000021',
  'No Heartbeat Branch','93900000-0000-4000-8000-000000000020','{}',
  extensions.st_setsrid(extensions.st_makepoint(78.6,12.5),4326),2,'ACTIVE',
  '93900000-0000-4000-8000-000000000001'
);

select throws_ok($$select dastak_v1_api.branch_reachability_stale_seconds(
  '93900000-0000-4000-8000-000000000022'
)$$, '55000','SYSTEM_CONFIGURATION_ERROR',
  'missing merchant-staleness configuration fails explicitly');

insert into dastak_v1.platform_settings(
  id,setting_key,scope_type,setting_value,updated_by,update_reason
) values
('93900000-0000-4000-8000-000000000010','delivery.customer_unreachable_policy','GLOBAL',
 '{"waitSeconds":120,"minimumContactAttempts":2,"contactChannels":["IN_APP_CALL","PHONE_CALL"]}',
 '93900000-0000-4000-8000-000000000001','Acceptance closure local policy.'),
('93900000-0000-4000-8000-000000000011','observability.alert_thresholds','GLOBAL',
 '{"outboxPendingCount":10,"notificationPendingCount":10,"paymentReconciliationOpenCount":0,"riderEscalationOpenCount":0,"merchantUnreachableBranchCount":0,"customerUnreachableDueCount":0}',
 '93900000-0000-4000-8000-000000000001','Acceptance closure local alerts.'),
('93900000-0000-4000-8000-000000000012','settlement.payout_cadence','GLOBAL',
 '{"mode":"MANUAL_TEST"}',
 '93900000-0000-4000-8000-000000000001','Acceptance closure local payout cadence.'),
('93900000-0000-4000-8000-000000000013','merchant.reachability_stale_seconds','GLOBAL',
 '300','93900000-0000-4000-8000-000000000001',
 'Acceptance closure local merchant staleness.');

insert into dastak_v1.branch_operational_states(
  branch_id,is_open,accepting_orders,updated_by
) values (
  '93900000-0000-4000-8000-000000000022',true,true,
  '93900000-0000-4000-8000-000000000001'
);

select is(dastak_v1_api.customer_unreachable_policy()->>'waitSeconds','120',
  'valid customer-unreachable policy is consumed');
select is(dastak_v1_api.customer_unreachable_policy()->>'minimumContactAttempts','2',
  'contact attempt minimum is authoritative');
select is(jsonb_array_length(dastak_v1_api.customer_unreachable_policy()->'contactChannels'),2,
  'configured contact channels are preserved');
select is(dastak_v1_api.operational_alert_thresholds()->>'outboxPendingCount','10',
  'operational alert thresholds are consumed');
select is(dastak_v1_api.payout_cadence_policy()->>'mode','MANUAL_TEST',
  'payout cadence policy is consumed');
select is(dastak_v1_api.branch_is_reachable(
  '93900000-0000-4000-8000-000000000022',pg_catalog.statement_timestamp()
),true,'branch activity records an authoritative heartbeat');
select is(dastak_v1_api.branch_is_reachable(
  '93900000-0000-4000-8000-000000000023',pg_catalog.statement_timestamp()
),false,'a branch without a heartbeat is operationally unreachable');
select ok(dastak_v1.validate_setting_value('merchant.reachability_stale_seconds','300'),
  'merchant staleness validates as an integer duration');
select is(dastak_v1.validate_setting_value('merchant.reachability_stale_seconds','29'),false,
  'unsafe merchant staleness values are rejected');
select is(dastak_v1.validate_setting_value('delivery.customer_unreachable_policy','[]'),true,
  'generic storage accepts JSON while the runtime validator owns policy shape');

select * from finish();
rollback;
