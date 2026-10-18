create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create schema dastak_v1;
create schema dastak_v1_api;
grant usage on schema auth,dastak_v1_api to authenticated;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function dastak_v1_api.assert_authenticated_actor(actor uuid) returns void language plpgsql as $$begin
  if actor is null or actor is distinct from auth.uid() then raise insufficient_privilege; end if;
end$$;
create table dastak_v1.merchant_organizations(id uuid primary key,status text,merchant_type text);
create table dastak_v1.merchant_branches(id uuid primary key,organization_id uuid,display_name text);
create table dastak_v1.merchant_users(id uuid primary key,account_id uuid,organization_id uuid,status text);
create table dastak_v1.permission_bundles(id uuid primary key,scope text,active boolean);
create table dastak_v1.permission_bundle_permissions(bundle_id uuid,permission_key text);
create table dastak_v1.merchant_permission_grants(merchant_user_id uuid,organization_id uuid,bundle_id uuid,branch_id uuid,revoked_at timestamptz);
create table dastak_v1.category_types(id uuid primary key,name text);
create table dastak_v1.categories(id uuid primary key,category_type_id uuid,name text);
create table dastak_v1.subcategories(id uuid primary key,category_id uuid,name text);
create table dastak_v1.brands(id uuid primary key,name text);
create table dastak_v1.skus(id uuid primary key,canonical_name text,variant_name text,pack_size text default '100 g',description text,
  subcategory_id uuid,brand_id uuid,status text default 'ACTIVE',quantity_value numeric,quantity_unit text,pack_count integer,diet_type text,
  list_price_paise integer default 100,selling_price_paise integer default 90,currency_code text default 'INR',
  search_document tsvector generated always as (to_tsvector('pg_catalog.simple',coalesce(canonical_name,'')||' '||coalesce(description,''))) stored);
create index fixture_sku_name on dastak_v1.skus(lower(canonical_name),id);
create table dastak_v1.merchant_sku_selections(branch_id uuid,sku_id uuid,state text,version integer,updated_at timestamptz,
  stock_quantity integer,stock_reserved_quantity integer,primary key(branch_id,sku_id));
create table dastak_v1.sku_images(id uuid primary key,sku_id uuid,image_key text,role text,status text,rights_status text,sort_order integer);
create table dastak_v1.sku_search_aliases(sku_id uuid,alias text,search_document tsvector generated always as (to_tsvector('pg_catalog.simple',alias)) stored);
insert into dastak_v1.merchant_organizations values
 ('95000000-0000-4000-8000-000000000001','ACTIVE','RETAIL'),('95000000-0000-4000-8000-000000000002','ACTIVE','RESTAURANT_CAFE');
insert into dastak_v1.merchant_branches values
 ('95000000-0000-4000-8000-000000000011','95000000-0000-4000-8000-000000000001','Current Store'),
 ('95000000-0000-4000-8000-000000000012','95000000-0000-4000-8000-000000000002','OTHER_MERCHANT_SECRET');
insert into dastak_v1.merchant_branches select md5('branch-'||i)::uuid,'95000000-0000-4000-8000-000000000001','Quiet Store '||i from generate_series(1,150)i;
insert into dastak_v1.merchant_users values
 ('95000000-0000-4000-8000-000000000021','95000000-0000-4000-8000-000000000031','95000000-0000-4000-8000-000000000001','ACTIVE'),
 ('95000000-0000-4000-8000-000000000022','95000000-0000-4000-8000-000000000032','95000000-0000-4000-8000-000000000001','ACTIVE');
insert into dastak_v1.permission_bundles values ('95000000-0000-4000-8000-000000000041','MERCHANT',true);
insert into dastak_v1.permission_bundle_permissions select '95000000-0000-4000-8000-000000000041',p
  from unnest(array['merchant.catalogue.selection.manage','merchant.fulfilment.manage','merchant.restaurant.menu.manage','merchant.opportunities.respond'])p;
insert into dastak_v1.merchant_permission_grants values
 ('95000000-0000-4000-8000-000000000021','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000041',null,null),
 ('95000000-0000-4000-8000-000000000022','95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000041','95000000-0000-4000-8000-000000000011',null);
insert into dastak_v1.category_types values ('95000000-0000-4000-8000-000000000051','Beverages');
insert into dastak_v1.categories values ('95000000-0000-4000-8000-000000000052','95000000-0000-4000-8000-000000000051','Hot drinks');
insert into dastak_v1.subcategories values ('95000000-0000-4000-8000-000000000053','95000000-0000-4000-8000-000000000052','Tea leaves');
insert into dastak_v1.brands values ('95000000-0000-4000-8000-000000000054','Acme');
insert into dastak_v1.skus(id,canonical_name,description,subcategory_id,brand_id)
 select md5('sku-'||i)::uuid,'A product '||lpad(i::text,5,'0'),'Aromatic',
 '95000000-0000-4000-8000-000000000053','95000000-0000-4000-8000-000000000054' from generate_series(1,5200)i;
insert into dastak_v1.skus(id,canonical_name,description,subcategory_id,brand_id,status) values
 ('95000000-0000-4000-8000-000000000061','Z Beyond cap tea','Aromatic','95000000-0000-4000-8000-000000000053','95000000-0000-4000-8000-000000000054','INACTIVE'),
 ('95000000-0000-4000-8000-000000000062','PRIVATE_DRAFT','draft','95000000-0000-4000-8000-000000000053',null,'DRAFT');
insert into dastak_v1.merchant_sku_selections values ('95000000-0000-4000-8000-000000000011','95000000-0000-4000-8000-000000000061','SELECTED',7,now(),11,3);
insert into dastak_v1.sku_search_aliases(sku_id,alias) values('95000000-0000-4000-8000-000000000061','chai');
insert into dastak_v1.sku_images values
 ('95000000-0000-4000-8000-000000000071','95000000-0000-4000-8000-000000000061','UNLICENSED_SECRET','PRIMARY','VERIFIED','UNCLEARED',0),
 ('95000000-0000-4000-8000-000000000072','95000000-0000-4000-8000-000000000061','cleared.png','PRIMARY','VERIFIED','CLEARED',1),
 ('95000000-0000-4000-8000-000000000073','95000000-0000-4000-8000-000000000061','gallery.png','GALLERY','VERIFIED','CLEARED',1);
