begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select has_table(
  'private',
  'delivery_assignment_attempts',
  'private delivery assignment attempts exist'
);
select is(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'private.delivery_assignment_attempts'::regclass
  ),
  true,
  'delivery assignment attempts have RLS enabled'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_assignment_attempts', 'SELECT'),
  false,
  'authenticated cannot read assignment attempts directly'
);
select is(
  has_table_privilege('authenticated', 'private.delivery_assignment_attempts', 'UPDATE'),
  false,
  'authenticated cannot forge assignment responses directly'
);

select has_function(
  'public',
  'get_delivery_partner_dispatch_snapshot',
  array['uuid']
);
select has_function(
  'public',
  'accept_delivery_assignment',
  array['uuid', 'uuid', 'text', 'text']
);
select has_function(
  'public',
  'decline_delivery_assignment',
  array['uuid', 'uuid', 'text', 'text', 'text']
);
select has_function(
  'public',
  'advance_delivery_assignment',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text']
);
select hasnt_function(
  'public',
  'advance_delivery_assignment',
  array['uuid', 'uuid', 'text', 'text', 'text'],
  'the unverified courier lifecycle RPC no longer exists'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.accept_delivery_assignment(uuid,uuid,text,text)'::regprocedure
  ) ~ 'hashtextextended\s*\(\s*p_account_id::text\s*\|\|',
  'accept idempotency is serialized by account'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'public.decline_delivery_assignment(uuid,uuid,text,text,text)'::regprocedure
  ) ~ 'hashtextextended\s*\(\s*p_account_id::text\s*\|\|',
  'decline idempotency is serialized by account'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.accept_delivery_assignment(uuid,uuid,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass the courier dispatch Edge Function'
);
select is(
  has_function_privilege(
    'service_role',
    'public.accept_delivery_assignment(uuid,uuid,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can accept after bearer verification'
);
select is(
  has_function_privilege(
    'service_role',
    'public.decline_delivery_assignment(uuid,uuid,text,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can decline after bearer verification'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.advance_delivery_assignment(uuid,uuid,text,text,text,text)',
    'EXECUTE'
  ),
  false,
  'authenticated cannot bypass courier lifecycle verification'
);
select is(
  has_function_privilege(
    'service_role',
    'public.advance_delivery_assignment(uuid,uuid,text,text,text,text)',
    'EXECUTE'
  ),
  true,
  'service role can advance a verified partner job'
);
select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'dastak-courier-dispatch'
      and schedule = '10 seconds'
      and active = true
  ),
  'automatic dispatch cron runs every ten seconds'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
(
  '81000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'dispatch-owner@example.test', '',
  now(), now(), now()
),
(
  '81000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'dispatch-merchant@example.test', '',
  now(), now(), now()
),
(
  '81000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'dispatch-customer@example.test', '',
  now(), now(), now()
),
(
  '81000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'dispatch-near@example.test', '',
  now(), now(), now()
),
(
  '81000000-0000-4000-8000-000000000005',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'dispatch-far@example.test', '',
  now(), now(), now()
);

set local role service_role;

insert into public.accounts (id, display_name, phone_number) values
  ('81000000-0000-4000-8000-000000000001', 'Dispatch Owner', '+919100000001'),
  ('81000000-0000-4000-8000-000000000002', 'Dispatch Merchant', '+919100000002'),
  ('81000000-0000-4000-8000-000000000003', 'Dispatch Customer', '+919100000003'),
  ('81000000-0000-4000-8000-000000000004', 'Near Partner', '+919100000004'),
  ('81000000-0000-4000-8000-000000000005', 'Far Partner', '+919100000005');

insert into private.account_memberships (account_id, role, approved_at) values
  ('81000000-0000-4000-8000-000000000001', 'owner', now()),
  ('81000000-0000-4000-8000-000000000002', 'merchant', now()),
  ('81000000-0000-4000-8000-000000000003', 'customer', null),
  ('81000000-0000-4000-8000-000000000004', 'dastak_partner', now()),
  ('81000000-0000-4000-8000-000000000005', 'dastak_partner', now());

insert into public.service_zones (id, name, boundary, active) values (
  '81000000-0000-4000-8000-000000000010',
  'Courier Dispatch Test Zone',
  extensions.st_geomfromtext(
    'POLYGON((78.55 12.60,78.55 12.75,78.75 12.75,78.75 12.60,78.55 12.60))',
    4326
  ),
  true
);

insert into private.merchant_stores (
  id, merchant_account_id, service_zone_id, name, address, location,
  is_published, accepting_orders
) values (
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000010',
  'Dispatch Test Store',
  '1 Dispatch Road',
  extensions.st_setsrid(extensions.st_makepoint(78.6200, 12.6800), 4326),
  true,
  true
);

insert into private.delivery_partner_applications (
  id, account_id, delivery_method, identity_evidence_object_path,
  status, reviewed_at, reviewed_by
) values
(
  '81000000-0000-4000-8000-000000000041',
  '81000000-0000-4000-8000-000000000004',
  'bike',
  'dastak-partner/81000000-0000-4000-8000-000000000004/identity.pdf',
  'approved',
  now(),
  '81000000-0000-4000-8000-000000000001'
),
(
  '81000000-0000-4000-8000-000000000051',
  '81000000-0000-4000-8000-000000000005',
  'bicycle',
  'dastak-partner/81000000-0000-4000-8000-000000000005/identity.pdf',
  'approved',
  now(),
  '81000000-0000-4000-8000-000000000001'
);

insert into private.delivery_partner_profiles (
  account_id, approved_application_id, delivery_method
) values
  (
    '81000000-0000-4000-8000-000000000004',
    '81000000-0000-4000-8000-000000000041',
    'bike'
  ),
  (
    '81000000-0000-4000-8000-000000000005',
    '81000000-0000-4000-8000-000000000051',
    'bicycle'
  );

insert into private.delivery_partner_availability (
  account_id, status, location, service_zone_id, last_seen_at, available_until
) values
(
  '81000000-0000-4000-8000-000000000004',
  'online',
  extensions.st_setsrid(extensions.st_makepoint(78.6202, 12.6800), 4326),
  '81000000-0000-4000-8000-000000000010',
  now(),
  now() + interval '15 minutes'
),
(
  '81000000-0000-4000-8000-000000000005',
  'online',
  extensions.st_setsrid(extensions.st_makepoint(78.6500, 12.7000), 4326),
  '81000000-0000-4000-8000-000000000010',
  now(),
  now() + interval '15 minutes'
);

insert into private.merchant_order_rate_cards (
  id, service_zone_id, delivery_fee_paise, active
) values (
  '81000000-0000-4000-8000-000000000060',
  '81000000-0000-4000-8000-000000000010',
  4000,
  true
);

insert into private.merchant_order_quotes (
  id, customer_account_id, store_id, rate_card_id, rate_card_version,
  dropoff, item_subtotal_paise, delivery_fee_paise, total_paise, expires_at,
  consumed_at
) values
(
  '81000000-0000-4000-8000-000000000071',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000060',
  1,
  extensions.st_setsrid(extensions.st_makepoint(78.6300, 12.6900), 4326),
  10000, 4000, 14000,
  now() + interval '5 minutes',
  now()
),
(
  '81000000-0000-4000-8000-000000000072',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000060',
  1,
  extensions.st_setsrid(extensions.st_makepoint(78.6310, 12.6910), 4326),
  11000, 4000, 15000,
  now() + interval '5 minutes',
  now()
),
(
  '81000000-0000-4000-8000-000000000073',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000060',
  1,
  extensions.st_setsrid(extensions.st_makepoint(78.6320, 12.6920), 4326),
  12000, 4000, 16000,
  now() + interval '5 minutes',
  now()
);

insert into private.merchant_orders (
  id, customer_account_id, store_id, service_zone_id, quote_id,
  status, payment_state, dropoff, item_subtotal_paise,
  delivery_fee_paise, total_paise, accepted_at
) values
(
  '81000000-0000-4000-8000-000000000081',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000010',
  '81000000-0000-4000-8000-000000000071',
  'merchant_accepted', 'paid',
  extensions.st_setsrid(extensions.st_makepoint(78.6300, 12.6900), 4326),
  10000, 4000, 14000, now()
),
(
  '81000000-0000-4000-8000-000000000082',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000010',
  '81000000-0000-4000-8000-000000000072',
  'merchant_accepted', 'paid',
  extensions.st_setsrid(extensions.st_makepoint(78.6310, 12.6910), 4326),
  11000, 4000, 15000, now()
),
(
  '81000000-0000-4000-8000-000000000083',
  '81000000-0000-4000-8000-000000000003',
  '81000000-0000-4000-8000-000000000020',
  '81000000-0000-4000-8000-000000000010',
  '81000000-0000-4000-8000-000000000073',
  'merchant_accepted', 'paid',
  extensions.st_setsrid(extensions.st_makepoint(78.6320, 12.6920), 4326),
  12000, 4000, 16000, now()
);

update private.merchant_orders
set status = 'ready', ready_at = now(), state_version = state_version + 1
where id = '81000000-0000-4000-8000-000000000081';

select is(
  (
    select partner_account_id
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000081'
      and status = 'offered'
  ),
  '81000000-0000-4000-8000-000000000004'::uuid,
  'the closest eligible online partner receives the first offer'
);
select is(
  (
    select extract(epoch from (respond_by - offered_at))::integer
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000081'
      and status = 'offered'
  ),
  60,
  'the response window is exactly sixty seconds'
);
select is(
  (
    select response_body #>> '{offer,orderId}'
    from public.get_delivery_partner_dispatch_snapshot(
      '81000000-0000-4000-8000-000000000004'
    )
  ),
  '81000000-0000-4000-8000-000000000081',
  'partner snapshot exposes only the active offer'
);
select is(
  (
    select response_body #>> '{error,code}'
    from public.accept_delivery_assignment(
      '81000000-0000-4000-8000-000000000005',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000081'
      ),
      'foreign-assignment',
      'foreign-assignment-digest'
    )
  ),
  'assignment_not_found',
  'another partner cannot accept the offer'
);

update private.delivery_assignment_attempts
set offered_at = now() - interval '61 seconds',
    respond_by = now() - interval '1 second'
where order_id = '81000000-0000-4000-8000-000000000081'
  and partner_account_id = '81000000-0000-4000-8000-000000000004';

select private.process_courier_dispatch(
  '81000000-0000-4000-8000-000000000081'
);

select is(
  (
    select status
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000081'
      and partner_account_id = '81000000-0000-4000-8000-000000000004'
  ),
  'expired',
  'an unanswered offer expires'
);
select is(
  (
    select partner_account_id
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000081'
      and status = 'offered'
  ),
  '81000000-0000-4000-8000-000000000005'::uuid,
  'expiry automatically offers the order to the next partner'
);

select is(
  (
    select response_status
    from public.decline_delivery_assignment(
      '81000000-0000-4000-8000-000000000005',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000081'
          and status = 'offered'
      ),
      'Cannot reach the store',
      'decline-order-one',
      'decline-order-one-digest'
    )
  ),
  200,
  'the offered partner can decline'
);
select is(
  (
    select count(*)::integer
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000081'
      and status in ('offered', 'accepted')
  ),
  0,
  'an exhausted order stays ready without repeating a partner'
);

update private.merchant_orders
set status = 'ready', ready_at = now(), state_version = state_version + 1
where id = '81000000-0000-4000-8000-000000000082';

select is(
  (
    select partner_account_id
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000082'
      and status = 'offered'
  ),
  '81000000-0000-4000-8000-000000000004'::uuid,
  'a new order starts with the closest partner again'
);

select is(
  (
    select response_body #>> '{currentJob,orderId}'
    from public.accept_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'offered'
      ),
      'accept-order-two',
      'accept-order-two-digest'
    )
  ),
  '81000000-0000-4000-8000-000000000082',
  'accepting moves the offer into the current job snapshot'
);
select is(
  (
    select status
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  'assigned',
  'accepting updates the merchant order to assigned'
);
select is(
  (
    select response_body #>> '{currentJob,orderId}'
    from public.accept_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'accept-order-two',
      'accept-order-two-digest'
    )
  ),
  '81000000-0000-4000-8000-000000000082',
  'accept replay is idempotent'
);

create temporary table handoff_test_codes (
  purpose text primary key,
  code text not null
) on commit drop;

insert into handoff_test_codes (purpose, code)
select 'pickup', order_item #>> '{handoffCode,code}'
from pg_catalog.jsonb_array_elements(
  (
    select response_body -> 'orders'
    from public.get_merchant_orders(
      '81000000-0000-4000-8000-000000000002'
    )
  )
) as order_item
where order_item ->> 'orderId' = '81000000-0000-4000-8000-000000000082';

insert into handoff_test_codes (purpose, code)
select 'pickup_wrong', case when code = '0000' then '0001' else '0000' end
from handoff_test_codes
where purpose = 'pickup';

select matches(
  (select code from handoff_test_codes where purpose = 'pickup'),
  '^[0-9]{4}$',
  'the assigned order exposes a four-digit pickup code to its merchant'
);
select is(
  (
    select order_item -> 'handoffCode'
    from pg_catalog.jsonb_array_elements(
      (
        select response_body -> 'orders'
        from public.get_customer_orders(
          '81000000-0000-4000-8000-000000000003'
        )
      )
    ) as order_item
    where order_item ->> 'orderId' = '81000000-0000-4000-8000-000000000082'
  ),
  'null'::jsonb,
  'the customer cannot see the merchant pickup code'
);
select ok(
  (
    select response_body::text not like '%handoffCode%'
    from public.get_delivery_partner_dispatch_snapshot(
      '81000000-0000-4000-8000-000000000004'
    )
  ),
  'the delivery partner snapshot never reveals a handoff code'
);
select ok(
  (
    select pickup_code_digest is not null
      and pickup_code_expires_at between
        pg_catalog.now() + interval '5 hours 59 minutes'
        and pg_catalog.now() + interval '6 hours 1 minute'
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  'the pickup code is stored only as a digest with a six-hour expiry'
);

update private.merchant_orders
set status = 'ready', ready_at = now(), state_version = state_version + 1
where id = '81000000-0000-4000-8000-000000000083';

select is(
  (
    select partner_account_id
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000083'
      and status = 'offered'
  ),
  '81000000-0000-4000-8000-000000000005'::uuid,
  'a partner with a current job cannot receive another offer'
);
select is(
  (
    select count(*)::integer
    from private.delivery_assignment_attempts
    where partner_account_id = '81000000-0000-4000-8000-000000000004'
      and status in ('offered', 'accepted')
  ),
  1,
  'each partner has at most one active offer or job'
);

update private.account_memberships
set suspended_until = now() + interval '1 hour'
where account_id = '81000000-0000-4000-8000-000000000005'
  and role = 'dastak_partner';

select private.process_courier_dispatch(
  '81000000-0000-4000-8000-000000000083'
);

select is(
  (
    select status
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000083'
  ),
  'expired',
  'suspension immediately invalidates an unanswered offer'
);
select is(
  (
    select response_body -> 'offer'
    from public.get_delivery_partner_dispatch_snapshot(
      '81000000-0000-4000-8000-000000000005'
    )
  ),
  'null'::jsonb,
  'a suspended partner has no visible offer'
);

select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'skip-to-pickup',
      'skip-to-pickup-digest',
      null
    )
  ),
  409,
  'a partner cannot skip an assigned job directly to pickup'
);

select is(
  (
    select response_body #>> '{currentJob,orderStatus}'
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'start_to_store',
      'start-to-store',
      'start-to-store-digest',
      null
    )
  ),
  'en_route_to_pickup',
  'the assigned partner can start travelling to the store'
);

select is(
  (
    select response_body #>> '{currentJob,orderStatus}'
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'arrive_at_store',
      'arrive-at-store',
      'arrive-at-store-digest',
      null
    )
  ),
  'at_store',
  'the partner can mark arrival at the store only after travelling'
);

select is(
  (
    select order_item ->> 'status'
    from pg_catalog.jsonb_array_elements(
      (
        select response_body -> 'orders'
        from public.get_customer_orders(
          '81000000-0000-4000-8000-000000000003'
        )
      )
    ) as order_item
    where order_item ->> 'orderId' = '81000000-0000-4000-8000-000000000082'
  ),
  'at_store',
  'the customer snapshot sees the partner at the store'
);
select is(
  (
    select order_item ->> 'status'
    from pg_catalog.jsonb_array_elements(
      (
        select response_body -> 'orders'
        from public.get_merchant_orders(
          '81000000-0000-4000-8000-000000000002'
        )
      )
    ) as order_item
    where order_item ->> 'orderId' = '81000000-0000-4000-8000-000000000082'
  ),
  'at_store',
  'the merchant snapshot sees the partner at the store'
);
select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'wrong-pickup-one',
      'wrong-pickup-one-digest',
      (select code from handoff_test_codes where purpose = 'pickup_wrong')
    )
  ),
  422,
  'an incorrect pickup code is rejected'
);
select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'wrong-pickup-one',
      'wrong-pickup-one-digest',
      (select code from handoff_test_codes where purpose = 'pickup_wrong')
    )
  ),
  422,
  'an incorrect-code retry is idempotent'
);
select is(
  (
    select pickup_code_failed_attempts
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  1,
  'an idempotent retry consumes only one attempt'
);
select is(
  (
    select pg_catalog.array_agg(result.response_status order by result.response_status)
    from (values (2), (3), (4), (5)) as attempt(number)
    cross join lateral public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'wrong-pickup-' || attempt.number,
      'wrong-pickup-digest-' || attempt.number,
      (select code from handoff_test_codes where purpose = 'pickup_wrong')
    ) as result
  ),
  array[422, 422, 422, 423],
  'five incorrect pickup attempts lock verification'
);
select ok(
  (
    select pickup_code_failed_attempts = 5 and pickup_code_locked_at is not null
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  'pickup verification records the attempt limit and lock time'
);
select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'locked-pickup-valid',
      'locked-pickup-valid-digest',
      (select code from handoff_test_codes where purpose = 'pickup')
    )
  ),
  423,
  'the correct pickup code cannot bypass a verification lock'
);

update private.merchant_orders
set pickup_code_failed_attempts = 0,
    pickup_code_locked_at = null,
    pickup_code_expires_at = pg_catalog.now() - interval '1 second'
where id = '81000000-0000-4000-8000-000000000082';

select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'expired-pickup-valid',
      'expired-pickup-valid-digest',
      (select code from handoff_test_codes where purpose = 'pickup')
    )
  ),
  410,
  'an expired pickup code cannot authorize collection'
);

update private.merchant_orders
set pickup_code_expires_at = pg_catalog.now() + interval '6 hours'
where id = '81000000-0000-4000-8000-000000000082';

select is(
  (
    select response_status
    from public.customer_cancel_order(
      '81000000-0000-4000-8000-000000000003',
      '81000000-0000-4000-8000-000000000082',
      'Need owner review while courier is at the store',
      'cancel-at-store',
      'cancel-at-store-digest'
    )
  ),
  202,
  'customer cancellation at the store remains an owner-review request'
);

select is(
  (
    select response_body #>> '{currentJob,orderStatus}'
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'confirm_pickup',
      'confirm-pickup',
      'confirm-pickup-digest',
      (
        select code from handoff_test_codes where purpose = 'pickup'
      )
    )
  ),
  'picked_up',
  'the partner confirms collection only after arriving at the store'
);

insert into handoff_test_codes (purpose, code)
select 'delivery', order_item #>> '{handoffCode,code}'
from pg_catalog.jsonb_array_elements(
  (
    select response_body -> 'orders'
    from public.get_customer_orders(
      '81000000-0000-4000-8000-000000000003'
    )
  )
) as order_item
where order_item ->> 'orderId' = '81000000-0000-4000-8000-000000000082';

insert into handoff_test_codes (purpose, code)
select 'delivery_wrong', case when code = '0000' then '0001' else '0000' end
from handoff_test_codes
where purpose = 'delivery';

select matches(
  (select code from handoff_test_codes where purpose = 'delivery'),
  '^[0-9]{4}$',
  'the collected order exposes a four-digit delivery code to its customer'
);
select is(
  (
    select order_item -> 'handoffCode'
    from pg_catalog.jsonb_array_elements(
      (
        select response_body -> 'orders'
        from public.get_merchant_orders(
          '81000000-0000-4000-8000-000000000002'
        )
      )
    ) as order_item
    where order_item ->> 'orderId' = '81000000-0000-4000-8000-000000000082'
  ),
  'null'::jsonb,
  'the merchant cannot see the customer delivery code'
);
select ok(
  (
    select delivery_code_digest is not null
      and delivery_code_expires_at between
        pg_catalog.now() + interval '5 hours 59 minutes'
        and pg_catalog.now() + interval '6 hours 1 minute'
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  'the delivery code is stored only as a digest with a six-hour expiry'
);

select is(
  (
    select response_body #>> '{currentJob,orderStatus}'
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'start_delivery',
      'start-delivery',
      'start-delivery-digest',
      null
    )
  ),
  'in_transit',
  'the collected order can start travelling to the customer'
);

select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'complete_delivery',
      'wrong-delivery-one',
      'wrong-delivery-one-digest',
      (select code from handoff_test_codes where purpose = 'delivery_wrong')
    )
  ),
  422,
  'an incorrect delivery code cannot complete the order'
);

select is(
  (
    select response_body -> 'currentJob'
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'accepted'
      ),
      'complete_delivery',
      'complete-delivery',
      'complete-delivery-digest',
      (
        select code from handoff_test_codes where purpose = 'delivery'
      )
    )
  ),
  'null'::jsonb,
  'delivery completion clears the partner current job'
);
select is(
  (
    select status
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  'delivered',
  'delivery completion updates the shared order status'
);
select is(
  (
    select status
    from private.delivery_assignment_attempts
    where order_id = '81000000-0000-4000-8000-000000000082'
  ),
  'completed',
  'delivery completion closes the accepted assignment'
);
select ok(
  (
    select assigned_at is not null
      and en_route_to_pickup_at is not null
      and arrived_at_store_at is not null
      and picked_up_at is not null
      and in_transit_at is not null
      and delivered_at is not null
    from private.merchant_orders
    where id = '81000000-0000-4000-8000-000000000082'
  ),
  'every courier lifecycle milestone is timestamped'
);
select is(
  (
    select response_status
    from public.advance_delivery_assignment(
      '81000000-0000-4000-8000-000000000004',
      (
        select id
        from private.delivery_assignment_attempts
        where order_id = '81000000-0000-4000-8000-000000000082'
          and status = 'completed'
      ),
      'complete_delivery',
      'complete-delivery',
      'complete-delivery-digest',
      (
        select code from handoff_test_codes where purpose = 'delivery'
      )
    )
  ),
  200,
  'delivery completion replays idempotently'
);

reset role;

select ok(
  exists (
    select 1 from audit.events where action = 'delivery_assignment_offered'
  ),
  'offers are audited'
);
select ok(
  exists (
    select 1 from audit.events where action = 'delivery_assignment_accepted'
  ),
  'acceptance is audited'
);
select ok(
  exists (
    select 1 from audit.events where action = 'delivery_assignment_declined'
  ),
  'declines are audited'
);
select ok(
  exists (
    select 1 from audit.events where action = 'delivery_assignment_expired'
  ),
  'expiry is audited'
);
select is(
  (
    select count(distinct action)::integer
    from audit.events
    where action in (
      'delivery_job_started_to_store',
      'delivery_job_arrived_at_store',
      'delivery_job_pickup_confirmed',
      'delivery_job_started_delivery',
      'delivery_job_completed'
    )
  ),
  5,
  'every courier lifecycle transition is audited'
);
select ok(
  (
    select count(*) >= 6
    from audit.events
    where action = 'delivery_handoff_code_rejected'
  ),
  'rejected handoff attempts are audited without recording the submitted code'
);

select * from finish();
rollback;
