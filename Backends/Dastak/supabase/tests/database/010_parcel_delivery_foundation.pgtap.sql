begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table('private', 'parcel_rate_cards', 'private parcel rates exist');
select has_table('private', 'parcel_quotes', 'private parcel quotes exist');
select has_table('private', 'parcel_deliveries', 'private parcel deliveries exist');
select has_table(
  'private', 'parcel_assignment_attempts', 'private parcel assignment attempts exist'
);
select has_table('private', 'parcel_payment_events', 'private parcel payment events exist');
select has_table(
  'private', 'parcel_partner_reliability_reviews',
  'private parcel reliability reviews exist'
);
select hasnt_column(
  'private', 'parcel_deliveries', 'pickup_code',
  'raw pickup codes are never stored'
);
select hasnt_column(
  'private', 'parcel_deliveries', 'delivery_code',
  'raw delivery codes are never stored'
);

select is(
  has_table_privilege('authenticated', 'private.parcel_deliveries', 'SELECT'),
  false,
  'authenticated users cannot read parcel rows directly'
);
select is(
  has_table_privilege('authenticated', 'private.parcel_deliveries', 'UPDATE'),
  false,
  'authenticated users cannot forge parcel transitions'
);
select is(
  has_table_privilege('authenticated', 'private.parcel_payment_events', 'INSERT'),
  false,
  'authenticated users cannot forge payment confirmation'
);

select has_function(
  'public', 'quote_parcel_delivery',
  array[
    'uuid', 'text', 'double precision', 'double precision', 'text',
    'double precision', 'double precision', 'text', 'integer', 'integer',
    'text', 'text'
  ]
);
select has_function(
  'public', 'create_parcel_delivery',
  array['uuid', 'uuid', 'text', 'text', 'text', 'integer', 'text', 'text']
);
select has_function(
  'public', 'record_parcel_payment_event',
  array['text', 'text', 'uuid', 'text', 'integer', 'timestamp with time zone', 'text']
);
select has_function(
  'public', 'advance_parcel_delivery',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text']
);
select is(
  has_function_privilege(
    'authenticated',
    'public.record_parcel_payment_event(text,text,uuid,text,integer,timestamp with time zone,text)',
    'EXECUTE'
  ),
  false,
  'authenticated users cannot confirm parcel payment'
);
select is(
  has_function_privilege(
    'service_role',
    'public.record_parcel_payment_event(text,text,uuid,text,integer,timestamp with time zone,text)',
    'EXECUTE'
  ),
  true,
  'verified provider processing can confirm parcel payment'
);
select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'dastak-parcel-dispatch'
      and schedule = '10 seconds'
      and active = true
  ),
  'parcel dispatch and reassignment run automatically'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '91000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'parcel-owner@example.test', '',
  now(), now(), now()
),
(
  '91000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'parcel-customer@example.test', '',
  now(), now(), now()
),
(
  '91000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'parcel-recipient@example.test', '',
  now(), now(), now()
),
(
  '91000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'parcel-near@example.test', '',
  now(), now(), now()
),
(
  '91000000-0000-4000-8000-000000000005',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'parcel-far@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('91000000-0000-4000-8000-000000000001', 'Parcel Owner', '+919200000001'),
  ('91000000-0000-4000-8000-000000000002', 'Parcel Customer', '+919200000002'),
  ('91000000-0000-4000-8000-000000000003', 'Parcel Recipient', '+919200000003'),
  ('91000000-0000-4000-8000-000000000004', 'Near Parcel Partner', '+919200000004'),
  ('91000000-0000-4000-8000-000000000005', 'Far Parcel Partner', '+919200000005');

insert into private.account_memberships (account_id, role, approved_at) values
  ('91000000-0000-4000-8000-000000000001', 'owner', now()),
  ('91000000-0000-4000-8000-000000000002', 'customer', null),
  ('91000000-0000-4000-8000-000000000003', 'customer', null),
  ('91000000-0000-4000-8000-000000000004', 'dastak_partner', now()),
  ('91000000-0000-4000-8000-000000000005', 'dastak_partner', now());

insert into public.service_zones (id, name, boundary, active) values (
  '91000000-0000-4000-8000-000000000010',
  'Parcel Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.55 12.60,78.55 12.75,78.75 12.75,78.75 12.60,78.55 12.60))',
    4326
  ),
  true
);

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by
) values
(
  '91000000-0000-4000-8000-000000000041',
  '91000000-0000-4000-8000-000000000004',
  'bike',
  'dastak-partner/91000000-0000-4000-8000-000000000004/identity.pdf',
  'approved', now(), '91000000-0000-4000-8000-000000000001'
),
(
  '91000000-0000-4000-8000-000000000051',
  '91000000-0000-4000-8000-000000000005',
  'bike',
  'dastak-partner/91000000-0000-4000-8000-000000000005/identity.pdf',
  'approved', now(), '91000000-0000-4000-8000-000000000001'
);

insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values
(
  '91000000-0000-4000-8000-000000000004',
  '91000000-0000-4000-8000-000000000041',
  'bike'
),
(
  '91000000-0000-4000-8000-000000000005',
  '91000000-0000-4000-8000-000000000051',
  'bike'
);

insert into private.delivery_partner_availability (
  account_id, status, location, service_zone_id, last_seen_at, available_until
) values
(
  '91000000-0000-4000-8000-000000000004',
  'online',
  extensions.st_setsrid(extensions.st_makepoint(78.6201, 12.6801), 4326),
  '91000000-0000-4000-8000-000000000010',
  now(), now() + interval '15 minutes'
),
(
  '91000000-0000-4000-8000-000000000005',
  'online',
  extensions.st_setsrid(extensions.st_makepoint(78.7000, 12.7000), 4326),
  '91000000-0000-4000-8000-000000000010',
  now(), now() + interval '15 minutes'
);

select is(
  (
    select response_status
    from public.upsert_parcel_rate_card(
      '91000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000010',
      'bike', 2500, 1000, 8000, true,
      'parcel-rate-1', 'parcel-rate-digest-1'
    )
  ),
  200,
  'owner can configure a versioned parcel rate'
);

create temporary table parcel_test_state (
  name text primary key,
  body jsonb not null
) on commit drop;

insert into parcel_test_state (name, body)
select 'quote-1', response_body
from public.quote_parcel_delivery(
  '91000000-0000-4000-8000-000000000002',
  'bike',
  12.6800, 78.6200, '1 Pickup Road',
  12.6900, 78.6400, '2 Drop Road',
  2300, 600,
  'parcel-quote-1', 'parcel-quote-digest-1'
);

select is(
  (select (body #>> '{deliveryFee,paise}')::integer from parcel_test_state where name = 'quote-1'),
  3000,
  'quote uses ceil(server route kilometres) and the active rate'
);
select is(
  (select (body ->> 'routeDistanceMeters')::integer from parcel_test_state where name = 'quote-1'),
  2300,
  'quote snapshots the server route distance'
);

insert into parcel_test_state (name, body)
select 'parcel-1', response_body
from public.create_parcel_delivery(
  '91000000-0000-4000-8000-000000000002',
  (select (body ->> 'quoteId')::uuid from parcel_test_state where name = 'quote-1'),
  '+919200000003', 'Parcel Recipient', 'Sealed documents', 5000,
  'parcel-create-1', 'parcel-create-digest-1'
);

select is(
  (select body ->> 'status' from parcel_test_state where name = 'parcel-1'),
  'payment_pending',
  'parcel waits for provider-confirmed payment'
);
select is(
  (select body ->> 'handoffCode' from parcel_test_state where name = 'parcel-1'),
  null,
  'no handoff code is exposed before payment and assignment'
);

select is(
  (
    select response_status
    from public.record_parcel_payment_event(
      'razorpay', 'parcel-capture-1',
      (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'),
      'payment_captured', 3000, now(), 'provider-payload-digest-1'
    )
  ),
  200,
  'provider-confirmed payment activates dispatch'
);

select is(
  (
    select status
    from private.parcel_deliveries
    where id = (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1')
  ),
  'assigned',
  'paid parcel is automatically assigned'
);
select is(
  (
    select partner_account_id
    from private.parcel_assignment_attempts
    where parcel_id = (
      select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'
    ) and status = 'offered'
  ),
  '91000000-0000-4000-8000-000000000004'::uuid,
  'nearest fresh eligible partner receives the assignment'
);
select ok(
  (
    select respond_by between now() + interval '50 seconds' and now() + interval '70 seconds'
    from private.parcel_assignment_attempts
    where parcel_id = (
      select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'
    ) and status = 'offered'
  ),
  'partner has a sixty-second acknowledgement window'
);

insert into parcel_test_state (name, body)
select 'assignment-1', private.parcel_assignment_json(assignment)
from private.parcel_assignment_attempts as assignment
where assignment.parcel_id = (
  select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'
) and assignment.status = 'offered';

select is(
  (
    select response_status
    from public.acknowledge_parcel_assignment(
      '91000000-0000-4000-8000-000000000004',
      (select (body ->> 'assignmentId')::uuid from parcel_test_state where name = 'assignment-1'),
      'parcel-ack-1', 'parcel-ack-digest-1'
    )
  ),
  200,
  'assigned partner acknowledges the automatic assignment'
);
select is(
  (
    select response_status
    from public.advance_parcel_delivery(
      '91000000-0000-4000-8000-000000000004',
      (select (body ->> 'assignmentId')::uuid from parcel_test_state where name = 'assignment-1'),
      'start_to_pickup', null,
      'parcel-start-1', 'parcel-start-digest-1'
    )
  ),
  200,
  'partner starts toward pickup'
);

select is(
  (
    select response_status
    from public.advance_parcel_delivery(
      '91000000-0000-4000-8000-000000000004',
      (select (body ->> 'assignmentId')::uuid from parcel_test_state where name = 'assignment-1'),
      'confirm_pickup', '000000',
      'parcel-wrong-pickup-1', 'parcel-wrong-pickup-digest-1'
    )
  ),
  422,
  'wrong pickup code is rejected'
);
select is(
  (
    select status
    from private.parcel_deliveries
    where id = (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1')
  ),
  'en_route_to_pickup',
  'wrong pickup code cannot advance the parcel'
);

select is(
  (
    select response_status
    from public.advance_parcel_delivery(
      '91000000-0000-4000-8000-000000000004',
      (select (body ->> 'assignmentId')::uuid from parcel_test_state where name = 'assignment-1'),
      'confirm_pickup',
      private.parcel_handoff_code(
        (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'),
        'pickup'
      ),
      'parcel-pickup-1', 'parcel-pickup-digest-1'
    )
  ),
  200,
  'correct sender pickup code records handoff'
);
select is(
  (
    select response_status
    from public.advance_parcel_delivery(
      '91000000-0000-4000-8000-000000000004',
      (select (body ->> 'assignmentId')::uuid from parcel_test_state where name = 'assignment-1'),
      'start_delivery', null,
      'parcel-transit-1', 'parcel-transit-digest-1'
    )
  ),
  200,
  'picked-up parcel enters transit explicitly'
);

select is(
  (
    select response_body #>> '{handoffCode,code}'
    from public.get_parcel_delivery_snapshot(
      '91000000-0000-4000-8000-000000000003',
      (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1')
    )
  ),
  private.parcel_handoff_code(
    (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'),
    'delivery'
  ),
  'only the recipient snapshot receives the delivery code in transit'
);

select is(
  (
    select response_status
    from public.advance_parcel_delivery(
      '91000000-0000-4000-8000-000000000004',
      (select (body ->> 'assignmentId')::uuid from parcel_test_state where name = 'assignment-1'),
      'complete_delivery',
      private.parcel_handoff_code(
        (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'),
        'delivery'
      ),
      'parcel-deliver-1', 'parcel-deliver-digest-1'
    )
  ),
  200,
  'recipient code completes delivery'
);
select is(
  (
    select status
    from private.parcel_deliveries
    where id = (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1')
  ),
  'delivered',
  'parcel reaches the terminal delivered state'
);

select is(
  (
    select response_status
    from public.report_parcel_safety_incident(
      '91000000-0000-4000-8000-000000000002',
      (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1'),
      'unsafe_handoff', 'The handoff location was unsafe.',
      'parcel-safety-1', 'parcel-safety-digest-1'
    )
  ),
  200,
  'a participant can persist a recent parcel safety incident'
);
select is(
  (
    select count(*)::integer
    from private.safety_cases
    where job_id = (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-1')
  ),
  1,
  'safety report is durable without claiming live response'
);

insert into parcel_test_state (name, body)
select 'quote-2', response_body
from public.quote_parcel_delivery(
  '91000000-0000-4000-8000-000000000002',
  'bike',
  12.6800, 78.6200, '1 Pickup Road',
  12.6900, 78.6400, '2 Drop Road',
  2300, 600,
  'parcel-quote-2', 'parcel-quote-digest-2'
);

insert into parcel_test_state (name, body)
select 'parcel-2', response_body
from public.create_parcel_delivery(
  '91000000-0000-4000-8000-000000000002',
  (select (body ->> 'quoteId')::uuid from parcel_test_state where name = 'quote-2'),
  '+919200000003', 'Parcel Recipient', 'Second sealed parcel', 1000,
  'parcel-create-2', 'parcel-create-digest-2'
);

select is(
  (
    select response_status
    from public.record_parcel_payment_event(
      'razorpay', 'parcel-capture-2',
      (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'),
      'payment_captured', 3000, now(), 'provider-payload-digest-2'
    )
  ),
  200,
  'second prepaid parcel enters automatic dispatch'
);

update private.parcel_assignment_attempts as assignment
set offered_at = pg_catalog.now() - interval '2 seconds',
    respond_by = pg_catalog.now() - interval '1 second'
where assignment.parcel_id = (
  select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'
) and assignment.partner_account_id = '91000000-0000-4000-8000-000000000004'
  and assignment.status = 'offered';

do $$
begin
  perform private.process_parcel_dispatch(
    (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'),
    '91000000-0000-4000-8000-000000000010'
  );
end;
$$;

select is(
  (
    select status
    from private.parcel_assignment_attempts
    where parcel_id = (
      select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'
    ) and partner_account_id = '91000000-0000-4000-8000-000000000004'
  ),
  'expired',
  'unacknowledged assignment expires'
);
select is(
  (
    select partner_account_id
    from private.parcel_assignment_attempts
    where parcel_id = (
      select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'
    ) and status = 'offered'
  ),
  '91000000-0000-4000-8000-000000000005'::uuid,
  'expired parcel is reassigned to the next nearest eligible partner'
);

select is(
  (
    select response_status
    from public.cancel_parcel_delivery(
      '91000000-0000-4000-8000-000000000002',
      (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'),
      'Sender cancelled before pickup.',
      'parcel-cancel-2', 'parcel-cancel-digest-2'
    )
  ),
  200,
  'customer can cancel before pickup'
);
select is(
  (
    select payment_status || ':' || refund_status
    from private.parcel_deliveries
    where id = (select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2')
  ),
  'refund_pending:pending',
  'pre-pickup paid cancellation requests a full delivery-fee refund'
);
select is(
  (
    select status || ':' || response_reason
    from private.parcel_assignment_attempts
    where parcel_id = (
      select (body ->> 'parcelId')::uuid from parcel_test_state where name = 'parcel-2'
    ) and partner_account_id = '91000000-0000-4000-8000-000000000005'
  ),
  'cancelled:customer_cancelled',
  'customer cancellation closes the reassigned offer explicitly'
);
select is(
  exists (
    select 1
    from private.parcel_partner_reliability_reviews
    where account_id = '91000000-0000-4000-8000-000000000005'
  ),
  false,
  'customer cancellation does not count as a partner miss'
);

do $$
begin
  perform private.record_parcel_assignment_miss(
    '91000000-0000-4000-8000-000000000005'
  );
  perform private.record_parcel_assignment_miss(
    '91000000-0000-4000-8000-000000000005'
  );
  perform private.record_parcel_assignment_miss(
    '91000000-0000-4000-8000-000000000005'
  );
end;
$$;
select ok(
  (
    select membership.suspended_until >= now() + interval '29 minutes'
    from private.account_memberships as membership
    where membership.account_id = '91000000-0000-4000-8000-000000000005'
      and membership.role = 'dastak_partner'
  ),
  'three assignment misses force a thirty-minute suspension'
);
do $$
begin
  perform private.record_parcel_assignment_miss(
    '91000000-0000-4000-8000-000000000005'
  );
  perform private.record_parcel_assignment_miss(
    '91000000-0000-4000-8000-000000000005'
  );
end;
$$;
select is(
  (
    select owner_review_required
    from private.parcel_partner_reliability_reviews
    where account_id = '91000000-0000-4000-8000-000000000005'
  ),
  true,
  'five misses in seven days require owner review'
);

select * from finish();
rollback;
