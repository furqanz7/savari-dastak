-- Reconnect only unoffered work inside its original Wave 1 window. Never resend
-- cancelled/expired orders, revive declined requests, or extend deadlines.
create function private.offer_reconnected_wave1(p_branches uuid[],p_actor uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare work record; branch uuid; offer uuid; snapshot jsonb; offered integer:=0;
begin
  if coalesce(cardinality(p_branches),0)=0 then return 0; end if;
  for work in
    select o.id order_id,a.id attempt_id,a.expires_at
    from dastak_v1.orders o join dastak_v1.matching_attempts a on a.order_id=o.id
    where o.status='MATCHING' and o.order_type in ('RETAIL_ONLY','MIXED')
      and a.wave='WAVE_1' and a.status='OPEN' and a.expires_at>clock_timestamp()
      and exists(select 1 from dastak_v1.matching_candidate_evaluations e
        where e.matching_attempt_id=a.id and e.branch_id=any(p_branches)
        and not exists(select 1 from dastak_v1.merchant_opportunities x
          where x.matching_attempt_id=a.id and x.branch_id=e.branch_id))
    order by o.id limit 50 for update of o skip locked
  loop
    if not (dastak_v1_api.order_transport_snapshot(work.order_id)->>'feasible')::boolean then continue; end if;
    foreach branch in array p_branches loop
      if work.expires_at<=clock_timestamp()
        or not dastak_v1_api.actor_has_wave1_merchant_permission(p_actor,
          (select organization_id from dastak_v1.merchant_branches where id=branch),
          'merchant.opportunities.respond',branch)
        or not dastak_v1_api.branch_is_reachable(branch,clock_timestamp())
        or exists(select 1 from dastak_v1.merchant_opportunities x
          where x.matching_attempt_id=work.attempt_id and x.branch_id=branch)
        or not exists(select 1 from dastak_v1.matching_candidate_evaluations e
          where e.matching_attempt_id=work.attempt_id and e.branch_id=branch) then continue; end if;
      snapshot:=dastak_v1_api.evaluate_wave1_candidate(work.order_id,branch);
      if not coalesce((snapshot->>'eligible')::boolean,false) then continue; end if;
      offer:=null;
      insert into dastak_v1.merchant_opportunities(matching_attempt_id,order_id,organization_id,branch_id,status,started_at,expires_at)
      select work.attempt_id,work.order_id,b.organization_id,b.id,'OFFERED',clock_timestamp(),work.expires_at
      from dastak_v1.merchant_branches b where b.id=branch returning id into offer;
      -- Existing reachability/emergency-pause triggers retain their final veto.
      if offer is null then continue; end if;
      insert into dastak_v1.merchant_opportunity_lines(opportunity_id,order_line_id,sku_id,
        product_name_snapshot,variant_snapshot,pack_size_snapshot,requested_quantity)
      select offer,l.id,l.sku_id,l.product_name_snapshot,l.variant_snapshot,l.pack_size_snapshot,l.quantity
      from dastak_v1.order_lines l where l.order_id=work.order_id and l.line_type='RETAIL_SKU';
      insert into dastak_v1.domain_events_outbox(event_key,aggregate_type,aggregate_id,aggregate_version,event_type,actor_id,payload)
      values(offer::text||':MERCHANT_OPPORTUNITY_OFFERED:1','MERCHANT_OPPORTUNITY',offer,1,
        'MERCHANT_OPPORTUNITY_OFFERED',p_actor,jsonb_build_object('opportunityId',offer,'orderId',work.order_id,
          'organizationId',(select organization_id from dastak_v1.merchant_branches where id=branch),
          'branchId',branch,'expiresAt',work.expires_at));
      insert into dastak_v1.audit_events(actor_id,action,resource_type,resource_id,metadata)
      values(p_actor,'WAVE_1_RECONNECTED_OPPORTUNITY','merchant_opportunity',offer,
        jsonb_build_object('orderId',work.order_id,'attemptId',work.attempt_id,'branchId',branch,'eligibility',snapshot));
      offered:=offered+1;
    end loop;
  end loop;
  return offered;
end;$$;
revoke all on function private.offer_reconnected_wave1(uuid[],uuid) from public,anon,authenticated,service_role;

-- Every authenticated Merchant feed heartbeat refreshes the existing owned-branch
-- liveness state before checking still-open, previously suppressed opportunities.
do $$declare definition text; begin
  definition:=pg_get_functiondef('dastak_v1_api.record_actor_merchant_heartbeats(uuid,timestamptz)'::regprocedure);
  if position('v_count integer;' in definition)=0 or position('select count(*) into v_count from upserted;' in definition)=0 then
    raise exception 'Merchant heartbeat source drift';
  end if;
  definition:=replace(definition,'v_count integer;','v_count integer; v_branches uuid[];');
  definition:=replace(definition,'select count(*) into v_count from upserted;',
    'select count(*),array_agg(branch_id order by branch_id) into v_count,v_branches from upserted;
     perform private.offer_reconnected_wave1(v_branches,p_actor_id);');
  execute definition;
end;$$;
