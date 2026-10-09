-- Run inside BEGIN / ROLLBACK only. Never commit these synthetic fixtures.
begin;
create temporary table india_checks(label text primary key);
create function pg_temp.india_check(p_ok boolean,p_label text) returns void
language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'India coverage check failed: %',p_label; end if;
  insert into india_checks values(p_label);
end;
$$;
select pg_temp.india_check(extensions.st_isvalid(boundary),'country geometry valid')
from private.dastak_country_coverage;
select pg_temp.india_check(extensions.st_covers(c.boundary,extensions.st_setsrid(extensions.st_makepoint(v.lon,v.lat),4326)),v.name)
from private.dastak_country_coverage c cross join (values
  ('Delhi',28.6139,77.2090),('Mumbai',19.0760,72.8777),('Bengaluru',12.9716,77.5946),
  ('Kolkata',22.5726,88.3639),('Chennai',13.0827,80.2707),('Srinagar',34.0837,74.7973),
  ('Leh',34.1526,77.5771),('Guwahati',26.1445,91.7362),('Itanagar',27.0844,93.6053),
  ('Port Blair',11.6234,92.7265),('Kavaratti',10.5593,72.6358),('Kanyakumari',8.0883,77.5385)
) v(name,lat,lon);
select pg_temp.india_check(not extensions.st_covers(c.boundary,extensions.st_setsrid(extensions.st_makepoint(v.lon,v.lat),4326)),v.name)
from private.dastak_country_coverage c cross join (values
  ('reject Pakistan',31.5204,74.3587),('reject Nepal',27.7172,85.3240),
  ('reject Bangladesh',23.8103,90.4125),('reject Sri Lanka',6.9271,79.8612),
  ('reject UK',51.5074,-0.1278)
) v(name,lat,lon);
select pg_temp.india_check(not has_function_privilege(r.role,
  'public.submit_merchant_application_v3(uuid,text,text,text,text,double precision,double precision,text,text,text)','EXECUTE'),
  r.role||' cannot impersonate Edge') from (values ('anon'),('authenticated')) r(role);
select pg_temp.india_check(has_function_privilege('service_role',
  'public.submit_merchant_application_v3(uuid,text,text,text,text,double precision,double precision,text,text,text)','EXECUTE'),
  'service handler allowed');
select pg_temp.india_check(not has_function_privilege('service_role',
  'private.ensure_dastak_local_service_zone(uuid,extensions.geometry,text)','EXECUTE'),'bootstrap internal only');
select pg_temp.india_check(not has_table_privilege('authenticated','private.dastak_country_coverage','SELECT'),'country private');

create temporary table india_fixture as select extensions.gen_random_uuid() as actor,extensions.gen_random_uuid() as second_actor;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select actor,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',actor||'@example.test','',now(),now(),now() from india_fixture
union all select second_actor,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',second_actor||'@example.test','',now(),now(),now() from india_fixture;
insert into public.accounts(id,display_name,phone_number)
select actor,'India rollback fixture','+919590009981' from india_fixture
union all select second_actor,'India rollback fixture two','+919590009982' from india_fixture;
insert into private.account_memberships(account_id,role)
select actor,'customer'::private.membership_role from india_fixture
union all select second_actor,'customer'::private.membership_role from india_fixture;
insert into storage.objects(bucket_id,name)
select 'dastak-evidence','merchant/'||actor||'/identity.pdf' from india_fixture
union all select 'dastak-evidence','merchant/'||second_actor||'/identity.pdf' from india_fixture;

create temporary table original_zones as select id,extensions.st_astext(boundary) as boundary,active,center,coverage_radius_m from public.service_zones;
create temporary table india_submit as select * from public.submit_merchant_application_v3(
  (select actor from india_fixture),'RETAIL','India Test Legal','Test Shop','Delhi rollback test',
  28.6139,77.2090,'merchant/'||(select actor from india_fixture)||'/identity.pdf','india-submit','india-digest');
select pg_temp.india_check(response_status=200 and response_body->>'status'='pending','Delhi application pending') from india_submit;
select pg_temp.india_check((select count(*) from public.service_zones)=(select count(*)+1 from original_zones),'one local zone created');
select pg_temp.india_check(coverage_radius_m=10000 and not exists(select 1 from extensions.st_dumppoints(boundary) dp where extensions.st_distance(center::extensions.geography,dp.geom::extensions.geography)>10001),'zone stays local')
from public.service_zones where id=(select (response_body->>'serviceZoneId')::uuid from india_submit);
select pg_temp.india_check(not private.customer_area_delivery_available(extensions.st_setsrid(extensions.st_makepoint(77.2090,28.6139),4326)),'zone alone has no delivery');
select pg_temp.india_check(not exists(select 1 from private.customer_area_stock(extensions.st_setsrid(extensions.st_makepoint(77.2090,28.6139),4326))),'zone alone has no stock');
select pg_temp.india_check(response_status=200 and response_body=(select response_body from india_submit),'idempotent replay')
from public.submit_merchant_application_v3(
  (select actor from india_fixture),'RETAIL','India Test Legal','Test Shop','Delhi rollback test',
  28.6139,77.2090,'merchant/'||(select actor from india_fixture)||'/identity.pdf','india-submit','india-digest');
select pg_temp.india_check(response_status=409,'digest mismatch rejected')
from public.submit_merchant_application_v3(
  (select actor from india_fixture),'RETAIL','India Test Legal','Test Shop','Delhi rollback test',
  28.6139,77.2090,'merchant/'||(select actor from india_fixture)||'/identity.pdf','india-submit','different-digest');
select pg_temp.india_check(response_status=409,'pending application cannot create another zone')
from public.submit_merchant_application_v3(
  (select actor from india_fixture),'RETAIL','India Test Legal','Test Shop','Mumbai rollback test',
  19.0760,72.8777,'merchant/'||(select actor from india_fixture)||'/identity.pdf','india-pending','india-pending-digest');
select pg_temp.india_check(response_status=422 and response_body->'error'->>'code'='outside_india','outside India rejected server side')
from public.submit_merchant_application_v3(
  (select second_actor from india_fixture),'RETAIL','Test Legal','Test Shop','Paris',
  48.8566,2.3522,'merchant/'||(select second_actor from india_fixture)||'/identity.pdf','india-outside','india-outside-digest');
select pg_temp.india_check(response_status=400,'missing evidence rejected before zone creation')
from public.submit_merchant_application_v3(
  (select second_actor from india_fixture),'RETAIL','Test Legal','Test Shop','Mumbai',
  19.076,72.8777,'merchant/'||(select second_actor from india_fixture)||'/missing.pdf','india-missing','india-missing-digest');
select pg_temp.india_check((select count(*) from public.service_zones)=(select count(*)+1 from original_zones),'failures and replays create no zones');

-- Reuse, neighbors, paused areas, clipping and original-zone preservation.
create temporary table neighbor_zone as select * from private.ensure_dastak_local_service_zone(
  (select actor from india_fixture),extensions.st_setsrid(extensions.st_makepoint(77.35,28.6139),4326),'Neighbor rollback test');
select pg_temp.india_check(zone_id is not null,'neighbor gets own bounded zone') from neighbor_zone;
select pg_temp.india_check(not extensions.st_overlaps(a.boundary,b.boundary),'neighbor zones do not overlap')
from public.service_zones a join public.service_zones b on a.id=(select zone_id from neighbor_zone)
and b.id=(select (response_body->>'serviceZoneId')::uuid from india_submit);
select pg_temp.india_check(zone_id=(select (response_body->>'serviceZoneId')::uuid from india_submit),'nearby applicant reuses existing zone')
from private.ensure_dastak_local_service_zone((select second_actor from india_fixture),
  extensions.st_setsrid(extensions.st_makepoint(77.2091,28.614),4326),'Delhi nearby');
update public.service_zones set active=false where id=(select zone_id from neighbor_zone);
select pg_temp.india_check(not exists(select 1 from private.ensure_dastak_local_service_zone(
  (select actor from india_fixture),extensions.st_setsrid(extensions.st_makepoint(77.35,28.6139),4326),'Paused test')),'paused area cannot be bypassed');
select pg_temp.india_check(not exists(select 1 from original_zones o join public.service_zones z using(id)
where o.boundary<>extensions.st_astext(z.boundary) or o.active<>z.active or o.coverage_radius_m<>z.coverage_radius_m
or not extensions.st_equals(o.center,z.center)),'original zones unchanged');


-- Existing Admin approval works unchanged in a newly bootstrapped area.
select pg_temp.india_check(not exists(select 1 from dastak_v1.merchant_branches b
join private.merchant_applications a on a.provisioned_branch_id=b.id where a.account_id=(select actor from india_fixture)),
'pending application has no branch');
create temporary table india_retail_approval as select * from public.review_merchant_application(
  (select account_id from private.account_memberships where role='owner' and public.is_active_owner(account_id) order by account_id limit 1),
  (select id from private.merchant_applications where account_id=(select actor from india_fixture)),
  'approve',null,'india-review','india-review-digest');
select pg_temp.india_check(response_status=200 and response_body->>'status'='approved','Admin can approve new-area retail') from india_retail_approval;
select pg_temp.india_check(not s.is_open and not s.accepting_orders,'approved retail starts closed')
from dastak_v1.branch_operational_states s where s.branch_id=(select (response_body->>'branchId')::uuid from india_retail_approval);
select pg_temp.india_check((dastak_v1_api.wave1_branch_configuration(b.id,b.organization_id,b.service_zone_id)->>'retailRadiusMeters')::integer>0,'new area inherits valid matching configuration')
from dastak_v1.merchant_branches b where b.id=(select (response_body->>'branchId')::uuid from india_retail_approval);
create temporary table india_food_submit as select * from public.submit_merchant_application_v3(
  (select second_actor from india_fixture),'RESTAURANT_CAFE','Cafe Legal','Cafe','Mumbai rollback cafe',
  19.0760,72.8777,'merchant/'||(select second_actor from india_fixture)||'/identity.pdf','india-food','india-food-digest');
select pg_temp.india_check(response_status=200 and response_body->>'status'='pending','Mumbai cafe application pending') from india_food_submit;
select pg_temp.india_check(response_status=200 and response_body->>'status'='rejected','Admin rejection preserved')
from public.review_merchant_application(
  (select account_id from private.account_memberships where role='owner' and public.is_active_owner(account_id) order by account_id limit 1),
  (select id from private.merchant_applications where account_id=(select second_actor from india_fixture)),
  'reject','Fixture rejection','india-food-reject','india-food-reject-digest');
select pg_temp.india_check(response_status=200 and response_body->>'applicationId'=(select response_body->>'applicationId' from india_food_submit),'rejected applicant resubmits same record')
from public.submit_merchant_application_v3(
  (select second_actor from india_fixture),'RESTAURANT_CAFE','Cafe Legal','Cafe','Mumbai rollback cafe',
  19.0760,72.8777,'merchant/'||(select second_actor from india_fixture)||'/identity.pdf','india-food-resubmit','india-food-resubmit-digest');
create temporary table india_food_approval as select * from public.review_merchant_application(
  (select account_id from private.account_memberships where role='owner' and public.is_active_owner(account_id) order by account_id limit 1),
  (select id from private.merchant_applications where account_id=(select second_actor from india_fixture)),
  'approve',null,'india-food-review','india-food-review-digest');
select pg_temp.india_check(response_status=200 and response_body->>'status'='approved','Admin can approve new-area cafe') from india_food_approval;
select pg_temp.india_check(not private.customer_restaurant_accepting((response_body->>'branchId')::uuid),'new cafe cannot accept orders yet') from india_food_approval;
select pg_temp.india_check(not s.is_open and not s.accepting_orders,'approved cafe starts closed')
from dastak_v1.branch_operational_states s where s.branch_id=(select (response_body->>'branchId')::uuid from india_food_approval);
select pg_temp.india_check((select count(*) from audit.events where actor_id in(select actor from india_fixture union all select second_actor from india_fixture)
  and action='dastak_local_service_zone_created')=3,'local bootstraps audited once');

select jsonb_build_object('passed',count(*),'checks',jsonb_agg(label order by label)) as india_verification from india_checks;
rollback;
