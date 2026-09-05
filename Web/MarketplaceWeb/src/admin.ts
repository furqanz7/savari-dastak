import {
  parseCustomerOrderSupportCase,
  parseMerchantOrder,
  type CustomerOrderSupportCase,
  type MerchantOrderSnapshot,
  type MerchantOrderStatus,
} from "./orders";
import { parseParcel, type ParcelDelivery } from "./parcels";

export type ReviewDecision = "approve" | "reject";
export type MerchantAdminApplication = {
  applicationId: string;
  accountId: string;
  applicantName: string;
  applicantPhone: string;
  merchantType: "RETAIL" | "RESTAURANT_CAFE";
  legalName: string;
  businessName: string;
  businessAddress: string;
  latitude: number;
  longitude: number;
  serviceZoneId: string;
  serviceZoneName: string;
  evidenceObjectPath: string;
  status: "pending" | "approved" | "rejected";
  submittedAt: string;
};
export type PartnerAdminApplication = {
  applicationId: string;
  accountId: string;
  displayName: string;
  phoneNumber: string;
  deliveryMethod: "walking" | "bicycle" | "motorbike" | "scooter" | "auto" | "goods_vehicle";
  identityEvidenceObjectPath: string;
  vehicleRegistrationNumber: string | null;
  vehicleMakeModel: string | null;
  vehicleEvidenceObjectPath: string | null;
  status: "pending" | "approved" | "rejected";
  submittedAt: string;
};
export type AdminOrder = {
  orderId: string;
  store: { storeId: string; name: string };
  status: MerchantOrderStatus;
  paymentState: "payment_pending" | "paid" | "not_collected" | "refund_pending" | "refunded";
  itemSubtotal: { paise: number };
  deliveryFee: { paise: number };
  total: { paise: number };
  itemCount: number;
  assignmentStatus: "offered" | "accepted" | "declined" | "expired" | "cancelled" | "completed" | null;
  controlledScope: "general" | "medicine" | "tobacco";
  refundDecision: {
    eligibility: "no_payment" | "full_refund" | "owner_review_required" |
      "merchant_fault_full_refund" | "delivery_fee_retained_unless_fault";
    decisionStatus: "not_required" | "eligible" | "review_required" | "denied";
    orderStatus: MerchantOrderStatus;
    reason: string;
  } | null;
  createdAt: string;
  updatedAt: string;
};
export type OwnerOperationsSummary = {
  openSupport: number;
  refundReviews: number;
  lockedHandoffs: number;
  stalledOrders: number;
  totalExceptions: number;
};
export type OwnerOrderException = {
  exceptionId: string;
  kind: "support" | "refund_review" | "handoff_locked" | "stalled_order";
  severity: "critical" | "attention";
  entityKind: "merchant_order" | "parcel_delivery";
  entityId: string;
  title: string;
  detail: string;
  status: string;
  purpose: "pickup" | "delivery" | null;
  occurredAt: string;
};
export type OwnerOperationsSnapshot = {
  summary: OwnerOperationsSummary;
  exceptions: OwnerOrderException[];
  parcels: ParcelDelivery[];
};
export type OwnerReconciliationResult = {
  merchantOrdersRecovered: number;
  parcelsRecovered: number;
  merchantOffersCreated: number;
  parcelOffersCreated: number;
  reconciledAt: string;
};

type AuthenticatedInput = { supabaseUrl: string; publishableKey: string; accessToken: string };
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class AdminRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "AdminRequestError";
  }
}

export async function getMerchantApplications(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  const source = record(await call("merchant-applications", input, { operation: "list" }, undefined, fetcher));
  if (!source || !Array.isArray(source.applications) || source.applications.length > 500) invalid();
  return source.applications.map(merchantApplication);
}

export async function getPartnerApplications(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  const source = record(await call("delivery-partners", input, { operation: "listPending" }, undefined, fetcher));
  if (!source || !Array.isArray(source.applications) || source.applications.length > 500) invalid();
  return source.applications.map(partnerApplication);
}

export async function reviewMerchantApplication(
  input: AuthenticatedInput & { applicationId: string; decision: ReviewDecision; reason?: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return review("merchant-applications", input, fetcher);
}

export async function reviewPartnerApplication(
  input: AuthenticatedInput & { applicationId: string; decision: ReviewDecision; reason?: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return review("delivery-partners", input, fetcher);
}

export async function getAdminOrders(input: AuthenticatedInput & { limit?: number }, fetcher: Fetcher = fetch) {
  const limit = input.limit ?? 50;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw validationError();
  const source = record(await call("merchant-orders", input, { operation: "ownerSnapshot", limit }, undefined, fetcher));
  if (!source || !Array.isArray(source.orders) || source.orders.length > limit) invalid();
  return source.orders.map(adminOrder);
}

export async function getOwnerOperations(input: AuthenticatedInput & { limit?: number }, fetcher: Fetcher = fetch) {
  const limit = input.limit ?? 50;
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw validationError();
  return ownerOperations(await call("merchant-orders", input, { operation: "ownerOperations", limit }, undefined, fetcher), limit);
}

export async function resolveOwnerSupportCase(
  input: AuthenticatedInput & { caseId: string; resolution: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
): Promise<CustomerOrderSupportCase> {
  const resolution = input.resolution.trim().replace(/\s+/g, " ");
  if (resolution.length < 5 || resolution.length > 500) throw validationError();
  return parseCustomerOrderSupportCase(await call("merchant-orders", input, {
    operation: "ownerResolveSupport",
    caseId: requiredUUID(input.caseId),
    resolution,
  }, input.idempotencyKey, fetcher));
}

export async function resetOwnerHandoff(
  input: AuthenticatedInput & {
    entityKind: "merchant_order" | "parcel_delivery";
    entityId: string;
    purpose: "pickup" | "delivery";
    reason: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
): Promise<MerchantOrderSnapshot | ParcelDelivery> {
  const reason = input.reason.trim().replace(/\s+/g, " ");
  if (reason.length < 5 || reason.length > 300) throw validationError();
  const body = input.entityKind === "merchant_order"
    ? { operation: "ownerResetHandoff", orderId: requiredUUID(input.entityId), purpose: input.purpose, reason }
    : { operation: "ownerResetParcelHandoff", parcelId: requiredUUID(input.entityId), purpose: input.purpose, reason };
  const payload = await call("merchant-orders", input, body, input.idempotencyKey, fetcher);
  return input.entityKind === "merchant_order" ? parseMerchantOrder(payload) : parseParcel(payload);
}

export async function reconcileOwnerOrders(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
): Promise<OwnerReconciliationResult> {
  return reconciliation(await call("merchant-orders", input, { operation: "ownerReconcile" }, undefined, fetcher));
}

export async function reviewOrderRefund(
  input: AuthenticatedInput & {
    orderId: string;
    outcome: "approve_full" | "approve_items_only" | "deny";
    faultSource: "merchant" | "dastak" | null;
    reason: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
): Promise<MerchantOrderSnapshot> {
  const orderId = requiredUUID(input.orderId);
  const reason = input.reason.trim().replace(/\s+/g, " ");
  if (!reason || reason.length > 300 ||
    !["approve_full", "approve_items_only", "deny"].includes(input.outcome) ||
    ![null, "merchant", "dastak"].includes(input.faultSource)) throw validationError();
  return parseMerchantOrder(await call("merchant-orders", input, {
    operation: "ownerReviewRefund",
    orderId,
    outcome: input.outcome,
    faultSource: input.faultSource,
    reason,
  }, input.idempotencyKey, fetcher));
}

export async function getEvidenceUrl(
  input: AuthenticatedInput & { objectPath: string },
  fetcher: Fetcher = fetch,
) {
  if (!validEvidencePath(input.objectPath)) throw validationError();
  const source = record(await call("issue-evidence-url", input, {
    operation: "download",
    bucket: "dastak-evidence",
    objectPath: input.objectPath,
  }, undefined, fetcher));
  const signedUrl = requiredText(source?.signedUrl, 2_000);
  let parsed: URL;
  try {
    parsed = new URL(signedUrl);
  } catch {
    invalid();
  }
  if (parsed.protocol !== "https:") invalid();
  return signedUrl;
}

async function review(
  service: "merchant-applications" | "delivery-partners",
  input: AuthenticatedInput & { applicationId: string; decision: ReviewDecision; reason?: string; idempotencyKey: string },
  fetcher: Fetcher,
) {
  const applicationId = requiredUUID(input.applicationId);
  const reason = input.reason?.trim().replace(/\s+/g, " ") || null;
  if ((input.decision !== "approve" && input.decision !== "reject") ||
    (input.decision === "reject" && !reason) || (reason && reason.length > 500)) throw validationError();
  return await call(service, input, {
    operation: "review",
    applicationId,
    decision: input.decision,
    reason,
  }, input.idempotencyKey, fetcher);
}

async function call(
  service: "merchant-applications" | "delivery-partners" | "merchant-orders" | "issue-evidence-url",
  auth: AuthenticatedInput,
  body: unknown,
  idempotencyKey: string | undefined,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/${service}`, {
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
    throw new AdminRequestError("network_error", "Dastak Admin could not reach the server.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new AdminRequestError(
      optionalText(error?.code, 80) ?? "admin_request_failed",
      optionalText(error?.message, 300) ?? "The admin request could not be completed.",
      response.status,
    );
  }
  return payload;
}

function merchantApplication(value: unknown): MerchantAdminApplication {
  const source = record(value);
  const accountId = requiredUUID(source?.accountId);
  const status = applicationStatus(source?.status);
  const evidenceObjectPath = requiredText(source?.evidenceObjectPath, 500);
  if (!evidenceObjectPath.startsWith(`merchant/${accountId}/`)) invalid();
  return {
    applicationId: requiredUUID(source?.applicationId),
    accountId,
    applicantName: requiredText(source?.applicantName, 100),
    applicantPhone: requiredText(source?.applicantPhone, 30),
    merchantType: merchantType(source?.merchantType),
    legalName: requiredText(source?.legalName, 160),
    businessName: requiredText(source?.businessName, 120),
    businessAddress: requiredText(source?.businessAddress, 300),
    latitude: coordinate(source?.latitude, -90, 90),
    longitude: coordinate(source?.longitude, -180, 180),
    serviceZoneId: requiredUUID(source?.serviceZoneId),
    serviceZoneName: requiredText(source?.serviceZoneName, 160),
    evidenceObjectPath,
    status,
    submittedAt: timestamp(source?.submittedAt),
  };
}

function partnerApplication(value: unknown): PartnerAdminApplication {
  const source = record(value);
  const accountId = requiredUUID(source?.accountId);
  const method = source?.deliveryMethod;
  const evidenceObjectPath = requiredText(source?.identityEvidenceObjectPath, 500);
  const vehicleRegistrationNumber = nullableText(source?.vehicleRegistrationNumber, 20);
  const vehicleMakeModel = nullableText(source?.vehicleMakeModel, 80);
  const vehicleEvidenceObjectPath = nullableText(source?.vehicleEvidenceObjectPath, 500);
  const normalizedMethod = method === "bike" ? "motorbike" : method === "car" ? "goods_vehicle" : method;
  const motorVehicle = ["motorbike", "scooter", "auto", "goods_vehicle"].includes(String(normalizedMethod));
  if (!["walking", "bicycle", "motorbike", "scooter", "auto", "goods_vehicle"].includes(String(normalizedMethod)) ||
    !evidenceObjectPath.startsWith(`dastak-partner/${accountId}/`) ||
    (motorVehicle && (
      !vehicleRegistrationNumber || !vehicleMakeModel || !vehicleEvidenceObjectPath ||
      vehicleEvidenceObjectPath === evidenceObjectPath ||
      !vehicleEvidenceObjectPath.startsWith(`dastak-partner/${accountId}/`)
    )) ||
    (!motorVehicle && (vehicleRegistrationNumber || vehicleMakeModel || vehicleEvidenceObjectPath))) invalid();
  return {
    applicationId: requiredUUID(source?.applicationId),
    accountId,
    displayName: requiredText(source?.displayName, 100),
    phoneNumber: requiredText(source?.phoneNumber, 30),
    deliveryMethod: normalizedMethod as PartnerAdminApplication["deliveryMethod"],
    identityEvidenceObjectPath: evidenceObjectPath,
    vehicleRegistrationNumber,
    vehicleMakeModel,
    vehicleEvidenceObjectPath,
    status: applicationStatus(source?.status),
    submittedAt: timestamp(source?.submittedAt),
  };
}

function adminOrder(value: unknown): AdminOrder {
  const source = record(value);
  const store = record(source?.store);
  const status = source?.status;
  const paymentState = source?.paymentState;
  const assignmentStatus = source?.assignmentStatus;
  const controlledScope = source?.controlledScope;
  const itemCount = source?.itemCount;
  if (!source || !store || !orderStatuses.has(status as MerchantOrderStatus) ||
    !paymentStates.has(String(paymentState)) ||
    !(assignmentStatus === null || assignmentStatuses.has(String(assignmentStatus))) ||
    !controlledScopes.has(String(controlledScope)) || typeof itemCount !== "number" ||
    !Number.isSafeInteger(itemCount) || itemCount < 0) invalid();
  return {
    orderId: requiredUUID(source.orderId),
    store: { storeId: requiredUUID(store.storeId), name: requiredText(store.name, 120) },
    status: status as MerchantOrderStatus,
    paymentState: paymentState as AdminOrder["paymentState"],
    itemSubtotal: money(source.itemSubtotal),
    deliveryFee: money(source.deliveryFee),
    total: money(source.total),
    itemCount,
    assignmentStatus: assignmentStatus as AdminOrder["assignmentStatus"],
    controlledScope: controlledScope as AdminOrder["controlledScope"],
    refundDecision: adminRefundDecision(source.refundDecision),
    createdAt: timestamp(source.createdAt),
    updatedAt: timestamp(source.updatedAt),
  };
}

function adminRefundDecision(value: unknown): AdminOrder["refundDecision"] {
  if (value === null || value === undefined) return null;
  const source = record(value);
  const eligibility = source?.eligibility;
  const decisionStatus = source?.decisionStatus;
  const orderStatus = source?.orderStatus;
  if (!source || !refundEligibilities.has(String(eligibility)) ||
    !refundDecisionStatuses.has(String(decisionStatus)) ||
    !orderStatuses.has(orderStatus as MerchantOrderStatus)) invalid();
  return {
    eligibility: eligibility as NonNullable<AdminOrder["refundDecision"]>["eligibility"],
    decisionStatus: decisionStatus as NonNullable<AdminOrder["refundDecision"]>["decisionStatus"],
    orderStatus: orderStatus as MerchantOrderStatus,
    reason: requiredText(source.reason, 300),
  };
}

function ownerOperations(value: unknown, limit: number): OwnerOperationsSnapshot {
  const source = record(value);
  const summary = record(source?.summary);
  if (!source || !summary || !Array.isArray(source.exceptions) || source.exceptions.length > limit ||
    !Array.isArray(source.parcels) || source.parcels.length > limit) invalid();
  return {
    summary: {
      openSupport: count(summary.openSupport),
      refundReviews: count(summary.refundReviews),
      lockedHandoffs: count(summary.lockedHandoffs),
      stalledOrders: count(summary.stalledOrders),
      totalExceptions: count(summary.totalExceptions),
    },
    exceptions: source.exceptions.map(ownerException),
    parcels: source.parcels.map(parseParcel),
  };
}

function ownerException(value: unknown): OwnerOrderException {
  const source = record(value);
  const kind = source?.kind;
  const severity = source?.severity;
  const entityKind = source?.entityKind;
  const purpose = source?.purpose;
  if (!source || !ownerExceptionKinds.has(String(kind)) || !ownerSeverities.has(String(severity)) ||
    !ownerEntityKinds.has(String(entityKind)) || !(purpose === null || purpose === undefined || purpose === "pickup" || purpose === "delivery")) invalid();
  return {
    exceptionId: requiredText(source.exceptionId, 200),
    kind: kind as OwnerOrderException["kind"],
    severity: severity as OwnerOrderException["severity"],
    entityKind: entityKind as OwnerOrderException["entityKind"],
    entityId: requiredUUID(source.entityId),
    title: requiredText(source.title, 160),
    detail: requiredText(source.detail, 500),
    status: requiredText(source.status, 80),
    purpose: (purpose ?? null) as OwnerOrderException["purpose"],
    occurredAt: timestamp(source.occurredAt),
  };
}

function reconciliation(value: unknown): OwnerReconciliationResult {
  const source = record(value);
  if (!source) invalid();
  return {
    merchantOrdersRecovered: count(source.merchantOrdersRecovered),
    parcelsRecovered: count(source.parcelsRecovered),
    merchantOffersCreated: count(source.merchantOffersCreated),
    parcelOffersCreated: count(source.parcelOffersCreated),
    reconciledAt: timestamp(source.reconciledAt),
  };
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const orderStatuses = new Set<MerchantOrderStatus>([
  "payment_pending", "paid", "merchant_accepted", "ready", "assigned", "en_route_to_pickup",
  "at_store", "picked_up", "in_transit", "delivered", "cancelled", "returning_to_merchant",
]);
const paymentStates = new Set(["payment_pending", "paid", "not_collected", "refund_pending", "refunded"]);
const assignmentStatuses = new Set(["offered", "accepted", "declined", "expired", "cancelled", "completed"]);
const controlledScopes = new Set(["general", "medicine", "tobacco"]);
const refundEligibilities = new Set([
  "no_payment", "full_refund", "owner_review_required",
  "merchant_fault_full_refund", "delivery_fee_retained_unless_fault",
]);
const refundDecisionStatuses = new Set(["not_required", "eligible", "review_required", "denied"]);
const ownerExceptionKinds = new Set(["support", "refund_review", "handoff_locked", "stalled_order"]);
const ownerSeverities = new Set(["critical", "attention"]);
const ownerEntityKinds = new Set(["merchant_order", "parcel_delivery"]);

function applicationStatus(value: unknown) {
  if (value !== "pending" && value !== "approved" && value !== "rejected") invalid();
  return value;
}
function merchantType(value: unknown): MerchantAdminApplication["merchantType"] {
  if (value !== "RETAIL" && value !== "RESTAURANT_CAFE") invalid();
  return value;
}
function coordinate(value: unknown, minimum: number, maximum: number) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) invalid();
  return value;
}
function money(value: unknown) {
  const paise = record(value)?.paise;
  if (typeof paise !== "number" || !Number.isSafeInteger(paise) || paise < 0) invalid();
  return { paise };
}
function count(value: unknown) {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) invalid();
  return value;
}
function validEvidencePath(value: string) {
  const parts = value.split("/");
  return parts.length === 3 && ["merchant", "merchant-ready", "dastak-partner", "rider-delivery"].includes(parts[0]) &&
    uuidPattern.test(parts[1]) && parts[2].length > 0;
}
function requiredUUID(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}
function timestamp(value: unknown) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) invalid();
  return value;
}
function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}
function requiredText(value: unknown, maximum: number) {
  const text = optionalText(value, maximum);
  if (!text) invalid();
  return text;
}
function nullableText(value: unknown, maximum: number) {
  return value === null || value === undefined ? null : requiredText(value, maximum);
}
function validationError() {
  return new AdminRequestError("validation_failed", "The admin request is invalid.", 400);
}
function invalid(): never {
  throw new AdminRequestError("invalid_response", "Dastak received an invalid admin response.", 502);
}
