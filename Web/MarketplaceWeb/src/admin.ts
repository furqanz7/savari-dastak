import { parseMerchantOrder, type MerchantOrderSnapshot, type MerchantOrderStatus } from "./orders";

export type ReviewDecision = "approve" | "reject";
export type MerchantAdminApplication = {
  applicationId: string;
  accountId: string;
  businessName: string;
  businessAddress: string;
  evidenceObjectPath: string;
  status: "pending" | "approved" | "rejected";
};
export type PartnerAdminApplication = {
  applicationId: string;
  accountId: string;
  displayName: string;
  phoneNumber: string;
  deliveryMethod: "walking" | "bicycle" | "bike" | "auto" | "car";
  identityEvidenceObjectPath: string;
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
    businessName: requiredText(source?.businessName, 120),
    businessAddress: requiredText(source?.businessAddress, 300),
    evidenceObjectPath,
    status,
  };
}

function partnerApplication(value: unknown): PartnerAdminApplication {
  const source = record(value);
  const accountId = requiredUUID(source?.accountId);
  const method = source?.deliveryMethod;
  const evidenceObjectPath = requiredText(source?.identityEvidenceObjectPath, 500);
  if (!["walking", "bicycle", "bike", "auto", "car"].includes(String(method)) ||
    !evidenceObjectPath.startsWith(`dastak-partner/${accountId}/`)) invalid();
  return {
    applicationId: requiredUUID(source?.applicationId),
    accountId,
    displayName: requiredText(source?.displayName, 100),
    phoneNumber: requiredText(source?.phoneNumber, 30),
    deliveryMethod: method as PartnerAdminApplication["deliveryMethod"],
    identityEvidenceObjectPath: evidenceObjectPath,
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

function applicationStatus(value: unknown) {
  if (value !== "pending" && value !== "approved" && value !== "rejected") invalid();
  return value;
}
function money(value: unknown) {
  const paise = record(value)?.paise;
  if (typeof paise !== "number" || !Number.isSafeInteger(paise) || paise < 0) invalid();
  return { paise };
}
function validEvidencePath(value: string) {
  const parts = value.split("/");
  return parts.length === 3 && ["merchant", "dastak-partner"].includes(parts[0]) &&
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
function validationError() {
  return new AdminRequestError("validation_failed", "The admin request is invalid.", 400);
}
function invalid(): never {
  throw new AdminRequestError("invalid_response", "Dastak received an invalid admin response.", 502);
}
