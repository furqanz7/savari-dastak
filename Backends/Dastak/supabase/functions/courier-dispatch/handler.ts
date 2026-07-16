import { json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type CourierDispatchMutationInput = {
  accountId: string;
  assignmentId: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type CourierDispatchDeclineInput = CourierDispatchMutationInput & {
  reason: string | null;
};

export type CourierDispatchDependencies = {
  authenticateBearer: AuthenticateBearer;
  getPartnerSnapshot: (accountId: string) => Promise<RpcResult>;
  acceptOffer: (input: CourierDispatchMutationInput) => Promise<RpcResult>;
  declineOffer: (input: CourierDispatchDeclineInput) => Promise<RpcResult>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleCourierDispatch(
  request: Request,
  dependencies: CourierDispatchDependencies,
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
      case "partnerSnapshot": {
        const result = await dependencies.getPartnerSnapshot(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "acceptOffer":
        return await assignmentMutation(
          request,
          body,
          actor.accountId,
          dependencies.acceptOffer,
        );
      case "declineOffer":
        return await declineMutation(request, body, actor.accountId, dependencies);
      default:
        return validationError();
    }
  } catch {
    return internalError();
  }
}

async function assignmentMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: CourierDispatchMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  if (!idempotencyKey || !assignmentId) return validationError();

  const normalized = { assignmentId };
  const result = await dependency({
    accountId,
    assignmentId,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function declineMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CourierDispatchDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  const reason = normalizeOptionalText(body.reason, 300);
  if (!idempotencyKey || !assignmentId || reason === undefined) return validationError();

  const normalized = { assignmentId, reason };
  const result = await dependencies.declineOffer({
    accountId,
    assignmentId,
    reason,
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

function normalizeOptionalText(value: unknown, maximumLength: number) {
  if (value === null || value === undefined) return null;
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
      message: "The courier dispatch request is invalid.",
    },
  }, 400);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The courier dispatch request could not be completed.",
    },
  }, 500);
}
