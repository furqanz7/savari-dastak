import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type ParcelRouteInput = {
  deliveryMethod: string;
  pickup: { latitude: number; longitude: number };
  dropoff: { latitude: number; longitude: number };
};

export type ParcelRoute = {
  distanceMeters: number;
  durationSeconds: number;
};

export type ParcelQuoteInput = ParcelRouteInput & {
  accountId: string;
  pickupAddress: string;
  dropoffAddress: string;
  routeDistanceMeters: number;
  routeDurationSeconds: number;
  idempotencyKey: string;
  requestDigest: string;
};

export type ParcelCreateInput = {
  accountId: string;
  quoteId: string;
  recipientPhoneNumber: string;
  recipientName: string;
  declaredContents: string;
  declaredValuePaise: number;
  idempotencyKey: string;
  requestDigest: string;
};

export type ParcelAssignmentMutationInput = {
  accountId: string;
  assignmentId: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type ParcelAssignmentDeclineInput = ParcelAssignmentMutationInput & {
  reason: string | null;
};

export type ParcelLifecycleAction =
  | "start_to_pickup"
  | "confirm_pickup"
  | "start_delivery"
  | "complete_delivery";

export type ParcelLifecycleInput = ParcelAssignmentMutationInput & {
  action: ParcelLifecycleAction;
  verificationCode: string | null;
};

export type ParcelCancellationInput = {
  accountId: string;
  parcelId: string;
  reason: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type ParcelSafetyIncidentInput = {
  accountId: string;
  parcelId: string;
  incidentType: string;
  reportText: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type ParcelCustomerSupportInput = {
  accountId: string;
  parcelId: string;
  category:
    | "delivery_status"
    | "merchant_or_items"
    | "payment"
    | "refund"
    | "cancellation"
    | "safety"
    | "other";
  message: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type ParcelDeliveryDependencies = {
  authenticateBearer: AuthenticateBearer;
  routeParcel: (input: ParcelRouteInput) => Promise<ParcelRoute>;
  quoteParcel: (input: ParcelQuoteInput) => Promise<RpcResult>;
  createParcel: (input: ParcelCreateInput) => Promise<RpcResult>;
  getCustomerSnapshot: (accountId: string) => Promise<RpcResult>;
  getParcelSnapshot: (accountId: string, parcelId: string) => Promise<RpcResult>;
  getPartnerSnapshot: (accountId: string) => Promise<RpcResult>;
  acknowledgeAssignment: (input: ParcelAssignmentMutationInput) => Promise<RpcResult>;
  declineAssignment: (input: ParcelAssignmentDeclineInput) => Promise<RpcResult>;
  advanceParcel: (input: ParcelLifecycleInput) => Promise<RpcResult>;
  cancelParcel: (input: ParcelCancellationInput) => Promise<RpcResult>;
  createCustomerSupport: (input: ParcelCustomerSupportInput) => Promise<RpcResult>;
  reportSafetyIncident: (input: ParcelSafetyIncidentInput) => Promise<RpcResult>;
};

export class ParcelRoutingUnavailableError extends Error {}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const phonePattern = /^\+[1-9][0-9]{7,14}$/;
const deliveryMethods = new Set(["walking", "bicycle", "bike", "auto"]);

export async function handleParcelDeliveries(
  request: Request,
  dependencies: ParcelDeliveryDependencies,
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
  if (!body || typeof body.operation !== "string") return validationError();

  try {
    switch (body.operation) {
      case "quote":
        return await quoteMutation(request, body, actor.accountId, dependencies);
      case "createParcel":
        return await createMutation(request, body, actor.accountId, dependencies.createParcel);
      case "customerSnapshot":
        return rpcResponse(await dependencies.getCustomerSnapshot(actor.accountId));
      case "parcelSnapshot": {
        const parcelId = validUUID(body.parcelId);
        if (!parcelId) return validationError();
        return rpcResponse(await dependencies.getParcelSnapshot(actor.accountId, parcelId));
      }
      case "partnerSnapshot":
        return rpcResponse(await dependencies.getPartnerSnapshot(actor.accountId));
      case "acknowledgeAssignment":
        return await assignmentMutation(
          request,
          body,
          actor.accountId,
          dependencies.acknowledgeAssignment,
        );
      case "declineAssignment":
        return await declineMutation(request, body, actor.accountId, dependencies);
      case "startToPickup":
        return await lifecycleMutation(
          request,
          body,
          actor.accountId,
          "start_to_pickup",
          false,
          dependencies.advanceParcel,
        );
      case "confirmPickup":
        return await lifecycleMutation(
          request,
          body,
          actor.accountId,
          "confirm_pickup",
          true,
          dependencies.advanceParcel,
        );
      case "startDelivery":
        return await lifecycleMutation(
          request,
          body,
          actor.accountId,
          "start_delivery",
          false,
          dependencies.advanceParcel,
        );
      case "completeDelivery":
        return await lifecycleMutation(
          request,
          body,
          actor.accountId,
          "complete_delivery",
          true,
          dependencies.advanceParcel,
        );
      case "cancelParcel":
        return await cancellationMutation(
          request,
          body,
          actor.accountId,
          dependencies.cancelParcel,
        );
      case "customerSupport":
        return await supportMutation(
          request,
          body,
          actor.accountId,
          dependencies.createCustomerSupport,
        );
      case "reportSafetyIncident":
        return await safetyMutation(
          request,
          body,
          actor.accountId,
          dependencies.reportSafetyIncident,
        );
      default:
        return validationError();
    }
  } catch (error) {
    if (error instanceof ParcelRoutingUnavailableError) return routingUnavailable();
    return internalError();
  }
}

async function quoteMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: ParcelDeliveryDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const deliveryMethod = validDeliveryMethod(body.deliveryMethod);
  const pickup = addressedPoint(body.pickup);
  const dropoff = addressedPoint(body.dropoff);
  if (!idempotencyKey || !deliveryMethod || !pickup || !dropoff) return validationError();

  const route = await dependencies.routeParcel({
    deliveryMethod,
    pickup: { latitude: pickup.latitude, longitude: pickup.longitude },
    dropoff: { latitude: dropoff.latitude, longitude: dropoff.longitude },
  });
  if (
    !Number.isInteger(route.distanceMeters) || route.distanceMeters <= 0 ||
    !Number.isInteger(route.durationSeconds) || route.durationSeconds <= 0
  ) {
    throw new ParcelRoutingUnavailableError("Route provider returned invalid data");
  }

  const normalized = {
    deliveryMethod,
    pickup,
    dropoff,
    routeDistanceMeters: route.distanceMeters,
    routeDurationSeconds: route.durationSeconds,
  };
  return rpcResponse(
    await dependencies.quoteParcel({
      accountId,
      deliveryMethod,
      pickup,
      dropoff,
      pickupAddress: pickup.address,
      dropoffAddress: dropoff.address,
      routeDistanceMeters: route.distanceMeters,
      routeDurationSeconds: route.durationSeconds,
      idempotencyKey,
      requestDigest: await canonicalDigest(normalized),
    }),
  );
}

async function createMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: ParcelCreateInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const quoteId = validUUID(body.quoteId);
  const recipientName = normalizedText(body.recipientName, 1, 80);
  const recipientPhoneNumber = typeof body.recipientPhoneNumber === "string" &&
      phonePattern.test(body.recipientPhoneNumber)
    ? body.recipientPhoneNumber
    : undefined;
  const declaredContents = normalizedText(body.declaredContents, 1, 300);
  const declaredValuePaise = validInteger(body.declaredValuePaise, 0, 100_000_000);
  if (
    !idempotencyKey || !quoteId || !recipientName || !recipientPhoneNumber ||
    !declaredContents || declaredValuePaise === undefined
  ) {
    return validationError();
  }

  const normalized = {
    quoteId,
    recipientName,
    recipientPhoneNumber,
    declaredContents,
    declaredValuePaise,
  };
  return rpcResponse(
    await dependency({
      accountId,
      ...normalized,
      idempotencyKey,
      requestDigest: await canonicalDigest(normalized),
    }),
  );
}

async function assignmentMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: ParcelAssignmentMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  if (!idempotencyKey || !assignmentId) return validationError();

  return rpcResponse(
    await dependency({
      accountId,
      assignmentId,
      idempotencyKey,
      requestDigest: await canonicalDigest({ assignmentId }),
    }),
  );
}

async function declineMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: ParcelDeliveryDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  const reason = optionalText(body.reason, 300);
  if (!idempotencyKey || !assignmentId || reason === undefined) return validationError();
  return rpcResponse(
    await dependencies.declineAssignment({
      accountId,
      assignmentId,
      reason,
      idempotencyKey,
      requestDigest: await canonicalDigest({ assignmentId, reason }),
    }),
  );
}

async function lifecycleMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  action: ParcelLifecycleAction,
  verificationRequired: boolean,
  dependency: (input: ParcelLifecycleInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  const verificationCode = verificationRequired
    ? validVerificationCode(body.verificationCode)
    : null;
  if (!idempotencyKey || !assignmentId || (verificationRequired && !verificationCode)) {
    return validationError();
  }
  const normalized = verificationRequired
    ? { assignmentId, action, verificationCode }
    : { assignmentId, action };
  return rpcResponse(
    await dependency({
      accountId,
      assignmentId,
      action,
      verificationCode,
      idempotencyKey,
      requestDigest: await canonicalDigest(normalized),
    }),
  );
}

async function cancellationMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: ParcelCancellationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const parcelId = validUUID(body.parcelId);
  const reason = normalizedText(body.reason, 1, 300);
  if (!idempotencyKey || !parcelId || !reason) return validationError();
  const normalized = { parcelId, reason };
  return rpcResponse(
    await dependency({
      accountId,
      parcelId,
      reason,
      idempotencyKey,
      requestDigest: await canonicalDigest(normalized),
    }),
  );
}

async function safetyMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: ParcelSafetyIncidentInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const parcelId = validUUID(body.parcelId);
  const incidentType = normalizedText(body.incidentType, 1, 80);
  const reportText = normalizedText(body.reportText, 1, 1000);
  if (!idempotencyKey || !parcelId || !incidentType || !reportText) return validationError();
  const normalized = { parcelId, incidentType, reportText };
  return rpcResponse(
    await dependency({
      accountId,
      parcelId,
      incidentType,
      reportText,
      idempotencyKey,
      requestDigest: await canonicalDigest(normalized),
    }),
  );
}

async function supportMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: ParcelCustomerSupportInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const parcelId = validUUID(body.parcelId);
  const category = validSupportCategory(body.category);
  const message = normalizedText(body.message, 10, 1000);
  if (!idempotencyKey || !parcelId || !category || !message) return validationError();
  const normalized = { parcelId, category, message };
  return rpcResponse(
    await dependency({
      accountId,
      ...normalized,
      idempotencyKey,
      requestDigest: await canonicalDigest(normalized),
    }),
  );
}

function rpcResponse(result: RpcResult) {
  return json(result.responseBody, result.responseStatus);
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    return record(await request.json());
  } catch {
    return undefined;
  }
}

function addressedPoint(value: unknown) {
  const point = record(value);
  if (!point) return undefined;
  const latitude = validNumber(point.latitude, -90, 90);
  const longitude = validNumber(point.longitude, -180, 180);
  const address = normalizedText(point.address, 1, 300);
  return latitude === undefined || longitude === undefined || !address
    ? undefined
    : { latitude, longitude, address };
}

function validDeliveryMethod(value: unknown) {
  return typeof value === "string" && deliveryMethods.has(value) ? value : undefined;
}

function validUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : undefined;
}

function validSupportCategory(value: unknown): ParcelCustomerSupportInput["category"] | undefined {
  return typeof value === "string" && [
      "delivery_status",
      "merchant_or_items",
      "payment",
      "refund",
      "cancellation",
      "safety",
      "other",
    ].includes(value)
    ? value as ParcelCustomerSupportInput["category"]
    : undefined;
}

function validVerificationCode(value: unknown) {
  return typeof value === "string" && /^[0-9]{6}$/.test(value) ? value : null;
}

function validInteger(value: unknown, minimum: number, maximum: number) {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum &&
      value <= maximum
    ? value
    : undefined;
}

function validNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : undefined;
}

function normalizedText(value: unknown, minimumLength: number, maximumLength: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= minimumLength && normalized.length <= maximumLength
    ? normalized
    : undefined;
}

function optionalText(value: unknown, maximumLength: number) {
  if (value === null || value === undefined) return null;
  return normalizedText(value, 1, maximumLength);
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
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "The parcel delivery request is invalid." },
  }, 400);
}

function routingUnavailable() {
  return json({
    error: { code: "routing_unavailable", message: "A delivery route is not available right now." },
  }, 503);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The parcel delivery request could not be completed.",
    },
  }, 500);
}
