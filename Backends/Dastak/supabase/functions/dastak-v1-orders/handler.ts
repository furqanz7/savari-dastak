import { corsPreflight, json } from "../_shared/http.ts";
import { V1RequestError } from "../_shared/v1-rpc.ts";
import type { V1Actor } from "../dastak-v1-catalogue/handler.ts";

export type V1OrderDependencies = {
  authenticateBearer: (authorization: string) => Promise<V1Actor>;
  submitOrder: (input: {
    accessToken: string;
    idempotencyKey: string;
    expectedVersion: number;
    order: Record<string, unknown>;
  }) => Promise<unknown>;
  listOrders: (input: {
    accessToken: string;
    limit: number;
    beforeCreatedAt: string | null;
    beforeOrderId: string | null;
  }) => Promise<unknown>;
  getOrder: (input: { accessToken: string; orderId: string }) => Promise<unknown>;
  cancelOrder: (input: {
    accessToken: string;
    orderId: string;
    idempotencyKey: string;
    expectedVersion: number;
  }) => Promise<unknown>;
  listMerchantOpportunities: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  acceptMerchantOpportunity: (input: {
    accessToken: string;
    opportunityId: string;
    requestScope: "FULL_BASKET" | "REQUESTED_SUBSET";
    expectedVersion: number;
    promisedPrepMinutes: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  declineMerchantOpportunity: (input: {
    accessToken: string;
    opportunityId: string;
    requestScope: "FULL_BASKET" | "REQUESTED_SUBSET";
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  listMerchantFulfilments: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  declareFulfilmentPackages: (input: {
    accessToken: string;
    fulfilmentId: string;
    packageCount: number;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  addFulfilmentReadyEvidence: (input: {
    accessToken: string;
    fulfilmentId: string;
    packageId: string | null;
    objectPath: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  markFulfilmentReady: (input: {
    accessToken: string;
    fulfilmentId: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  reportFulfilmentProblem: (input: {
    accessToken: string;
    fulfilmentId: string;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  listAdminExecutionOrders: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  getAdminExecutionTrace: (input: {
    accessToken: string;
    orderId: string;
  }) => Promise<unknown>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleV1Orders(request: Request, dependencies: V1OrderDependencies) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();
  let actor: V1Actor;
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await parseBody(request);
  if (!body || typeof body.operation !== "string") return validationError();

  try {
    switch (body.operation) {
      case "submit": {
        const idempotencyKey = requiredIdempotencyKey(request);
        const expectedVersion = integer(body.expectedVersion, 0, 0);
        const order = record(body.order);
        if (!idempotencyKey || expectedVersion === undefined || !order) return validationError();
        const result = await dependencies.submitOrder({
          accessToken: actor.accessToken,
          idempotencyKey,
          expectedVersion,
          order,
        });
        return json(result, 201);
      }
      case "list": {
        const parsedLimit = integer(body.limit, 1, 100);
        if (body.limit !== null && body.limit !== undefined && parsedLimit === undefined) {
          return validationError();
        }
        const limit = parsedLimit ?? 20;
        const cursor = record(body.cursor);
        const beforeCreatedAt = cursor && validTimestamp(cursor.createdAt)
          ? cursor.createdAt as string
          : null;
        const beforeOrderId = cursor ? requiredUUID(cursor.orderId) ?? null : null;
        if (
          (body.cursor !== null && body.cursor !== undefined && cursor === undefined) ||
          (cursor !== undefined && (!beforeCreatedAt || !beforeOrderId))
        ) return validationError();
        return json(
          await dependencies.listOrders({
            accessToken: actor.accessToken,
            limit,
            beforeCreatedAt,
            beforeOrderId,
          }),
        );
      }
      case "get": {
        const orderId = requiredUUID(body.orderId);
        if (!orderId) return validationError();
        return json(await dependencies.getOrder({ accessToken: actor.accessToken, orderId }));
      }
      case "cancel": {
        const orderId = requiredUUID(body.orderId);
        const idempotencyKey = requiredIdempotencyKey(request);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        if (!orderId || !idempotencyKey || !expectedVersion) return validationError();
        return json(
          await dependencies.cancelOrder({
            accessToken: actor.accessToken,
            orderId,
            idempotencyKey,
            expectedVersion,
          }),
        );
      }
      case "merchantOpportunities": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) {
          return validationError();
        }
        return json(
          await dependencies.listMerchantOpportunities({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "acceptMerchantOpportunity": {
        const opportunityId = requiredUUID(body.opportunityId);
        const requestScope = merchantRequestScope(body.requestScope);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const promisedPrepMinutes = integer(body.promisedPrepMinutes, 1, 24 * 60);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !opportunityId || !requestScope || !expectedVersion || !promisedPrepMinutes ||
          !idempotencyKey
        ) {
          return validationError();
        }
        return json(
          await dependencies.acceptMerchantOpportunity({
            accessToken: actor.accessToken,
            opportunityId,
            requestScope,
            expectedVersion,
            promisedPrepMinutes,
            idempotencyKey,
          }),
        );
      }
      case "declineMerchantOpportunity": {
        const opportunityId = requiredUUID(body.opportunityId);
        const requestScope = merchantRequestScope(body.requestScope);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!opportunityId || !requestScope || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.declineMerchantOpportunity({
            accessToken: actor.accessToken,
            opportunityId,
            requestScope,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "merchantFulfilments": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) return validationError();
        return json(
          await dependencies.listMerchantFulfilments({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "declareFulfilmentPackages": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const packageCount = integer(body.packageCount, 1, 1000);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!fulfilmentId || !packageCount || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.declareFulfilmentPackages({
            accessToken: actor.accessToken,
            fulfilmentId,
            packageCount,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "addFulfilmentReadyEvidence": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const parsedPackageId = body.packageId === null || body.packageId === undefined
          ? null
          : requiredUUID(body.packageId);
        const objectPath = requiredText(body.objectPath, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !fulfilmentId || !objectPath || !expectedVersion || !idempotencyKey ||
          (body.packageId !== null && body.packageId !== undefined && !parsedPackageId)
        ) return validationError();
        const packageId = parsedPackageId ?? null;
        return json(
          await dependencies.addFulfilmentReadyEvidence({
            accessToken: actor.accessToken,
            fulfilmentId,
            packageId,
            objectPath,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "markFulfilmentReady": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!fulfilmentId || !expectedVersion || !idempotencyKey) return validationError();
        return json(
          await dependencies.markFulfilmentReady({
            accessToken: actor.accessToken,
            fulfilmentId,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "reportFulfilmentProblem": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !fulfilmentId || !reason || reason.length < 3 || !expectedVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.reportFulfilmentProblem({
            accessToken: actor.accessToken,
            fulfilmentId,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "adminExecutionOrders": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) {
          return validationError();
        }
        return json(
          await dependencies.listAdminExecutionOrders({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "adminExecutionTrace": {
        const orderId = requiredUUID(body.orderId);
        if (!orderId) return validationError();
        return json(
          await dependencies.getAdminExecutionTrace({
            accessToken: actor.accessToken,
            orderId,
          }),
        );
      }
      default:
        return validationError();
    }
  } catch (error) {
    return requestFailure(error);
  }
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    const source = await request.text();
    if (source.length === 0 || source.length > 250_000) return undefined;
    return record(JSON.parse(source));
  } catch {
    return undefined;
  }
}

function requiredUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function requiredText(value: unknown, maximum: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : undefined;
}

function validTimestamp(value: unknown) {
  return typeof value === "string" && value.length <= 40 && Number.isFinite(Date.parse(value));
}

function merchantRequestScope(value: unknown) {
  return value === "FULL_BASKET" || value === "REQUESTED_SUBSET" ? value : undefined;
}

function integer(value: unknown, minimum: number, maximum: number) {
  if (value === null || value === undefined) return undefined;
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum &&
      value <= maximum
    ? value
    : undefined;
}

function requiredIdempotencyKey(request: Request) {
  const key = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  return key.length >= 1 && key.length <= 200 ? key : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json(
    { error: { code: "validation_failed", message: "The order request is invalid." } },
    400,
  );
}

function requestFailure(error: unknown) {
  if (error instanceof V1RequestError) {
    return json({ error: { code: error.code, message: error.message } }, error.status);
  }
  return json({
    error: { code: "internal_error", message: "The order request could not be processed." },
  }, 500);
}
