-- Only the test harness's disposable local catalogue_reconcile_test database.
drop schema if exists dastak_v1 cascade;
drop schema if exists supabase_migrations cascade;
create schema dastak_v1;
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key, name text, statements text[]);
insert into supabase_migrations.schema_migrations(version,name) values ('20261014224848','prayer_essentials_fixture');
create table dastak_v1.catalogue_browse_versions(version int primary key, state text);
create table dastak_v1.catalogue_browse_nodes(
  version int, node_key text, parent_key text, kind text, label text, sort_order int,
  primary key(version,node_key)
);
create table dastak_v1.catalogue_browse_sources(
  version int, node_key text, source_order int, type_slug text, category_slug text,
  subcategory_slug text, excluded_category_slugs text[] not null default '{}',
  excluded_subcategory_slugs text[] not null default '{}', primary key(version,node_key,source_order)
);
create table dastak_v1.category_types(id uuid primary key, slug text, status text);
create table dastak_v1.categories(id uuid primary key, category_type_id uuid, slug text, status text);
create table dastak_v1.subcategories(id uuid primary key, category_id uuid, slug text, status text);
create table dastak_v1.brands(id uuid primary key, status text);
create table dastak_v1.skus(id uuid primary key, subcategory_id uuid, brand_id uuid, status text);
insert into dastak_v1.catalogue_browse_versions values (1,'ACTIVE');
insert into dastak_v1.catalogue_browse_nodes values
  (1,'fresh-items',null,'SECTION','Fresh Items',10),
  (1,'dairy-bread-eggs','fresh-items','DESTINATION','Dairy, Bread & Eggs',10),
  (1,'milk','dairy-bread-eggs','RAIL','Milk',10),
  (1,'dairy-alternatives','dairy-bread-eggs','RAIL','Dairy Alternatives',120),
  (1,'grocery-kitchen',null,'SECTION','Grocery & Kitchen',20),
  (1,'pooja-store','grocery-kitchen','DESTINATION','Janamaz and Tasbih',10),
  (1,'janamaz','pooja-store','RAIL','Janamaz',10);
insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug,category_slug) values
  (1,'dairy-bread-eggs',10,'dairy-bread-eggs',null),
  (1,'milk',10,'dairy-bread-eggs','milk'),
  (1,'pooja-store',10,'prayer-essentials',null),
  (1,'janamaz',10,'prayer-essentials','janamaz');
insert into dastak_v1.category_types values
  ('00000000-0000-0000-0000-000000000001','dairy-bread-eggs','ACTIVE'),
  ('00000000-0000-0000-0000-000000000002','prayer-essentials','ACTIVE');
insert into dastak_v1.categories values
  ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','milk','ACTIVE'),
  ('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000001','dairy-alternatives','ACTIVE'),
  ('00000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000002','janamaz','ACTIVE');
insert into dastak_v1.subcategories values
  ('00000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000011','fresh-milk','ACTIVE'),
  ('00000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000012','soy-milk','ACTIVE'),
  ('00000000-0000-0000-0000-000000000023','00000000-0000-0000-0000-000000000013','standard-janamaz','ACTIVE');
insert into dastak_v1.skus values
  ('00000000-0000-0000-0000-000000000031','00000000-0000-0000-0000-000000000021',null,'ACTIVE'),
  ('00000000-0000-0000-0000-000000000032','00000000-0000-0000-0000-000000000022',null,'ACTIVE'),
  ('00000000-0000-0000-0000-000000000033','00000000-0000-0000-0000-000000000023',null,'ACTIVE');
