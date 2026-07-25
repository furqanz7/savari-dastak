import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { RazorpayApiError, RazorpayTestClient } from "../_shared/razorpay.ts";
import { handleDastakPayments, type PaymentActionInput } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleDastakPayments(request, {
    authenticateBearer: verifyBearerUser,
    createCheckout,
    processRefund,
  })
);

async function createCheckout(input: PaymentActionInput) {
  const prepared = await rpc(input.entityType === "parcel"
    ? "prepare_parcel_razorpay_checkout"
    : "prepare_merchant_order_razorpay_checkout", {
    p_account_id: input.accountId,
    [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
  });
  if (prepared.responseStatus !== 200) return prepared;

  try {
    const details = checkoutDetails(prepared.responseBody);
    const client = razorpayClient();
    const providerOrder = details.providerOrderId
      ? await client.fetchOrder(details.providerOrderId)
      : await client.resolveOrder({
        amountPaise: details.amountPaise,
        currency: details.currency,
        receipt: details.receipt,
        orderId: details.orderId,
      });
    if (
      providerOrder.amount !== details.amountPaise || providerOrder.currency !== details.currency ||
      providerOrder.receipt !== details.receipt || providerOrder.status === "paid" ||
      (details.providerOrderId !== undefined && providerOrder.id !== details.providerOrderId)
    ) return providerConflict();

    const attached = await rpc(input.entityType === "parcel"
      ? "attach_parcel_razorpay_order"
      : "attach_merchant_order_razorpay_order", {
      p_account_id: input.accountId,
      [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
      p_provider_order_reference: providerOrder.id,
      p_amount_paise: details.amountPaise,
      p_currency: details.currency,
    });
    if (attached.responseStatus !== 200) return attached;
    return {
      responseBody: {
        ...details,
        orderId: details.entityId,
        providerOrderId: providerOrder.id,
        keyId: client.keyId,
      },
      responseStatus: 200,
    };
  } catch (error) {
    return providerError(error);
  }
}

async function processRefund(input: PaymentActionInput) {
  const prepared = await rpc(input.entityType === "parcel"
    ? "prepare_parcel_razorpay_refund"
    : "prepare_merchant_order_razorpay_refund", {
    p_account_id: input.accountId,
    [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
  });
  if (prepared.responseStatus !== 200) return prepared;

  try {
    const details = refundDetails(prepared.responseBody);
    if (details.refundState === "processed") {
      return { responseBody: { orderId: details.orderId, refundState: "processed" }, responseStatus: 200 };
    }
    const client = razorpayClient();
    const providerRefund = details.providerRefundId
      ? { id: details.providerRefundId, amount: details.amountPaise }
      : await client.resolveRefund({
        providerPaymentId: details.providerPaymentId,
        amountPaise: details.amountPaise,
        currency: details.currency,
        receipt: details.receipt,
        orderId: details.orderId,
      });
    if (providerRefund.amount !== details.amountPaise) return providerConflict();

    return await rpc(input.entityType === "parcel"
      ? "attach_parcel_razorpay_refund"
      : "attach_merchant_order_razorpay_refund", {
      p_account_id: input.accountId,
      [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
      p_provider_refund_reference: providerRefund.id,
      p_amount_paise: details.amountPaise,
    });
  } catch (error) {
    return providerError(error);
  }
}

async function rpc(functionName: string, parameters: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(functionName, parameters);
  if (error) throw error;
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return { responseBody: row.response_body, responseStatus: row.response_status };
}

function checkoutDetails(value: unknown) {
  const source = record(value);
  const entityId = text(source?.entityId ?? source?.orderId, 36);
  const amountPaise = money(source?.amountPaise);
  const receipt = text(source?.receipt, 40);
  const providerOrderId = source?.providerOrderId === null
    ? undefined
    : text(source?.providerOrderId, 200);
  if (!entityId || !receipt || !amountPaise || source?.currency !== "INR") throw new Error("Invalid checkout details");
  return { entityId, orderId: entityId, amountPaise, receipt, providerOrderId, currency: "INR" as const };
}

function refundDetails(value: unknown) {
  const source = record(value);
  const orderId = text(source?.entityId ?? source?.orderId, 36);
  const providerPaymentId = text(source?.providerPaymentId, 200);
  const providerRefundId = source?.providerRefundId === null
    ? undefined
    : text(source?.providerRefundId, 200);
  const amountPaise = money(source?.amountPaise);
  const receipt = text(source?.receipt, 40);
  const refundState = source?.refundState;
  if (
    !orderId || !providerPaymentId || !amountPaise || !receipt || source?.currency !== "INR" ||
    (refundState !== "pending" && refundState !== "processed")
  ) throw new Error("Invalid refund details");
  return { orderId, providerPaymentId, providerRefundId, amountPaise, receipt, refundState, currency: "INR" as const };
}

function razorpayClient() {
  return new RazorpayTestClient(requiredEnv("RAZORPAY_KEY_ID"), requiredEnv("RAZORPAY_KEY_SECRET"));
}

function providerError(error: unknown) {
  const status = error instanceof RazorpayApiError && error.status === 409 ? 409 : 503;
  return {
    responseBody: {
      error: {
        code: status === 409 ? "provider_reference_conflict" : "payment_provider_unavailable",
        message: status === 409
          ? "The payment provider returned conflicting order details."
          : "Razorpay checkout is not configured or is temporarily unavailable.",
      },
    },
    responseStatus: status,
  };
}

function providerConflict() {
  return providerError(new RazorpayApiError(409));
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function text(value: unknown, maximum: number) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum ? value : undefined;
}

function money(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 && value <= 100_000_000
    ? value
    : undefined;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
