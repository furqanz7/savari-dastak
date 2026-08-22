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
    listAdminExecutionOrders: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_admin_execution_orders", {
        p_limit: input.limit,
      }),
    getAdminExecutionTrace: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_admin_execution_trace", {
        p_order_id: input.orderId,
      }),
  })
);
