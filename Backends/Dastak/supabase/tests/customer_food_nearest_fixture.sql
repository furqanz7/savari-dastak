-- Local paging/authorization harness, NOT a substitute for PostGIS accuracy tests.
-- This host lacks PostGIS; domains and deterministic metre distances stand in for it.
create schema extensions;
create schema private;
create domain extensions.geometry as point;
create domain extensions.geography as point;
create function extensions.st_distance(a extensions.geography, b extensions.geography)
  returns double precision language sql immutable as $$ select a::point <-> b::point $$;
alter table dastak_v1.merchant_branches add column location extensions.geometry;
create table private.customer_delivery_addresses(id uuid primary key, account_id uuid, location extensions.geometry, updated_at timestamptz);
revoke all on private.customer_delivery_addresses from public, anon, authenticated;
insert into private.customer_delivery_addresses values
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',point(0,0),'2026-10-08T00:00:00Z'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',point(20500,0),'2026-10-08T00:00:00Z'),
  ('ffffffff-ffff-4fff-8fff-ffffffffffff','99999999-9999-4999-8999-999999999999',point(0,0),'2026-10-08T00:00:00Z');
update dastak_v1.merchant_branches b set location=point((206-i)*100,0) from generate_series(1,205)i where b.id=md5('branch'||i)::uuid;
-- Equal names AND equal distance must still advance by exact branch identity.
update dastak_v1.merchant_branches set location=point(10600,0) where id=md5('branch201')::uuid;
update dastak_v1.merchant_branches set location=null where id in (md5('branch1')::uuid,md5('branch2')::uuid);
