import { json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };
type Scope = "medicine" | "tobacco";
type TobaccoKind = "cigarette" | "cigar" | "rolling_tobacco";
type Location = { latitude: number; longitude: number };
type Mutation = { accountId: string; idempotencyKey: string; requestDigest: string };

export type AdultAttestationInput = Mutation & {
  policyVersion: string; affirmedAdult: boolean; affirmedNotForMinor: boolean;
};
export type ControlledBrowseInput = { accountId: string; scope: Scope } & Location;
export type ControlledQuoteInput = Mutation & {
  scope: Scope; storeId: string;
  lines: Array<{ productId: string; quantity: number }>;
  dropoffLatitude: number; dropoffLongitude: number;
  prescriptionEvidencePath: string | null;
};
export type ControlledOrderInput = Mutation & { quoteId: string };
export type ControlledOrderSnapshotInput = { accountId: string; orderId: string };
export type StoreComplianceInput = Mutation & {
  scope: Scope; evidenceObjectPath: string | null;
};
export type StoreComplianceReviewInput = Mutation & {
  complianceId: string; decision: "approve" | "reject" | "suspend";
  validUntil: string | null; reason: string | null;
};
export type ControlledProductInput = Mutation & {
  productId: string; tobaccoKind: TobaccoKind | null;
};
export type ControlledProductReviewInput = Mutation & {
  productId: string; decision: "approve" | "reject" | "suspend"; reason: string | null;
};
export type ControlledPolicyInput = Mutation & {
  version: string; allowedTobaccoKinds: TobaccoKind[]; active: boolean;
};
export type ExclusionZoneInput = Mutation & {
  zoneId: string | null; name: string; kind: "school" | "college";
  latitude: number; longitude: number; radiusMeters: number; active: boolean;
};
export type RestrictedHandoffInput = Mutation & {
  assignmentId: string; verificationCode: string;
  visualAgeCheck: "passed" | "failed" | "uncertain"; reason: string | null;
};
export type RestrictedReturnInput = Mutation & { orderId: string; reason: string };

export type ControlledCategoryDependencies = {
  authenticateBearer: AuthenticateBearer;
  attestAdult: (input: AdultAttestationInput) => Promise<RpcResult>;
  browseCatalogue: (input: ControlledBrowseInput) => Promise<RpcResult>;
  quoteOrder: (input: ControlledQuoteInput) => Promise<RpcResult>;
  createOrder: (input: ControlledOrderInput) => Promise<RpcResult>;
  getOrderSnapshot: (input: ControlledOrderSnapshotInput) => Promise<RpcResult>;
  submitStoreCompliance: (input: StoreComplianceInput) => Promise<RpcResult>;
  reviewStoreCompliance: (input: StoreComplianceReviewInput) => Promise<RpcResult>;
  submitProduct: (input: ControlledProductInput) => Promise<RpcResult>;
  reviewProduct: (input: ControlledProductReviewInput) => Promise<RpcResult>;
  upsertPolicy: (input: ControlledPolicyInput) => Promise<RpcResult>;
  upsertExclusionZone: (input: ExclusionZoneInput) => Promise<RpcResult>;
  verifyRestrictedHandoff: (input: RestrictedHandoffInput) => Promise<RpcResult>;
  confirmRestrictedReturn: (input: RestrictedReturnInput) => Promise<RpcResult>;
  getPrescriptionEvidencePath: (input: ControlledOrderSnapshotInput) => Promise<string | null>;
  signEvidenceDownload: (objectPath: string) => Promise<string>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const tobaccoKinds = new Set<TobaccoKind>(["cigarette", "cigar", "rolling_tobacco"]);

export async function handleControlledCategories(
  request: Request,
  dependencies: ControlledCategoryDependencies,
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
      case "attestAdult": return attestAdult(request, body, actor.accountId, dependencies);
      case "browse": return browse(body, actor.accountId, dependencies);
      case "quote": return quote(request, body, actor.accountId, dependencies);
      case "createOrder": return createOrder(request, body, actor.accountId, dependencies);
      case "orderSnapshot": return orderSnapshot(body, actor.accountId, dependencies);
      case "submitStoreCompliance":
        return submitStoreCompliance(request, body, actor.accountId, dependencies);
      case "reviewStoreCompliance":
        return reviewStoreCompliance(request, body, actor.accountId, dependencies);
      case "submitProduct": return submitProduct(request, body, actor.accountId, dependencies);
      case "reviewProduct": return reviewProduct(request, body, actor.accountId, dependencies);
      case "upsertPolicy": return upsertPolicy(request, body, actor.accountId, dependencies);
      case "upsertExclusionZone":
        return upsertExclusionZone(request, body, actor.accountId, dependencies);
      case "verifyRestrictedHandoff":
        return verifyRestrictedHandoff(request, body, actor.accountId, dependencies);
      case "confirmRestrictedReturn":
        return confirmRestrictedReturn(request, body, actor.accountId, dependencies);
      case "prescriptionDownloadURL":
        return prescriptionDownload(body, actor.accountId, dependencies);
      default: return validationError();
    }
  } catch {
    return internalError();
  }
}

async function attestAdult(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const policyVersion = normalizedText(body.policyVersion, 80);
  if (!policyVersion || body.affirmedAdult !== true || body.affirmedNotForMinor !== true) {
    return validationError();
  }
  return mutation(request, accountId, {
    policyVersion, affirmedAdult: true, affirmedNotForMinor: true,
  }, dependencies.attestAdult);
}

async function browse(
  body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const scope = controlledScope(body.scope);
  const point = location(body.location);
  if (!scope || !point) return validationError();
  return rpcResponse(await dependencies.browseCatalogue({ accountId, scope, ...point }));
}

async function quote(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const scope = controlledScope(body.scope);
  const storeId = uuid(body.storeId);
  const lines = orderLines(body.lines);
  const dropoff = location(body.dropoff);
  const prescriptionEvidencePath = optionalText(body.prescriptionEvidencePath, 500);
  if (!scope || !storeId || !lines || !dropoff || prescriptionEvidencePath === undefined) {
    return validationError();
  }
  return mutation(request, accountId, {
    scope, storeId, lines,
    dropoffLatitude: dropoff.latitude,
    dropoffLongitude: dropoff.longitude,
    prescriptionEvidencePath,
  }, dependencies.quoteOrder);
}

async function createOrder(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const quoteId = uuid(body.quoteId);
  return quoteId
    ? mutation(request, accountId, { quoteId }, dependencies.createOrder)
    : validationError();
}

async function orderSnapshot(
  body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const orderId = uuid(body.orderId);
  if (!orderId) return validationError();
  return rpcResponse(await dependencies.getOrderSnapshot({ accountId, orderId }));
}

async function submitStoreCompliance(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const scope = controlledScope(body.scope);
  const evidenceObjectPath = optionalText(body.evidenceObjectPath, 500);
  if (!scope || evidenceObjectPath === undefined ||
    ((scope === "medicine") !== (evidenceObjectPath !== null))) return validationError();
  return mutation(
    request, accountId, { scope, evidenceObjectPath }, dependencies.submitStoreCompliance,
  );
}

async function reviewStoreCompliance(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const complianceId = uuid(body.complianceId);
  const decision = reviewDecision(body.decision);
  const validUntil = optionalDate(body.validUntil);
  const reason = optionalText(body.reason, 500);
  if (!complianceId || !decision || validUntil === undefined || reason === undefined ||
    (decision !== "approve" && !reason)) return validationError();
  return mutation(request, accountId, {
    complianceId, decision, validUntil, reason,
  }, dependencies.reviewStoreCompliance);
}

async function submitProduct(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const productId = uuid(body.productId);
  const tobaccoKind = optionalTobaccoKind(body.tobaccoKind);
  return productId && tobaccoKind !== undefined
    ? mutation(request, accountId, { productId, tobaccoKind }, dependencies.submitProduct)
    : validationError();
}

async function reviewProduct(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const productId = uuid(body.productId);
  const decision = reviewDecision(body.decision);
  const reason = optionalText(body.reason, 500);
  if (!productId || !decision || reason === undefined || (decision !== "approve" && !reason)) {
    return validationError();
  }
  return mutation(request, accountId, { productId, decision, reason }, dependencies.reviewProduct);
}

async function upsertPolicy(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const version = normalizedText(body.version, 80);
  const allowedTobaccoKinds = tobaccoKindList(body.allowedTobaccoKinds);
  if (!version || !allowedTobaccoKinds || typeof body.active !== "boolean") {
    return validationError();
  }
  return mutation(request, accountId, {
    version, allowedTobaccoKinds, active: body.active,
  }, dependencies.upsertPolicy);
}

async function upsertExclusionZone(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const zoneId = optionalUUID(body.zoneId);
  const name = normalizedText(body.name, 120);
  const kind = body.kind === "school" || body.kind === "college" ? body.kind : undefined;
  const point = location(body.center);
  if (zoneId === undefined || !name || !kind || !point ||
    typeof body.radiusMeters !== "number" || !Number.isInteger(body.radiusMeters) ||
    body.radiusMeters < 1 || body.radiusMeters > 5_000 || typeof body.active !== "boolean") {
    return validationError();
  }
  return mutation(request, accountId, {
    zoneId, name, kind, ...point, radiusMeters: body.radiusMeters, active: body.active,
  }, dependencies.upsertExclusionZone);
}

async function verifyRestrictedHandoff(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const assignmentId = uuid(body.assignmentId);
  const verificationCode = typeof body.verificationCode === "string" && /^[0-9]{4}$/.test(body.verificationCode)
    ? body.verificationCode : undefined;
  const visualAgeCheck = body.visualAgeCheck === "passed" || body.visualAgeCheck === "failed" ||
      body.visualAgeCheck === "uncertain" ? body.visualAgeCheck : undefined;
  const reason = optionalText(body.reason, 500);
  if (!assignmentId || !verificationCode || !visualAgeCheck || reason === undefined ||
    (visualAgeCheck !== "passed" && !reason)) return validationError();
  return mutation(request, accountId, {
    assignmentId, verificationCode, visualAgeCheck, reason,
  }, dependencies.verifyRestrictedHandoff);
}

async function confirmRestrictedReturn(
  request: Request, body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const orderId = uuid(body.orderId);
  const reason = normalizedText(body.reason, 500);
  return orderId && reason
    ? mutation(request, accountId, { orderId, reason }, dependencies.confirmRestrictedReturn)
    : validationError();
}

async function prescriptionDownload(
  body: Record<string, unknown>, accountId: string,
  dependencies: ControlledCategoryDependencies,
) {
  const orderId = uuid(body.orderId);
  if (!orderId) return validationError();
  const objectPath = await dependencies.getPrescriptionEvidencePath({ accountId, orderId });
  if (!objectPath) {
    return json({ error: { code: "evidence_not_found", message: "Prescription evidence was not found." } }, 404);
  }
  return json({ signedUrl: await dependencies.signEvidenceDownload(objectPath), expiresIn: 300 });
}

async function mutation<T extends Record<string, unknown>>(
  request: Request, accountId: string, normalized: T,
  dependency: (input: Mutation & T) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  if (!idempotencyKey) return validationError();
  return rpcResponse(await dependency({
    accountId, ...normalized, idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  }));
}

function rpcResponse(result: RpcResult) {
  return json(result.responseBody, result.responseStatus);
}
async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try { return record(await request.json()); } catch { return undefined; }
}
function orderLines(value: unknown) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) return undefined;
  const seen = new Set<string>();
  const lines: Array<{ productId: string; quantity: number }> = [];
  for (const raw of value) {
    const line = record(raw);
    const productId = uuid(line?.productId);
    const quantity = line?.quantity;
    if (!productId || typeof quantity !== "number" || !Number.isInteger(quantity) ||
      quantity < 1 || quantity > 99 || seen.has(productId)) return undefined;
    seen.add(productId);
    lines.push({ productId, quantity });
  }
  return lines;
}
function location(value: unknown): Location | undefined {
  const point = record(value);
  if (!point || typeof point.latitude !== "number" || !Number.isFinite(point.latitude) ||
    point.latitude < -90 || point.latitude > 90 || typeof point.longitude !== "number" ||
    !Number.isFinite(point.longitude) || point.longitude < -180 || point.longitude > 180) {
    return undefined;
  }
  return { latitude: point.latitude, longitude: point.longitude };
}
function controlledScope(value: unknown): Scope | undefined {
  return value === "medicine" || value === "tobacco" ? value : undefined;
}
function reviewDecision(value: unknown) {
  return value === "approve" || value === "reject" || value === "suspend" ? value : undefined;
}
function optionalTobaccoKind(value: unknown): TobaccoKind | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "string" && tobaccoKinds.has(value as TobaccoKind)
    ? value as TobaccoKind : undefined;
}
function tobaccoKindList(value: unknown): TobaccoKind[] | undefined {
  if (!Array.isArray(value) || value.length < 1 || value.length > 3) return undefined;
  const kinds = value.map(optionalTobaccoKind);
  if (kinds.some((kind) => !kind)) return undefined;
  const unique = [...new Set(kinds as TobaccoKind[])];
  return unique.length === kinds.length ? unique : undefined;
}
function optionalDate(value: unknown): string | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "string" && value.length <= 40 && !Number.isNaN(Date.parse(value))
    ? value : undefined;
}
function normalizedText(value: unknown, maximumLength: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximumLength ? normalized : undefined;
}
function optionalText(value: unknown, maximumLength: number): string | null | undefined {
  return value === null || value === undefined ? null : normalizedText(value, maximumLength);
}
function uuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : undefined;
}
function optionalUUID(value: unknown): string | null | undefined {
  return value === null || value === undefined ? null : uuid(value);
}
function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : undefined;
}
function requiredIdempotencyKey(request: Request) {
  const key = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  return key.length >= 1 && key.length <= 200 ? key : undefined;
}
async function canonicalDigest(value: unknown) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value)));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
function authenticationRequired() {
  return json({ error: { code: "authentication_required", message: "A valid bearer token is required." } }, 401);
}
function validationError() {
  return json({ error: { code: "validation_failed", message: "The controlled-category request is invalid." } }, 400);
}
function internalError() {
  return json({ error: { code: "internal_error", message: "The controlled-category request could not be completed." } }, 500);
}
