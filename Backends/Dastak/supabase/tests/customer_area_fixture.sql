-- Synthetic local schema. Native box/point is a PostGIS stand-in, NOT a geodesic test.
\ir customer_food_pages_fixture.sql
create role service_role;
create schema private;
create schema extensions;
create domain extensions.geometry as point;
create domain extensions.geography as point;
create function extensions.st_covers(b box,p extensions.geometry) returns boolean language sql immutable strict as $$select p::point <@ b$$;
create function extensions.st_distance(a extensions.geography,b extensions.geography) returns double precision language sql immutable as $$select a::point <-> b::point$$;
create function extensions.st_makepoint(a double precision,b double precision) returns extensions.geometry language sql immutable as $$select point(a,b)$$;
create function extensions.st_setsrid(a extensions.geometry,b integer) returns extensions.geometry language sql immutable as $$select a$$;
alter table public.service_zones add column boundary box;
update public.service_zones set boundary=box(point(-100,-100),point(100,100));
insert into public.service_zones values ('ffffffff-ffff-4fff-8fff-ffffffffffff',true,box(point(500,500),point(600,600)));
alter table dastak_v1.merchant_branches add column location extensions.geometry;
update dastak_v1.merchant_branches set location=point(0,0);
create table private.customer_delivery_addresses(id uuid primary key,account_id uuid,location extensions.geometry,updated_at timestamptz,is_default boolean);
insert into private.customer_delivery_addresses values
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',point(0,0),'2026-10-08T00:00:00Z',true),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',point(1000,1000),'2026-10-08T00:00:00Z',false),
 ('99999999-9999-4999-8999-999999999999','99999999-9999-4999-8999-999999999999',point(0,0),'2026-10-08T00:00:00Z',true);
create table public.accounts(id uuid primary key,account_state text);
create table private.account_memberships(account_id uuid,role text,approved_at timestamptz,suspended_until timestamptz);
create table private.account_personas(account_id uuid,persona text,state text);
create table private.delivery_partner_applications(id uuid primary key,account_id uuid,status text);
create table private.delivery_partner_profiles(account_id uuid,approved_application_id uuid,governance_status text);
create table private.delivery_partner_availability(account_id uuid,status text,location extensions.geometry,service_zone_id uuid,available_until timestamptz);
create table dastak_v1.skus(id uuid primary key,status text);
create table dastak_v1.merchant_sku_selections(branch_id uuid,sku_id uuid,state text,stock_quantity integer);
create table dastak_v1.orders(id uuid primary key,customer_id uuid,status text);
create table dastak_v1.order_context_snapshots(order_id uuid,delivery_address jsonb);
create table dastak_v1.order_lines(order_id uuid,line_type text,sku_id uuid,quantity integer);
create function dastak_v1_api.wave1_branch_configuration(a uuid,b uuid,c uuid) returns jsonb language sql as $$select '{"retailRadiusMeters":1000}'::jsonb$$;
create or replace function dastak_v1_api.restaurant_menu_json(branch uuid,admin_mode boolean) returns jsonb language sql as $$
 select jsonb_build_object('restaurant',jsonb_build_object('branchId',b.id,'branchStatus',b.status,'isOpen',coalesce(s.is_open,false),'acceptingOrders',coalesce(s.accepting_orders,false)))
 from dastak_v1.merchant_branches b left join dastak_v1.branch_operational_states s on s.branch_id=b.id where b.id=branch;
$$;
-- Test the guarded source transformation independently of full lifecycle fixtures.
-- These five stubs are NOT matching end-to-end coverage. Production predicate shapes were checked read-only.
do $$declare signature text; begin
 foreach signature in array array[
  'evaluate_wave1_candidate(p_order_id uuid,p_branch_id uuid)',
  'start_wave2(p_order_id uuid,p_actor_id uuid)',
  'lock_best_wave2_plan(p_order_id uuid,p_actor_id uuid,p_force boolean)',
  'accept_wave2_opportunity(p_order_id uuid,p_actor_id uuid,p_key text,p_version bigint,p_minutes integer)',
  'recovery_branch_eligibility(p_order_id uuid,p_branch_id uuid)'
 ] loop
  execute 'create function dastak_v1_api.'||signature||' returns boolean language plpgsql as $body$
   declare v_order dastak_v1.orders%rowtype; v_case record; result boolean;
   begin select * into v_order from dastak_v1.orders where id=p_order_id;
    select p_order_id order_id into v_case;
    select (selection.stock_quantity is null or selection.stock_quantity>=1) into result
      from dastak_v1.merchant_sku_selections selection where selection.sku_id=''00000000-0000-4000-8000-000000000003'';
    return result; end; $body$';
 end loop;
end;$$;
insert into dastak_v1.merchant_organizations values ('11111111-1111-4111-8111-111111111111','Retail','RETAIL','ACTIVE');
insert into dastak_v1.merchant_branches values ('11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Retail','ACTIVE',point(0,0));
insert into dastak_v1.branch_operational_states values ('11111111-1111-4111-8111-111111111111',true,true);
insert into dastak_v1.skus select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'ACTIVE' from generate_series(1,4)i;
insert into dastak_v1.merchant_sku_selections select '11111111-1111-4111-8111-111111111111',id,'SELECTED',case when id::text like '%001' then 5 when id::text like '%002' then 0 when id::text like '%004' then 10 else null end from dastak_v1.skus;
insert into public.accounts values ('22222222-2222-4222-8222-222222222222','ACTIVE');
insert into private.account_memberships values ('22222222-2222-4222-8222-222222222222','dastak_partner',now(),null);
insert into private.delivery_partner_applications values ('22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222','approved');
insert into private.delivery_partner_profiles values ('22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222','ACTIVE');
insert into private.delivery_partner_availability values ('22222222-2222-4222-8222-222222222222','online',point(0,0),'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',now()+interval '10 minutes');
insert into dastak_v1.orders values ('00000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','CREATED');
-- Source-patch fixture only; the production implementation retains its row locks.
create function dastak_v1_api.apply_order_stock(p_hold_id uuid,p_action text) returns void language plpgsql as $$
declare v_selection record; v_line record;
begin
 select null::integer stock_quantity into v_selection;
 select p_hold_id order_id into v_line;
 if p_action='RESERVE' then
   if v_selection.stock_quantity is null then return; end if;
 end if;
end;$$;
