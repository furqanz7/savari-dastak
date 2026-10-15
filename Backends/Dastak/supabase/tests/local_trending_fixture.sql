-- Isolated PostgreSQL fixture. Point distance is a SQL-logic stand-in, not a
-- PostGIS/geodesic integration test. No real orders or merchant stock are used.
\ir customer_area_fixture.sql
create function extensions.st_dwithin(a extensions.geography,b extensions.geography,d double precision)
returns boolean language sql immutable strict as $$select (a::point <-> b::point)*111195<=d$$;
create function private.customer_area_stock(p_location extensions.geometry,p_sku_id uuid default null)
returns table(sku_id uuid,available_quantity integer) language sql stable as $$
  select selection.sku_id,max(selection.stock_quantity)::integer from dastak_v1.merchant_sku_selections selection
  join dastak_v1.merchant_branches branch on branch.id=selection.branch_id and branch.status='ACTIVE'
  join dastak_v1.branch_operational_states state on state.branch_id=branch.id and state.is_open and state.accepting_orders
  where selection.state='SELECTED' and selection.stock_quantity>0
    and (p_sku_id is null or selection.sku_id=p_sku_id)
    and extensions.st_dwithin(branch.location::extensions.geography,p_location::extensions.geography,30000.001)
  group by selection.sku_id;
$$;
create function private.customer_owned_area(p_actor_id uuid,p_address_id uuid,p_address_version timestamptz)
returns extensions.geometry language plpgsql stable as $$
declare address private.customer_delivery_addresses%rowtype;
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_actor_id is distinct from auth.uid() then raise exception using errcode='42501',message='customer required'; end if;
  select * into address from private.customer_delivery_addresses where id=p_address_id and account_id=p_actor_id;
  if not found then raise exception using errcode='42501',message='delivery address unavailable'; end if;
  if p_address_version is null or address.updated_at<>p_address_version then
    raise exception using errcode='22023',message='delivery address changed'; end if;
  return address.location;
end;$$;
alter table dastak_v1.orders add column delivered_at timestamptz;
alter table dastak_v1.order_lines add column status text default 'FULFILLED';
create table dastak_v1.category_types(id uuid primary key,status text,slug text);
create table dastak_v1.categories(id uuid primary key,category_type_id uuid,status text);
create table dastak_v1.subcategories(id uuid primary key,category_id uuid,status text);
create table dastak_v1.brands(id uuid primary key,name text,slug text,status text);
create table dastak_v1.sku_images(id uuid primary key,sku_id uuid,image_key text,role text,status text,rights_status text,sort_order integer);
alter table dastak_v1.skus add column subcategory_id uuid,add column brand_id uuid,
  add column canonical_name text,add column slug text,add column variant_name text,add column pack_size text,
  add column description text,add column barcode text,add column quantity_value numeric,add column quantity_unit text,
  add column pack_count integer,add column manufacturer_name text,add column country_of_origin_code text,
  add column diet_type text,add column shelf_life_days integer,add column attribute_data jsonb default '{}',
  add column list_price_paise bigint default 1000,add column selling_price_paise bigint default 1000,
  add column currency_code text default 'INR',add column logistics_attributes jsonb default '{}';
insert into dastak_v1.category_types values(md5('type')::uuid,'ACTIVE','groceries');
insert into dastak_v1.categories values(md5('category')::uuid,md5('type')::uuid,'ACTIVE');
insert into dastak_v1.subcategories values(md5('sub')::uuid,md5('category')::uuid,'ACTIVE');
insert into dastak_v1.brands values(md5('brand')::uuid,'Test dairy','test-dairy','ACTIVE');
update dastak_v1.skus set subcategory_id=md5('sub')::uuid,brand_id=md5('brand')::uuid,slug='sku-'||id,
  pack_size=case when id::text like '%002' then '500 ml' else '1 L' end,
  canonical_name=case when id::text like '%001' then 'Test Milk 1 L' when id::text like '%002' then 'Test Milk 500 ml'
    when id::text like '%003' then 'Unavailable product' else 'Test Butter' end;
insert into dastak_v1.sku_images select md5('image'||id)::uuid,id,'test/'||id||'.jpg','PRIMARY','VERIFIED','CLEARED',0 from dastak_v1.skus;
create function dastak_v1_api.customer_area_availability(p_actor_id uuid,p_address_id uuid,p_address_version timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare origin extensions.geometry; result jsonb;
begin
  origin:=private.customer_owned_area(p_actor_id,p_address_id,p_address_version);
  result:=jsonb_build_object('addressId',p_address_id,'addressVersion',p_address_version,'stock','{}'::jsonb);
  return result;
end;$$;
insert into dastak_v1.orders(id,customer_id,status,delivered_at) select md5('trend-order'||i)::uuid,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',case when i=4 then 'CANCELLED' else 'DELIVERED' end,
  case when i=5 then now()-interval '31 days' else now()-interval '1 day' end from generate_series(1,9)i;
insert into dastak_v1.order_context_snapshots select md5('trend-order'||i)::uuid,
  case when i=6 then '{"latitude":0,"longitude":1}'::jsonb
    when i=7 then '{}'::jsonb else '{"latitude":0,"longitude":0}'::jsonb end from generate_series(1,9)i;
insert into dastak_v1.order_lines(order_id,line_type,sku_id,quantity,status) select md5('trend-order'||i)::uuid,'RETAIL_SKU',
  ('00000000-0000-4000-8000-'||lpad((case when i=2 then 2 when i=3 then 4 when i=8 then 3 else 1 end)::text,12,'0'))::uuid,
  case when i=3 then 99 else 1 end,case when i=9 then 'REFUNDED' else 'FULFILLED' end from generate_series(1,9)i;
