import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type PaymentActionInput = {
  accountId: string;
  orderId: string;
  refundId: string | null;
  entityType: "merchant_order" | "parcel" | "dastak_v1_order";
  idempotencyKey: string;
  requestDigest: string;
};

export type PaymentFailureInput = PaymentActionInput & {
  attemptId: string;
  failureCode: string;
};

export type DastakPaymentDependencies = {
  authenticateBearer: AuthenticateBearer;
  createCheckout: (input: PaymentActionInput) => Promise<RpcResult>;
  processRefund: (input: PaymentActionInput) => Promise<RpcResult>;
  reportPaymentFailure: (input: PaymentFailureInput) => Promise<RpcResult>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleDastakPayments(
  request: Request,
  dependencies: DastakPaymentDependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();

  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await parseBody(request);
  const entityType = body?.entityType === "parcel"
    ? "parcel"
    : body?.entityType === "dastak_v1_order"
    ? "dastak_v1_order"
    : body?.entityType === undefined || body?.entityType === "merchant_order"
    ? "merchant_order"
    : undefined;
  const orderId = validUUID(entityType === "parcel" ? body?.parcelId : body?.orderId);
  const refundId = validUUID(body?.refundId) ?? null;
  const idempotencyKey = requiredIdempotencyKey(request);
  if (
    !body || !entityType || !orderId || !idempotencyKey ||
    (body.operation === "processRefund" && entityType === "dastak_v1_order" && !refundId)
  ) return validationError();

  const attemptId = validUUID(body.paymentAttemptId);
  const failureCode = validFailureCode(body.failureCode);
  const normalized = {
    operation: body.operation,
    entityType,
    orderId,
    ...(attemptId ? { attemptId } : {}),
    ...(failureCode ? { failureCode } : {}),
    ...(refundId ? { refundId } : {}),
  };
  const input: PaymentActionInput = {
    accountId: actor.accountId,
    orderId,
    refundId,
    entityType,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  };

  try {
    if (body.operation === "createCheckout") {
      const result = await dependencies.createCheckout(input);
      return json(result.responseBody, result.responseStatus);
    }
    if (body.operation === "processRefund") {
      const result = await dependencies.processRefund(input);
      return json(result.responseBody, result.responseStatus);
    }
    if (
      body.operation === "reportPaymentFailure" && entityType === "dastak_v1_order" &&
      attemptId && failureCode
    ) {
      const result = await dependencies.reportPaymentFailure({
        ...input,
        attemptId,
        failureCode,
      });
      return json(result.responseBody, result.responseStatus);
    }
    return validationError();
  } catch {
    return json({
      error: {
        code: "payment_provider_unavailable",
        message: "The payment provider is unavailable right now.",
      },
    }, 502);
  }
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    const value = await request.json();
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : undefined;
  } catch {
    return undefined;
  }
}

function validUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : undefined;
}

function validFailureCode(value: unknown) {
  return typeof value === "string" && /^[A-Z][A-Z0-9_]{0,79}$/.test(value) ? value : undefined;
}

function requiredIdempotencyKey(request: Request) {
  const key = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  return key.length >= 1 && key.length <= 200 ? key : undefined;
}

async function canonicalDigest(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "The payment request is invalid." },
  }, 400);
}
