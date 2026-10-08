do $$
#variable_conflict use_variable
declare id uuid:=md5('branch205')::uuid; result jsonb; before_status text; before_open boolean; begin
 update dastak_v1.branch_operational_states set is_open=false,accepting_orders=false where branch_id=id;
 select status into before_status from dastak_v1.merchant_branches where merchant_branches.id=id;
 select is_open into before_open from dastak_v1.branch_operational_states where branch_id=id;
 begin perform private.admin_set_restaurant_customer_visibility('99999999-9999-4999-8999-999999999999',id,false,1,'Reviewed','unauthorized'); raise exception 'non-admin accepted'; exception when insufficient_privilege then null; end;
 result:=public.dastak_v1_admin_set_restaurant_customer_visibility(id,false,1,'Reviewed merchant request','remove-one');
 assert not (result->>'customerListingVisible')::boolean and (result->>'version')::integer=2;
 assert (select count(*)=1 from dastak_v1.audit_events),'one audit event';
 assert public.dastak_v1_admin_set_restaurant_customer_visibility(id,false,1,'Reviewed merchant request','remove-one')=result,'idempotent replay';
 assert (select count(*)=1 from dastak_v1.audit_events),'no duplicate audit';
 assert (select status=before_status from dastak_v1.merchant_branches where merchant_branches.id=id),'status preserved';
 assert (select is_open=before_open from dastak_v1.branch_operational_states where branch_id=id),'operations preserved';
 assert not private.customer_restaurant_accepting(id);
 update private.delivery_partner_availability set status='online',location=point(0,0),service_zone_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',available_until=now()+interval '10 minutes';
 update private.delivery_partner_profiles set governance_status='ACTIVE';
 update private.account_memberships set suspended_until=null;
 insert into dastak_v1.orders(id,customer_id,status,availability_policy_version,restaurant_branch_id)
 values('00000000-0000-4000-8000-000000000020','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','CREATED',1,id);
 begin insert into dastak_v1.order_context_snapshots values('00000000-0000-4000-8000-000000000020','{"latitude":0,"longitude":0}'); raise exception 'removed restaurant submission accepted'; exception when object_not_in_prerequisite_state then
  assert sqlerrm='This restaurant is no longer available. Your cart is saved.'; end;
 update dastak_v1.orders set restaurant_branch_id=id where orders.id='00000000-0000-4000-8000-000000000002';
 begin update dastak_v1.orders set status='PAID' where orders.id='00000000-0000-4000-8000-000000000002'; raise exception 'removed restaurant confirmation accepted'; exception when object_not_in_prerequisite_state then
  assert sqlerrm='This restaurant is no longer available. Your cart is saved.'; end;
 assert not (public.dastak_v1_customer_area_availability('dddddddd-dddd-4ddd-8ddd-dddddddddddd','2026-10-08T00:00:00Z')->'restaurants' ? id::text),'fresh snapshot removes cached store';
 assert jsonb_array_length(public.dastak_v1_customer_restaurants_area_page('dddddddd-dddd-4ddd-8ddd-dddddddddddd','2026-10-08T00:00:00Z',null,100,null,null,null,id)->'restaurants')=0,'exact branch lookup hidden';
 begin perform public.dastak_v1_admin_set_restaurant_customer_visibility(id,true,2,'Different','remove-one'); raise exception 'key collision accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.dastak_v1_admin_set_restaurant_customer_visibility(id,true,1,'Reviewed','stale'); raise exception 'stale version accepted'; exception when serialization_failure then null; end;
 begin perform public.dastak_v1_admin_set_restaurant_customer_visibility('11111111-1111-4111-8111-111111111111',false,1,'Reviewed','retail'); raise exception 'retail accepted'; exception when object_not_in_prerequisite_state then null; end;
 result:=dastak_v1_api.admin_merchant_governance_page(null,null,null,null,100,null,null);
 assert result->'merchants'->0->'branch'->'customerListingVisible'='false'::jsonb,'Admin sees removed store';
 perform public.dastak_v1_admin_set_restaurant_customer_visibility(id,true,2,'Reviewed restoration','restore-one');
 assert (public.dastak_v1_customer_area_availability('dddddddd-dddd-4ddd-8ddd-dddddddddddd','2026-10-08T00:00:00Z')->'restaurants' ? id::text),'restored store listed';
 assert not private.customer_restaurant_accepting(id),'restore does not reopen store';
 assert not has_function_privilege('anon','public.dastak_v1_admin_set_restaurant_customer_visibility(uuid,boolean,bigint,text,text)','execute');
end;$$;
select 'Restaurant removal/restore assertions passed (isolated governance fixture)' as result;
