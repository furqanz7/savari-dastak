-- Included only in the verifier's BEGIN/ROLLBACK transaction.
create temporary table radius_checks(label text primary key);
create function pg_temp.radius_check(ok boolean,label text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception '30 km check failed: %',label; end if;
  insert into radius_checks values(label);
end;$$;
create temporary table radius_fixture as select gen_random_uuid() actor,gen_random_uuid() retail,
  gen_random_uuid() cafe,gen_random_uuid() home,gen_random_uuid() test_order,
  extensions.st_setsrid(extensions.st_makepoint(77.209,28.6139),4326) origin;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',actor||'@example.test','',now(),now(),now() from radius_fixture;
insert into public.accounts(id,display_name,phone_number)
select actor,'30 km rollback fixture','+919590009983' from radius_fixture;
insert into private.account_memberships(account_id,role) select actor,'customer' from radius_fixture;
create temporary table radius_zone as select * from private.ensure_dastak_local_service_zone(
  (select actor from radius_fixture),(select origin from radius_fixture),'30 km rollback zone');
insert into dastak_v1.merchant_organizations(id,legal_name,display_name,merchant_type,status,created_by)
select retail,'Test retail','Test retail','RETAIL'::dastak_v1.merchant_type,'ACTIVE'::dastak_v1.merchant_status,actor from radius_fixture
union all select cafe,'Test cafe','Test cafe','RESTAURANT_CAFE'::dastak_v1.merchant_type,'ACTIVE'::dastak_v1.merchant_status,actor from radius_fixture;
insert into dastak_v1.merchant_branches(id,organization_id,display_name,service_zone_id,location,status,created_by)
select retail,retail,'Test retail',(select zone_id from radius_zone),origin,'ACTIVE'::dastak_v1.branch_status,actor from radius_fixture
union all select cafe,cafe,'Test cafe',(select zone_id from radius_zone),origin,'ACTIVE'::dastak_v1.branch_status,actor from radius_fixture;
insert into dastak_v1.branch_operational_states(branch_id,is_open,accepting_orders,updated_by)
select retail,false,false,actor from radius_fixture union all select cafe,false,false,actor from radius_fixture;
insert into private.customer_delivery_addresses(id,account_id,label,address,details,building,location,is_default)
select home,actor,'Test','Rollback test','Test','Test building',origin,true from radius_fixture;
select set_config('request.jwt.claim.sub',actor::text,true) from radius_fixture;

do $$
declare fixture record; distance integer; availability jsonb; page jsonb; version timestamptz; point extensions.geometry;
begin
  select * into fixture from radius_fixture;
  foreach distance in array array[0,29999,30001] loop
    point:=extensions.st_project(fixture.origin::extensions.geography,distance,0)::extensions.geometry;
    update private.customer_delivery_addresses set location=point where id=fixture.home returning updated_at into version;
    availability:=public.dastak_v1_customer_area_availability(fixture.home,version);
    perform pg_temp.radius_check((availability->>'groceryServiceable')::boolean=(distance<=30000),'Grocery distance '||distance);
    perform pg_temp.radius_check((availability->>'foodServiceable')::boolean=(distance<=30000),'Food distance '||distance);
    perform pg_temp.radius_check(not (availability->>'deliveryAvailable')::boolean,'No rider remains blocked at '||distance);
    page:=public.dastak_v1_customer_restaurants_area_page(fixture.home,version,null,100,null,null,null,fixture.cafe);
    perform pg_temp.radius_check(jsonb_array_length(page->'restaurants')=case when distance<=30000 then 1 else 0 end,'Food page distance '||distance);
    page:=dastak_v1_api.list_customer_restaurants_page(fixture.actor,null,100,null,null,fixture.cafe);
    perform pg_temp.radius_check(jsonb_array_length(page->'restaurants')=case when distance<=30000 then 1 else 0 end,'Legacy Food page distance '||distance);
  end loop;
  -- Exact boundary predicate uses metres, not rounded UI distances or degrees.
  point:=extensions.st_project(fixture.origin::extensions.geography,30000,0)::extensions.geometry;
  update private.customer_delivery_addresses set location=point where id=fixture.home returning updated_at into version;
  availability:=public.dastak_v1_customer_area_availability(fixture.home,version);
  perform pg_temp.radius_check((availability->>'groceryServiceable')::boolean,'30 km inclusive boundary');
  perform pg_temp.radius_check(not extensions.st_covers((select boundary from public.service_zones where id=(select zone_id from radius_zone)),point),'Customer outside original 10 km zone');
  perform pg_temp.radius_check(availability->'stock'='{}'::jsonb,'Closed empty merchant has no stock');
  perform pg_temp.radius_check(availability->'restaurants'->>fixture.cafe::text='false','Closed cafe stays listed and disabled');
  update dastak_v1.branch_operational_states s set is_open=true,accepting_orders=true,version=s.version+1 where branch_id=fixture.retail;
  insert into dastak_v1.merchant_sku_selections(branch_id,sku_id,state,stock_quantity,selected_by)
  select fixture.retail,id,'SELECTED',5,fixture.actor from dastak_v1.skus where status='ACTIVE' order by id limit 1;
  availability:=public.dastak_v1_customer_area_availability(fixture.home,version);
  perform pg_temp.radius_check(exists(select 1 from jsonb_each_text(availability->'stock') where value='5'),'Positive stock at 30 km outside merchant zone');
  perform pg_temp.radius_check(private.checkout_pickup_branches(point,
    (select jsonb_build_array(jsonb_build_object('skuId',sku_id,'quantity',1)) from dastak_v1.merchant_sku_selections where branch_id=fixture.retail))=array[fixture.retail],'Quote pickup uses same radius');
  -- Synthetic CREATED order only: never submit, secure, dispatch or pay it.
  -- Seed a legacy context to compare both evaluator policies in isolation.
  insert into dastak_v1.orders(id,display_order_number,customer_id,order_type,availability_policy_version)
  values(fixture.test_order,'TEST-'||fixture.test_order,fixture.actor,'RETAIL_ONLY',0);
  insert into dastak_v1.order_context_snapshots(order_id,delivery_address,recipient,snapshot_hash)
  values(fixture.test_order,jsonb_build_object('latitude',extensions.st_y(point),'longitude',extensions.st_x(point)),
    '{}'::jsonb,decode(repeat('00',32),'hex'));
  insert into dastak_v1.order_lines(order_id,line_type,sku_id,product_name_snapshot,quantity,unit_price_paise)
  select fixture.test_order,'RETAIL_SKU',sku_id,'Test product',1,100 from dastak_v1.merchant_sku_selections where branch_id=fixture.retail;
  availability:=dastak_v1_api.evaluate_wave1_candidate(fixture.test_order,fixture.retail);
  perform pg_temp.radius_check(availability->'exclusionReasons' ? 'CUSTOMER_OUTSIDE_SERVICE_ZONE','Legacy matching keeps zone rule');
  update dastak_v1.orders o set availability_policy_version=1,version=o.version+1 where id=fixture.test_order;
  availability:=dastak_v1_api.evaluate_wave1_candidate(fixture.test_order,fixture.retail);
  perform pg_temp.radius_check((availability->>'eligible')::boolean,'New matching eligible at 30 km');
  availability:=dastak_v1_api.evaluate_wave2_candidate(fixture.test_order,fixture.retail);
  perform pg_temp.radius_check((availability->>'eligible')::boolean,'Wave 2 uses same 30 km evaluator');
  -- New submission must still reject no-rider context, even with nearby stock.
  insert into dastak_v1.orders(id,display_order_number,customer_id,order_type)
  values(gen_random_uuid(),'TEST-BLOCK-'||fixture.test_order,fixture.actor,'RETAIL_ONLY') returning id into fixture.test_order;
  begin insert into dastak_v1.order_context_snapshots(order_id,delivery_address,recipient,snapshot_hash)
    values(fixture.test_order,jsonb_build_object('latitude',extensions.st_y(point),'longitude',extensions.st_x(point)),
      '{}'::jsonb,decode(repeat('00',32),'hex'));
    raise exception 'No rider context accepted'; exception when object_not_in_prerequisite_state then
    perform pg_temp.radius_check(true,'New-order trigger rejects no rider'); end;
  update dastak_v1.merchant_sku_selections s set stock_quantity=0,version=s.version+1 where branch_id=fixture.retail;
  availability:=public.dastak_v1_customer_area_availability(fixture.home,version);
  perform pg_temp.radius_check(availability->'stock'='{}'::jsonb,'Zero stock is unavailable');
  begin perform private.checkout_pickup_branches(point,
    (select jsonb_build_array(jsonb_build_object('skuId',sku_id,'quantity',1)) from dastak_v1.merchant_sku_selections where branch_id=fixture.retail));
    raise exception 'Zero stock quoted'; exception when object_not_in_prerequisite_state then
    perform pg_temp.radius_check(true,'Zero stock cannot get pickup quote'); end;
  update dastak_v1.merchant_branches set customer_listing_visible=false where id=fixture.cafe;
  availability:=public.dastak_v1_customer_area_availability(fixture.home,version);
  perform pg_temp.radius_check(not (availability->>'foodServiceable')::boolean,'Admin-removed cafe not serviceable');
  perform pg_temp.radius_check((availability->>'groceryServiceable')::boolean,'Services independent');
  page:=public.dastak_v1_customer_restaurants_area_page(fixture.home,version,null,100,null,null,null,fixture.cafe);
  perform pg_temp.radius_check(jsonb_array_length(page->'restaurants')=0,'Admin-removed cafe excluded from page');
  update dastak_v1.merchant_branches set customer_listing_visible=true,location=null where id=fixture.cafe;
  availability:=public.dastak_v1_customer_area_availability(fixture.home,version);
  perform pg_temp.radius_check(not (availability->>'foodServiceable')::boolean,'Missing provider location fails closed');
  begin perform public.dastak_v1_customer_area_availability(fixture.home,version+interval '1 second');
    raise exception 'Stale address accepted'; exception when invalid_parameter_value then
    perform pg_temp.radius_check(true,'Address version still enforced'); end;
end;$$;
select pg_temp.radius_check(not has_function_privilege('anon','public.dastak_v1_customer_area_availability(uuid,timestamptz)','execute'),'Authenticated owned address required');
select pg_temp.radius_check(not has_function_privilege('authenticated','private.customer_area_stock(extensions.geometry,uuid)','execute'),'Private inventory grants unchanged');
