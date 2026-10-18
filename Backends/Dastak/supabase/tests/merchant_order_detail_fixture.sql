create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create schema dastak_v1;
create schema dastak_v1_api;
grant usage on schema auth,dastak_v1_api to authenticated;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create table dastak_v1.merchant_branches(id uuid primary key,organization_id uuid,display_name text);
create table dastak_v1.orders(id uuid primary key,display_order_number text,status text,order_type text,created_at timestamptz);
create table dastak_v1.fulfilments(id uuid primary key,order_id uuid,branch_id uuid,payload jsonb);
create table dastak_v1.merchant_opportunities(id uuid primary key,order_id uuid,branch_id uuid,payload jsonb);
create table dastak_v1.restaurant_order_requests(id uuid primary key,order_id uuid,branch_id uuid,payload jsonb);
create table dastak_v1.recovery_opportunities(id uuid primary key,order_id uuid,branch_id uuid);
alter table dastak_v1.recovery_opportunities
 add column recovery_case_id uuid default '99000000-0000-4000-8000-000000000091',
 add column order_line_id uuid default '99000000-0000-4000-8000-000000000071',
 add column status text default 'SELECTED',add column requested_quantity integer default 2,add column version integer default 1,
 add column started_at timestamptz default now(),add column expires_at timestamptz default now(),add column promised_prep_minutes integer,
 add column sku_id uuid default '99000000-0000-4000-8000-000000000092';
create table dastak_v1.skus(id uuid primary key,canonical_name text,variant_name text,pack_size text);
insert into dastak_v1.skus values('99000000-0000-4000-8000-000000000092','Recovery tea',null,'100 g');
create table dastak_v1.returns(id uuid primary key,order_id uuid);
create table dastak_v1.return_stops(id uuid primary key,return_id uuid,return_mission_id uuid,branch_id uuid,status text,package_count integer,arrived_at timestamptz,completed_at timestamptz);
create table dastak_v1.settlement_entries(id uuid primary key,order_id uuid,fulfilment_id uuid,entry_type text,status text,calculation_status text,amount_paise bigint,currency_code text,eligible_at timestamptz,settled_at timestamptz,subject_type text,subject_id uuid);
create table dastak_v1.merchant_users(account_id uuid,organization_id uuid,status text);
create table dastak_v1.fixture_permissions(actor uuid,branch uuid,permission text);
create function dastak_v1_api.assert_authenticated_actor(actor uuid) returns void language plpgsql as $$ begin if actor is null or actor is distinct from auth.uid() then raise insufficient_privilege; end if; end $$;
create function dastak_v1_api.actor_has_wave1_merchant_permission(actor uuid,organization uuid,permission text,branch uuid) returns boolean language sql stable as $$
 select exists(select 1 from dastak_v1.fixture_permissions p join dastak_v1.merchant_branches b on b.id=p.branch where p.actor=$1 and b.organization_id=$2 and p.permission=$3 and p.branch=$4)
$$;
create function dastak_v1_api.merchant_fulfilment_json(actor uuid,target uuid) returns jsonb language sql stable as $$ select payload from dastak_v1.fulfilments where id=target $$;
create function dastak_v1_api.merchant_opportunity_json(actor uuid,target uuid) returns jsonb language sql stable as $$ select payload from dastak_v1.merchant_opportunities where id=target $$;
create function dastak_v1_api.restaurant_request_json(actor uuid,target uuid) returns jsonb language sql stable as $$ select payload from dastak_v1.restaurant_order_requests where id=target $$;

insert into dastak_v1.merchant_branches values
 ('99000000-0000-4000-8000-000000000011','99000000-0000-4000-8000-000000000021','Store A'),
 ('99000000-0000-4000-8000-000000000012','99000000-0000-4000-8000-000000000021','Store B');
insert into dastak_v1.orders values ('99000000-0000-4000-8000-000000000031','DSK-OLD-001','DELIVERED','MIXED','2010-01-01');
insert into dastak_v1.fixture_permissions
 select '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000011',p from unnest(array['merchant.fulfilment.manage','merchant.opportunities.respond']) p;
insert into dastak_v1.fixture_permissions values ('99000000-0000-4000-8000-000000000002','99000000-0000-4000-8000-000000000011','merchant.opportunities.respond');
insert into dastak_v1.merchant_users values ('99000000-0000-4000-8000-000000000001','99000000-0000-4000-8000-000000000021','ACTIVE');
insert into dastak_v1.fulfilments values
 ('99000000-0000-4000-8000-000000000041','99000000-0000-4000-8000-000000000031','99000000-0000-4000-8000-000000000011',
 '{"id":"99000000-0000-4000-8000-000000000041","status":"COMPLETED","version":3,"productSubtotalPaise":1000,"packageCount":2,"promisedPrepMinutes":15,"lines":[{"orderLineId":"99000000-0000-4000-8000-000000000071","name":"Own tea","quantity":2,"unitPricePaise":500,"lineSubtotalPaise":1000,"customerNote":"PRIVATE_SECRET","selection":{"options":[{"id":"99000000-0000-4000-8000-000000000072","groupId":"99000000-0000-4000-8000-000000000073","groupName":"Sweetness","name":"Less sugar","priceDeltaPaise":0,"privateData":"PRIVATE_SECRET"}]}}],"evidence":[{"id":"99000000-0000-4000-8000-000000000074","capturedAt":"2026-10-18T00:00:00Z","contentType":"image/jpeg","objectPath":"PRIVATE_SECRET"}],"problemReports":[],"recoveryCases":[],"delivery":{"riderAssigned":true,"rider":{"displayName":"Rider A","phone":"PRIVATE_SECRET"},"stopStatus":"COMPLETED","pickupCode":"PRIVATE_SECRET"},"tracking":{"dropoff":"PRIVATE_SECRET"},"customer":{"address":"PRIVATE_SECRET"},"totalPaise":99999}'),
 ('99000000-0000-4000-8000-000000000042','99000000-0000-4000-8000-000000000031','99000000-0000-4000-8000-000000000012','{"id":"99000000-0000-4000-8000-000000000042","name":"OTHER_STORE_SECRET"}');
insert into dastak_v1.merchant_opportunities select '99000000-0000-4000-8000-000000000051',order_id,branch_id,payload||'{"id":"99000000-0000-4000-8000-000000000051","status":"SELECTED"}' from dastak_v1.fulfilments where id='99000000-0000-4000-8000-000000000041';
insert into dastak_v1.restaurant_order_requests select '99000000-0000-4000-8000-000000000052',order_id,branch_id,payload||'{"id":"99000000-0000-4000-8000-000000000052","status":"CONFIRMED"}' from dastak_v1.fulfilments where id='99000000-0000-4000-8000-000000000041';
insert into dastak_v1.recovery_opportunities(id,order_id,branch_id) values ('99000000-0000-4000-8000-000000000053','99000000-0000-4000-8000-000000000031','99000000-0000-4000-8000-000000000011');
insert into dastak_v1.returns values ('99000000-0000-4000-8000-000000000061','99000000-0000-4000-8000-000000000031');
insert into dastak_v1.return_stops values
 ('99000000-0000-4000-8000-000000000062','99000000-0000-4000-8000-000000000061','99000000-0000-4000-8000-000000000063','99000000-0000-4000-8000-000000000011','COMPLETED',2,now(),now()),
 ('99000000-0000-4000-8000-000000000064','99000000-0000-4000-8000-000000000061','99000000-0000-4000-8000-000000000063','99000000-0000-4000-8000-000000000012','COMPLETED',99,now(),now());
insert into dastak_v1.settlement_entries select
 '99000000-0000-4000-8000-000000000081','99000000-0000-4000-8000-000000000031','99000000-0000-4000-8000-000000000041','MERCHANT_PRODUCT_VALUE','ELIGIBLE','CALCULATED',1000,'INR',now(),null,'MERCHANT_ORGANIZATION','99000000-0000-4000-8000-000000000021';
insert into dastak_v1.settlement_entries select
 '99000000-0000-4000-8000-000000000082','99000000-0000-4000-8000-000000000031','99000000-0000-4000-8000-000000000042','OTHER_STORE_SECRET','ELIGIBLE','CALCULATED',99999,'INR',now(),null,'MERCHANT_ORGANIZATION','99000000-0000-4000-8000-000000000021';
-- A targeted old read must not become a scan of only the latest 100 records.
insert into dastak_v1.fulfilments select md5('new-'||i)::uuid,md5('other-order-'||i)::uuid,'99000000-0000-4000-8000-000000000011','{}' from generate_series(1,150)i;
