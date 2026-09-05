export type OrderLocation = { latitude: number; longitude: number };
export type AddressedOrderLocation = OrderLocation & { address: string };
export type OrderLineInput = { productId: string; quantity: number };

export type CustomerCourierSnapshot = {
  displayName: string;
  phoneNumber: string;
  deliveryMethod: "walking" | "bicycle" | "retired" | "bike" | "auto";
  location: OrderLocation | null;
  lastSeenAt: string | null;
};

export type MerchantOrderAddressSnapshot = {
  label: string | null;
  address: string | null;
  details: string | null;
  displayAddress: string | null;
};

export type MerchantOrderTimeline = {
  createdAt: string;
  acceptedAt?: string;
  readyAt?: string;
  assignedAt?: string;
  enRouteToPickupAt?: string;
  atStoreAt?: string;
  pickedUpAt?: string;
  inTransitAt?: string;
  deliveredAt?: string;
  cancelledAt?: string;
};

export type CustomerOrderActions = {
  canPay: boolean;
  cancellationMode: "cancel" | "request_review" | "pending_review" | "none";
  canTrack: boolean;
  canContactStore: boolean;
  canContactCourier: boolean;
  canRequestSupport: boolean;
};

export type CustomerOrderSupportCategory = "delivery_status" | "merchant_or_items" | "payment" | "refund" | "cancellation" | "safety" | "other";

export type CustomerOrderSupportCase = {
  caseId: string;
  reference: string;
  entityKind: "merchant_order" | "parcel_delivery";
  entityId: string;
  category: CustomerOrderSupportCategory;
  message: string;
  status: "open" | "in_review" | "resolved" | "closed";
  resolution?: string;
  resolvedAt?: string;
  createdAt: string;
  updatedAt: string;
};

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
  deliveryAddress?: MerchantOrderAddressSnapshot;
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
  store?: { name: string; phoneNumber: string; pickup: AddressedOrderLocation };
  courier?: CustomerCourierSnapshot;
  timeline?: MerchantOrderTimeline;
  handoffCode: { purpose: "pickup" | "delivery"; code: string; expiresAt: string } | null;
  refundDecision: {
    eligibility: string;
    decisionStatus: string;
    itemRefund: { paise: number } | null;
    deliveryFeeRefund: { paise: number } | null;
    reason: string;
  } | null;
  customerActions?: CustomerOrderActions;
  supportCases?: CustomerOrderSupportCase[];
  createdAt: string;
  updatedAt: string;
};

export type MerchantOrderPaymentState = MerchantOrderSnapshot["paymentState"];

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

export async function getCustomerOrderDetail(
  input: AuthenticatedInput & { orderId: string },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantOrder(await call(input, {
    operation: "customerDetail",
    orderId: input.orderId,
  }, undefined, fetcher));
}

export async function createMerchantOrderSupport(
  input: AuthenticatedInput & { orderId: string; category: CustomerOrderSupportCategory; message: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, {
    operation: "customerSupport",
    orderId: input.orderId,
    category: input.category,
    message: input.message,
  }, input.idempotencyKey, fetcher));
  if (!payload) invalid();
  return parseCustomerOrderSupportCase(payload.supportCase);
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
    deliveryAddress: addressSnapshot(source.deliveryAddress),
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
    deliveryAddress: addressSnapshot(source.deliveryAddress),
    store: storeSnapshot(source.store),
    courier: courierSnapshot(source.courier),
    timeline: orderTimeline(source.timeline),
    stateVersion,
    handoffCode: handoffCode(source.handoffCode),
    refundDecision: refundDecision(source.refundDecision),
    customerActions: customerActions(source.customerActions),
    supportCases: supportCases(source.supportCases),
    createdAt: timestamp(source.createdAt),
    updatedAt: timestamp(source.updatedAt),
  };
}

function customerActions(value: unknown): CustomerOrderActions | undefined {
  if (value === null || value === undefined) return undefined;
  const source = record(value);
  const cancellationMode = source?.cancellationMode;
  if (!source || !["cancel", "request_review", "pending_review", "none"].includes(String(cancellationMode))) invalid();
  const fields = ["canPay", "canTrack", "canContactStore", "canContactCourier", "canRequestSupport"] as const;
  if (fields.some((field) => typeof source[field] !== "boolean")) invalid();
  return {
    canPay: source.canPay as boolean,
    cancellationMode: cancellationMode as CustomerOrderActions["cancellationMode"],
    canTrack: source.canTrack as boolean,
    canContactStore: source.canContactStore as boolean,
    canContactCourier: source.canContactCourier as boolean,
    canRequestSupport: source.canRequestSupport as boolean,
  };
}

function supportCases(value: unknown): CustomerOrderSupportCase[] | undefined {
  if (value === null || value === undefined) return undefined;
  if (!Array.isArray(value)) invalid();
  return value.map(parseCustomerOrderSupportCase);
}

export function parseCustomerOrderSupportCase(value: unknown): CustomerOrderSupportCase {
  const source = record(value);
  const entityKind = source?.entityKind;
  const category = source?.category;
  const status = source?.status;
  if (!source || !["merchant_order", "parcel_delivery"].includes(String(entityKind)) ||
    !["delivery_status", "merchant_or_items", "payment", "refund", "cancellation", "safety", "other"].includes(String(category)) ||
    !["open", "in_review", "resolved", "closed"].includes(String(status))) invalid();
  return {
    caseId: requiredUUID(source.caseId),
    reference: requiredText(source.reference, 40),
    entityKind: entityKind as CustomerOrderSupportCase["entityKind"],
    entityId: requiredUUID(source.entityId),
    category: category as CustomerOrderSupportCategory,
    message: requiredText(source.message, 1000),
    status: status as CustomerOrderSupportCase["status"],
    resolution: optionalText(source.resolution, 1000),
    resolvedAt: optionalTimestamp(source.resolvedAt),
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

function addressedLocation(value: unknown): AddressedOrderLocation {
  return { ...location(value), address: requiredText(record(value)?.address, 300) };
}

function nullableText(value: unknown, maximum: number) {
  return value === null || value === undefined ? null : requiredText(value, maximum);
}

function addressSnapshot(value: unknown): MerchantOrderAddressSnapshot | undefined {
  if (value === undefined || value === null) return undefined;
  const source = record(value);
  if (!source) invalid();
  return {
    label: nullableText(source.label, 40),
    address: nullableText(source.address, 300),
    details: nullableText(source.details, 300),
    displayAddress: nullableText(source.displayAddress, 620),
  };
}

function storeSnapshot(value: unknown): MerchantOrderSnapshot["store"] {
  if (value === undefined || value === null) return undefined;
  const source = record(value);
  if (!source) invalid();
  return {
    name: requiredText(source.name, 160),
    phoneNumber: phone(source.phoneNumber),
    pickup: addressedLocation(source.pickup),
  };
}

function courierSnapshot(value: unknown): CustomerCourierSnapshot | undefined {
  if (value === undefined || value === null) return undefined;
  const source = record(value);
  const deliveryMethod = source?.deliveryMethod;
  if (!source || typeof deliveryMethod !== "string" || !deliveryMethods.has(deliveryMethod)) invalid();
  return {
    displayName: requiredText(source.displayName, 100),
    phoneNumber: phone(source.phoneNumber),
    deliveryMethod: deliveryMethod as CustomerCourierSnapshot["deliveryMethod"],
    location: source.location === null || source.location === undefined ? null : location(source.location),
    lastSeenAt: source.lastSeenAt === null || source.lastSeenAt === undefined ? null : timestamp(source.lastSeenAt),
  };
}

function orderTimeline(value: unknown): MerchantOrderTimeline | undefined {
  if (value === undefined || value === null) return undefined;
  const source = record(value);
  if (!source) invalid();
  return {
    createdAt: timestamp(source.createdAt),
    acceptedAt: optionalTimestamp(source.acceptedAt),
    readyAt: optionalTimestamp(source.readyAt),
    assignedAt: optionalTimestamp(source.assignedAt),
    enRouteToPickupAt: optionalTimestamp(source.enRouteToPickupAt),
    atStoreAt: optionalTimestamp(source.atStoreAt),
    pickedUpAt: optionalTimestamp(source.pickedUpAt),
    inTransitAt: optionalTimestamp(source.inTransitAt),
    deliveredAt: optionalTimestamp(source.deliveredAt),
    cancelledAt: optionalTimestamp(source.cancelledAt),
  };
}

function optionalTimestamp(value: unknown) {
  return value === null || value === undefined ? undefined : timestamp(value);
}

function phone(value: unknown) {
  const result = requiredText(value, 16);
  if (!/^\+[1-9][0-9]{7,14}$/.test(result)) invalid();
  return result;
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
const deliveryMethods = new Set(["walking", "bicycle", "retired", "bike", "auto"]);
