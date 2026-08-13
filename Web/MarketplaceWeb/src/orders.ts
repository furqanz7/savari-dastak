export type OrderLocation = { latitude: number; longitude: number };
export type OrderLineInput = { productId: string; quantity: number };

export type MerchantOrderLine = {
  productId: string;
  name: string;
  unitLabel: string;
  unitPrice: { paise: number };
  quantity: number;
  lineSubtotal: { paise: number };
};

type MerchantOrderPricing = {
  storeId: string;
  lines: MerchantOrderLine[];
  itemSubtotal: { paise: number };
  deliveryFee: { paise: number };
  deliveryDistanceMeters: number;
  total: { paise: number };
  dropoff: OrderLocation;
};

export type MerchantOrderQuote = MerchantOrderPricing & {
  quoteId: string;
  expiresAt: string;
};

export type MerchantOrderStatus =
  | "payment_pending"
  | "paid"
  | "merchant_accepted"
  | "ready"
  | "assigned"
  | "en_route_to_pickup"
  | "at_store"
  | "picked_up"
  | "in_transit"
  | "delivered"
  | "cancelled"
  | "returning_to_merchant";

export type MerchantOrderSnapshot = MerchantOrderPricing & {
  orderId: string;
  status: MerchantOrderStatus;
  paymentState: "payment_pending" | "paid" | "not_collected" | "refund_pending" | "refunded";
  stateVersion: number;
  handoffCode: { purpose: "pickup" | "delivery"; code: string; expiresAt: string } | null;
  refundDecision: {
    eligibility: string;
    decisionStatus: string;
    itemRefund: { paise: number } | null;
    deliveryFeeRefund: { paise: number } | null;
    reason: string;
  } | null;
  createdAt: string;
  updatedAt: string;
};

type AuthenticatedInput = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class OrderRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "OrderRequestError";
  }
}

export async function quoteMerchantOrder(
  input: AuthenticatedInput & {
    storeId: string;
    lines: OrderLineInput[];
    dropoff: OrderLocation;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrderQuote(await call(input, {
    operation: "quote",
    storeId: input.storeId,
    lines: input.lines,
    dropoff: input.dropoff,
  }, input.idempotencyKey, fetcher));
}

export async function createMerchantOrder(
  input: AuthenticatedInput & { quoteId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "create",
    quoteId: input.quoteId,
  }, input.idempotencyKey, fetcher));
}

export async function getCustomerOrders(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, { operation: "customerSnapshot" }, undefined, fetcher));
  if (!payload || !Array.isArray(payload.orders)) invalid();
  return payload.orders.map(parseMerchantOrder);
}

export async function getMerchantOrders(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, { operation: "merchantSnapshot" }, undefined, fetcher));
  if (!payload || !Array.isArray(payload.orders)) invalid();
  const orders = payload.orders.map(parseMerchantOrder);
  return orders.filter((order) =>
    order.status !== "payment_pending" &&
    order.paymentState !== "payment_pending" &&
    !(order.status === "cancelled" && order.paymentState === "not_collected")
  );
}

export async function acceptMerchantOrder(
  input: AuthenticatedInput & { orderId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "merchantAccept",
    orderId: input.orderId,
  }, input.idempotencyKey, fetcher));
}

export async function rejectMerchantOrder(
  input: AuthenticatedInput & { orderId: string; reason: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "merchantReject",
    orderId: input.orderId,
    reason: input.reason,
  }, input.idempotencyKey, fetcher));
}

export async function markMerchantOrderReady(
  input: AuthenticatedInput & { orderId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "merchantMarkReady",
    orderId: input.orderId,
  }, input.idempotencyKey, fetcher));
}

export async function cancelMerchantOrder(
  input: AuthenticatedInput & { orderId: string; reason: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "customerCancel",
    orderId: input.orderId,
    reason: input.reason,
  }, input.idempotencyKey, fetcher));
}

export async function confirmMerchantCancellationReturn(
  input: AuthenticatedInput & { orderId: string; reason: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "merchantConfirmReturn",
    orderId: input.orderId,
    reason: input.reason,
  }, input.idempotencyKey, fetcher));
}

export function parseMerchantOrderQuote(value: unknown): MerchantOrderQuote {
  const source = record(value);
  if (!source) invalid();
  return {
    quoteId: requiredUUID(source.quoteId),
    storeId: requiredUUID(source.storeId),
    lines: lines(source.lines),
    itemSubtotal: money(source.itemSubtotal),
    deliveryFee: money(source.deliveryFee),
    deliveryDistanceMeters: deliveryDistance(source.deliveryDistanceMeters),
    total: money(source.total),
    dropoff: location(source.dropoff),
    expiresAt: timestamp(source.expiresAt),
  };
}

export function parseMerchantOrder(value: unknown): MerchantOrderSnapshot {
  const source = record(value);
  if (!source || ["customerAccountId", "merchantAccountId", "courierAccountId"].some((key) => key in source)) {
    invalid();
  }
  const status = requiredText(source.status, 40);
  const paymentState = requiredText(source.paymentState, 40);
  if (!orderStatuses.has(status) || !paymentStates.has(paymentState)) invalid();
  const stateVersion = source.stateVersion;
  if (typeof stateVersion !== "number" || !Number.isInteger(stateVersion) || stateVersion < 1) invalid();

  return {
    orderId: requiredUUID(source.orderId),
    storeId: requiredUUID(source.storeId),
    status: status as MerchantOrderStatus,
    paymentState: paymentState as MerchantOrderSnapshot["paymentState"],
    lines: lines(source.lines),
    itemSubtotal: money(source.itemSubtotal),
    deliveryFee: money(source.deliveryFee),
    deliveryDistanceMeters: deliveryDistance(source.deliveryDistanceMeters),
    total: money(source.total),
    dropoff: location(source.dropoff),
    stateVersion,
    handoffCode: handoffCode(source.handoffCode),
    refundDecision: refundDecision(source.refundDecision),
    createdAt: timestamp(source.createdAt),
    updatedAt: timestamp(source.updatedAt),
  };
}

export function orderStatusLabel(status: MerchantOrderStatus) {
  switch (status) {
    case "payment_pending": return "Payment pending";
    case "paid": return "Waiting for merchant";
    case "merchant_accepted": return "Merchant accepted";
    case "ready": return "Ready for pickup";
    case "assigned": return "Delivery partner assigned";
    case "en_route_to_pickup": return "Partner heading to store";
    case "at_store": return "Partner at store";
    case "picked_up": return "Order picked up";
    case "in_transit": return "On the way";
    case "delivered": return "Delivered";
    case "cancelled": return "Cancelled";
    case "returning_to_merchant": return "Returning to merchant";
  }
}

export function canCancelOrder(status: MerchantOrderStatus) {
  return !["delivered", "cancelled", "returning_to_merchant"].includes(status);
}

export function formatDeliveryDistance(distanceMeters: number) {
  if (distanceMeters < 1000) return `${distanceMeters} m`;
  return `${new Intl.NumberFormat("en-IN", { maximumFractionDigits: 1 }).format(distanceMeters / 1000)} km`;
}

async function call(
  auth: AuthenticatedInput,
  body: unknown,
  idempotencyKey: string | undefined,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/merchant-orders`, {
      method: "POST",
      headers: {
        apikey: auth.publishableKey,
        authorization: `Bearer ${auth.accessToken}`,
        "content-type": "application/json",
        ...(idempotencyKey ? { "X-Idempotency-Key": idempotencyKey } : {}),
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new OrderRequestError("network_error", "Dastak could not reach the order service.", 0);
  }

  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new OrderRequestError(
      optionalText(error?.code, 80) ?? "order_unavailable",
      optionalText(error?.message, 300) ?? "The order request is unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function lines(value: unknown): MerchantOrderLine[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) invalid();
  return value.map((lineValue) => {
    const source = record(lineValue);
    const quantity = source?.quantity;
    if (!source || typeof quantity !== "number" || !Number.isInteger(quantity) || quantity < 1 || quantity > 99) invalid();
    return {
      productId: requiredUUID(source.productId),
      name: requiredText(source.name, 160),
      unitLabel: requiredText(source.unitLabel, 40),
      unitPrice: money(source.unitPrice),
      quantity,
      lineSubtotal: money(source.lineSubtotal),
    };
  });
}

function deliveryDistance(value: unknown) {
  if (
    typeof value !== "number" || !Number.isInteger(value) ||
    value < 0 || value > 1_000_000
  ) invalid();
  return value;
}

function location(value: unknown): OrderLocation {
  const source = record(value);
  const latitude = source?.latitude;
  const longitude = source?.longitude;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) invalid();
  return { latitude, longitude };
}

function money(value: unknown) {
  const paise = record(value)?.paise;
  if (typeof paise !== "number" || !Number.isInteger(paise) || paise < 0 || paise > 100_000_000) invalid();
  return { paise };
}

function handoffCode(value: unknown): MerchantOrderSnapshot["handoffCode"] {
  if (value === null || value === undefined) return null;
  const source = record(value);
  const purpose = source?.purpose;
  if (!source || (purpose !== "pickup" && purpose !== "delivery")) invalid();
  return {
    purpose,
    code: requiredText(source.code, 12),
    expiresAt: timestamp(source.expiresAt),
  };
}

function refundDecision(value: unknown): MerchantOrderSnapshot["refundDecision"] {
  if (value === null || value === undefined) return null;
  const source = record(value);
  if (!source) invalid();
  return {
    eligibility: requiredText(source.eligibility, 80),
    decisionStatus: requiredText(source.decisionStatus, 80),
    itemRefund: source.itemRefund === null ? null : money(source.itemRefund),
    deliveryFeeRefund: source.deliveryFeeRefund === null ? null : money(source.deliveryFeeRefund),
    reason: requiredText(source.reason, 300),
  };
}

function timestamp(value: unknown) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) invalid();
  return value;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}

function requiredText(value: unknown, maximum: number) {
  const result = optionalText(value, maximum);
  if (!result) invalid();
  return result;
}

function requiredUUID(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}

function invalid(): never {
  throw new OrderRequestError("invalid_response", "Dastak received an invalid order response.", 502);
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const orderStatuses = new Set([
  "payment_pending", "paid", "merchant_accepted", "ready", "assigned", "en_route_to_pickup",
  "at_store", "picked_up", "in_transit", "delivered", "cancelled", "returning_to_merchant",
]);
const paymentStates = new Set(["payment_pending", "paid", "not_collected", "refund_pending", "refunded"]);
