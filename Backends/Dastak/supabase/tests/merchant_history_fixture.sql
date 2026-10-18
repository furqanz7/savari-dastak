-- Extends the minimal detail fixture; does not model the entire migration chain.
create schema private;
create function private.dastak_v1_handoff_code(uuid,text,integer) returns text language sql as $$select 'guarded-code'::text$$;
alter table dastak_v1.fulfilments add column organization_id uuid,add column status text,add column committed_at timestamptz;
update dastak_v1.fulfilments set organization_id='99000000-0000-4000-8000-000000000021',status='COMPLETED',committed_at='2026-10-01T00:00:00.123456Z';
insert into dastak_v1.orders(id,status,created_at)
 select distinct order_id,'DELIVERED',now() from dastak_v1.fulfilments f
 where not exists(select 1 from dastak_v1.orders o where o.id=f.order_id);
update dastak_v1.orders set status='PREPARING' where id='99000000-0000-4000-8000-000000000031';
update dastak_v1.fulfilments set status='PREPARING',committed_at='2010-01-01'
 where id in ('99000000-0000-4000-8000-000000000041','99000000-0000-4000-8000-000000000042');
-- A COMPLETED fulfilment is historical even when its parent is not terminal.
insert into dastak_v1.fulfilments(id,order_id,branch_id,organization_id,status,committed_at,payload)
 values('99000000-0000-4000-8000-000000000043','99000000-0000-4000-8000-000000000031',
 '99000000-0000-4000-8000-000000000011','99000000-0000-4000-8000-000000000021','COMPLETED','2009-01-01','{}');
update dastak_v1.fulfilments set payload=jsonb_build_object('id',id,'status',status,'branchId',branch_id);
alter table dastak_v1.recovery_opportunities add column organization_id uuid default '99000000-0000-4000-8000-000000000021';
alter table dastak_v1.skus add column image_key text;
create table dastak_v1.return_missions(id uuid primary key,created_at timestamptz);
insert into dastak_v1.return_missions values('99000000-0000-4000-8000-000000000063',now());
alter table dastak_v1.return_stops add column stop_sequence integer default 1;
create table dastak_v1.return_verifications(id uuid primary key,return_stop_id uuid,handoff_type text,status text,code_version integer);
insert into dastak_v1.return_verifications values('99000000-0000-4000-8000-000000000094','99000000-0000-4000-8000-000000000062','RETURN_RIDER_TO_MERCHANT','ACTIVE',1);
alter table dastak_v1.settlement_entries add column created_at timestamptz default now();
