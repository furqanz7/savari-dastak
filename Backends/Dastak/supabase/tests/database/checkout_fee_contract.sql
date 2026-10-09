-- Isolated PostgreSQL contract harness, NOT a production/Supabase migration.
-- Spatial helpers below use planar metres; this verifies SQL execution/guards,
-- not PostGIS deployment, geography accuracy, or a real matching/payment flow.
\set ON_ERROR_STOP on
create schema extensions;
create schema private;
create schema dastak_v1;
create schema dastak_v1_api;
create schema auth;
create role anon;
create role authenticated;
create role service_role;
create domain extensions.geometry as point;
create domain extensions.geography as point;
create function extensions.st_makepoint(double precision,double precision) returns extensions.geometry
  language sql immutable as 'select point($1,$2)::extensions.geometry';
create function extensions.st_setsrid(extensions.geometry,integer) returns extensions.geometry
  language sql immutable as 'select $1';
create function extensions.st_distance(extensions.geography,extensions.geography) returns double precision
  language sql immutable as 'select $1::point <-> $2::point';
create function extensions.st_covers(extensions.geometry,extensions.geometry) returns boolean
  language sql immutable as 'select ($1::point <-> $2::point)<10000';
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.actor',true),'')::uuid;
$$;
create table public.service_zones(id uuid primary key,active boolean,boundary extensions.geometry);
create table dastak_v1.merchant_organizations(id uuid primary key,status text,merchant_type text);
create table dastak_v1.merchant_branches(id uuid primary key,organization_id uuid,status text,service_zone_id uuid,location extensions.geometry);
create table dastak_v1.branch_operational_states(branch_id uuid,is_open boolean,accepting_orders boolean);
create table dastak_v1.merchant_sku_selections(branch_id uuid,sku_id uuid,state text,stock_quantity integer);
create table dastak_v1.operational_pause_controls(active boolean,scope text,branch_id uuid,service_zone_id uuid);
create table dastak_v1.categories(id uuid primary key,status text);
create table dastak_v1.subcategories(id uuid primary key,category_id uuid,status text);
create table dastak_v1.brands(id uuid primary key,status text);
create table dastak_v1.skus(id uuid primary key,subcategory_id uuid,brand_id uuid,status text,currency_code text,selling_price_paise bigint);
create table private.customer_delivery_addresses(id uuid primary key,account_id uuid,updated_at timestamptz,location extensions.geometry);
create table dastak_v1.orders(id uuid primary key,restaurant_branch_id uuid);
create table dastak_v1.order_context_snapshots(order_id uuid,delivery_address jsonb);
create table dastak_v1.order_lines(order_id uuid,line_type text,sku_id uuid,quantity integer);
create table dastak_v1.fulfilments(order_id uuid,branch_id uuid,status text);
create table dastak_v1.order_price_snapshots(order_id uuid,snapshot_kind text,subtotal_paise bigint,
  delivery_fee_paise bigint,platform_fee_paise bigint,tax_paise bigint,discount_paise bigint,total_paise bigint,calculation_details jsonb);
create table private.test_food(id uuid primary key,branch_id uuid,base_price bigint,option_id uuid,option_price bigint);
create function private.customer_owned_area(uuid,uuid,timestamptz) returns extensions.geometry language plpgsql stable as $$
declare address private.customer_delivery_addresses%rowtype;
begin
  if $1 is distinct from auth.uid() or $1 is null then raise exception using errcode='42501'; end if;
  select * into address from private.customer_delivery_addresses where id=$2 and account_id=$1;
  if not found then raise exception using errcode='42501'; end if;
  if address.updated_at is distinct from $3 then raise exception using errcode='22023'; end if;
  return address.location;
end;
$$;
create function private.customer_restaurant_accepting(uuid) returns boolean language sql stable as $$
  select coalesce((select is_open and accepting_orders from dastak_v1.branch_operational_states where branch_id=$1),false);
$$;
create function private.customer_area_delivery_available(extensions.geometry) returns boolean language sql stable as 'select false';
create function dastak_v1_api.wave1_branch_configuration(uuid,uuid,uuid) returns jsonb language sql stable as $$select '{"retailRadiusMeters":5000}'::jsonb$$;
create function dastak_v1_api.branch_distance_meters(uuid,uuid) returns numeric language sql stable as $$
  select extensions.st_distance(a.location::extensions.geography,b.location::extensions.geography)::numeric
    from dastak_v1.merchant_branches a,dastak_v1.merchant_branches b where a.id=$1 and b.id=$2;
$$;
create function dastak_v1_api.pickup_route_distance_meters(uuid,uuid[]) returns bigint language plpgsql stable as $$
begin
  return (select private.checkout_route_distance(extensions.st_makepoint((delivery_address->>'longitude')::double precision,
    (delivery_address->>'latitude')::double precision),$2) from dastak_v1.order_context_snapshots where order_id=$1);
end;
$$;
-- SQL body referencing the newly created route helper is validated at execution.
create function dastak_v1_api.restaurant_selection_snapshot(uuid,uuid,jsonb) returns jsonb language plpgsql stable as $$
declare item private.test_food%rowtype; options uuid[];
begin
  select * into item from private.test_food where id=$2 and branch_id=$1;
  if not found then raise exception using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid order by value),'{}') into options from jsonb_array_elements_text($3);
  if cardinality(options)>1 or (cardinality(options)=1 and options[1]<>item.option_id) then raise exception using errcode='22023'; end if;
  return jsonb_build_object('selectionKey',$2::text||options::text,'unitPricePaise',item.base_price+case when cardinality(options)=1 then item.option_price else 0 end);
end;
$$;
create function dastak_v1_api.calculate_delivery_fee_paise(bigint) returns bigint language plpgsql immutable as $$
begin
  if $1 is null or $1<0 then raise exception using errcode='22023'; end if;
  if $1<=1000 then return 1500; end if;
  if $1<=2000 then return 2000; end if;
  return 2000+500*ceil(($1-2000)::numeric/1000)::bigint;
end;
$$;
-- One genuine historical order, seeded BEFORE new policy/default.
insert into dastak_v1.orders values('00000000-0000-4000-8000-000000000090',null);
\ir ../../migrations/20261009111558_checkout_fee_quotes.sql
create trigger fees before insert on dastak_v1.order_price_snapshots
  for each row execute function dastak_v1.apply_authoritative_delivery_fee();
create function private.test_assert(boolean,text) returns void language plpgsql as $$
begin if $1 is distinct from true then raise exception 'FAILED: %',$2; end if; end;
$$;
insert into public.service_zones values('00000000-0000-4000-8000-000000000001',true,point(0,0));
insert into dastak_v1.merchant_organizations values('00000000-0000-4000-8000-000000000002','ACTIVE','RETAIL');
insert into dastak_v1.merchant_branches values
 ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000002','ACTIVE','00000000-0000-4000-8000-000000000001',point(1000,0)),
 ('00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000002','ACTIVE','00000000-0000-4000-8000-000000000001',point(2500,0));
insert into dastak_v1.branch_operational_states select id,true,true from dastak_v1.merchant_branches;
insert into dastak_v1.categories values('00000000-0000-4000-8000-000000000010','ACTIVE');
insert into dastak_v1.subcategories values('00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000010','ACTIVE');
insert into dastak_v1.skus values
 ('00000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000011',null,'ACTIVE','INR',10000),
 ('00000000-0000-4000-8000-000000000013','00000000-0000-4000-8000-000000000011',null,'ACTIVE','INR',5000);
insert into dastak_v1.merchant_sku_selections values
 ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000012','SELECTED',10),
 ('00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000013','SELECTED',10);
insert into private.customer_delivery_addresses values('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000021','2026-10-09T00:00:00Z',point(0,0));
insert into private.test_food values('00000000-0000-4000-8000-000000000030','00000000-0000-4000-8000-000000000003',20000,'00000000-0000-4000-8000-000000000031',3000);
set test.actor='00000000-0000-4000-8000-000000000021';
do $$
declare quote jsonb; basket jsonb:='[{"lineType":"RETAIL_SKU","skuId":"00000000-0000-4000-8000-000000000012","quantity":1}]';
  home uuid:='00000000-0000-4000-8000-000000000020'; version timestamptz:='2026-10-09T00:00:00Z';
begin
  perform private.test_assert(dastak_v1_api.calculate_delivery_fee_paise(0)=1500 and dastak_v1_api.calculate_delivery_fee_paise(1000)=1500
    and dastak_v1_api.calculate_delivery_fee_paise(1001)=2000 and dastak_v1_api.calculate_delivery_fee_paise(2000)=2000
    and dastak_v1_api.calculate_delivery_fee_paise(2001)=2500 and dastak_v1_api.calculate_delivery_fee_paise(3000)=2500
    and dastak_v1_api.calculate_delivery_fee_paise(3001)=3000,'delivery boundaries');
  perform private.test_assert(private.checkout_customer_platform_fee(0)=0 and private.checkout_customer_platform_fee(24)=0
    and private.checkout_customer_platform_fee(25)=1 and private.checkout_customer_platform_fee(74)=1
    and private.checkout_customer_platform_fee(75)=2,'half-up rounding');
  quote:=public.dastak_v1_customer_checkout_quote(home,version,basket);
  perform private.test_assert(quote->>'deliveryFeePaise'='1500' and quote->>'platformFeePaise'='230' and quote->>'totalPaise'='11730','one merchant fees');
  perform private.test_assert(quote->>'deliveryAvailable'='false','cart quote allowed without rider');
  quote:=public.dastak_v1_customer_checkout_quote(home,version,basket||'[{"lineType":"RETAIL_SKU","skuId":"00000000-0000-4000-8000-000000000013","quantity":1}]');
  perform private.test_assert(quote->>'deliveryDistanceMeters'='2500' and quote->>'deliveryFeePaise'='2500' and quote->>'platformFeePaise'='350','two merchant route');
  quote:=public.dastak_v1_customer_checkout_quote(home,version,'[{"lineType":"FOOD_MENU_ITEM","menuItemId":"00000000-0000-4000-8000-000000000030","optionIds":["00000000-0000-4000-8000-000000000031"],"quantity":2}]','00000000-0000-4000-8000-000000000003');
  perform private.test_assert(quote->>'subtotalPaise'='46000' and quote->>'platformFeePaise'='950' and quote->>'totalPaise'='48450','food options and tariff');
  begin perform public.dastak_v1_customer_checkout_quote(home,version+interval '1 second',basket); raise exception 'accepted stale address'; exception when sqlstate '22023' then null; end;
  begin perform public.dastak_v1_customer_checkout_quote('00000000-0000-4000-8000-000000000099',version,basket); raise exception 'accepted unowned address'; exception when sqlstate '42501' then null; end;
  begin perform public.dastak_v1_customer_checkout_quote(home,version,basket||basket); raise exception 'accepted duplicate'; exception when sqlstate '22023' then null; end;
  begin perform public.dastak_v1_customer_checkout_quote(home,version,jsonb_set(basket,'{0,quantity}','99')); raise exception 'accepted missing stock'; exception when sqlstate '55000' then null; end;
  perform private.test_assert((select count(*)=1 from dastak_v1.orders) and not exists(select 1 from dastak_v1.order_price_snapshots),'quote never writes order or bill');
  begin update dastak_v1.orders set checkout_pricing_version=1 where checkout_pricing_version=0;
    raise exception 'changed historical pricing version'; exception when sqlstate '22023' then null; end;
  perform private.test_assert(not has_function_privilege('anon','public.dastak_v1_customer_checkout_quote(uuid,timestamptz,jsonb,uuid)','execute')
    and has_function_privilege('authenticated','public.dastak_v1_customer_checkout_quote(uuid,timestamptz,jsonb,uuid)','execute')
    and not has_function_privilege('authenticated','private.checkout_pickup_branches(extensions.geometry,jsonb,uuid)','execute'),'RPC grants');
end;
$$;
insert into dastak_v1.orders(id) values('00000000-0000-4000-8000-000000000091');
insert into dastak_v1.order_context_snapshots values('00000000-0000-4000-8000-000000000091','{"latitude":0,"longitude":0}');
insert into dastak_v1.order_lines values('00000000-0000-4000-8000-000000000091','RETAIL_SKU','00000000-0000-4000-8000-000000000012',1);
insert into dastak_v1.order_price_snapshots values('00000000-0000-4000-8000-000000000091','SUBMITTED',10000,0,0,0,0,10000,'{}');
-- Actual matching picks the farther merchant: secured price must replace estimate.
insert into dastak_v1.fulfilments values('00000000-0000-4000-8000-000000000091','00000000-0000-4000-8000-000000000004','RESERVED_PREPAYMENT');
insert into dastak_v1.order_price_snapshots values('00000000-0000-4000-8000-000000000091','FULLY_SECURED',10000,1500,230,0,0,11730,'{}');
update dastak_v1.merchant_branches set location=point(4500,0); -- Must not reprice collection later.
insert into dastak_v1.order_price_snapshots values('00000000-0000-4000-8000-000000000091','PAID',10000,2500,250,0,0,12750,'{}');
insert into dastak_v1.order_price_snapshots values('00000000-0000-4000-8000-000000000090','FULLY_SECURED',10000,0,0,0,0,10000,'{}');
select private.test_assert((select total_paise=11730 from dastak_v1.order_price_snapshots where snapshot_kind='SUBMITTED'),'submission estimate');
select private.test_assert((select total_paise=12750 from dastak_v1.order_price_snapshots where order_id='00000000-0000-4000-8000-000000000091' and snapshot_kind='FULLY_SECURED'),'actual secured fee');
select private.test_assert((select total_paise=12750 from dastak_v1.order_price_snapshots where snapshot_kind='PAID'),'paid commitment unchanged');
select private.test_assert((select total_paise=10000 from dastak_v1.order_price_snapshots where order_id='00000000-0000-4000-8000-000000000090'),'historical policy unchanged');
select 'CHECKOUT_FEE_CONTRACT_OK' as result;
