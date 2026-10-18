-- Separate active work from bounded history without changing the other operations feeds.
create index if not exists fulfilments_merchant_history_cursor_idx
  on dastak_v1.fulfilments (branch_id, committed_at desc, id desc);

create function dastak_v1_api.merchant_fulfilment_is_history(p_status text,p_order_status text)
returns boolean language sql immutable security invoker set search_path='' as $$
 select p_status in ('COMPLETED','RELEASED') or p_order_status in
 ('DELIVERED','CANCELLED','CANCELLED_PREPAYMENT','PAYMENT_EXPIRED','UNAVAILABLE',
  'DELIVERY_FAILED','RETURNED','REFUNDED','DASTAK_FULFILMENT_FAILURE');
$$;

-- Preserve every operations feed while including completed fulfilments in history.
create or replace function dastak_v1_api.list_merchant_fulfilments(
  p_actor_id uuid, p_limit integer default 50
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  return pg_catalog.jsonb_build_object(
    'fulfilments', coalesce((
      select pg_catalog.jsonb_agg(dastak_v1_api.merchant_fulfilment_json(p_actor_id, visible.id)
        order by visible.committed_at desc, visible.id desc)
      from (
        -- Active work has no shared recent-history limit. The request deadline
        -- remains bounded on clients; a failed read is unknown, never empty.
        select f.id,f.committed_at from dastak_v1.fulfilments f
        join dastak_v1.orders o on o.id=f.order_id
        where f.status in ('RESERVED_PREPAYMENT','PREPARING','READY','PICKED_UP')
          and not dastak_v1_api.merchant_fulfilment_is_history(f.status::text,o.status::text)
          and dastak_v1_api.actor_has_wave1_merchant_permission(
            p_actor_id,f.organization_id,'merchant.fulfilment.manage',f.branch_id)
        union all
        (select f.id,f.committed_at from dastak_v1.fulfilments f
         join dastak_v1.orders o on o.id=f.order_id
         where dastak_v1_api.merchant_fulfilment_is_history(f.status::text,o.status::text)
           and dastak_v1_api.actor_has_wave1_merchant_permission(
             p_actor_id,f.organization_id,'merchant.fulfilment.manage',f.branch_id)
         order by f.committed_at desc,f.id desc
         limit least(greatest(coalesce(p_limit,50),1),100))
      ) visible
    ), '[]'::jsonb),
    'recoveryOpportunities', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', opportunity.id, 'recoveryCaseId', opportunity.recovery_case_id,
        'orderId', opportunity.order_id, 'orderLineId', opportunity.order_line_id,
        'status', opportunity.status, 'requestedQuantity', opportunity.requested_quantity,
        'startedAt', opportunity.started_at, 'expiresAt', opportunity.expires_at,
        'promisedPrepMinutes', opportunity.promised_prep_minutes, 'version', opportunity.version,
        'branch', pg_catalog.jsonb_build_object('id', branch.id, 'displayName', branch.display_name),
        'sku', pg_catalog.jsonb_build_object('id', sku.id, 'name', sku.canonical_name,
          'variantName', sku.variant_name, 'packSize', sku.pack_size, 'imageKey', sku.image_key)
      ) order by opportunity.started_at desc, opportunity.id desc)
      from dastak_v1.recovery_opportunities opportunity
      join dastak_v1.merchant_branches branch on branch.id = opportunity.branch_id
      join dastak_v1.skus sku on sku.id = opportunity.sku_id
      where opportunity.status in ('OFFERED','SELECTED','DECLINED','EXPIRED','CLOSED')
        and dastak_v1_api.actor_has_wave1_merchant_permission(
          p_actor_id, opportunity.organization_id, 'merchant.fulfilment.manage', opportunity.branch_id)
    ), '[]'::jsonb),
    'returnReceipts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'returnId', customer_return.id, 'returnMissionId', mission.id, 'returnStopId', stop.id,
        'orderId', customer_return.order_id, 'status', stop.status, 'packageCount', stop.package_count,
        'verificationStatus', verification.status,
        'receiptCode', case when verification.status = 'ACTIVE' then private.dastak_v1_handoff_code(
          verification.id, verification.handoff_type, verification.code_version) else null end,
        'arrivedAt', stop.arrived_at, 'completedAt', stop.completed_at,
        'branch', pg_catalog.jsonb_build_object('id', branch.id, 'displayName', branch.display_name)
      ) order by mission.created_at desc, stop.stop_sequence)
      from dastak_v1.return_stops stop
      join dastak_v1.return_missions mission on mission.id = stop.return_mission_id
      join dastak_v1.returns customer_return on customer_return.id = stop.return_id
      join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
      join dastak_v1.return_verifications verification
        on verification.return_stop_id = stop.id and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT'
      where dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, branch.organization_id, 'merchant.fulfilment.manage', branch.id)
    ), '[]'::jsonb),
    'settlements', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', entry.id, 'orderId', entry.order_id, 'fulfilmentId', entry.fulfilment_id,
        'entryType', entry.entry_type, 'status', entry.status, 'calculationStatus', entry.calculation_status,
        'amountPaise', entry.amount_paise, 'currency', entry.currency_code,
        'eligibleAt', entry.eligible_at, 'settledAt', entry.settled_at
      ) order by entry.created_at desc, entry.id desc)
      from dastak_v1.settlement_entries entry
      where entry.subject_type = 'MERCHANT_ORGANIZATION'
        and exists (select 1 from dastak_v1.merchant_users merchant_user
          where merchant_user.account_id = p_actor_id and merchant_user.organization_id = entry.subject_id
            and merchant_user.status = 'ACTIVE')
    ), '[]'::jsonb)
  );
end;
$$;


-- Historical discovery is branch-authorized and keyset-paged, not offset-paged.
create function dastak_v1_api.merchant_fulfilment_history(
 p_actor_id uuid,p_branch_id uuid,p_before_at timestamptz default null,
 p_before_id uuid default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_organization_id uuid;
 v_rows jsonb;
 v_next jsonb;
begin
 perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
 if p_branch_id is null or p_limit is null or p_limit < 1 or p_limit > 100
   or ((p_before_at is null) <> (p_before_id is null)) then
   raise exception using errcode='22023',message='Invalid history page';
 end if;
 select organization_id into v_organization_id from dastak_v1.merchant_branches where id=p_branch_id;
 if v_organization_id is null or not dastak_v1_api.actor_has_wave1_merchant_permission(
   p_actor_id,v_organization_id,'merchant.fulfilment.manage',p_branch_id) then
   raise exception using errcode='42501',message='Merchant history unavailable';
 end if;
 with candidates as materialized (
   select f.id,f.committed_at from dastak_v1.fulfilments f
   join dastak_v1.orders o on o.id=f.order_id
   where f.branch_id=p_branch_id and f.organization_id=v_organization_id
     and dastak_v1_api.merchant_fulfilment_is_history(f.status::text,o.status::text)
     and (p_before_at is null or (f.committed_at,f.id) < (p_before_at,p_before_id))
   order by f.committed_at desc,f.id desc limit p_limit+1
 ), page as (
   select * from candidates order by committed_at desc,id desc limit p_limit
 )
 select coalesce((select pg_catalog.jsonb_agg(
      dastak_v1_api.merchant_fulfilment_json(p_actor_id,id) order by committed_at desc,id desc) from page),'[]'::jsonb),
   case when (select count(*) from candidates)>p_limit then
     (select pg_catalog.jsonb_build_object('committedAt',committed_at,'id',id)
      from page order by committed_at,id limit 1) else null end
 into v_rows,v_next;
 return pg_catalog.jsonb_build_object('branchId',p_branch_id,'fulfilments',v_rows,'nextCursor',v_next);
end;
$$;

create function public.dastak_v1_merchant_fulfilment_history(
 p_branch_id uuid,p_before_at timestamptz default null,p_before_id uuid default null,p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$
 select dastak_v1_api.merchant_fulfilment_history(auth.uid(),p_branch_id,p_before_at,p_before_id,p_limit);
$$;
revoke all on function dastak_v1_api.merchant_fulfilment_is_history(text,text) from public,anon,authenticated,service_role;
revoke all on function dastak_v1_api.merchant_fulfilment_history(uuid,uuid,timestamptz,uuid,integer),
 public.dastak_v1_merchant_fulfilment_history(uuid,timestamptz,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function dastak_v1_api.merchant_fulfilment_history(uuid,uuid,timestamptz,uuid,integer),
 public.dastak_v1_merchant_fulfilment_history(uuid,timestamptz,uuid,integer) to authenticated;
notify pgrst,'reload schema';
