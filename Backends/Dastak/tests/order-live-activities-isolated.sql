-- Isolated PostgreSQL fixture only. Run against a new empty local database.
\set ON_ERROR_STOP on
do $$ begin
  if not exists(select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists(select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;
create schema dastak_v1;
create schema dastak_v1_api;
create schema auth;
create schema private;
create table public.accounts(id uuid primary key);
create table auth.sessions(id uuid primary key, user_id uuid);
create table private.account_memberships(account_id uuid, role text, suspended_until timestamptz);
create table private.revoked_account_sessions(session_id uuid primary key, account_id uuid);
create table dastak_v1.orders(id uuid primary key, customer_id uuid, status text, version bigint, updated_at timestamptz);
create table dastak_v1.delivery_missions(order_id uuid, assigned_rider_id uuid, status text, updated_at timestamptz, created_at timestamptz);
create table dastak_v1.notification_routes(event_type text, audience text, notification_type text,
  platform text, title text, body text, enabled boolean default true, version bigint default 1,
  primary key(event_type,audience,notification_type));
create table dastak_v1.fulfilments(id uuid primary key, order_id uuid, status text);
create table dastak_v1.domain_events_outbox(event_key text primary key, aggregate_type text,
  aggregate_id uuid, aggregate_version bigint, event_type text, payload jsonb);
create table dastak_v1.verification_handoffs(order_id uuid, handoff_type text, created_at timestamptz, pin_verified_at timestamptz);
create function auth.role() returns text language sql as $$ select current_setting('role',true) $$;
create function dastak_v1_api.assert_authenticated_actor(uuid) returns void language plpgsql as $$ begin raise exception 'Fixture actor denied' using errcode='42501'; end $$;
create function dastak_v1_api.delivery_tracking_json(uuid) returns jsonb language sql as $$ select null::jsonb $$;
create function dastak_v1_api.order_json_pre_tracking(p_order_id uuid,p_customer_id uuid) returns jsonb language sql as $$
  select jsonb_build_object('status',o.status,'fulfilmentProgress',jsonb_build_object('state','PREPARING','estimatedReadyAt','sample'))
    from dastak_v1.orders o where o.id=p_order_id and o.customer_id=p_customer_id;
$$;
create function dastak_v1_api.order_json(uuid,uuid) returns jsonb language sql as $$ select null::jsonb $$;
revoke all on function dastak_v1_api.order_json(uuid,uuid) from public,anon,authenticated;
\ir ../supabase/migrations/20261014111434_customer_order_live_activities.sql
\ir ../supabase/migrations/20261014121929_live_activity_rider_arrival.sql
\ir ../supabase/migrations/20261014192213_live_activity_assigning_rider.sql
\ir ../supabase/migrations/20261014195708_preserve_preparation_before_rider_assignment.sql
insert into public.accounts values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222');
insert into auth.sessions values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111');
insert into private.account_memberships values ('11111111-1111-1111-1111-111111111111','customer',null);
insert into dastak_v1.orders values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','11111111-1111-1111-1111-111111111111','PREPARING',3,now()),
 ('cccccccc-cccc-cccc-cccc-cccccccccccc','22222222-2222-2222-2222-222222222222','PREPARING',1,now());
insert into dastak_v1.fulfilments values
 ('dddddddd-dddd-dddd-dddd-dddddddddddd','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','PREPARING'),
 ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','PREPARING');
do $$
declare jobs jsonb; job jsonb; next_jobs jsonb; v_id uuid;
begin
  if has_function_privilege('authenticated','public.dastak_claim_order_live_activities()','execute')
    or has_table_privilege('authenticated','dastak_v1.order_live_activities','select') then
    raise exception 'Client may access private tracking tokens';
  end if;
  begin
    perform public.dastak_register_order_live_activity('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'cccccccc-cccc-cccc-cccc-cccccccccccc','wrong',repeat('a',64),'sandbox');
    raise exception 'Accepted other customers order';
  exception when insufficient_privilege then null; end;
  perform public.dastak_register_order_live_activity('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','sample',repeat('a',64),'sandbox');
  jobs := public.dastak_claim_order_live_activities(); job := jobs->0;
  if jsonb_array_length(jobs) <> 1 or job->>'status' <> 'PREPARING' then raise exception 'Preparation was skipped'; end if;
  if public.dastak_claim_order_live_activities() <> '[]'::jsonb then raise exception 'Duplicate lease'; end if;
  -- Rotate while an older push is in flight; its completion may not retire the new token.
  perform public.dastak_register_order_live_activity('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','sample',repeat('b',64),'sandbox');
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,1,'PREPARING',true,true);
  if exists(select 1 from dastak_v1.order_live_activities where ended_at is not null) then raise exception 'Stale token completion won'; end if;
  job := public.dastak_claim_order_live_activities()->0;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'PREPARING',true,false);
  if public.dastak_claim_order_live_activities() <> '[]'::jsonb then raise exception 'Unchanged state spam'; end if;
  update dastak_v1.fulfilments set status='READY' where id='dddddddd-dddd-dddd-dddd-dddddddddddd';
  set constraints all immediate;
  if dastak_v1_api.order_waiting_for_rider('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
    or exists(select 1 from dastak_v1.domain_events_outbox) then raise exception 'Partial preparation incorrectly assigning'; end if;
  update dastak_v1.fulfilments set status='READY' where id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'ASSIGNING_RIDER' then raise exception 'Ready order did not enter assignment'; end if;
  if (select count(*) from dastak_v1.domain_events_outbox where event_type='RIDER_ASSIGNMENT_PENDING') <> 1 then raise exception 'Missing or duplicated Ready notification'; end if;
  if dastak_v1_api.order_json('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','11111111-1111-1111-1111-111111111111') #>> '{fulfilmentProgress,state}' <> 'ASSIGNING_RIDER'
    then raise exception 'Order UI projection disagrees with background activity'; end if;
  if dastak_v1_api.order_json('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','11111111-1111-1111-1111-111111111111') #>> '{fulfilmentProgress,estimatedReadyAt}' <> 'sample'
    then raise exception 'Preparation metadata lost'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'ASSIGNING_RIDER',true,false);
  insert into dastak_v1.delivery_missions values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '22222222-2222-2222-2222-222222222222','ASSIGNED',now(),now());
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'PREPARING' then raise exception 'Assignment did not end waiting stage'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'PREPARING',true,false);
  update dastak_v1.delivery_missions set assigned_rider_id = null, status = 'SEARCHING_RIDER';
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'ASSIGNING_RIDER' then raise exception 'Rider search did not restore waiting stage'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'ASSIGNING_RIDER',true,false);
  update dastak_v1.orders set status = 'AWAITING_PAYMENT';
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'AWAITING_PAYMENT' then raise exception 'Unconfirmed order incorrectly assigning'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'AWAITING_PAYMENT',true,false);
  update dastak_v1.orders set status = 'OUT_FOR_DELIVERY' where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  update dastak_v1.delivery_missions set assigned_rider_id = '22222222-2222-2222-2222-222222222222', status = 'OUT_FOR_DELIVERY';
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'OUT_FOR_DELIVERY' then raise exception 'Missing on the way'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'OUT_FOR_DELIVERY',true,false);
  update dastak_v1.delivery_missions set status = 'ARRIVED';
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'RIDER_ARRIVED' then raise exception 'Mission-only arrival did not trigger update'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'RIDER_ARRIVED',true,false);
  if public.dastak_claim_order_live_activities() <> '[]'::jsonb then raise exception 'Arrival repeatedly requeued'; end if;
  update dastak_v1.orders set status = 'CANCELLED', version = 4 where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'CANCELLED' then raise exception 'Cancellation not sent'; end if;
  perform public.dastak_complete_order_live_activity((job->>'id')::uuid,(job->>'leaseId')::uuid,2,'CANCELLED',true,true);
  if public.dastak_claim_order_live_activities() <> '[]'::jsonb then raise exception 'Ended activity requeued'; end if;
  -- Session deletion ends the system surface without exposing any new status.
  perform public.dastak_register_order_live_activity('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','sample-2',repeat('c',64),'sandbox');
  insert into private.revoked_account_sessions values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111');
  job := public.dastak_claim_order_live_activities()->0;
  if job->>'status' <> 'ENDED' then raise exception 'Revoked session still receives order state'; end if;
  begin
    perform public.dastak_register_order_live_activity('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','sample-3',repeat('d',64),'sandbox');
    raise exception 'Revoked session registered again';
  exception when insufficient_privilege then null; end;
end $$;
do $$ begin
  if not exists(select 1 from dastak_v1.notification_routes where event_type='RIDER_ASSIGNMENT_PENDING'
    and audience='CUSTOMER' and notification_type='customer.assigning_rider' and platform='all'
    and title='Assigning your rider') then raise exception 'Missing assigning notification route'; end if;
  if exists(select 1 from dastak_v1.notification_routes where event_type='DELIVERY_MISSION_CREATED'
    and notification_type='customer.assigning_rider' and enabled) then raise exception 'Early assignment alert still enabled'; end if;
  if has_function_privilege('authenticated','dastak_v1_api.order_waiting_for_rider(uuid)','execute') then raise exception 'Ready state helper exposed'; end if;
end $$;
select 'assignment and reassignment, arrival, notification route, ownership, privileges, leases, token rotation, cancellation and session expiry passed' as result;
