import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type DeliveryMethod =
  | "walking"
  | "bicycle"
  | "motorbike"
  | "scooter"
  | "auto"
  | "goods_vehicle";
export type DeliveryPartnerApplicationStatus = "pending" | "approved" | "rejected";

export type DeliveryPartnerApplication = {
  applicationId: string;
  accountId: string;
  displayName: string;
  phoneNumber: string;
  deliveryMethod: DeliveryMethod;
  identityEvidenceObjectPath: string;
  vehicleRegistrationNumber: string | null;
  vehicleMakeModel: string | null;
  vehicleEvidenceObjectPath: string | null;
  status: DeliveryPartnerApplicationStatus;
  submittedAt: string;
};

type RpcResult = { responseBody: unknown; responseStatus: number };

export type SubmitDeliveryPartnerApplicationInput = {
  accountId: string;
  deliveryMethod: DeliveryMethod;
  identityEvidenceObjectPath: string;
  vehicleRegistrationNumber: string | null;
  vehicleMakeModel: string | null;
  vehicleEvidenceObjectPath: string | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type ReviewDeliveryPartnerApplicationInput = {
  ownerId: string;
  applicationId: string;
  decision: "approve" | "reject";
  reason: string | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type SetDeliveryPartnerAvailabilityInput = {
  accountId: string;
  online: boolean;
  latitude: number | null;
  longitude: number | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type PublishDeliveryPartnerLocationInput = {
  accountId: string;
  latitude: number;
  longitude: number;
  idempotencyKey: string;
  requestDigest: string;
};

export type DeliveryPartnerDependencies = {
  authenticateBearer: AuthenticateBearer;
  isActiveOwner: (accountId: string) => Promise<boolean>;
  submitApplication: (input: SubmitDeliveryPartnerApplicationInput) => Promise<RpcResult>;
  getSelfSnapshot: (accountId: string) => Promise<RpcResult>;
  listPendingApplications: (ownerId: string) => Promise<DeliveryPartnerApplication[]>;
  reviewApplication: (input: ReviewDeliveryPartnerApplicationInput) => Promise<RpcResult>;
  setAvailability: (input: SetDeliveryPartnerAvailabilityInput) => Promise<RpcResult>;
  publishLocation: (input: PublishDeliveryPartnerLocationInput) => Promise<RpcResult>;
};

const deliveryMethods = new Set<DeliveryMethod>([
  "walking",
  "bicycle",
  "motorbike",
  "scooter",
  "auto",
  "goods_vehicle",
]);
const motorVehicleMethods = new Set<DeliveryMethod>([
  "motorbike",
  "scooter",
  "auto",
  "goods_vehicle",
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleDeliveryPartners(
  request: Request,
  dependencies: DeliveryPartnerDependencies,
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
      case "submit":
        return await submit(request, body, actor.accountId, dependencies);
      case "selfSnapshot": {
        const result = await dependencies.getSelfSnapshot(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "listPending":
        return await listPending(actor.accountId, dependencies);
      case "review":
        return await review(request, body, actor.accountId, dependencies);
      case "setAvailability":
        return await setAvailability(request, body, actor.accountId, dependencies);
      case "publishLocation":
        return await publishLocation(request, body, actor.accountId, dependencies);
      default:
        return validationError();
    }
  } catch {
    return internalError();
  }
}

async function publishLocation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: DeliveryPartnerDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const location = parseLocation(body.location);
  if (!idempotencyKey || !location) return validationError();

  const result = await dependencies.publishLocation({
    accountId,
    ...location,
    idempotencyKey,
    requestDigest: await canonicalDigest(location),
  });
  return json(result.responseBody, result.responseStatus);
}

async function submit(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: DeliveryPartnerDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const deliveryMethod = deliveryMethods.has(body.deliveryMethod as DeliveryMethod)
    ? body.deliveryMethod as DeliveryMethod
    : undefined;
  const identityEvidenceObjectPath = typeof body.identityEvidenceObjectPath === "string"
    ? body.identityEvidenceObjectPath
    : "";
  const vehicleRegistrationNumber = normalizeVehicleRegistration(body.vehicleRegistrationNumber);
  const vehicleMakeModel = normalizeRequiredText(body.vehicleMakeModel, 80);
  const vehicleEvidenceObjectPath = typeof body.vehicleEvidenceObjectPath === "string"
    ? body.vehicleEvidenceObjectPath
    : "";
  const requiresVehicle = deliveryMethod ? motorVehicleMethods.has(deliveryMethod) : false;
  if (
    !idempotencyKey || !deliveryMethod ||
    !validEvidencePath(identityEvidenceObjectPath, accountId) ||
    (requiresVehicle && (
      !vehicleRegistrationNumber || !vehicleMakeModel ||
      !validEvidencePath(vehicleEvidenceObjectPath, accountId) ||
      vehicleEvidenceObjectPath === identityEvidenceObjectPath
    )) ||
    (!requiresVehicle && (
      body.vehicleRegistrationNumber !== undefined && body.vehicleRegistrationNumber !== null ||
      body.vehicleMakeModel !== undefined && body.vehicleMakeModel !== null ||
      body.vehicleEvidenceObjectPath !== undefined && body.vehicleEvidenceObjectPath !== null
    ))
  ) {
    return validationError();
  }

  const normalized = {
    deliveryMethod,
    identityEvidenceObjectPath,
    vehicleRegistrationNumber: requiresVehicle ? vehicleRegistrationNumber! : null,
    vehicleMakeModel: requiresVehicle ? vehicleMakeModel! : null,
    vehicleEvidenceObjectPath: requiresVehicle ? vehicleEvidenceObjectPath : null,
  };
  const result = await dependencies.submitApplication({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function listPending(
  ownerId: string,
  dependencies: DeliveryPartnerDependencies,
) {
  if (!await dependencies.isActiveOwner(ownerId)) return accessDenied();
  return json({ applications: await dependencies.listPendingApplications(ownerId) });
}

async function review(
  request: Request,
  body: Record<string, unknown>,
  ownerId: string,
  dependencies: DeliveryPartnerDependencies,
) {
  if (!await dependencies.isActiveOwner(ownerId)) return accessDenied();

  const idempotencyKey = requiredIdempotencyKey(request);
  const applicationId = validUUID(body.applicationId);
  const decision: "approve" | "reject" | undefined =
    body.decision === "approve" || body.decision === "reject" ? body.decision : undefined;
  const reason = body.reason === null || body.reason === undefined
    ? null
    : normalizeRequiredText(body.reason, 500);
  if (
    !idempotencyKey || !applicationId || !decision ||
    (body.reason !== null && body.reason !== undefined && !reason) ||
    (decision === "reject" && !reason)
  ) {
    return validationError();
  }

  const normalized = { applicationId, decision, reason: reason ?? null };
  const result = await dependencies.reviewApplication({
    ownerId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function setAvailability(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: DeliveryPartnerDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  if (!idempotencyKey || typeof body.online !== "boolean") return validationError();

  const location = body.online ? parseLocation(body.location) : undefined;
  if (
    (body.online && !location) ||
    (!body.online && body.location !== undefined && body.location !== null)
  ) {
    return validationError();
  }

  const normalized = {
    online: body.online,
    latitude: location?.latitude ?? null,
    longitude: location?.longitude ?? null,
  };
  const result = await dependencies.setAvailability({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
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

function validEvidencePath(path: string, accountId: string) {
  const segments = path.split("/");
  return segments.length === 3 && segments[0] === "dastak-partner" &&
    segments[1] === accountId && segments[2].length > 0;
}

function validUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : undefined;
}

function normalizeRequiredText(value: unknown, maximumLength: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximumLength ? normalized : undefined;
}

function normalizeVehicleRegistration(value: unknown) {
  const normalized = normalizeRequiredText(value, 20)?.toUpperCase();
  return normalized && normalized.length >= 4 && /^[A-Z0-9 -]+$/.test(normalized)
    ? normalized
    : undefined;
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
      message: "The delivery partner request is invalid.",
    },
  }, 400);
}

function accessDenied() {
  return json({
    error: {
      code: "access_denied",
      message: "Only an active owner can perform this operation.",
    },
  }, 403);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The delivery partner request could not be processed.",
    },
  }, 500);
}
