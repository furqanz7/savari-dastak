import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type MerchantApplicationStatus = "pending" | "approved" | "rejected";
export type MerchantType = "RETAIL" | "RESTAURANT_CAFE";

export type MerchantApplication = {
  applicationId: string;
  accountId: string;
  applicantName: string;
  applicantPhone: string;
  merchantType: MerchantType;
  legalName: string;
  businessName: string;
  businessAddress: string;
  latitude: number;
  longitude: number;
  serviceZoneId: string;
  serviceZoneName: string;
  evidenceObjectPath: string;
  status: MerchantApplicationStatus;
  submittedAt: string;
};

export type SubmitMerchantApplicationInput = {
  accountId: string;
  merchantType: MerchantType;
  legalName: string;
  businessName: string;
  businessAddress: string;
  latitude: number;
  longitude: number;
  evidenceObjectPath: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type SubmitMerchantApplication = (
  input: SubmitMerchantApplicationInput,
) => Promise<{ responseBody: unknown; responseStatus: number }>;

export type GetMerchantApplicationSnapshot = (
  accountId: string,
) => Promise<{ responseBody: unknown; responseStatus: number }>;

export type ListMerchantApplications = (
  ownerId: string,
) => Promise<MerchantApplication[]>;

export type ReviewMerchantApplicationInput = {
  ownerId: string;
  applicationId: string;
  decision: "approve" | "reject";
  reason: string | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type ReviewMerchantApplication = (
  input: ReviewMerchantApplicationInput,
) => Promise<{ responseBody: unknown; responseStatus: number }>;

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  isActiveOwner: (accountId: string) => Promise<boolean>;
  submitMerchantApplication: SubmitMerchantApplication;
  getMerchantApplicationSnapshot: GetMerchantApplicationSnapshot;
  listMerchantApplications: ListMerchantApplications;
  reviewMerchantApplication: ReviewMerchantApplication;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleMerchantApplications(
  request: Request,
  dependencies: Dependencies,
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
      case "selfSnapshot":
        return await selfSnapshot(actor.accountId, dependencies);
      case "list":
        return await list(actor.accountId, dependencies);
      case "review":
        return await review(request, body, actor.accountId, dependencies);
      default:
        return validationError();
    }
  } catch {
    return internalError();
  }
}

async function selfSnapshot(accountId: string, dependencies: Dependencies) {
  const result = await dependencies.getMerchantApplicationSnapshot(accountId);
  return json(result.responseBody, result.responseStatus);
}

async function submit(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: Dependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const merchantType: MerchantType | undefined =
    body.merchantType === "RETAIL" || body.merchantType === "RESTAURANT_CAFE"
      ? body.merchantType
      : undefined;
  const legalName = normalizeRequiredText(body.legalName, 160);
  const businessName = normalizeRequiredText(body.businessName, 120);
  const businessAddress = normalizeRequiredText(body.businessAddress, 300);
  const latitude = finiteNumber(body.latitude, -90, 90);
  const longitude = finiteNumber(body.longitude, -180, 180);
  const evidenceObjectPath = typeof body.evidenceObjectPath === "string"
    ? body.evidenceObjectPath
    : "";
  if (
    !idempotencyKey || !merchantType || !legalName || !businessName || !businessAddress ||
    latitude === undefined || longitude === undefined ||
    !validMerchantEvidencePath(evidenceObjectPath, accountId)
  ) {
    return validationError();
  }

  const normalized = {
    merchantType,
    legalName,
    businessName,
    businessAddress,
    latitude,
    longitude,
    evidenceObjectPath,
  };
  const result = await dependencies.submitMerchantApplication({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function list(accountId: string, dependencies: Dependencies) {
  if (!await dependencies.isActiveOwner(accountId)) return accessDenied();
  return json({
    applications: await dependencies.listMerchantApplications(accountId),
  });
}

async function review(
  request: Request,
  body: Record<string, unknown>,
  ownerId: string,
  dependencies: Dependencies,
) {
  if (!await dependencies.isActiveOwner(ownerId)) return accessDenied();

  const idempotencyKey = requiredIdempotencyKey(request);
  const applicationId = typeof body.applicationId === "string" ? body.applicationId : "";
  const decision = body.decision === "approve" || body.decision === "reject"
    ? body.decision
    : undefined;
  const normalizedReason = body.reason === null || body.reason === undefined
    ? null
    : normalizeRequiredText(body.reason, 500);
  if (
    !idempotencyKey || !uuidPattern.test(applicationId) || !decision ||
    (body.reason !== null && body.reason !== undefined && !normalizedReason) ||
    (decision === "reject" && !normalizedReason)
  ) {
    return validationError();
  }

  const normalized: {
    applicationId: string;
    decision: "approve" | "reject";
    reason: string | null;
  } = {
    applicationId,
    decision,
    reason: normalizedReason ?? null,
  };
  const result = await dependencies.reviewMerchantApplication({
    ownerId,
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
    return body && typeof body === "object" ? body as Record<string, unknown> : undefined;
  } catch {
    return undefined;
  }
}

function normalizeRequiredText(value: unknown, maximumLength: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximumLength ? normalized : undefined;
}

function finiteNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : undefined;
}

function validMerchantEvidencePath(path: string, accountId: string) {
  const segments = path.split("/");
  return segments.length === 3 && segments[0] === "merchant" &&
    segments[1] === accountId && segments[2].length > 0;
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
      message: "The merchant application request is invalid.",
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
      message: "Merchant applications could not be processed.",
    },
  }, 500);
}
