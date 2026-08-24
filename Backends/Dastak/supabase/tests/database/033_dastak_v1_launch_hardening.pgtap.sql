begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('dastak_v1', 'notification_intents', 'durable notification intents exist');
select has_table('dastak_v1', 'notification_deliveries', 'durable device delivery attempts exist');
select has_table('dastak_v1', 'invariant_incidents', 'persistent invariant incidents exist');
select has_table('dastak_v1', 'invariant_monitor_runs', 'invariant monitor runs are recorded');

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'dastak_v1'
      and relation.relname in (
        'notification_routes', 'notification_intents', 'notification_deliveries',
        'invariant_definitions', 'invariant_monitor_runs',
        'invariant_incidents', 'invariant_incident_history'
      ) and relation.relrowsecurity
  ),
  7::bigint,
  'all Step 6 operational tables enforce RLS'
);
select is(
  has_table_privilege('authenticated', 'dastak_v1.notification_deliveries', 'SELECT'),
  false,
  'clients cannot inspect device delivery truth directly'
);
select is(
  has_function_privilege(
    'authenticated', 'public.dastak_v1_fanout_outbox(text,integer)', 'EXECUTE'
  ), false,
  'authenticated clients cannot claim the transactional outbox'
);
select is(
  has_function_privilege(
    'service_role', 'public.dastak_v1_fanout_outbox(text,integer)', 'EXECUTE'
  ), true,
  'only the service worker can fan out transactional events'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.dastak_v1_complete_notification_delivery(uuid,text,boolean,boolean,integer,text)',
    'EXECUTE'
  ), false,
  'clients cannot forge notification completion'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    '94000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'hardening-owner@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  ),
  (
    '94000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'hardening-customer@example.test', '',
    pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
  );
insert into public.accounts (id, display_name, phone_number) values
  ('94000000-0000-4000-8000-000000000001', 'Hardening Owner', '+919400000001'),
  ('94000000-0000-4000-8000-000000000002', 'Hardening Customer', '+919400000002');
insert into private.account_memberships (account_id, role, approved_at) values
  ('94000000-0000-4000-8000-000000000001', 'owner', pg_catalog.now()),
  ('94000000-0000-4000-8000-000000000002', 'customer', null);

select is(
  dastak_v1_api.actor_has_platform_permission(
    '94000000-0000-4000-8000-000000000001', 'platform.system_health.read'
  ), false,
  'an owner membership alone has no V1 platform permission'
);
insert into dastak_v1.platform_permission_grants (
  account_id, bundle_id, granted_by, grant_reason
) values (
  '94000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-00000000000c',
  '94000000-0000-4000-8000-000000000001',
  'Step 6 explicit super admin test grant.'
);
select is(
  dastak_v1_api.actor_has_platform_permission(
    '94000000-0000-4000-8000-000000000001', 'platform.system_health.read'
  ), true,
  'an explicit active bundle grants only recorded platform powers'
);

insert into dastak_v1.orders (
  id, display_order_number, customer_id, order_type, status,
  submitted_at, version
) values (
  '94000000-0000-4000-8000-000000000010', 'DV1-HARDENING',
  '94000000-0000-4000-8000-000000000002', 'RETAIL_ONLY',
  'MATCHING', pg_catalog.now(), 2
);
select public.dastak_v1_register_device_token(
  '94000000-0000-4000-8000-000000000002', 'hardening-device-a', 'ios'
);
select public.dastak_v1_register_device_token(
  '94000000-0000-4000-8000-000000000002', 'hardening-device-b', 'ios'
);
insert into dastak_v1.domain_events_outbox (
  event_key, aggregate_type, aggregate_id, aggregate_version,
  event_type, actor_id, payload
) values (
  '94000000-0000-4000-8000-000000000010:ORDER_SUBMITTED:2',
  'ORDER', '94000000-0000-4000-8000-000000000010', 2,
  'ORDER_SUBMITTED', '94000000-0000-4000-8000-000000000002',
  pg_catalog.jsonb_build_object(
    'orderId', '94000000-0000-4000-8000-000000000010'::uuid,
    'branchId', '94000000-0000-4000-8000-000000000099'::uuid,
    'merchantDisplayName', 'MUST NEVER LEAK'
  )
);

select is(
  public.dastak_v1_fanout_outbox('tap-worker-a', 10) ->> 'eventsPublished',
  '1',
  'worker atomically publishes a pending domain event after durable fan-out'
);
select is(
  public.dastak_v1_fanout_outbox('tap-worker-b', 10) ->> 'eventsPublished',
  '0',
  'a published event cannot be fanned out twice'
);
select is(
  (
    select pg_catalog.count(*)
    from dastak_v1.notification_intents intent
    where intent.recipient_account_id = '94000000-0000-4000-8000-000000000002'
  ),
  2::bigint,
  'event plus recipient plus notification type deduplicates once per supported platform'
);
select is(
  (
    select pg_catalog.count(*)
    from dastak_v1.notification_deliveries delivery
    where delivery.recipient_account_id = '94000000-0000-4000-8000-000000000002'
  ),
  2::bigint,
  'one durable delivery exists for each active customer device'
);
select ok(
  (
    select pg_catalog.bool_and(
      intent.payload ?& array['entityType', 'orderId', 'eventType']
      and not (intent.payload ?| array['branchId', 'merchantId', 'merchantDisplayName'])
    )
    from dastak_v1.notification_intents intent
    where intent.recipient_account_id = '94000000-0000-4000-8000-000000000002'
  ),
  'customer notification payload contains a safe V1 route and no merchant identity'
);

create temp table tap_hardening_jobs on commit drop as
select value as job
from pg_catalog.jsonb_array_elements(
  public.dastak_v1_claim_notification_deliveries('tap-worker-a', 10)
);
select is(
  (
    select pg_catalog.count(*)
    from tap_hardening_jobs
    where job ->> 'deviceToken' in ('hardening-device-a', 'hardening-device-b')
  ),
  2::bigint,
  'one worker claims every currently available device job'
);
select is(
  pg_catalog.jsonb_array_length(
    public.dastak_v1_claim_notification_deliveries('tap-worker-b', 10)
  ),
  0,
  'a competing worker cannot claim in-flight jobs'
);

create temp table tap_success_completion on commit drop as
select public.dastak_v1_complete_notification_delivery(
  (job ->> 'deliveryId')::uuid, 'tap-worker-a', true, false, 200, ''
) as body
from tap_hardening_jobs where job ->> 'deviceToken' = 'hardening-device-a';
select is(
  (select body ->> 'status' from tap_success_completion), 'SENT',
  'provider success durably marks one delivery Sent'
);
select is(
  (
    select public.dastak_v1_complete_notification_delivery(
      (job ->> 'deliveryId')::uuid, 'tap-worker-a', true, false, 200, ''
    ) ->> 'idempotentReplay'
    from tap_hardening_jobs where job ->> 'deviceToken' = 'hardening-device-a'
  ), 'true',
  'duplicate provider completion is an idempotent replay'
);
select is(
  (
    select public.dastak_v1_complete_notification_delivery(
      (job ->> 'deliveryId')::uuid, 'tap-worker-a', false, false, 503,
      '{"reason":"ServiceUnavailable"}'
    ) ->> 'status'
    from tap_hardening_jobs where job ->> 'deviceToken' = 'hardening-device-b'
  ), 'PENDING',
  'a transient provider failure releases the claim into configured backoff'
);
update dastak_v1.notification_deliveries delivery
set available_at = pg_catalog.clock_timestamp()
where delivery.status = 'PENDING';
create temp table tap_retry_jobs on commit drop as
select value as job
from pg_catalog.jsonb_array_elements(
  public.dastak_v1_claim_notification_deliveries('tap-worker-retry', 10)
);
select is(
  (
    select pg_catalog.count(*)
    from tap_retry_jobs
    where job ->> 'deviceToken' = 'hardening-device-b'
  ), 1::bigint,
  'a retry becomes exclusively claimable after its backoff'
);
select is(
  (
    select public.dastak_v1_complete_notification_delivery(
      (job ->> 'deliveryId')::uuid, 'tap-worker-retry', false, true, 410,
      '{"reason":"Unregistered"}'
    ) ->> 'status'
    from tap_retry_jobs where job ->> 'deviceToken' = 'hardening-device-b'
  ), 'DEAD_LETTER',
  'a permanent provider token failure is terminal and observable'
);
select ok(
  (
    select token.disabled_at is not null
    from public.dastak_device_tokens token
    where token.device_token = 'hardening-device-b'
  ),
  'invalid provider tokens are disabled without deleting delivery history'
);
select public.dastak_v1_register_device_token(
  '94000000-0000-4000-8000-000000000002', 'hardening-device-b', 'ios'
);
select ok(
  (
    select token.disabled_at is null and token.version = 3
    from public.dastak_device_tokens token
    where token.device_token = 'hardening-device-b'
  ),
  'a newly observed valid token explicitly reactivates with a version increment'
);

insert into dastak_v1.platform_settings (
  id, setting_key, scope_type, setting_value, updated_by, update_reason
) values
  (
    '94000000-0000-4000-8000-000000000040',
    'observability.outbox_stale_seconds', 'GLOBAL', '300',
    '94000000-0000-4000-8000-000000000001',
    'Launch-hardening local outbox threshold.'
  ),
  (
    '94000000-0000-4000-8000-000000000041',
    'observability.alert_thresholds', 'GLOBAL',
    '{"outboxPendingCount":100,"notificationPendingCount":100,"paymentReconciliationOpenCount":0,"riderEscalationOpenCount":0,"merchantUnreachableBranchCount":0,"customerUnreachableDueCount":0}',
    '94000000-0000-4000-8000-000000000001',
    'Launch-hardening local operational alert thresholds.'
  );

create temp table tap_monitor_run on commit drop as
select public.dastak_v1_run_invariant_monitors('tap-worker-a') as body;
select is(
  (select body ->> 'findingCount' from tap_monitor_run), '0',
  'the locked impossible-state monitors return zero for valid launch truth'
);
select is(
  (
    select pg_catalog.count(*)
    from dastak_v1.invariant_monitor_runs run
    where run.worker_id = 'tap-worker-a'
  ),
  1::bigint,
  'every invariant monitor execution is persisted'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub', '94000000-0000-4000-8000-000000000001', true
);
create temp table tap_system_health on commit drop as
select public.dastak_v1_admin_system_health() as body;
select ok(
  (select body from tap_system_health)
    ?& array['healthy', 'outbox', 'notifications', 'incidents', 'workerConfigured'],
  'explicitly authorized Operations receives the minimum health snapshot'
);
select is(
  (select body #>> '{outbox,staleThresholdSeconds}' from tap_system_health),
  '300',
  'system health applies the configured stale-outbox threshold'
);
select is(
  (select body ->> 'healthy' from tap_system_health),
  'false',
  'an unscheduled worker makes launch health fail closed'
);
reset role;
select is(
  (
    select pg_catalog.count(*) from dastak_v1.audit_events audit
    where audit.action = 'SYSTEM_HEALTH_READ'
      and audit.actor_id = '94000000-0000-4000-8000-000000000001'
  ), 1::bigint,
  'high-sensitivity health reads are audited'
);

select is(
  (
    select pg_catalog.count(*) from cron.job job
    where job.jobname = 'dastak-order-notification-worker'
  ), 0::bigint,
  'the unsafe legacy notification schedule is retired'
);

select * from finish();
rollback;
