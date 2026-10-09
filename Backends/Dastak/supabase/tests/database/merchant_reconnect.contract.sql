-- Real linked-schema test, included in a BEGIN/ROLLBACK verifier transaction.
-- All actor, branch, inventory, order and notification fixtures are synthetic.
create temporary table reconnect_fixture as select gen_random_uuid() actor,gen_random_uuid() organization,
  gen_random_uuid() branch,gen_random_uuid() member;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',actor||'@example.test','',now(),now(),now() from reconnect_fixture;
insert into public.accounts(id,display_name,phone_number) select actor,'Reconnect rollback fixture','+919590009984' from reconnect_fixture;
insert into dastak_v1.merchant_organizations(id,legal_name,display_name,merchant_type,status,created_by)
select organization,'Reconnect fixture','Reconnect fixture','RETAIL','ACTIVE',actor from reconnect_fixture;
insert into dastak_v1.merchant_branches(id,organization_id,display_name,service_zone_id,location,status,created_by)
select branch,organization,'Reconnect fixture',z.id,z.center,'ACTIVE',actor from reconnect_fixture
cross join public.service_zones z where z.id='4378540f-ff0c-40ea-b95b-862eba222087';
insert into dastak_v1.branch_operational_states(branch_id,is_open,accepting_orders,updated_by)
select branch,true,true,actor from reconnect_fixture;
insert into dastak_v1.merchant_users(id,organization_id,account_id,status,created_by)
select member,organization,actor,'ACTIVE',actor from reconnect_fixture;
insert into dastak_v1.merchant_permission_grants(merchant_user_id,organization_id,bundle_id,branch_id,granted_by,grant_reason)
select f.member,f.organization,p.bundle_id,f.branch,f.actor,'Rollback test owner'
from reconnect_fixture f cross join (select bp.bundle_id from dastak_v1.permission_bundle_permissions bp
join dastak_v1.permission_bundles b on b.id=bp.bundle_id and b.scope='MERCHANT' and b.active
where bp.permission_key='merchant.opportunities.respond' order by bp.bundle_id limit 1) p;
create temporary table reconnect_sku as select id from dastak_v1.skus where status='ACTIVE' order by id limit 1;
insert into dastak_v1.merchant_sku_selections(branch_id,sku_id,state,stock_quantity,selected_by)
select f.branch,s.id,'SELECTED',99,f.actor from reconnect_fixture f cross join reconnect_sku s;
create temporary table reconnect_orders as select label,gen_random_uuid() id,gen_random_uuid() attempt
from unnest(array['open','cancelled','expired','closed-store','declined','wave2-open']) label;
insert into dastak_v1.orders(id,display_order_number,customer_id,order_type,status,submitted_at,availability_policy_version)
select o.id,'TEST-RECONNECT-'||o.id,f.actor,'RETAIL_ONLY',case when o.label='cancelled' then 'CANCELLED_PREPAYMENT'::dastak_v1.order_status else 'MATCHING'::dastak_v1.order_status end,
now(),0 from reconnect_orders o cross join reconnect_fixture f;
insert into dastak_v1.order_context_snapshots(order_id,delivery_address,recipient,snapshot_hash)
select o.id,jsonb_build_object('latitude',extensions.st_y(z.center),'longitude',extensions.st_x(z.center)),
jsonb_build_object('name','Fixture','phoneNumber','+919590009984'),decode(repeat('00',32),'hex')
from reconnect_orders o cross join public.service_zones z where z.id='4378540f-ff0c-40ea-b95b-862eba222087';
insert into dastak_v1.order_lines(order_id,line_type,sku_id,product_name_snapshot,quantity,unit_price_paise)
select o.id,'RETAIL_SKU',s.id,'Fixture SKU',1,100 from reconnect_orders o cross join reconnect_sku s;
insert into dastak_v1.order_lines(order_id,line_type,sku_id,product_name_snapshot,quantity,unit_price_paise)
select o.id,'RETAIL_SKU',s.id,'Uncovered fixture SKU',1,100 from reconnect_orders o
cross join (select id from dastak_v1.skus where status='ACTIVE' and id not in(select id from reconnect_sku) order by id limit 1) s
where o.label='wave2-open';
insert into dastak_v1.matching_attempts(id,order_id,wave,status,started_at,expires_at)
select attempt,id,case when label='wave2-open' then 'WAVE_2'::dastak_v1.matching_wave else 'WAVE_1'::dastak_v1.matching_wave end,'OPEN',clock_timestamp()-interval '10 minutes',
  case when label='expired' then clock_timestamp()-interval '1 second' else clock_timestamp()+interval '3 minutes' end from reconnect_orders;
insert into dastak_v1.matching_candidate_evaluations(matching_attempt_id,order_id,organization_id,branch_id,eligible,eligibility_snapshot)
select o.attempt,o.id,f.organization,f.branch,true,'{}'::jsonb from reconnect_orders o cross join reconnect_fixture f;
-- A previously declined opportunity is not offered again on heartbeat.
insert into dastak_v1.merchant_opportunities(matching_attempt_id,order_id,organization_id,branch_id,status,started_at,expires_at,responded_by,responded_at)
select o.attempt,o.id,f.organization,f.branch,'DECLINED',clock_timestamp(),a.expires_at,f.actor,clock_timestamp()
from reconnect_orders o cross join reconnect_fixture f join dastak_v1.matching_attempts a on a.id=o.attempt where o.label='declined';
select set_config('request.jwt.claim.sub',actor::text,true) from reconnect_fixture;
select set_config('request.jwt.claim.role','authenticated',true);
do $$declare f record; response jsonb; count_before integer; begin
  select * into f from reconnect_fixture;
  -- Temporarily leave the store closed: owned heartbeat must not grant work.
  update dastak_v1.branch_operational_states s set is_open=false,accepting_orders=false,version=s.version+1 where branch_id=f.branch;
  perform public.dastak_v1_list_merchant_opportunities(100);
  assert not exists(select 1 from dastak_v1.merchant_opportunities where order_id in(select id from reconnect_orders where label<>'declined')),'closed store received work';
  update dastak_v1.branch_operational_states s set is_open=true,accepting_orders=true,version=s.version+1 where branch_id=f.branch;
  -- Close just this synthetic order so it also must not revive.
  update dastak_v1.orders o set status='CANCELLED_PREPAYMENT',version=o.version+1 where id=(select id from reconnect_orders where label='closed-store');
  response:=public.dastak_v1_list_merchant_opportunities(100);
  assert exists(select 1 from jsonb_array_elements(response->'opportunities') x where x->>'displayOrderNumber'='TEST-RECONNECT-'||(select id::text from reconnect_orders where label='open')),'reconnected merchant feed did not contain pending order';
  assert (select count(*)=1 from dastak_v1.merchant_opportunities where order_id=(select id from reconnect_orders where label='open')),'pending order not offered exactly once';
  assert (select count(*)=1 from dastak_v1.merchant_opportunity_lines l join dastak_v1.merchant_opportunities x on x.id=l.opportunity_id where x.order_id=(select id from reconnect_orders where label='open')),'offer lines missing';
  assert (select count(*)=1 from dastak_v1.merchant_opportunities where order_id=(select id from reconnect_orders where label='wave2-open')),'Wave 2 reconnect offer missing';
  assert (select count(*)=1 from dastak_v1.merchant_opportunity_lines l join dastak_v1.merchant_opportunities x on x.id=l.opportunity_id where x.order_id=(select id from reconnect_orders where label='wave2-open')),'Wave 2 included unavailable SKU lines';
  assert not exists(select 1 from dastak_v1.merchant_opportunities where order_id in(select id from reconnect_orders where label in ('cancelled','expired','closed-store'))),'cancelled or expired work revived';
  assert (select count(*)=1 from dastak_v1.domain_events_outbox where event_type='MERCHANT_OPPORTUNITY_OFFERED' and payload->>'orderId'=(select id::text from reconnect_orders where label='open')),'durable notification missing';
  assert not exists(select 1 from dastak_v1.merchant_opportunities x join dastak_v1.matching_attempts a on a.id=x.matching_attempt_id where x.order_id in(select id from reconnect_orders) and x.expires_at<>a.expires_at),'deadline was extended';
  select count(*) into count_before from dastak_v1.merchant_opportunities where order_id in(select id from reconnect_orders);
  perform public.dastak_v1_list_merchant_opportunities(100);
  assert (select count(*)=count_before from dastak_v1.merchant_opportunities where order_id in(select id from reconnect_orders)),'heartbeat duplicated an offer';
  assert not has_function_privilege('authenticated','private.offer_reconnected_wave1(uuid[],uuid)','execute');
  assert not has_function_privilege('service_role','private.offer_reconnected_wave1(uuid[],uuid)','execute');
end;$$;
