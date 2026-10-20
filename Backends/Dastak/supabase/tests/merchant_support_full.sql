-- Run only in the guarded, isolated full-chain fixture. Every record rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok((select relrowsecurity from pg_class where oid='private.merchant_support_tickets'::regclass), 'ticket RLS enabled');
select ok((select relrowsecurity from pg_class where oid='private.merchant_support_messages'::regclass), 'message RLS enabled');
select ok(not has_table_privilege('anon','private.merchant_support_tickets','SELECT'), 'anon cannot read tickets directly');
select ok(not has_table_privilege('authenticated','private.merchant_support_messages','SELECT'), 'signed-in user cannot read messages directly');
select ok(not has_table_privilege('service_role','private.merchant_support_tickets','INSERT'), 'service cannot insert tickets directly');
select ok(not has_function_privilege('anon','public.merchant_support_command(uuid,jsonb)','EXECUTE'), 'anon cannot call RPC');
select ok(not has_function_privilege('authenticated','public.merchant_support_command(uuid,jsonb)','EXECUTE'), 'signed-in user cannot call RPC');
select ok(has_function_privilege('service_role','public.merchant_support_command(uuid,jsonb)','EXECUTE'), 'service may call constrained RPC');
select ok(not (select prosecdef from pg_proc where oid='public.merchant_support_command(uuid,jsonb)'::regprocedure), 'public wrapper is security invoker');
select ok((select prosecdef from pg_proc where oid='private.merchant_support_command(uuid,jsonb)'::regprocedure), 'private command is security definer');
select ok((select proconfig @> array['lock_timeout=500ms']::text[] from pg_proc where oid='private.merchant_support_command(uuid,jsonb)'::regprocedure), 'other support lock waits are bounded');
select matches(pg_get_functiondef('private.merchant_support_command(uuid,jsonb)'::regprocedure),'pg_try_advisory_xact_lock','creation uses nonblocking admission lock');
select matches(pg_get_functiondef('private.merchant_support_command(uuid,jsonb)'::regprocedure),'for update nowait','mutation uses nonblocking row lock');

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('a5000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','support-admin@example.test','',now(),'{}','{}',now(),now()),
('a5000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','support-user@example.test','',now(),'{}','{}',now(),now()),
('a5000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','support-superadmin@example.test','',now(),'{}','{}',now(),now());
insert into public.accounts(id,display_name,phone_number,account_state) values
('a5000000-0000-4000-8000-000000000001','Fixture Support Admin','+919600050001','ACTIVE'),
('a5000000-0000-4000-8000-000000000002','Fixture Customer','+919600050002','ACTIVE'),
('a5000000-0000-4000-8000-000000000003','Fixture Superadmin','+919600050003','ACTIVE');
insert into private.account_memberships(account_id,role) values
('a5000000-0000-4000-8000-000000000001','customer'),('a5000000-0000-4000-8000-000000000002','customer'),('a5000000-0000-4000-8000-000000000003','customer');
select lives_ok($$select dastak_v1_api.bootstrap_superadmin('a5000000-0000-4000-8000-000000000003')$$, 'actual full-schema Admin bootstrap succeeds');
do $$begin perform set_config('request.jwt.claim.sub','a5000000-0000-4000-8000-000000000003',true); end$$;
set local role authenticated;
select lives_ok($$select public.dastak_set_executive_admin(1::smallint,'support-admin@example.test',1::bigint,'Rollback-only support access fixture.')$$, 'actual Executive Admin assignment succeeds');
reset role;

do $$begin perform set_config('support.base', jsonb_build_object('operation','create','ticketId','b5000000-0000-4000-8000-000000000001','requestId','c5000000-0000-4000-8000-000000000001','tokenHash',repeat('a',64),'category','ACCESS','subject','Fixture access question','message','Please help with this fixture request')::text,true); end$$;
set local role service_role;
select is(public.merchant_support_command(null,current_setting('support.base')::jsonb)->>'status','OPEN','public creation works through actual service role');
select is(jsonb_array_length(public.merchant_support_command(null,current_setting('support.base')::jsonb)->'messages'),1,'identical create replay has one message');
select ok(not (public.merchant_support_command(null,current_setting('support.base')::jsonb) ? 'token_hash'),'receipt does not expose hash');
select throws_ok($$select public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"subject":"Changed fixture subject"}')$$,'23505','support_conflict','changed create replay conflicts');
select throws_ok($$select public.merchant_support_command(null,current_setting('support.base')::jsonb || jsonb_build_object('operation','read','tokenHash',repeat('b',64)))$$,'P0002','support_not_found','wrong capability cannot read');
select throws_ok($$select public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"adminRead"}')$$,'42501','support_forbidden','missing Admin denied');
select throws_ok($$select public.merchant_support_command('a5000000-0000-4000-8000-000000000002',current_setting('support.base')::jsonb || '{"operation":"adminRead"}')$$,'42501','support_forbidden','Customer cannot impersonate Admin');
select is(public.merchant_support_command('a5000000-0000-4000-8000-000000000001',current_setting('support.base')::jsonb || '{"operation":"adminRead"}')->>'subject','Fixture access question','actual active Admin can read');
select is(jsonb_array_length(public.merchant_support_command('a5000000-0000-4000-8000-000000000001','{"operation":"adminList"}')->'tickets'),1,'actual Admin can list');
select is(public.merchant_support_command('a5000000-0000-4000-8000-000000000001',current_setting('support.base')::jsonb || '{"operation":"adminReply","requestId":"c5000000-0000-4000-8000-000000000002","message":"Fixture support response","status":"RESOLVED","version":1}')->>'version','2','Admin reply advances version');
select is(public.merchant_support_command('a5000000-0000-4000-8000-000000000001',current_setting('support.base')::jsonb || '{"operation":"adminReply","requestId":"c5000000-0000-4000-8000-000000000002","message":"Fixture support response","status":"RESOLVED","version":1}')->>'version','2','Admin retry is idempotent despite old version');
select is(public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"read"}')->>'status','RESOLVED','capability read sees resolution');
select throws_ok($$select public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"reply","requestId":"c5000000-0000-4000-8000-000000000003","version":1}')$$,'40001','support_stale','stale reply cannot overwrite');
select throws_ok($$select public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"reply","requestId":"c5000000-0000-4000-8000-000000000003","version":2}')$$,'54000','support_rate_limited','Merchant cooldown enforced');
reset role;
-- Only fixture support timestamps change; no account/audit trigger is replaced.
update private.merchant_support_messages set created_at=clock_timestamp()-interval '1 minute' where side='MERCHANT';
set local role service_role;
select is(public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"reply","requestId":"c5000000-0000-4000-8000-000000000003","version":2}')->>'status','OPEN','Merchant reply reopens conversation');
select is(jsonb_array_length(public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"reply","requestId":"c5000000-0000-4000-8000-000000000003","version":2}')->'messages'),3,'Merchant retry preserves one added message');
reset role;
update private.account_memberships set suspended_until=now()+interval '1 hour' where account_id='a5000000-0000-4000-8000-000000000001' and role='owner';
set local role service_role;
select throws_ok($$select public.merchant_support_command('a5000000-0000-4000-8000-000000000001','{"operation":"adminList"}')$$,'42501','support_forbidden','actual suspended membership revokes access');
reset role;
update private.account_memberships set suspended_until=null where account_id='a5000000-0000-4000-8000-000000000001' and role='owner';
update auth.users set email='changed-support-admin@example.test' where id='a5000000-0000-4000-8000-000000000001';
set local role service_role;
select throws_ok($$select public.merchant_support_command('a5000000-0000-4000-8000-000000000001','{"operation":"adminList"}')$$,'42501','support_forbidden','actual email mismatch revokes access');
reset role;
update auth.users set email='support-admin@example.test' where id='a5000000-0000-4000-8000-000000000001';
update public.accounts set account_state='DELETION_PENDING',deletion_requested_at=now(),anonymized_at=now() where id='a5000000-0000-4000-8000-000000000001';
set local role service_role;
select throws_ok($$select public.merchant_support_command('a5000000-0000-4000-8000-000000000001','{"operation":"adminList"}')$$,'42501','support_forbidden','actual inactive account revokes access');
reset role;

-- Create the rest of the hourly allowance with the real command, then verify
-- admission exhaustion does not disable recovery for the original request.
set local role service_role;
do $$begin for i in 2..30 loop perform public.merchant_support_command(null,current_setting('support.base')::jsonb || jsonb_build_object('ticketId',gen_random_uuid(),'requestId',gen_random_uuid())); end loop; end$$;
select throws_ok($$select public.merchant_support_command(null,current_setting('support.base')::jsonb || jsonb_build_object('ticketId',gen_random_uuid(),'requestId',gen_random_uuid()))$$,'54000','support_rate_limited','actual hourly admission cap enforced');
select is(public.merchant_support_command(null,current_setting('support.base')::jsonb)->>'version','3','original create replay works after admission exhausted');
select is(public.merchant_support_command(null,current_setting('support.base')::jsonb || '{"operation":"read"}')->>'status','OPEN','recovery read works after admission exhausted');
reset role;
select is((select count(*) from private.merchant_support_tickets),30::bigint,'bounded fixture ticket count');
select is((select count(*) from auth.users),3::bigint,'support commands did not create extra identities');
select throws_ok($$select '{"message":"hello\u0000there"}'::jsonb$$,'22P05','unsupported Unicode escape sequence','PostgreSQL also rejects NUL; Edge now rejects it before RPC');
select * from finish();
rollback;
