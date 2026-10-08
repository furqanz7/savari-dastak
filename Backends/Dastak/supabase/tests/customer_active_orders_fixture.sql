alter table dastak_v1.orders add column order_type text not null default 'RETAIL_ONLY';
alter table dastak_v1.orders add column version bigint not null default 1;
alter table dastak_v1.orders add column created_at timestamptz not null default now();
create table private.merchant_orders(id uuid primary key,customer_account_id uuid,status text,state_version bigint,created_at timestamptz);
update dastak_v1.orders set status='DELIVERED';
insert into dastak_v1.orders(id,customer_id,status,created_at)
 select md5('completed-'||i)::uuid,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','DELIVERED',now() from generate_series(1,150)i;
insert into dastak_v1.orders(id,customer_id,status,order_type,created_at) values
 ('00000000-0000-4000-8000-000000000991','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','PREPARING','RETAIL_ONLY','2026-01-01'),
 ('00000000-0000-4000-8000-000000000992','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','OUT_FOR_DELIVERY','FOOD_ONLY','2026-01-02'),
 ('00000000-0000-4000-8000-000000000993','99999999-9999-4999-8999-999999999999','PREPARING','RETAIL_ONLY','2026-01-03');
insert into private.merchant_orders values
 ('00000000-0000-4000-8000-000000000994','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','merchant_accepted',2,'2026-01-04'),
 ('00000000-0000-4000-8000-000000000995','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','delivered',2,'2026-01-05'),
 ('00000000-0000-4000-8000-000000000996','99999999-9999-4999-8999-999999999999','paid',2,'2026-01-06');
