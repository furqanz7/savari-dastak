-- Native SQL projection harness. Temporary copies retain the actual table
-- column shapes but never update an actual account, mission or order.
create temporary table contact_missions as select * from dastak_v1.delivery_missions where false;
create temporary table contact_accounts as select * from public.accounts where false;
create temporary table contact_availability as select * from private.delivery_partner_availability where false;
do $$declare definition text; begin
  definition:=pg_get_functiondef('dastak_v1_api.delivery_tracking_json(uuid)'::regprocedure);
  definition:=replace(definition,'FUNCTION dastak_v1_api.delivery_tracking_json(','FUNCTION pg_temp.contact_tracking(');
  definition:=replace(definition,'from dastak_v1.delivery_missions','from pg_temp.contact_missions');
  definition:=replace(definition,'from public.accounts','from pg_temp.contact_accounts');
  definition:=replace(definition,'from private.delivery_partner_availability','from pg_temp.contact_availability');
  execute definition;
end;$$;
insert into contact_accounts(id,display_name,phone_number) values
  ('ce200000-0000-4000-8000-000000000001','Fixture rider','+919876543210');
insert into contact_missions(id,order_id,assigned_rider_id,status,created_at,assigned_at) values
  ('ce200000-0000-4000-8000-000000000002','ce200000-0000-4000-8000-000000000003',
  'ce200000-0000-4000-8000-000000000001','ASSIGNED',now(),now());
do $$declare phase text; result jsonb; begin
  foreach phase in array array['ASSIGNED','EN_ROUTE_TO_PICKUPS','PICKUP_IN_PROGRESS','ALL_PACKAGES_PICKED_UP','OUT_FOR_DELIVERY','ARRIVED','DELIVERY_RECOVERY'] loop
    update contact_missions set status=phase::dastak_v1.delivery_mission_status;
    result:=pg_temp.contact_tracking('ce200000-0000-4000-8000-000000000003');
    assert result->>'riderPhoneNumber'='+919876543210', 'active assigned rider phone must be available';
    assert result->'location'='null'::jsonb, 'call does not depend on rider GPS';
  end loop;
  update contact_accounts set phone_number='javascript:alert(1)';
  assert pg_temp.contact_tracking('ce200000-0000-4000-8000-000000000003')->'riderPhoneNumber'='null'::jsonb,'invalid phone rejected';
  update contact_missions set assigned_rider_id=null;
  assert pg_temp.contact_tracking('ce200000-0000-4000-8000-000000000003') is null,'unassigned mission has no contact';
  assert pg_temp.contact_tracking('ce200000-0000-4000-8000-000000000099') is null,'unknown order has no contact';
  assert not has_function_privilege('anon','dastak_v1_api.delivery_tracking_json(uuid)','execute');
  assert not has_function_privilege('authenticated','dastak_v1_api.delivery_tracking_json(uuid)','execute');
end;$$;
