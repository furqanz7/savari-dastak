-- Transaction-local fixture helpers. Never installed by migrations or discovered as standalone pgTAP.
-- Tests opt in explicitly; no production admission guard is altered.
create function pg_temp.available_rider(p_zone uuid,p_reviewer uuid)
returns void language plpgsql as $$
declare rider uuid:=gen_random_uuid(); application uuid:=gen_random_uuid();
begin
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at)
  values(rider,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',rider||'@example.test','',now());
  insert into public.accounts(id,display_name,phone_number)
  values(rider,'Isolated eligible rider','+91999'||lpad((abs(hashtext(rider::text)::bigint)%10000000)::text,7,'0'));
  insert into private.account_memberships(account_id,role,approved_at) values(rider,'dastak_partner',now());
  insert into private.delivery_partner_applications
    (id,account_id,delivery_method,identity_evidence_object_path,status,reviewed_at,reviewed_by)
  values(application,rider,'motorbike','dastak-partner/'||rider||'/id.jpg','approved',now(),p_reviewer);
  insert into private.delivery_partner_profiles(account_id,approved_application_id,delivery_method)
  values(rider,application,'motorbike');
  insert into private.delivery_partner_availability
    (account_id,status,location,service_zone_id,last_seen_at,available_until)
  select rider,'online',extensions.st_pointonsurface(boundary),id,now(),now()+interval '1 hour'
  from public.service_zones where id=p_zone;
end;
$$;

create function pg_temp.stocked_store(p_zone uuid,p_owner uuid,p_sku uuid,p_quantity integer)
returns void language plpgsql as $$
declare organization uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid();
begin
  insert into dastak_v1.platform_settings(setting_key,scope_type,setting_value,updated_by,update_reason)
  values('matching.retail_radius_meters','GLOBAL','3000',p_owner,'Isolated stock fixture') on conflict do nothing;
  insert into dastak_v1.platform_settings(setting_key,scope_type,setting_value,updated_by,update_reason)
  values('merchant.reachability_stale_seconds','GLOBAL','120',p_owner,'Isolated stock fixture') on conflict do nothing;
  insert into dastak_v1.merchant_organizations(id,legal_name,display_name,merchant_type,status,created_by)
  values(organization,'Fixture Retail Legal','Fixture Retail','RETAIL','ACTIVE',p_owner);
  insert into dastak_v1.merchant_branches(id,organization_id,display_name,service_zone_id,address_snapshot,location,capacity_limit,status,created_by)
  values(branch,organization,'Fixture Store',p_zone,'{}',extensions.st_setsrid(extensions.st_makepoint(78.62,12.68),4326),5,'ACTIVE',p_owner);
  insert into dastak_v1.branch_operational_states(branch_id,is_open,accepting_orders,updated_by)
  values(branch,true,true,p_owner);
  insert into dastak_v1.merchant_branch_reachability(branch_id,last_seen_at,reported_by)
  values(branch,now(),p_owner) on conflict(branch_id) do nothing;
  insert into dastak_v1.merchant_sku_selections(branch_id,sku_id,state,selected_by,stock_quantity)
  values(branch,p_sku,'SELECTED',p_owner,p_quantity);
end;
$$;
