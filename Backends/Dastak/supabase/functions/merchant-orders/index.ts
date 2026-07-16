import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type CreateMerchantOrderInput,
  type CustomerCancelOrderInput,
  handleMerchantOrders,
  type MerchantOrderMutationInput,
  type MerchantRejectOrderInput,
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
    getMerchantOrders,
    merchantAccept,
    merchantReject,
    merchantMarkReady,
    customerCancel,
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

async function getMerchantOrders(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_merchant_orders", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_merchant_orders");
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
