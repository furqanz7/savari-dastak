-- Additive, read-only, branch-scoped historical detail. Existing list and
-- Customer/Delivery projections are deliberately unchanged.
create function dastak_v1_api.merchant_detail_fields(p_value jsonb, p_keys text[])
returns jsonb language sql immutable security invoker set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_object_agg(key, value), '{}'::jsonb)
  from pg_catalog.jsonb_each(case when pg_catalog.jsonb_typeof(p_value)='object' then p_value else '{}'::jsonb end) where key = any(p_keys);
$$;

create function dastak_v1_api.merchant_detail_record(p_kind text, p_value jsonb)
returns jsonb language sql immutable security invoker set search_path = '' as $$
  select dastak_v1_api.merchant_detail_fields(p_value, array[
    'id','status','version','productSubtotalPaise','promisedPrepMinutes','packageCount',
    'startedAt','expiresAt','offeredAt','respondedAt','responseReason',
    'prepStartedAt','estimatedReadyAt','actualReadyAt'
  ]) || pg_catalog.jsonb_build_object(
    'kind',p_kind,
    'offeredAt',coalesce(nullif(p_value->'offeredAt','null'::jsonb),p_value->'startedAt'),
    'lines',coalesce((select pg_catalog.jsonb_agg(
      dastak_v1_api.merchant_detail_fields(line, array['orderLineId','name','quantity','variant','packSize','unitPricePaise','lineSubtotalPaise'])
      || pg_catalog.jsonb_build_object('selection',pg_catalog.jsonb_build_object('options',coalesce((
        select pg_catalog.jsonb_agg(dastak_v1_api.merchant_detail_fields(opt,array['id','groupId','groupName','name','priceDeltaPaise']))
        from pg_catalog.jsonb_array_elements(coalesce(nullif(line #> '{selection,options}','null'::jsonb),'[]'::jsonb)) opt
      ),'[]'::jsonb)))) from pg_catalog.jsonb_array_elements(coalesce(nullif(p_value->'lines','null'::jsonb),'[]'::jsonb)) line),'[]'::jsonb),
    'evidence',coalesce((select pg_catalog.jsonb_agg(dastak_v1_api.merchant_detail_fields(photo,array['id','contentType','capturedAt']))
      from pg_catalog.jsonb_array_elements(coalesce(nullif(p_value->'evidence','null'::jsonb),'[]'::jsonb)) photo),'[]'::jsonb),
    'problems',coalesce((select pg_catalog.jsonb_agg(dastak_v1_api.merchant_detail_fields(problem,array['id','statusAtReport','reason','reportedAt']))
      from pg_catalog.jsonb_array_elements(coalesce(nullif(p_value->'problemReports','null'::jsonb),'[]'::jsonb)) problem),'[]'::jsonb),
    'recovery',coalesce((select pg_catalog.jsonb_agg(dastak_v1_api.merchant_detail_fields(recovery,array['id','status','reason','openedAt','resolvedAt']))
      from pg_catalog.jsonb_array_elements(coalesce(nullif(p_value->'recoveryCases','null'::jsonb),'[]'::jsonb)) recovery),'[]'::jsonb),
    'delivery',dastak_v1_api.merchant_detail_fields(p_value->'delivery',array['riderAssigned','stopStatus','pickedUpAt'])
      || pg_catalog.jsonb_build_object('riderName',p_value #> '{delivery,rider,displayName}')
  );
$$;

create function dastak_v1_api.merchant_order_detail(p_actor_id uuid,p_branch_id uuid,p_target_kind text,p_target_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_order_id uuid;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_manage boolean;
  v_respond boolean;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  select * into v_branch from dastak_v1.merchant_branches where id=p_branch_id;
  if not found then raise exception using errcode='P0002',message='Merchant order not found'; end if;
  v_manage := dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,v_branch.organization_id,'merchant.fulfilment.manage',p_branch_id);
  v_respond := dastak_v1_api.actor_has_wave1_merchant_permission(p_actor_id,v_branch.organization_id,'merchant.opportunities.respond',p_branch_id);
  case p_target_kind
    when 'FULFILMENT' then
      select order_id into v_order_id from dastak_v1.fulfilments where id=p_target_id and branch_id=p_branch_id and v_manage;
    when 'OPPORTUNITY' then
      select order_id into v_order_id from dastak_v1.merchant_opportunities where id=p_target_id and branch_id=p_branch_id and v_respond;
    when 'RESTAURANT_REQUEST' then
      select order_id into v_order_id from dastak_v1.restaurant_order_requests where id=p_target_id and branch_id=p_branch_id and v_respond;
    when 'RECOVERY' then
      select order_id into v_order_id from dastak_v1.recovery_opportunities where id=p_target_id and branch_id=p_branch_id and v_manage;
    when 'RETURN' then
      select customer_return.order_id into v_order_id from dastak_v1.return_stops stop
        join dastak_v1.returns customer_return on customer_return.id=stop.return_id
        where stop.id=p_target_id and stop.branch_id=p_branch_id and v_manage;
    else raise exception using errcode='22023',message='Invalid Merchant detail target';
  end case;
  if v_order_id is null then raise exception using errcode='P0002',message='Merchant order not found'; end if;
  select * into v_order from dastak_v1.orders where id=v_order_id;
  if not found then raise exception using errcode='P0002',message='Merchant order not found'; end if;
  return pg_catalog.jsonb_build_object(
    'target',pg_catalog.jsonb_build_object('kind',p_target_kind,'id',p_target_id,'branchId',p_branch_id),
    'branch',pg_catalog.jsonb_build_object('id',v_branch.id,'displayName',v_branch.display_name),
    'order',pg_catalog.jsonb_build_object('id',v_order.id,'displayOrderNumber',v_order.display_order_number,
      'status',v_order.status,'orderType',v_order.order_type,'createdAt',v_order.created_at),
    'records',coalesce((select pg_catalog.jsonb_agg(record order by kind,id) from (
      select 'FULFILMENT' kind,f.id,dastak_v1_api.merchant_detail_record('FULFILMENT',dastak_v1_api.merchant_fulfilment_json(p_actor_id,f.id)) record
        from dastak_v1.fulfilments f where f.order_id=v_order_id and f.branch_id=p_branch_id and v_manage
      union all
      select 'OPPORTUNITY',o.id,dastak_v1_api.merchant_detail_record('OPPORTUNITY',dastak_v1_api.merchant_opportunity_json(p_actor_id,o.id))
        from dastak_v1.merchant_opportunities o where o.order_id=v_order_id and o.branch_id=p_branch_id and v_respond
      union all
      select 'RESTAURANT_REQUEST',r.id,dastak_v1_api.merchant_detail_record('RESTAURANT_REQUEST',dastak_v1_api.restaurant_request_json(p_actor_id,r.id))
        from dastak_v1.restaurant_order_requests r where r.order_id=v_order_id and r.branch_id=p_branch_id and v_respond
    ) scoped),'[]'::jsonb),
    'recoveryOffers',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',r.id,'recoveryCaseId',r.recovery_case_id,'orderId',r.order_id,'orderLineId',r.order_line_id,
      'status',r.status,'requestedQuantity',r.requested_quantity,'version',r.version,
      'startedAt',r.started_at,'expiresAt',r.expires_at,'promisedPrepMinutes',r.promised_prep_minutes,
      'branch',pg_catalog.jsonb_build_object('id',v_branch.id,'displayName',v_branch.display_name),
      'sku',pg_catalog.jsonb_build_object('id',s.id,'name',s.canonical_name,'variantName',s.variant_name,'packSize',s.pack_size)
    ) order by r.id) from dastak_v1.recovery_opportunities r join dastak_v1.skus s on s.id=r.sku_id
      where r.order_id=v_order_id and r.branch_id=p_branch_id and v_manage),'[]'::jsonb),
    'returns',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'returnId',r.id,'returnMissionId',s.return_mission_id,'returnStopId',s.id,'orderId',r.order_id,
      'status',s.status,'packageCount',s.package_count,'arrivedAt',s.arrived_at,'completedAt',s.completed_at,
      'branch',pg_catalog.jsonb_build_object('id',v_branch.id,'displayName',v_branch.display_name)
    ) order by s.id) from dastak_v1.return_stops s join dastak_v1.returns r on r.id=s.return_id
      where r.order_id=v_order_id and s.branch_id=p_branch_id and v_manage),'[]'::jsonb),
    'settlements',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',e.id,'orderId',e.order_id,'fulfilmentId',e.fulfilment_id,'entryType',e.entry_type,'status',e.status,
      'calculationStatus',e.calculation_status,'amountPaise',e.amount_paise,'currency',e.currency_code,
      'eligibleAt',e.eligible_at,'settledAt',e.settled_at
    ) order by e.id) from dastak_v1.settlement_entries e join dastak_v1.fulfilments f on f.id=e.fulfilment_id
      where e.order_id=v_order_id and f.order_id=v_order_id and f.branch_id=p_branch_id and v_manage
        and e.subject_type='MERCHANT_ORGANIZATION' and e.subject_id=v_branch.organization_id
        and exists(select 1 from dastak_v1.merchant_users u where u.account_id=p_actor_id and u.organization_id=e.subject_id and u.status='ACTIVE')),'[]'::jsonb)
  );
end;
$$;

create function public.dastak_v1_merchant_order_detail(p_branch_id uuid,p_target_kind text,p_target_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select dastak_v1_api.merchant_order_detail(auth.uid(),p_branch_id,p_target_kind,p_target_id);
$$;
revoke all on function dastak_v1_api.merchant_detail_fields(jsonb,text[]),dastak_v1_api.merchant_detail_record(text,jsonb)
  from public,anon,authenticated,service_role;
revoke all on function dastak_v1_api.merchant_order_detail(uuid,uuid,text,uuid),public.dastak_v1_merchant_order_detail(uuid,text,uuid)
  from public,anon,authenticated,service_role;
grant execute on function dastak_v1_api.merchant_order_detail(uuid,uuid,text,uuid),public.dastak_v1_merchant_order_detail(uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
