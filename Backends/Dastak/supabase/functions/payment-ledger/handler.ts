import { json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type OwnerFinancialRateCardInput = {
  accountId: string;
  serviceZoneId: string;
  deliveryFeePaise: number;
  merchantCommissionBps: number;
  courierPayoutPaise: number;
  active: boolean;
  idempotencyKey: string;
  requestDigest: string;
};

export type PaymentLedgerDependencies = {
  authenticateBearer: AuthenticateBearer;
  upsertRateCard: (input: OwnerFinancialRateCardInput) => Promise<RpcResult>;
  getOrderSnapshot: (accountId: string, orderId: string) => Promise<RpcResult>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handlePaymentLedger(
  request: Request,
  dependencies: PaymentLedgerDependencies,
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
      case "ownerUpsertRateCard":
        return await ownerUpsertRateCard(request, body, actor.accountId, dependencies);
      case "ownerOrderSnapshot":
        return await ownerOrderSnapshot(body, actor.accountId, dependencies);
      default:
        return validationError();
    }
  } catch {
    return internalError();
  }
}

async function ownerUpsertRateCard(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: PaymentLedgerDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const serviceZoneId = validUUID(body.serviceZoneId);
  const deliveryFeePaise = validInteger(body.deliveryFeePaise, 0, 100_000_000);
  const merchantCommissionBps = validInteger(body.merchantCommissionBps, 0, 10_000);
  const courierPayoutPaise = validInteger(body.courierPayoutPaise, 0, 100_000_000);
  const active = typeof body.active === "boolean" ? body.active : undefined;
  if (
    !idempotencyKey || !serviceZoneId || deliveryFeePaise === undefined ||
    merchantCommissionBps === undefined || courierPayoutPaise === undefined ||
    courierPayoutPaise > deliveryFeePaise || active === undefined
  ) return validationError();

  const normalized = {
    serviceZoneId,
    deliveryFeePaise,
    merchantCommissionBps,
    courierPayoutPaise,
    active,
  };
  const result = await dependencies.upsertRateCard({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function ownerOrderSnapshot(
  body: Record<string, unknown>,
  accountId: string,
  dependencies: PaymentLedgerDependencies,
) {
  const orderId = validUUID(body.orderId);
  if (!orderId) return validationError();
  const result = await dependencies.getOrderSnapshot(accountId, orderId);
  return json(result.responseBody, result.responseStatus);
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    const body = await request.json();
    return record(body);
  } catch {
    return undefined;
  }
}

function validInteger(value: unknown, minimum: number, maximum: number) {
  return typeof value === "number" && Number.isSafeInteger(value) &&
      value >= minimum && value <= maximum
    ? value
    : undefined;
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
      message: "The payment ledger request is invalid.",
    },
  }, 400);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The payment ledger request could not be processed.",
    },
  }, 500);
}
