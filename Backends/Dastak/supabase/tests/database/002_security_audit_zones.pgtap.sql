begin;

select plan(38);

select policies_are('public', 'accounts', array['accounts_select_self']);
select table_privs_are('authenticated', 'public', 'accounts', array['SELECT']);
select has_table('audit', 'events');
select col_is_pk('audit', 'events', 'id');
select has_table('private', 'safety_cases');
select has_table('public', 'service_zones');
select has_column('public', 'service_zones', 'boundary');
select is((select relrowsecurity from pg_class where oid = 'audit.events'::regclass), true, 'audit events has RLS enabled');
select is((select relrowsecurity from pg_class where oid = 'private.safety_cases'::regclass), true, 'safety cases has RLS enabled');
select is((select relrowsecurity from pg_class where oid = 'public.service_zones'::regclass), true, 'service zones has RLS enabled');
select is(has_table_privilege('authenticated', 'audit.events', 'SELECT'), false, 'authenticated cannot read audit events');
select is(has_table_privilege('authenticated', 'audit.events', 'INSERT'), false, 'authenticated cannot insert audit events');
select is(has_table_privilege('authenticated', 'audit.events', 'UPDATE'), false, 'authenticated cannot update audit events');
select is(has_table_privilege('authenticated', 'audit.events', 'DELETE'), false, 'authenticated cannot delete audit events');
select is(has_table_privilege('authenticated', 'private.safety_cases', 'SELECT'), false, 'authenticated cannot read safety cases');
select is(has_table_privilege('authenticated', 'private.safety_cases', 'INSERT'), false, 'authenticated cannot insert safety cases');
select is(has_table_privilege('authenticated', 'public.service_zones', 'SELECT'), true, 'authenticated can read service zones');
select is(has_table_privilege('authenticated', 'public.service_zones', 'INSERT'), false, 'authenticated cannot insert service zones');
select is(has_table_privilege('authenticated', 'public.service_zones', 'UPDATE'), false, 'authenticated cannot update service zones');
select is(has_table_privilege('authenticated', 'public.service_zones', 'DELETE'), false, 'authenticated cannot delete service zones');
select has_policy('public', 'service_zones', 'service_zones_select_active');
select is(
  (select qual from pg_policies where schemaname = 'public' and tablename = 'service_zones' and policyname = 'service_zones_select_active'),
  '(active = true)',
  'service zone policy returns active zones only'
);
select has_trigger('audit', 'events', 'audit_events_immutable');
select is((select public from storage.buckets where id = 'dastak-evidence'), false, 'Dastak evidence bucket is private');
select is((select public from storage.buckets where id = 'dastak-catalogue'), true, 'Dastak catalogue bucket is public');
select policies_are('storage', 'objects', array[
  'dastak_evidence_insert_own',
  'dastak_evidence_select_own',
  'dastak_evidence_update_own'
]);

insert into audit.events (action, entity_type) values ('tap_insert', 'test');
select throws_ok(
  $$update audit.events set action = 'changed' where action = 'tap_insert'$$,
  'P0001',
  'audit.events is append-only',
  'audit update trigger rejects every update'
);
select throws_ok(
  $$delete from audit.events where action = 'tap_insert'$$,
  'P0001',
  'audit.events is append-only',
  'audit update trigger rejects every delete'
);

insert into public.service_zones (name, boundary, active) values
  ('tap active zone', extensions.st_geomfromtext('POLYGON((0 0, 0 1, 1 1, 0 0))', 4326), true),
  ('tap inactive zone', extensions.st_geomfromtext('POLYGON((2 2, 2 3, 3 3, 2 2))', 4326), false);
set local role authenticated;
select results_eq(
  $$select name from public.service_zones where name like 'tap %' order by name$$,
  array['tap active zone']::text[],
  'authenticated reads active service zones only'
);
reset role;

select is(
  has_table_privilege('authenticated', 'storage.objects', 'DELETE'),
  false,
  'authenticated has no storage.objects delete privilege'
);

insert into storage.objects (bucket_id, name) values
  ('dastak-evidence', 'dastak-partner/11111111-1111-4111-8111-111111111111/existing.jpg'),
  ('dastak-evidence', 'dastak-partner/22222222-2222-4222-8222-222222222222/foreign.jpg');

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);

select results_eq(
  $$select name from storage.objects where bucket_id = 'dastak-evidence' order by name$$,
  array['dastak-partner/11111111-1111-4111-8111-111111111111/existing.jpg']::text[],
  'authenticated selects only its own exact evidence path'
);
select lives_ok(
  $$insert into storage.objects (bucket_id, name) values ('dastak-evidence', 'dastak-partner/11111111-1111-4111-8111-111111111111/new.jpg')$$,
  'authenticated inserts its own exact evidence path'
);
select throws_like(
  $$insert into storage.objects (bucket_id, name) values ('dastak-evidence', 'dastak-partner/22222222-2222-4222-8222-222222222222/denied.jpg')$$,
  '%row-level security%',
  'authenticated cannot insert a foreign evidence path'
);
select throws_like(
  $$insert into storage.objects (bucket_id, name) values ('dastak-evidence', 'dastak-partner/11111111-1111-4111-8111-111111111111/nested/file.jpg')$$,
  '%row-level security%',
  'authenticated cannot insert a nested evidence path'
);
select throws_like(
  $$insert into storage.objects (bucket_id, name) values ('dastak-evidence', 'dastak-partner/11111111-1111-4111-8111-111111111111/')$$,
  '%row-level security%',
  'authenticated cannot insert an empty evidence filename'
);
select results_eq(
  $$update storage.objects set metadata = '{"verified":true}'::jsonb where name = 'dastak-partner/11111111-1111-4111-8111-111111111111/existing.jpg' returning name$$,
  array['dastak-partner/11111111-1111-4111-8111-111111111111/existing.jpg']::text[],
  'authenticated updates its own evidence object'
);
select results_eq(
  $$update storage.objects set metadata = '{"verified":true}'::jsonb where name = 'dastak-partner/22222222-2222-4222-8222-222222222222/foreign.jpg' returning name$$,
  array[]::text[],
  'authenticated cannot update a foreign evidence object'
);
select throws_like(
  $$delete from storage.objects where name = 'dastak-partner/11111111-1111-4111-8111-111111111111/existing.jpg'$$,
  '%permission denied%',
  'authenticated cannot delete evidence objects'
);
reset role;

select * from finish();
rollback;
