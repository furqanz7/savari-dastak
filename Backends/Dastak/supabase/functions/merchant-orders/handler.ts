import { json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type MerchantOrderStatus =
  | "payment_pending"
  | "paid"
  | "merchant_accepted"
  | "ready"
  | "assigned"
  | "en_route_to_pickup"
  | "picked_up"
  | "in_transit"
  | "delivered"
  | "cancelled"
  | "returning_to_merchant";

export type MerchantOrderPaymentState =
  | "payment_pending"
  | "paid"
  | "not_collected"
  | "refund_pending"
  | "refunded";

export type MerchantOrderLine = {
  productId: string;
  name: string;
  unitLabel: string;
  unitPrice: { paise: number };
  quantity: number;
  lineSubtotal: { paise: number };
};

export type MerchantOrderRefundDecision = {
  decisionId: string;
  eligibility:
    | "no_payment"
    | "full_refund"
    | "owner_review_required"
    | "merchant_fault_full_refund"
    | "delivery_fee_retained_unless_fault";
  decisionStatus: "not_required" | "eligible" | "review_required" | "denied";
  itemRefund: { paise: number } | null;
  deliveryFeeRefund: { paise: number } | null;
  reason: string;
  createdAt: string;
};

export type MerchantOrderQuote = {
  quoteId: string;
  storeId: string;
  lines: MerchantOrderLine[];
  itemSubtotal: { paise: number };
  deliveryFee: { paise: number };
  total: { paise: number };
  dropoff: { latitude: number; longitude: number };
  expiresAt: string;
};

export type MerchantOrderSnapshot = {
  orderId: string;
  storeId: string;
  status: MerchantOrderStatus;
  paymentState: MerchantOrderPaymentState;
  lines: MerchantOrderLine[];
  itemSubtotal: { paise: number };
  deliveryFee: { paise: number };
  total: { paise: number };
  dropoff: { latitude: number; longitude: number };
  stateVersion: number;
  refundDecision: MerchantOrderRefundDecision | null;
  createdAt: string;
  updatedAt: string;
};

type RpcResult = { responseBody: unknown; responseStatus: number };
type OrderLineInput = { productId: string; quantity: number };

export type QuoteMerchantOrderInput = {
  accountId: string;
  storeId: string;
  lines: OrderLineInput[];
  dropoffLatitude: number;
  dropoffLongitude: number;
  idempotencyKey: string;
  requestDigest: string;
};

export type CreateMerchantOrderInput = {
  accountId: string;
  quoteId: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type MerchantOrderMutationInput = {
  accountId: string;
  orderId: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type MerchantRejectOrderInput = MerchantOrderMutationInput & { reason: string };
export type CustomerCancelOrderInput = MerchantOrderMutationInput & { reason: string };

export type MerchantOrderDependencies = {
  authenticateBearer: AuthenticateBearer;
  quoteOrder: (input: QuoteMerchantOrderInput) => Promise<RpcResult>;
  createOrder: (input: CreateMerchantOrderInput) => Promise<RpcResult>;
  getCustomerOrders: (accountId: string) => Promise<RpcResult>;
  getMerchantOrders: (accountId: string) => Promise<RpcResult>;
  merchantAccept: (input: MerchantOrderMutationInput) => Promise<RpcResult>;
  merchantReject: (input: MerchantRejectOrderInput) => Promise<RpcResult>;
  merchantMarkReady: (input: MerchantOrderMutationInput) => Promise<RpcResult>;
  customerCancel: (input: CustomerCancelOrderInput) => Promise<RpcResult>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleMerchantOrders(
  request: Request,
  dependencies: MerchantOrderDependencies,
) {
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();

  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await parseBody(request);
  if (!body || typeof body.operation !== "string") return validationError();

  try {
    switch (body.operation) {
      case "quote":
        return await quoteOrder(request, body, actor.accountId, dependencies);
      case "create":
        return await createOrder(request, body, actor.accountId, dependencies);
      case "customerSnapshot": {
        const result = await dependencies.getCustomerOrders(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "merchantSnapshot": {
        const result = await dependencies.getMerchantOrders(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "merchantAccept":
        return await orderMutation(
          request,
          body,
          actor.accountId,
          dependencies.merchantAccept,
        );
      case "merchantReject":
        return await reasonedMutation(
          request,
          body,
          actor.accountId,
          dependencies.merchantReject,
        );
      case "merchantMarkReady":
        return await orderMutation(
          request,
          body,
          actor.accountId,
          dependencies.merchantMarkReady,
        );
      case "customerCancel":
        return await reasonedMutation(
          request,
          body,
          actor.accountId,
          dependencies.customerCancel,
        );
      default:
        return validationError();
    }
  } catch {
    return internalError();
  }
}

async function quoteOrder(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: MerchantOrderDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const storeId = validUUID(body.storeId);
  const lines = parseLines(body.lines);
  const dropoff = parseLocation(body.dropoff);
  if (!idempotencyKey || !storeId || !lines || !dropoff) return validationError();

  const normalized = {
    storeId,
    lines,
    dropoffLatitude: dropoff.latitude,
    dropoffLongitude: dropoff.longitude,
  };
  const result = await dependencies.quoteOrder({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function createOrder(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: MerchantOrderDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const quoteId = validUUID(body.quoteId);
  if (!idempotencyKey || !quoteId) return validationError();

  const normalized = { quoteId };
  const result = await dependencies.createOrder({
    accountId,
    quoteId,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function orderMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: MerchantOrderMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const orderId = validUUID(body.orderId);
  if (!idempotencyKey || !orderId) return validationError();

  const normalized = { orderId };
  const result = await dependency({
    accountId,
    orderId,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function reasonedMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: MerchantRejectOrderInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const orderId = validUUID(body.orderId);
  const reason = normalizeRequiredText(body.reason, 300);
  if (!idempotencyKey || !orderId || !reason) return validationError();

  const normalized = { orderId, reason };
  const result = await dependency({
    accountId,
    orderId,
    reason,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

function parseLines(value: unknown): OrderLineInput[] | undefined {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) return undefined;
  const seen = new Set<string>();
  const lines: OrderLineInput[] = [];
  for (const valueLine of value) {
    const line = record(valueLine);
    const productId = validUUID(line?.productId);
    const quantity = line?.quantity;
    if (
      !productId || seen.has(productId) || typeof quantity !== "number" ||
      !Number.isInteger(quantity) || quantity < 1 || quantity > 99
    ) {
      return undefined;
    }
    seen.add(productId);
    lines.push({ productId, quantity });
  }
  return lines;
}

async function parseBody(
  request: Request,
): Promise<Record<string, unknown> | undefined> {
  try {
    const body = await request.json();
    return record(body);
  } catch {
    return undefined;
  }
}

function parseLocation(value: unknown) {
  const location = record(value);
  if (!location) return undefined;
  const latitude = location.latitude;
  const longitude = location.longitude;
  return typeof latitude === "number" && Number.isFinite(latitude) &&
      latitude >= -90 && latitude <= 90 &&
      typeof longitude === "number" && Number.isFinite(longitude) &&
      longitude >= -180 && longitude <= 180
    ? { latitude, longitude }
    : undefined;
}

function normalizeRequiredText(value: unknown, maximumLength: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximumLength ? normalized : undefined;
}

function validUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
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
    error: {
      code: "authentication_required",
      message: "A valid bearer token is required.",
    },
  }, 401);
}

function validationError() {
  return json({
    error: {
      code: "validation_failed",
      message: "The merchant order request is invalid.",
    },
  }, 400);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The merchant order request could not be processed.",
    },
  }, 500);
}
