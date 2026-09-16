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
        select fulfilment.id, fulfilment.committed_at
        from dastak_v1.fulfilments fulfilment
        where fulfilment.status in ('RESERVED_PREPAYMENT','PREPARING','READY','PICKED_UP','COMPLETED','RELEASED')
          and dastak_v1_api.actor_has_wave1_merchant_permission(
            p_actor_id, fulfilment.organization_id, 'merchant.fulfilment.manage', fulfilment.branch_id)
        order by fulfilment.committed_at desc, fulfilment.id desc
        limit least(greatest(coalesce(p_limit,50),1),100)
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
