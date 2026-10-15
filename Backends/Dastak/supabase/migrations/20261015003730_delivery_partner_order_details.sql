-- Read-only rider-owned detail. No verification secrets or provider payloads.
create function dastak_v1_api.delivery_partner_legacy_order_detail(p_account_id uuid,p_kind text,p_work_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  a private.delivery_assignment_attempts%rowtype; pa private.parcel_assignment_attempts%rowtype;
  o private.merchant_orders%rowtype; p private.parcel_deliveries%rowtype;
  result jsonb; stops jsonb; terminal boolean; state text; source jsonb;
begin
  if p_kind='LEGACY_DELIVERY' then
    select * into a from private.delivery_assignment_attempts where id=p_work_id
      and partner_account_id=p_account_id and status in ('accepted','completed','cancelled');
    if not found then raise no_data_found; end if;
    select * into o from private.merchant_orders where id=a.order_id;
    state:=o.status; terminal:=a.status in ('completed','cancelled');
    result:=pg_catalog.jsonb_build_object('id',o.id,'displayOrderNumber','Order '||pg_catalog.left(o.id::text,8),
      'orderType','LEGACY_DELIVERY','version',o.state_version,'createdAt',o.created_at,'updatedAt',o.updated_at,
      'price',pg_catalog.jsonb_build_object('snapshotKind','FINAL_PAYABLE','subtotalPaise',o.item_subtotal_paise,
        'deliveryFeePaise',o.delivery_fee_paise,'platformFeePaise',o.platform_fee_paise,'discountPaise',0,'taxPaise',0,'totalPaise',o.total_paise,'currencyCode','INR'),
      'lines',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',l.product_id,'lineType','LEGACY_ITEM',
        'name',l.product_name,'packSize',l.unit_label,'quantity',l.quantity,'unitPricePaise',l.unit_price_paise,
        'lineTotalPaise',l.line_subtotal_paise,'status',state)) from private.merchant_order_lines l where l.order_id=o.id),'[]'::jsonb),
      'deliveryAddress',case when terminal then null else pg_catalog.jsonb_build_object('line1',coalesce(o.dropoff_address,'Delivery destination'),
        'line2',o.dropoff_details,'countryCode','IN','latitude',extensions.st_y(o.dropoff),'longitude',extensions.st_x(o.dropoff)) end);
    source:=private.delivery_assignment_json(a);
    stops:=pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id',p_work_id,'sequence',1,
      'name',source#>>'{store,name}','address',source#>>'{store,address}','status',state));
  elsif p_kind='PARCEL' then
    select * into pa from private.parcel_assignment_attempts where id=p_work_id
      and partner_account_id=p_account_id and status in ('acknowledged','completed','cancelled');
    if not found then raise no_data_found; end if;
    select * into p from private.parcel_deliveries where id=pa.parcel_id;
    state:=p.status; terminal:=pa.status in ('completed','cancelled');
    result:=pg_catalog.jsonb_build_object('id',p.id,'displayOrderNumber','Parcel '||pg_catalog.left(p.id::text,8),
      'orderType','PARCEL','version',1,'createdAt',p.created_at,'updatedAt',p.updated_at,
      'price',pg_catalog.jsonb_build_object('snapshotKind','FINAL_PAYABLE','subtotalPaise',0,'deliveryFeePaise',p.delivery_fee_paise,
        'platformFeePaise',0,'discountPaise',0,'taxPaise',0,'totalPaise',p.delivery_fee_paise,'currencyCode','INR'),
      'lines',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id',p.id,'lineType','PARCEL',
        'name',p.declared_contents,'quantity',1,'unitPricePaise',0,'lineTotalPaise',0,'status',state)),
      'deliveryAddress',case when terminal then null else pg_catalog.jsonb_build_object('line1',p.dropoff_address,'countryCode','IN',
        'latitude',extensions.st_y(p.dropoff),'longitude',extensions.st_x(p.dropoff)) end,
      'recipient',case when terminal then null else pg_catalog.jsonb_build_object('name',p.recipient_name,'phoneNumber',p.recipient_phone_number) end);
    stops:=case when terminal then '[]'::jsonb else pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'id',p_work_id,'sequence',1,'name','Parcel pickup','address',p.pickup_address,'packageCount',1,'status',state)) end;
  else raise no_data_found; end if;
  result:=result||pg_catalog.jsonb_build_object('status',case when state='delivered' then 'DELIVERED'
    when state='cancelled' then 'CANCELLED' when state in ('picked_up','in_transit') then 'OUT_FOR_DELIVERY' else 'PREPARING' end);
  return pg_catalog.jsonb_build_object('kind',p_kind,'workId',p_work_id,'missionStatus',state,
    'terminal',terminal,'order',result,'pickupStops',stops,'collection',null);
end;
$$;
revoke all on function dastak_v1_api.delivery_partner_legacy_order_detail(uuid,text,uuid) from public,anon,authenticated;
-- Callable only through the ownership/approved-access outer read.
revoke all on function dastak_v1_api.delivery_partner_legacy_order_detail(uuid,text,uuid) from service_role;

create function dastak_v1_api.delivery_partner_order_detail(p_account_id uuid,p_kind text,p_work_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_order_id uuid; v_customer_id uuid; v_status text; v_terminal boolean;
  v_order jsonb; v_stops jsonb := '[]'::jsonb; v_collection jsonb;
  v_snapshot jsonb;
begin
  if not exists (
    select 1 from private.account_memberships m
    join private.delivery_partner_profiles p on p.account_id=m.account_id
    join private.delivery_partner_applications a on a.id=p.approved_application_id and a.account_id=p.account_id and a.status='approved'
    join public.accounts account on account.id=m.account_id and account.account_state='ACTIVE'
    where m.account_id=p_account_id and m.role='dastak_partner' and m.approved_at is not null
      and (m.suspended_until is null or m.suspended_until<=pg_catalog.now())
      and p.governance_status='ACTIVE'
      and not exists(select 1 from private.account_personas persona where persona.account_id=p_account_id
        and persona.persona='DELIVERY' and persona.state='DELETED')
  ) then raise exception using errcode='42501',message='active delivery access required'; end if;

  if p_kind='V1_DELIVERY' then
    select order_id,status::text into v_order_id,v_status from dastak_v1.delivery_missions
      where id=p_work_id and assigned_rider_id=p_account_id;
    if not found then raise no_data_found; end if;
    v_snapshot := dastak_v1_api.rider_mission_json(p_account_id,p_work_id);
    v_stops := coalesce(v_snapshot->'pickupStops','[]'::jsonb);
    v_collection := dastak_v1_api.launch_collection_mission_json(p_work_id,p_account_id);
    v_terminal := v_status in ('DELIVERED','CANCELLED');
  elsif p_kind='RETURN' then
    select order_id,status::text into v_order_id,v_status from dastak_v1.return_missions
      where id=p_work_id and assigned_rider_id=p_account_id;
    if not found then raise no_data_found; end if;
    v_terminal := v_status in ('COMPLETED','CANCELLED');
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',s.id,'sequence',s.stop_sequence,'status',s.status,'packageCount',s.package_count,
      'name',b.display_name,'address',b.address_snapshot
    ) order by s.stop_sequence),'[]'::jsonb) into v_stops
    from dastak_v1.return_stops s join dastak_v1.merchant_branches b on b.id=s.branch_id
    where s.return_mission_id=p_work_id;
  else
    return dastak_v1_api.delivery_partner_legacy_order_detail(p_account_id,p_kind,p_work_id);
  end if;

  select customer_id into v_customer_id from dastak_v1.orders where id=v_order_id;
  v_snapshot := dastak_v1_api.order_json(v_order_id,v_customer_id);
  -- Allowlist; never expose support cases, PINs, refund/provider or tracking internals.
  v_order := pg_catalog.jsonb_build_object('id',v_snapshot->'id','displayOrderNumber',v_snapshot->'displayOrderNumber',
    'orderType',v_snapshot->'orderType','status',v_snapshot->'status','version',v_snapshot->'version',
    'price',v_snapshot->'price','lines',v_snapshot->'lines','createdAt',v_snapshot->'createdAt',
    'updatedAt',v_snapshot->'updatedAt','submittedAt',v_snapshot->'submittedAt','deliveredAt',v_snapshot->'deliveredAt',
    'deliveryAddress',case when v_terminal then null else v_snapshot->'deliveryAddress' end,
    'recipient',case when v_terminal then null else v_snapshot->'recipient' end);
  return pg_catalog.jsonb_build_object('kind',p_kind,'workId',p_work_id,'missionStatus',v_status,
    'terminal',v_terminal,'order',v_order,'pickupStops',v_stops,'collection',v_collection);
exception when no_data_found then
  raise exception using errcode='P0002',message='delivery work not found';
end;
$$;
revoke all on function dastak_v1_api.delivery_partner_order_detail(uuid,text,uuid) from public,anon,authenticated;
grant execute on function dastak_v1_api.delivery_partner_order_detail(uuid,text,uuid) to service_role;

create function public.dastak_delivery_partner_order_detail(p_account_id uuid,p_kind text,p_work_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select dastak_v1_api.delivery_partner_order_detail(p_account_id,p_kind,p_work_id);
$$;
revoke all on function public.dastak_delivery_partner_order_detail(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.dastak_delivery_partner_order_detail(uuid,text,uuid) to service_role;
