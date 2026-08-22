import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { verifyBearerSession } from "../_shared/auth.ts";
import { callAuthenticatedRPC } from "../_shared/v1-rpc.ts";
import { handleV1Orders } from "./handler.ts";

Deno.serve((request) =>
  handleV1Orders(request, {
    authenticateBearer: verifyBearerSession,
    submitOrder: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_submit_order", {
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
        p_order: input.order,
      }),
    listOrders: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_list_customer_orders", {
        p_limit: input.limit,
        p_before_created_at: input.beforeCreatedAt,
        p_before_order_id: input.beforeOrderId,
      }),
    getOrder: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_get_order", {
        p_order_id: input.orderId,
      }),
    cancelOrder: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_cancel_prepayment_order", {
        p_order_id: input.orderId,
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
      }),
    listMerchantOpportunities: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_list_merchant_opportunities", {
        p_limit: input.limit,
      }),
    acceptMerchantOpportunity: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        input.requestScope === "FULL_BASKET"
          ? "dastak_v1_accept_wave1_opportunity"
          : "dastak_v1_accept_wave2_opportunity",
        {
          p_opportunity_id: input.opportunityId,
          p_idempotency_key: input.idempotencyKey,
          p_expected_version: input.expectedVersion,
          p_promised_prep_minutes: input.promisedPrepMinutes,
        },
      ),
    declineMerchantOpportunity: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        input.requestScope === "FULL_BASKET"
          ? "dastak_v1_decline_opportunity"
          : "dastak_v1_decline_wave2_opportunity",
        {
          p_opportunity_id: input.opportunityId,
          p_idempotency_key: input.idempotencyKey,
          p_expected_version: input.expectedVersion,
        },
      ),
    listMerchantFulfilments: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_merchant_fulfilments", {
        p_limit: input.limit,
      }),
    declareFulfilmentPackages: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_declare_fulfilment_packages", {
        p_fulfilment_id: input.fulfilmentId,
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
        p_package_count: input.packageCount,
      }),
    addFulfilmentReadyEvidence: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_add_fulfilment_ready_evidence", {
        p_fulfilment_id: input.fulfilmentId,
        p_package_id: input.packageId,
        p_object_path: input.objectPath,
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
      }),
    markFulfilmentReady: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_mark_fulfilment_ready", {
        p_fulfilment_id: input.fulfilmentId,
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
      }),
    reportFulfilmentProblem: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_report_fulfilment_problem", {
        p_fulfilment_id: input.fulfilmentId,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
      }),
    listAdminExecutionOrders: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_admin_execution_orders", {
        p_limit: input.limit,
      }),
    getAdminExecutionTrace: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_admin_execution_trace", {
        p_order_id: input.orderId,
      }),
    getAdminSystemHealth: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_admin_system_health", {}),
    authorizeExceptionalDeliveryHandoff: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_authorize_exceptional_delivery_handoff",
        {
          p_mission_id: input.missionId,
          p_delivery_evidence_id: input.deliveryEvidenceId,
          p_reason: input.reason,
          p_expected_mission_version: input.expectedMissionVersion,
          p_idempotency_key: input.idempotencyKey,
        },
      ),
    reportExactSkuFailure: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_report_exact_sku_failure", {
        p_fulfilment_id: input.fulfilmentId,
        p_order_line_id: input.orderLineId,
        p_reason: input.reason,
        p_expected_fulfilment_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    createExactSkuRecoveryOffer: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_create_exact_sku_recovery_offer", {
        p_recovery_case_id: input.recoveryCaseId,
        p_branch_id: input.branchId,
        p_expected_case_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    respondExactSkuRecoveryOffer: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_respond_exact_sku_recovery_offer", {
        p_recovery_opportunity_id: input.recoveryOpportunityId,
        p_response: input.response,
        p_promised_prep_minutes: input.promisedPrepMinutes,
        p_expected_opportunity_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    failExactSkuRecovery: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_fail_exact_sku_recovery", {
        p_recovery_case_id: input.recoveryCaseId,
        p_reason: input.reason,
        p_expected_case_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    reportCustomerIssue: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_report_customer_issue", {
        p_order_id: input.orderId,
        p_order_line_id: input.orderLineId,
        p_category: input.category,
        p_description: input.description,
        p_object_path: input.objectPath,
        p_content_type: input.contentType,
        p_idempotency_key: input.idempotencyKey,
      }),
    decideCustomerIssue: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_decide_customer_issue", {
        p_issue_id: input.issueId,
        p_decision: input.decision,
        p_refund_amount_paise: input.refundAmountPaise,
        p_fault_source: input.faultSource,
        p_return_package_count: input.returnPackageCount,
        p_reason: input.reason,
        p_expected_issue_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    assignReturnRider: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_assign_return_rider", {
        p_return_mission_id: input.returnMissionId,
        p_rider_id: input.riderId,
        p_expected_mission_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    manageDeliveryRecovery: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_manage_delivery_recovery", {
        p_recovery_case_id: input.recoveryCaseId,
        p_action: input.action,
        p_fault_source: input.faultSource,
        p_refund_amount_paise: input.refundAmountPaise,
        p_corrected_address: input.correctedAddress,
        p_reason: input.reason,
        p_expected_case_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    finalizeSettlementCalculation: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_finalize_settlement_calculation", {
        p_settlement_entry_id: input.settlementEntryId,
        p_expected_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
    settleEntry: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_settle_entry", {
        p_settlement_entry_id: input.settlementEntryId,
        p_settlement_reference: input.settlementReference,
        p_expected_version: input.expectedVersion,
        p_idempotency_key: input.idempotencyKey,
      }),
  })
);
