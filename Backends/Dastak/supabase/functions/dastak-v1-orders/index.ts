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
  })
);
