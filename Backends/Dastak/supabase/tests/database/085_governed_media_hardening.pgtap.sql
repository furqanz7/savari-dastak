begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select no_plan();
select ok((select relrowsecurity from pg_class where oid='dastak_v1.governed_entity_media'::regclass),
 'private governed metadata has RLS enabled');
select has_index('dastak_v1','governed_entity_media','governed_entity_media_created_by_idx',
 'the creator foreign key has a supporting index');
select ok(not has_table_privilege('anon','dastak_v1.governed_entity_media','SELECT'), 'anonymous direct media reads remain denied');
select ok(not has_table_privilege('authenticated','dastak_v1.governed_entity_media','INSERT'), 'clients cannot insert media directly');
select ok(not has_function_privilege('authenticated','public.dastak_v1_prepare_governed_media(uuid,text,uuid,bigint,text,bigint,text,text,text)','EXECUTE'),
 'media preparation remains behind the service boundary');

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at)
values('a8500000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','media-owner@example.test','',now()),
('a8500000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','media-customer@example.test','',now());
insert into public.accounts(id,display_name,phone_number) values
('a8500000-0000-4000-8000-000000000001','Media Admin','+919850000001'),
('a8500000-0000-4000-8000-000000000002','Media Customer','+919850000002');
insert into private.account_memberships(account_id,role,approved_at) values
('a8500000-0000-4000-8000-000000000001','owner',now()),
('a8500000-0000-4000-8000-000000000002','customer',null);
select dastak_v1_api.bootstrap_superadmin('a8500000-0000-4000-8000-000000000001');
insert into dastak_v1.category_types(id,name,slug,status,created_by)
values('a8510000-0000-4000-8000-000000000001','Media Fixture','media-fixture','DRAFT','a8500000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','a8500000-0000-4000-8000-000000000001',true);
set local role service_role;
create temporary table media_intent as select public.dastak_v1_prepare_governed_media(
 'a8500000-0000-4000-8000-000000000001','CATEGORY_TYPE','a8510000-0000-4000-8000-000000000001',1,
 'image/png',100,'Reviewed fixture source','Replace fixture art','prepare-media') body;
select is((select body from media_intent),public.dastak_v1_prepare_governed_media(
 'a8500000-0000-4000-8000-000000000001','CATEGORY_TYPE','a8510000-0000-4000-8000-000000000001',1,
 'image/png',100,'Reviewed fixture source','Replace fixture art','prepare-media'),'media preparation remains idempotent with RLS');
select lives_ok($$select public.dastak_v1_finalize_governed_media(
 'a8500000-0000-4000-8000-000000000001','CATEGORY_TYPE','a8510000-0000-4000-8000-000000000001',
 (select (body->>'assetId')::uuid from media_intent),1,repeat('a',64),'image/png',100,100,100,
 'Replace fixture art','finalize-media')$$,'authorized media finalization works through the existing wrapper');
reset role;
select is((select count(*) from dastak_v1.governed_entity_media where entity_id='a8510000-0000-4000-8000-000000000001' and status='ACTIVE'),1::bigint,
 'finalization activates exactly one asset');
select is((select media_version from dastak_v1.category_types where id='a8510000-0000-4000-8000-000000000001'),2::bigint,
 'governed presentation version advances');
select set_config('request.jwt.claim.sub','a8500000-0000-4000-8000-000000000002',true);
set local role service_role;
select throws_ok($$select public.dastak_v1_prepare_governed_media(
 'a8500000-0000-4000-8000-000000000002','CATEGORY_TYPE','a8510000-0000-4000-8000-000000000001',2,
 'image/png',100,'Reviewed fixture source','Unauthorized replacement','deny-media')$$,
 '42501','platform permission required','service boundary still rejects an unprivileged Customer actor');
reset role;
select * from finish();
rollback;
