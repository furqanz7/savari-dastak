import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  RazorpayApiError,
  RazorpayClient,
  razorpayModeForEntity,
  type RazorpayPaymentMode,
} from "../_shared/razorpay.ts";
import {
  handleDastakPayments,
  type PaymentActionInput,
  type PaymentCompletionInput,
} from "./handler.ts";
import { sha256Hex, verifyRazorpayPaymentSignature } from "./verification.ts";

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
    reportPaymentFailure,
    completeCustomCheckout,
  })
);

async function completeCustomCheckout(input: PaymentCompletionInput) {
  try {
    const paymentMode = razorpayPaymentMode();
    const context = completionContext(
      await rpcJson(
        "dastak_v1_custom_checkout_completion_context_mode",
        {
          p_account_id: input.accountId,
          p_order_id: input.orderId,
          p_attempt_id: input.attemptId,
          p_provider_mode: paymentMode,
        },
      ),
    );
    if (context.providerMode !== paymentMode) {
      return completionRejected(
        409,
        "provider_mode_mismatch",
        "The payment response belongs to a different provider environment.",
      );
    }
    if (context.providerOrderId !== input.providerOrderId) {
      return completionRejected(
        409,
        "provider_order_mismatch",
        "The payment response belongs to a different provider order.",
      );
    }
    if (
      !await verifyRazorpayPaymentSignature(
        razorpayCredentials(paymentMode).keySecret,
        context.providerOrderId,
        input.providerPaymentId,
        input.providerSignature,
      )
    ) {
      return completionRejected(
        400,
        "invalid_payment_signature",
        "The payment response could not be verified.",
      );
    }

    return {
      responseBody: await rpcJson("dastak_v1_record_custom_checkout_completion_mode", {
        p_account_id: input.accountId,
        p_order_id: input.orderId,
        p_attempt_id: input.attemptId,
        p_provider_order_reference: context.providerOrderId,
        p_provider_payment_reference: input.providerPaymentId,
        p_signature_digest: await sha256Hex(input.providerSignature),
        p_request_digest: input.requestDigest,
        p_idempotency_key: input.idempotencyKey,
        p_provider_mode: paymentMode,
      }),
      responseStatus: 202,
    };
  } catch (error) {
    return completionDatabaseError(error);
  }
}

async function reportPaymentFailure(
  input: PaymentActionInput & {
    attemptId: string;
    failureCode: string;
  },
) {
  return {
    responseBody: await rpcJson("dastak_v1_mark_payment_attempt_failed", {
      p_account_id: input.accountId,
      p_attempt_id: input.attemptId,
      p_failure_code: input.failureCode,
    }),
    responseStatus: 200,
  };
}

async function createCheckout(input: PaymentActionInput) {
  let paymentMode: RazorpayPaymentMode;
  try {
    paymentMode = razorpayModeForEntity(razorpayPaymentMode(), input.entityType);
  } catch (error) {
    return providerError(error);
  }
  const prepared = input.entityType === "dastak_v1_order"
    ? {
      responseBody: await rpcJson("dastak_v1_prepare_razorpay_checkout_mode", {
        p_account_id: input.accountId,
        p_order_id: input.orderId,
        p_idempotency_key: input.idempotencyKey,
        p_provider_mode: paymentMode,
      }),
      responseStatus: 200,
    }
    : await rpc(
      input.entityType === "parcel"
        ? "prepare_parcel_razorpay_checkout"
        : "prepare_merchant_order_razorpay_checkout",
      {
        p_account_id: input.accountId,
        [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
      },
    );
  if (prepared.responseStatus !== 200) return prepared;

  let details: ReturnType<typeof checkoutDetails> | undefined;
  try {
    details = checkoutDetails(prepared.responseBody);
    if (input.entityType === "dastak_v1_order" && !details.attemptId) {
      throw new Error("Dastak V1 checkout is missing its payment attempt");
    }
    if (input.entityType === "dastak_v1_order" && details.providerMode !== paymentMode) {
      throw new Error("Dastak V1 checkout provider mode mismatch");
    }
    const client = razorpayClient(paymentMode);
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

    const attached = input.entityType === "dastak_v1_order"
      ? {
        responseBody: await rpcJson("dastak_v1_attach_razorpay_order_mode", {
          p_account_id: input.accountId,
          p_attempt_id: details.attemptId,
          p_provider_order_reference: providerOrder.id,
          p_amount_paise: details.amountPaise,
          p_currency: details.currency,
          p_provider_mode: paymentMode,
        }),
        responseStatus: 200,
      }
      : await rpc(
        input.entityType === "parcel"
          ? "attach_parcel_razorpay_order"
          : "attach_merchant_order_razorpay_order",
        {
          p_account_id: input.accountId,
          [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
          p_provider_order_reference: providerOrder.id,
          p_amount_paise: details.amountPaise,
          p_currency: details.currency,
        },
      );
    if (attached.responseStatus !== 200) return attached;
    return {
      responseBody: {
        ...details,
        orderId: details.entityId,
        entityType: input.entityType,
        providerOrderId: providerOrder.id,
        keyId: client.keyId,
        providerMode: paymentMode,
      },
      responseStatus: 200,
    };
  } catch (error) {
    if (input.entityType === "dastak_v1_order" && details?.attemptId) {
      await rpcJson("dastak_v1_mark_payment_attempt_failed", {
        p_account_id: input.accountId,
        p_attempt_id: details.attemptId,
        p_failure_code: "PROVIDER_CHECKOUT_UNAVAILABLE",
      }).catch(() => undefined);
    }
    return providerError(error);
  }
}

async function processRefund(input: PaymentActionInput) {
  let paymentMode: RazorpayPaymentMode;
  try {
    paymentMode = razorpayModeForEntity(razorpayPaymentMode(), input.entityType);
  } catch (error) {
    return providerError(error);
  }
  const prepared = input.entityType === "dastak_v1_order"
    ? {
      responseBody: await rpcJson("dastak_v1_prepare_razorpay_refund_mode", {
        p_account_id: input.accountId,
        p_refund_id: input.refundId,
        p_idempotency_key: input.idempotencyKey,
        p_provider_mode: paymentMode,
      }),
      responseStatus: 200,
    }
    : await rpc(
      input.entityType === "parcel"
        ? "prepare_parcel_razorpay_refund"
        : "prepare_merchant_order_razorpay_refund",
      {
        p_account_id: input.accountId,
        [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
      },
    );
  if (prepared.responseStatus !== 200) return prepared;

  try {
    const details = refundDetails(prepared.responseBody);
    if (input.entityType === "dastak_v1_order" && details.providerMode !== paymentMode) {
      throw new Error("Dastak V1 refund provider mode mismatch");
    }
    if (details.refundState === "processed") {
      return {
        responseBody: { orderId: details.orderId, refundState: "processed" },
        responseStatus: 200,
      };
    }
    const client = razorpayClient(paymentMode);
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

    if (input.entityType === "dastak_v1_order") {
      return {
        responseBody: await rpcJson("dastak_v1_attach_razorpay_refund_mode", {
          p_account_id: input.accountId,
          p_refund_id: input.refundId,
          p_provider_refund_reference: providerRefund.id,
          p_amount_paise: details.amountPaise,
          p_provider_mode: paymentMode,
        }),
        responseStatus: 200,
      };
    }
    return await rpc(
      input.entityType === "parcel"
        ? "attach_parcel_razorpay_refund"
        : "attach_merchant_order_razorpay_refund",
      {
        p_account_id: input.accountId,
        [input.entityType === "parcel" ? "p_parcel_id" : "p_order_id"]: input.orderId,
        p_provider_refund_reference: providerRefund.id,
        p_amount_paise: details.amountPaise,
      },
    );
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

async function rpcJson(functionName: string, parameters: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(functionName, parameters);
  if (error) throw error;
  const value = Array.isArray(data) ? data[0] : data;
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return value as Record<string, unknown>;
}

function checkoutDetails(value: unknown) {
  const source = record(value);
  const entityId = text(source?.entityId ?? source?.orderId, 36);
  const amountPaise = money(source?.amountPaise);
  const receipt = text(source?.receipt, 40);
  const providerOrderId = source?.providerOrderId === null
    ? undefined
    : text(source?.providerOrderId, 200);
  const attemptId = source?.attemptId === undefined ? undefined : text(source.attemptId, 36);
  const providerMode = paymentMode(source?.providerMode);
  if (!entityId || !receipt || !amountPaise || source?.currency !== "INR") {
    throw new Error("Invalid checkout details");
  }
  return {
    entityId,
    orderId: entityId,
    amountPaise,
    receipt,
    providerOrderId,
    attemptId,
    providerMode,
    currency: "INR" as const,
  };
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
  const providerMode = paymentMode(source?.providerMode);
  if (
    !orderId || !providerPaymentId || !amountPaise || !receipt || source?.currency !== "INR" ||
    (refundState !== "pending" && refundState !== "processed")
  ) throw new Error("Invalid refund details");
  return {
    orderId,
    providerPaymentId,
    providerRefundId,
    amountPaise,
    receipt,
    refundState,
    providerMode,
    currency: "INR" as const,
  };
}

function completionContext(value: unknown) {
  const source = record(value);
  const orderId = text(source?.orderId, 36);
  const paymentId = text(source?.paymentId, 36);
  const attemptId = text(source?.attemptId, 36);
  const providerOrderId = text(source?.providerOrderId, 200);
  const amountPaise = money(source?.amountPaise);
  const providerMode = paymentMode(source?.providerMode);
  if (
    !orderId || !paymentId || !attemptId || !providerOrderId || !amountPaise || !providerMode ||
    !/^order_[A-Za-z0-9]+$/.test(providerOrderId) || source?.currency !== "INR"
  ) throw new Error("Invalid custom checkout completion context");
  return { orderId, paymentId, attemptId, providerOrderId, amountPaise, providerMode };
}

function razorpayClient(mode: RazorpayPaymentMode) {
  const credentials = razorpayCredentials(mode);
  return new RazorpayClient(credentials.keyId, credentials.keySecret, mode);
}

function razorpayCredentials(mode: RazorpayPaymentMode) {
  return mode === "TEST"
    ? {
      keyId: requiredEnv("RAZORPAY_TEST_KEY_ID"),
      keySecret: requiredEnv("RAZORPAY_TEST_KEY_SECRET"),
    }
    : {
      keyId: requiredEnv("RAZORPAY_KEY_ID"),
      keySecret: requiredEnv("RAZORPAY_KEY_SECRET"),
    };
}

function razorpayPaymentMode(): RazorpayPaymentMode {
  const mode = Deno.env.get("RAZORPAY_PAYMENT_MODE");
  if (mode !== "TEST" && mode !== "LIVE") {
    throw new Error("RAZORPAY_PAYMENT_MODE must be TEST or LIVE");
  }
  return mode;
}

function paymentMode(value: unknown): RazorpayPaymentMode | undefined {
  return value === "TEST" || value === "LIVE" ? value : undefined;
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

function completionRejected(status: number, code: string, message: string) {
  return { responseBody: { error: { code, message } }, responseStatus: status };
}

function completionDatabaseError(error: unknown) {
  const code = record(error)?.code;
  if (code === "42501") {
    return completionRejected(
      403,
      "payment_completion_forbidden",
      "This payment cannot be completed by this account.",
    );
  }
  if (code === "P0002") {
    return completionRejected(
      404,
      "payment_attempt_not_found",
      "The payment attempt was not found.",
    );
  }
  if (code === "22023" || code === "23505" || code === "55000") {
    return completionRejected(
      409,
      "payment_completion_conflict",
      "The payment response conflicts with the active attempt.",
    );
  }
  return completionRejected(
    503,
    "payment_completion_unavailable",
    "Dastak could not verify the payment response right now.",
  );
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function text(value: unknown, maximum: number) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum
    ? value
    : undefined;
}

function money(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 &&
      value <= 100_000_000
    ? value
    : undefined;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
