import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type CreateMerchantOrderInput,
  type CustomerCancelOrderInput,
  type CustomerOrderSupportInput,
  handleMerchantOrders,
  type MerchantConfirmReturnInput,
  type MerchantOrderMutationInput,
  type MerchantRejectOrderInput,
  type OwnerResetHandoffInput,
  type OwnerResetParcelHandoffInput,
  type OwnerResolveSupportInput,
  type OwnerReviewRefundInput,
  type QuoteMerchantOrderInput,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleMerchantOrders(request, {
    authenticateBearer: verifyBearerUser,
    quoteOrder,
    createOrder,
    getCustomerOrders,
    getCustomerOrder,
    createCustomerSupport,
    getMerchantOrders,
    getOwnerOrders,
    getOwnerOperations,
    merchantAccept,
    merchantReject,
    merchantMarkReady,
    customerCancel,
    merchantConfirmReturn,
    ownerReviewRefund,
    ownerResetHandoff,
    ownerResolveSupport,
    ownerResetParcelHandoff,
    ownerReconcile,
  })
);

async function quoteOrder(input: QuoteMerchantOrderInput) {
  const { data, error } = await serviceClient.rpc("quote_merchant_order", {
    p_account_id: input.accountId,
    p_store_id: input.storeId,
    p_lines: input.lines,
    p_dropoff_latitude: input.dropoffLatitude,
    p_dropoff_longitude: input.dropoffLongitude,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "quote_merchant_order");
}

async function createOrder(input: CreateMerchantOrderInput) {
  const { data, error } = await serviceClient.rpc("create_merchant_order", {
    p_account_id: input.accountId,
    p_quote_id: input.quoteId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "create_merchant_order");
}

async function getCustomerOrders(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_customer_orders", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_customer_orders");
}

async function getCustomerOrder(accountId: string, orderId: string) {
  const { data, error } = await serviceClient.rpc("get_customer_order_snapshot", {
    p_account_id: accountId,
    p_order_id: orderId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_customer_order_snapshot");
}

async function createCustomerSupport(input: CustomerOrderSupportInput) {
  const { data, error } = await serviceClient.rpc("create_customer_order_support_case", {
    p_account_id: input.accountId,
    p_entity_kind: "merchant_order",
    p_entity_id: input.orderId,
    p_category: input.category,
    p_message: input.message,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "create_customer_order_support_case");
}

async function getMerchantOrders(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_merchant_orders", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_merchant_orders");
}

async function getOwnerOrders(accountId: string, limit: number) {
  const { data, error } = await serviceClient.rpc("get_owner_merchant_orders", {
    p_account_id: accountId,
    p_limit: limit,
  });
  if (error) throw error;
  return rpcResponse(data, "get_owner_merchant_orders");
}

async function getOwnerOperations(accountId: string, limit: number) {
  const { data, error } = await serviceClient.rpc("get_owner_order_operations", {
    p_account_id: accountId,
    p_limit: limit,
  });
  if (error) throw error;
  return rpcResponse(data, "get_owner_order_operations");
}

async function merchantAccept(input: MerchantOrderMutationInput) {
  return orderMutation("merchant_accept_order", input);
}

async function merchantMarkReady(input: MerchantOrderMutationInput) {
  return orderMutation("merchant_mark_order_ready", input);
}

async function merchantReject(input: MerchantRejectOrderInput) {
  const { data, error } = await serviceClient.rpc("merchant_reject_order", {
    p_account_id: input.accountId,
    p_order_id: input.orderId,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "merchant_reject_order");
}

async function customerCancel(input: CustomerCancelOrderInput) {
  const { data, error } = await serviceClient.rpc("customer_cancel_order", {
    p_account_id: input.accountId,
    p_order_id: input.orderId,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "customer_cancel_order");
}

async function merchantConfirmReturn(input: MerchantConfirmReturnInput) {
  const { data, error } = await serviceClient.rpc(
    "merchant_confirm_customer_cancellation_return",
    {
      p_account_id: input.accountId,
      p_order_id: input.orderId,
      p_reason: input.reason,
      p_idempotency_key: input.idempotencyKey,
      p_request_digest: input.requestDigest,
    },
  );
  if (error) throw error;
  return rpcResponse(data, "merchant_confirm_customer_cancellation_return");
}

async function ownerReviewRefund(input: OwnerReviewRefundInput) {
  const { data, error } = await serviceClient.rpc("owner_review_merchant_order_refund", {
    p_account_id: input.accountId,
    p_order_id: input.orderId,
    p_outcome: input.outcome,
    p_fault_source: input.faultSource,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "owner_review_merchant_order_refund");
}

async function ownerResetHandoff(input: OwnerResetHandoffInput) {
  const { data, error } = await serviceClient.rpc("owner_reset_order_handoff_code", {
    p_account_id: input.accountId,
    p_order_id: input.orderId,
    p_purpose: input.purpose,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "owner_reset_order_handoff_code");
}

async function ownerResolveSupport(input: OwnerResolveSupportInput) {
  const { data, error } = await serviceClient.rpc("owner_resolve_customer_support_case", {
    p_account_id: input.accountId,
    p_case_id: input.caseId,
    p_resolution: input.resolution,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "owner_resolve_customer_support_case");
}

async function ownerResetParcelHandoff(input: OwnerResetParcelHandoffInput) {
  const { data, error } = await serviceClient.rpc("owner_reset_parcel_handoff_code", {
    p_account_id: input.accountId,
    p_parcel_id: input.parcelId,
    p_purpose: input.purpose,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "owner_reset_parcel_handoff_code");
}

async function ownerReconcile(accountId: string) {
  const { data, error } = await serviceClient.rpc("owner_reconcile_order_lifecycle", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "owner_reconcile_order_lifecycle");
}

async function orderMutation(
  functionName: "merchant_accept_order" | "merchant_mark_order_ready",
  input: MerchantOrderMutationInput,
) {
  const { data, error } = await serviceClient.rpc(functionName, {
    p_account_id: input.accountId,
    p_order_id: input.orderId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, functionName);
}

function rpcResponse(data: unknown, functionName: string) {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return {
    responseBody: row.response_body,
    responseStatus: row.response_status,
  };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
