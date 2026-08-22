-- Dastak V1 Step 5: role-shaped recovery, return, refund and settlement projections.

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_step4b;

create function dastak_v1_api.order_json(
  p_order_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order jsonb;
begin
  v_order := dastak_v1_api.order_json_step4b(p_order_id, p_customer_id);
  if v_order is null then return null; end if;

  return v_order || pg_catalog.jsonb_build_object(
    'support', pg_catalog.jsonb_build_object(
      'canReportIssue', (v_order ->> 'status') = 'DELIVERED',
      'recovery', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', recovery.id,
          'type', recovery.case_type,
          'status', recovery.status,
          'orderLineId', recovery.order_line_id,
          'openedAt', recovery.opened_at,
          'resolvedAt', recovery.resolved_at,
          'customerMessage', case
            when recovery.status in ('OPEN', 'SEARCHING_EXACT_SKU', 'ACTION_REQUIRED')
              then 'We are resolving an issue with your order.'
            when recovery.status = 'RECOVERED'
              then 'Your order is back on track.'
            when recovery.status = 'RECOVERY_FAILED'
              then 'We could not recover this item. Your refund is being arranged.'
            else 'The issue has been resolved.'
          end
        ) order by recovery.opened_at, recovery.id)
        from dastak_v1.recovery_cases recovery
        where recovery.order_id = p_order_id
      ), '[]'::jsonb),
      'issues', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', issue.id,
          'orderLineId', issue.order_line_id,
          'category', issue.category,
          'status', issue.status,
          'description', issue.description,
          'reportedAt', issue.reported_at,
          'resolution', issue.resolution,
          'resolvedAt', issue.resolved_at,
          'version', issue.version,
          'evidence', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'id', evidence.id,
              'objectPath', evidence.object_path,
              'contentType', evidence.content_type,
              'capturedAt', evidence.captured_at
            ) order by evidence.captured_at, evidence.id)
            from dastak_v1.customer_issue_evidence evidence
            where evidence.issue_id = issue.id
          ), '[]'::jsonb)
        ) order by issue.reported_at, issue.id)
        from dastak_v1.customer_issues issue
        where issue.order_id = p_order_id
          and issue.customer_id = p_customer_id
      ), '[]'::jsonb),
      'returns', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', customer_return.id,
          'source', customer_return.source,
          'status', customer_return.status,
          'physicalReturnRequired', customer_return.physical_return_required,
          'reason', customer_return.reason,
          'requestedAt', customer_return.requested_at,
          'completedAt', customer_return.completed_at,
          'packageCount', (
            select count(*) from dastak_v1.return_packages package
            where package.return_id = customer_return.id
          ),
          'mission', case when mission.id is null then null else
            pg_catalog.jsonb_build_object(
              'id', mission.id,
              'status', mission.status,
              'assignedAt', mission.assigned_at,
              'arrivedCustomerAt', mission.arrived_customer_at,
              'pickupCompletedAt', mission.pickup_completed_at,
              'completedAt', mission.completed_at,
              'pickupVerificationStatus', pickup_verification.status,
              'pickupCode', case when pickup_verification.status = 'ACTIVE'
                then private.dastak_v1_handoff_code(
                  pickup_verification.id,
                  pickup_verification.handoff_type,
                  pickup_verification.code_version
                ) else null end
            ) end
        ) order by customer_return.requested_at, customer_return.id)
        from dastak_v1.returns customer_return
        left join dastak_v1.return_missions mission
          on mission.return_id = customer_return.id
        left join dastak_v1.return_verifications pickup_verification
          on pickup_verification.return_mission_id = mission.id
         and pickup_verification.handoff_type = 'CUSTOMER_TO_RETURN_RIDER'
        where customer_return.order_id = p_order_id
          and customer_return.requested_by = p_customer_id
      ), '[]'::jsonb),
      'refunds', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', refund.id,
          'orderLineId', refund.order_line_id,
          'status', refund.status,
          'destination', refund.destination,
          'amountPaise', refund.amount_paise,
          'currency', refund.currency_code,
          'reason', refund.reason,
          'createdAt', refund.created_at,
          'completedAt', refund.completed_at
        ) order by refund.created_at, refund.id)
        from dastak_v1.refunds refund
        where refund.order_id = p_order_id
      ), '[]'::jsonb)
    )
  );
end;
$$;

alter function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  rename to merchant_fulfilment_json_step4;

create function dastak_v1_api.merchant_fulfilment_json(
  p_actor_id uuid,
  p_fulfilment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_fulfilment dastak_v1.fulfilments%rowtype;
begin
  v_result := dastak_v1_api.merchant_fulfilment_json_step4(
    p_actor_id, p_fulfilment_id
  );
  select fulfilment.* into v_fulfilment
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = p_fulfilment_id;

  return v_result || pg_catalog.jsonb_build_object(
    'fulfilmentType', v_fulfilment.fulfilment_type,
    'canReportExactSkuFailure',
      v_fulfilment.status = 'PREPARING'
      and v_fulfilment.package_count is null
      and exists (
        select 1
        from dastak_v1.fulfilment_lines fulfilment_line
        join dastak_v1.order_lines line on line.id = fulfilment_line.order_line_id
        where fulfilment_line.fulfilment_id = v_fulfilment.id
          and line.line_type = 'RETAIL_SKU'
          and line.status = 'FULFILLING'
      ),
    'recoveryCases', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', recovery.id,
        'orderLineId', recovery.order_line_id,
        'status', recovery.status,
        'reason', recovery.reason,
        'openedAt', recovery.opened_at,
        'resolvedAt', recovery.resolved_at
      ) order by recovery.opened_at, recovery.id)
      from dastak_v1.recovery_cases recovery
      where recovery.source_fulfilment_id = v_fulfilment.id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function dastak_v1_api.list_merchant_fulfilments(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  return pg_catalog.jsonb_build_object(
    'fulfilments', coalesce((
      select pg_catalog.jsonb_agg(
        dastak_v1_api.merchant_fulfilment_json(p_actor_id, visible.id)
        order by visible.committed_at desc, visible.id desc
      )
      from (
        select fulfilment.id, fulfilment.committed_at
        from dastak_v1.fulfilments fulfilment
        where fulfilment.status in (
          'RESERVED_PREPAYMENT', 'PREPARING', 'READY', 'PICKED_UP', 'RELEASED'
        )
          and dastak_v1_api.actor_has_wave1_merchant_permission(
            p_actor_id, fulfilment.organization_id,
            'merchant.fulfilment.manage', fulfilment.branch_id
          )
        order by fulfilment.committed_at desc, fulfilment.id desc
        limit least(greatest(coalesce(p_limit, 50), 1), 100)
      ) visible
    ), '[]'::jsonb),
    'recoveryOpportunities', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', opportunity.id,
        'recoveryCaseId', opportunity.recovery_case_id,
        'orderId', opportunity.order_id,
        'orderLineId', opportunity.order_line_id,
        'status', opportunity.status,
        'requestedQuantity', opportunity.requested_quantity,
        'startedAt', opportunity.started_at,
        'expiresAt', opportunity.expires_at,
        'promisedPrepMinutes', opportunity.promised_prep_minutes,
        'version', opportunity.version,
        'branch', pg_catalog.jsonb_build_object(
          'id', branch.id, 'displayName', branch.display_name
        ),
        'sku', pg_catalog.jsonb_build_object(
          'id', sku.id, 'name', sku.canonical_name,
          'variantName', sku.variant_name, 'packSize', sku.pack_size,
          'imageKey', sku.image_key
        )
      ) order by opportunity.started_at desc, opportunity.id desc)
      from dastak_v1.recovery_opportunities opportunity
      join dastak_v1.merchant_branches branch on branch.id = opportunity.branch_id
      join dastak_v1.skus sku on sku.id = opportunity.sku_id
      where opportunity.status in ('OFFERED', 'SELECTED', 'DECLINED', 'EXPIRED', 'CLOSED')
        and dastak_v1_api.actor_has_wave1_merchant_permission(
          p_actor_id, opportunity.organization_id,
          'merchant.fulfilment.manage', opportunity.branch_id
        )
    ), '[]'::jsonb),
    'returnReceipts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'returnId', customer_return.id,
        'returnMissionId', mission.id,
        'returnStopId', stop.id,
        'orderId', customer_return.order_id,
        'status', stop.status,
        'packageCount', stop.package_count,
        'verificationStatus', verification.status,
        'receiptCode', case when verification.status = 'ACTIVE'
          then private.dastak_v1_handoff_code(
            verification.id, verification.handoff_type, verification.code_version
          ) else null end,
        'arrivedAt', stop.arrived_at,
        'completedAt', stop.completed_at,
        'branch', pg_catalog.jsonb_build_object(
          'id', branch.id, 'displayName', branch.display_name
        )
      ) order by mission.created_at desc, stop.stop_sequence)
      from dastak_v1.return_stops stop
      join dastak_v1.return_missions mission on mission.id = stop.return_mission_id
      join dastak_v1.returns customer_return on customer_return.id = stop.return_id
      join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
      join dastak_v1.return_verifications verification
        on verification.return_stop_id = stop.id
       and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT'
      where dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, branch.organization_id,
        'merchant.fulfilment.manage', branch.id
      )
    ), '[]'::jsonb),
    'settlements', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', entry.id,
        'orderId', entry.order_id,
        'fulfilmentId', entry.fulfilment_id,
        'entryType', entry.entry_type,
        'status', entry.status,
        'calculationStatus', entry.calculation_status,
        'amountPaise', entry.amount_paise,
        'currency', entry.currency_code,
        'eligibleAt', entry.eligible_at,
        'settledAt', entry.settled_at
      ) order by entry.created_at desc, entry.id desc)
      from dastak_v1.settlement_entries entry
      where entry.subject_type = 'MERCHANT_ORGANIZATION'
        and exists (
          select 1 from dastak_v1.merchant_users merchant_user
          where merchant_user.account_id = p_actor_id
            and merchant_user.organization_id = entry.subject_id
            and merchant_user.status = 'ACTIVE'
        )
    ), '[]'::jsonb)
  );
end;
$$;

alter function dastak_v1_api.delivery_partner_snapshot(uuid)
  rename to delivery_partner_snapshot_step4;

create function dastak_v1_api.delivery_partner_snapshot(p_rider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_snapshot jsonb;
  v_mission dastak_v1.return_missions%rowtype;
begin
  v_snapshot := dastak_v1_api.delivery_partner_snapshot_step4(p_rider_id);
  select mission.* into v_mission
  from dastak_v1.return_missions mission
  where mission.assigned_rider_id = p_rider_id
    and mission.status not in ('COMPLETED', 'CANCELLED')
  order by mission.assigned_at desc, mission.id desc
  limit 1;

  return v_snapshot || pg_catalog.jsonb_build_object(
    'returnMission', case when v_mission.id is null then null else
      pg_catalog.jsonb_build_object(
        'id', v_mission.id,
        'returnId', v_mission.return_id,
        'orderId', v_mission.order_id,
        'status', v_mission.status,
        'transportType', v_mission.assigned_transport_type,
        'assignedAt', v_mission.assigned_at,
        'arrivedCustomerAt', v_mission.arrived_customer_at,
        'pickupCompletedAt', v_mission.pickup_completed_at,
        'completedAt', v_mission.completed_at,
        'version', v_mission.version,
        'customerDestination', (
          select pg_catalog.jsonb_build_object(
            'address', context.delivery_address,
            'recipient', context.recipient
          ) from dastak_v1.order_context_snapshots context
          where context.order_id = v_mission.order_id
        ),
        'packageCount', (
          select count(*) from dastak_v1.return_packages package
          where package.return_id = v_mission.return_id
        ),
        'pickupVerification', (
          select pg_catalog.jsonb_build_object(
            'status', verification.status,
            'failedAttempts', verification.failed_attempts
          ) from dastak_v1.return_verifications verification
          where verification.return_mission_id = v_mission.id
            and verification.handoff_type = 'CUSTOMER_TO_RETURN_RIDER'
        ),
        'evidence', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'id', evidence.id,
            'objectPath', evidence.object_path,
            'contentType', evidence.content_type,
            'capturedAt', evidence.captured_at
          ) order by evidence.captured_at, evidence.id)
          from dastak_v1.return_evidence evidence
          where evidence.return_mission_id = v_mission.id
            and evidence.captured_by = p_rider_id
        ), '[]'::jsonb),
        'stops', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'id', stop.id,
            'sequence', stop.stop_sequence,
            'status', stop.status,
            'packageCount', stop.package_count,
            'arrivedAt', stop.arrived_at,
            'completedAt', stop.completed_at,
            'branch', pg_catalog.jsonb_build_object(
              'id', branch.id,
              'displayName', branch.display_name,
              'address', branch.address_snapshot
            ),
            'verificationStatus', verification.status,
            'failedAttempts', verification.failed_attempts
          ) order by stop.stop_sequence)
          from dastak_v1.return_stops stop
          join dastak_v1.merchant_branches branch on branch.id = stop.branch_id
          join dastak_v1.return_verifications verification
            on verification.return_stop_id = stop.id
          where stop.return_mission_id = v_mission.id
        ), '[]'::jsonb),
        'canArriveCustomer', v_mission.status = 'ASSIGNED',
        'canCaptureEvidence', v_mission.status = 'AT_CUSTOMER',
        'canVerifyPickup', v_mission.status = 'AT_CUSTOMER',
        'canCompleteReturnStops', v_mission.status = 'RETURNING_TO_MERCHANTS'
      ) end
  );
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_step4b;

create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trace jsonb;
begin
  v_trace := dastak_v1_api.admin_execution_trace_step4b(p_actor_id, p_order_id);
  return v_trace || pg_catalog.jsonb_build_object(
    'failureAndFinance', pg_catalog.jsonb_build_object(
      'recoveryCases', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', recovery.id,
          'type', recovery.case_type,
          'status', recovery.status,
          'faultSource', recovery.fault_source,
          'orderLineId', recovery.order_line_id,
          'sourceFulfilmentId', recovery.source_fulfilment_id,
          'deliveryMissionId', recovery.delivery_mission_id,
          'replacementFulfilmentId', recovery.replacement_fulfilment_id,
          'reason', recovery.reason,
          'resolution', recovery.resolution,
          'openedBy', recovery.opened_by,
          'openedAt', recovery.opened_at,
          'resolvedBy', recovery.resolved_by,
          'resolvedAt', recovery.resolved_at,
          'version', recovery.version,
          'opportunities', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'id', opportunity.id,
              'branchId', opportunity.branch_id,
              'organizationId', opportunity.organization_id,
              'skuId', opportunity.sku_id,
              'requestedQuantity', opportunity.requested_quantity,
              'status', opportunity.status,
              'expiresAt', opportunity.expires_at,
              'promisedPrepMinutes', opportunity.promised_prep_minutes,
              'respondedBy', opportunity.responded_by,
              'respondedAt', opportunity.responded_at,
              'version', opportunity.version
            ) order by opportunity.started_at, opportunity.id)
            from dastak_v1.recovery_opportunities opportunity
            where opportunity.recovery_case_id = recovery.id
          ), '[]'::jsonb)
        ) order by recovery.opened_at, recovery.id)
        from dastak_v1.recovery_cases recovery
        where recovery.order_id = p_order_id
      ), '[]'::jsonb),
      'customerIssues', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', issue.id, 'customerId', issue.customer_id,
          'orderLineId', issue.order_line_id, 'category', issue.category,
          'status', issue.status, 'description', issue.description,
          'reportedAt', issue.reported_at, 'reviewedBy', issue.reviewed_by,
          'reviewedAt', issue.reviewed_at, 'resolution', issue.resolution,
          'resolvedAt', issue.resolved_at, 'version', issue.version,
          'evidence', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'id', evidence.id, 'objectPath', evidence.object_path,
              'contentType', evidence.content_type,
              'capturedBy', evidence.captured_by,
              'capturedAt', evidence.captured_at
            ) order by evidence.captured_at, evidence.id)
            from dastak_v1.customer_issue_evidence evidence
            where evidence.issue_id = issue.id
          ), '[]'::jsonb)
        ) order by issue.reported_at, issue.id)
        from dastak_v1.customer_issues issue
        where issue.order_id = p_order_id
      ), '[]'::jsonb),
      'returns', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', customer_return.id, 'source', customer_return.source,
          'status', customer_return.status,
          'physicalReturnRequired', customer_return.physical_return_required,
          'refundAmountPaise', customer_return.approved_refund_amount_paise,
          'refundFaultSource', customer_return.refund_fault_source,
          'deliveryFaultSource', customer_return.delivery_recovery_fault_source,
          'reason', customer_return.reason,
          'requestedBy', customer_return.requested_by,
          'requestedAt', customer_return.requested_at,
          'decidedBy', customer_return.decided_by,
          'decidedAt', customer_return.decided_at,
          'completedAt', customer_return.completed_at,
          'version', customer_return.version,
          'mission', case when mission.id is null then null else
            pg_catalog.jsonb_build_object(
              'id', mission.id, 'status', mission.status,
              'assignedRiderId', mission.assigned_rider_id,
              'transportType', mission.assigned_transport_type,
              'assignedAt', mission.assigned_at,
              'arrivedCustomerAt', mission.arrived_customer_at,
              'pickupCompletedAt', mission.pickup_completed_at,
              'completedAt', mission.completed_at,
              'version', mission.version
            ) end,
          'packages', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'id', package.id, 'packageNumber', package.package_number,
              'destinationBranchId', package.destination_branch_id,
              'sourceDeliveryPackageId', package.source_delivery_package_id,
              'status', package.status,
              'custodyOwnerType', package.current_custody_owner_type,
              'custodyOwnerId', package.current_custody_owner_id,
              'version', package.version
            ) order by package.package_number)
            from dastak_v1.return_packages package
            where package.return_id = customer_return.id
          ), '[]'::jsonb),
          'verifications', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'id', verification.id, 'type', verification.handoff_type,
              'status', verification.status,
              'failedAttempts', verification.failed_attempts,
              'activatedAt', verification.activated_at,
              'consumedAt', verification.consumed_at,
              'blockedAt', verification.blocked_at
            ) order by verification.created_at, verification.id)
            from dastak_v1.return_verifications verification
            where verification.return_id = customer_return.id
          ), '[]'::jsonb)
        ) order by customer_return.requested_at, customer_return.id)
        from dastak_v1.returns customer_return
        left join dastak_v1.return_missions mission
          on mission.return_id = customer_return.id
        where customer_return.order_id = p_order_id
      ), '[]'::jsonb),
      'refunds', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', refund.id, 'status', refund.status,
          'faultSource', refund.fault_source,
          'destination', refund.destination,
          'amountPaise', refund.amount_paise,
          'currency', refund.currency_code,
          'reason', refund.reason,
          'providerRefundId', refund.provider_refund_reference,
          'createdAt', refund.created_at,
          'completedAt', refund.completed_at,
          'failureCode', refund.failure_code,
          'version', refund.version
        ) order by refund.created_at, refund.id)
        from dastak_v1.refunds refund where refund.order_id = p_order_id
      ), '[]'::jsonb),
      'settlements', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', entry.id, 'subjectType', entry.subject_type,
          'subjectId', entry.subject_id, 'fulfilmentId', entry.fulfilment_id,
          'deliveryMissionId', entry.delivery_mission_id,
          'entryType', entry.entry_type, 'status', entry.status,
          'calculationStatus', entry.calculation_status,
          'grossAmountPaise', entry.gross_amount_paise,
          'amountPaise', entry.amount_paise, 'currency', entry.currency_code,
          'eligibleAt', entry.eligible_at, 'settledAt', entry.settled_at,
          'settlementReference', entry.settlement_reference,
          'version', entry.version
        ) order by entry.created_at, entry.id)
        from dastak_v1.settlement_entries entry where entry.order_id = p_order_id
      ), '[]'::jsonb),
      'permissions', pg_catalog.jsonb_build_object(
        'canManageRecovery', dastak_v1_api.actor_has_platform_permission(
          p_actor_id, 'platform.recovery.manage'
        ),
        'canApproveReturns', dastak_v1_api.actor_has_platform_permission(
          p_actor_id, 'platform.returns.approve'
        ),
        'canApproveRefunds', dastak_v1_api.actor_has_platform_permission(
          p_actor_id, 'platform.refunds.approve'
        ),
        'canProcessRefunds', dastak_v1_api.actor_has_platform_permission(
          p_actor_id, 'platform.refunds.process'
        ),
        'canManageSettlements', dastak_v1_api.actor_has_platform_permission(
          p_actor_id, 'platform.settlements.manage'
        )
      )
    )
  );
end;
$$;

revoke all on function dastak_v1_api.order_json_step4b(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.order_json(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.merchant_fulfilment_json_step4(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.list_merchant_fulfilments(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.delivery_partner_snapshot_step4(uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.delivery_partner_snapshot(uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.admin_execution_trace_step4b(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function dastak_v1_api.order_json_step4b(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.order_json(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.merchant_fulfilment_json_step4(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.merchant_fulfilment_json(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.list_merchant_fulfilments(uuid, integer)
  to authenticated;
grant execute on function dastak_v1_api.delivery_partner_snapshot_step4(uuid)
  to service_role;
grant execute on function dastak_v1_api.delivery_partner_snapshot(uuid)
  to service_role;
grant execute on function dastak_v1_api.admin_execution_trace_step4b(uuid, uuid)
  to authenticated;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to authenticated;

comment on function dastak_v1_api.order_json(uuid, uuid) is
  'Customer-safe Step 5 projection; no retail merchant identity or internal routing is exposed.';

create function public.dastak_v1_advance_return_mission(
  p_account_id uuid,
  p_return_mission_id uuid,
  p_action text,
  p_return_stop_id uuid,
  p_object_path text,
  p_verification_code text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.advance_return_mission(
    p_account_id, p_return_mission_id, p_action, p_return_stop_id,
    p_object_path, p_verification_code, p_idempotency_key
  );
$$;

revoke execute on function public.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function dastak_v1_api.advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) to service_role;
grant execute on function public.dastak_v1_advance_return_mission(
  uuid, uuid, text, uuid, text, text, text
) to service_role;

create function public.dastak_v1_can_inspect_evidence(p_account_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.actor_has_platform_permission(
    p_account_id, 'platform.orders.trace'
  ) or dastak_v1_api.actor_has_platform_permission(
    p_account_id, 'platform.recovery.manage'
  ) or dastak_v1_api.actor_has_platform_permission(
    p_account_id, 'platform.returns.approve'
  );
$$;

revoke execute on function public.dastak_v1_can_inspect_evidence(uuid)
  from public, anon, authenticated, service_role;
grant execute on function dastak_v1_api.actor_has_platform_permission(uuid, text)
  to service_role;
grant execute on function public.dastak_v1_can_inspect_evidence(uuid)
  to service_role;
