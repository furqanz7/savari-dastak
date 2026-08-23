import { corsPreflight, json } from "../_shared/http.ts";
import { V1RequestError } from "../_shared/v1-rpc.ts";

export type V1Actor = { accountId: string; accessToken: string };
export type V1CatalogueDependencies = {
  authenticateBearer: (authorization: string) => Promise<V1Actor>;
  customerCatalogue: (input: {
    accessToken: string;
    query: string | null;
    categoryId: string | null;
    subcategoryId: string | null;
    limit: number;
    afterName: string | null;
    afterSkuId: string | null;
  }) => Promise<unknown>;
  customerRestaurants: (input: {
    accessToken: string;
    query: string | null;
    limit: number;
  }) => Promise<unknown>;
  adminSnapshot: (input: { accessToken: string; skuLimit: number }) => Promise<unknown>;
  merchantSnapshot: (input: {
    accessToken: string;
    branchId: string | null;
    limit: number;
  }) => Promise<unknown>;
  merchantRestaurantMenu: (input: {
    accessToken: string;
    branchId: string | null;
  }) => Promise<unknown>;
  importCatalogue: (input: {
    accessToken: string;
    idempotencyKey: string;
    catalogue: Record<string, unknown>;
  }) => Promise<unknown>;
  updateSku: (input: {
    accessToken: string;
    skuId: string;
    idempotencyKey: string;
    expectedVersion: number;
    patch: Record<string, unknown>;
  }) => Promise<unknown>;
  updateMerchantSelection: (input: {
    accessToken: string;
    branchId: string;
    skuId: string;
    selected: boolean;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  updateBranchOperationalState: (input: {
    accessToken: string;
    branchId: string;
    isOpen: boolean;
    acceptingOrders: boolean;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  upsertRestaurantMenuEntity: (input: {
    accessToken: string;
    branchId: string;
    entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION";
    entityId: string | null;
    expectedVersion: number;
    payload: Record<string, unknown>;
    idempotencyKey: string;
  }) => Promise<unknown>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleV1Catalogue(
  request: Request,
  dependencies: V1CatalogueDependencies,
) {
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
      case "customerCatalogue":
        return await customerCatalogue(body, actor, dependencies);
      case "customerRestaurants": {
        const query = optionalText(body.query, 80);
        const parsedLimit = optionalInteger(body.limit, 1, 100);
        if (
          query === undefined ||
          (body.limit !== null && body.limit !== undefined && parsedLimit === undefined)
        ) {
          return validationError();
        }
        return json(
          await dependencies.customerRestaurants({
            accessToken: actor.accessToken,
            query,
            limit: parsedLimit ?? 50,
          }),
        );
      }
      case "adminSnapshot": {
        const parsedLimit = optionalInteger(body.skuLimit, 1, 1000);
        if (body.skuLimit !== null && body.skuLimit !== undefined && parsedLimit === undefined) {
          return validationError();
        }
        const skuLimit = parsedLimit ?? 1000;
        const result = await dependencies.adminSnapshot({
          accessToken: actor.accessToken,
          skuLimit,
        });
        return json(result);
      }
      case "merchantSnapshot": {
        const branchId = optionalUUID(body.branchId);
        const parsedLimit = optionalInteger(body.limit, 1, 1000);
        if (
          branchId === undefined ||
          (body.limit !== null && body.limit !== undefined && parsedLimit === undefined)
        ) {
          return validationError();
        }
        return json(
          await dependencies.merchantSnapshot({
            accessToken: actor.accessToken,
            branchId,
            limit: parsedLimit ?? 1000,
          }),
        );
      }
      case "merchantRestaurantMenu": {
        const branchId = optionalUUID(body.branchId);
        if (branchId === undefined) return validationError();
        return json(
          await dependencies.merchantRestaurantMenu({
            accessToken: actor.accessToken,
            branchId,
          }),
        );
      }
      case "importCatalogue": {
        const idempotencyKey = requiredIdempotencyKey(request);
        const catalogue = record(body.catalogue);
        if (!idempotencyKey || !catalogue) return validationError();
        const result = await dependencies.importCatalogue({
          accessToken: actor.accessToken,
          idempotencyKey,
          catalogue,
        });
        return json(result);
      }
      case "updateSku":
        return await updateSku(request, body, actor, dependencies);
      case "updateMerchantSelection":
        return await updateMerchantSelection(request, body, actor, dependencies);
      case "updateBranchOperationalState":
        return await updateBranchOperationalState(request, body, actor, dependencies);
      case "upsertRestaurantMenuEntity":
        return await upsertRestaurantMenuEntity(request, body, actor, dependencies);
      default:
        return validationError();
    }
  } catch (error) {
    return requestFailure(error);
  }
}

async function upsertRestaurantMenuEntity(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  const entityId = optionalUUID(body.entityId);
  const expectedVersion = optionalInteger(body.expectedVersion, 0, Number.MAX_SAFE_INTEGER);
  const payload = record(body.payload);
  const entityType = body.entityType;
  if (
    !idempotencyKey || !branchId || entityId === undefined ||
    expectedVersion === undefined || !payload ||
    !["CATEGORY", "ITEM", "OPTION_GROUP", "OPTION"].includes(String(entityType))
  ) {
    return validationError();
  }
  return json(
    await dependencies.upsertRestaurantMenuEntity({
      accessToken: actor.accessToken,
      branchId,
      entityType: entityType as "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION",
      entityId,
      expectedVersion,
      payload,
      idempotencyKey,
    }),
  );
}

async function updateMerchantSelection(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  const skuId = requiredUUID(body.skuId);
  const expectedVersion = optionalInteger(body.expectedVersion, 0, Number.MAX_SAFE_INTEGER);
  if (
    !idempotencyKey || !branchId || !skuId || expectedVersion === undefined ||
    typeof body.selected !== "boolean"
  ) return validationError();
  return json(
    await dependencies.updateMerchantSelection({
      accessToken: actor.accessToken,
      branchId,
      skuId,
      selected: body.selected,
      expectedVersion,
      idempotencyKey,
    }),
  );
}

async function updateBranchOperationalState(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  const expectedVersion = optionalInteger(body.expectedVersion, 0, Number.MAX_SAFE_INTEGER);
  if (
    !idempotencyKey || !branchId || expectedVersion === undefined ||
    typeof body.isOpen !== "boolean" || typeof body.acceptingOrders !== "boolean"
  ) {
    return validationError();
  }
  return json(
    await dependencies.updateBranchOperationalState({
      accessToken: actor.accessToken,
      branchId,
      isOpen: body.isOpen,
      acceptingOrders: body.acceptingOrders,
      expectedVersion,
      idempotencyKey,
    }),
  );
}

async function customerCatalogue(
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const query = optionalText(body.query, 80);
  const categoryId = optionalUUID(body.categoryId);
  const subcategoryId = optionalUUID(body.subcategoryId);
  const parsedLimit = optionalInteger(body.limit, 1, 250);
  const limit = parsedLimit ?? 100;
  const cursor = record(body.cursor);
  const afterName = cursor ? optionalText(cursor.name, 160) : null;
  const afterSkuId = cursor ? optionalUUID(cursor.skuId) : null;
  if (
    query === undefined || categoryId === undefined || subcategoryId === undefined ||
    (body.limit !== null && body.limit !== undefined && parsedLimit === undefined) ||
    (body.cursor !== null && body.cursor !== undefined && cursor === undefined) ||
    (cursor !== undefined && (!afterName || !afterSkuId))
  ) {
    return validationError();
  }
  const result = await dependencies.customerCatalogue({
    accessToken: actor.accessToken,
    query,
    categoryId,
    subcategoryId,
    limit,
    afterName: afterName ?? null,
    afterSkuId: afterSkuId ?? null,
  });
  return json(result);
}

async function updateSku(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const skuId = requiredUUID(body.skuId);
  const expectedVersion = optionalInteger(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
  const patch = record(body.patch);
  if (!idempotencyKey || !skuId || !expectedVersion || !patch || Object.keys(patch).length === 0) {
    return validationError();
  }
  const result = await dependencies.updateSku({
    accessToken: actor.accessToken,
    skuId,
    idempotencyKey,
    expectedVersion,
    patch,
  });
  return json(result);
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    const source = await request.text();
    if (source.length === 0 || source.length > 2_000_000) return undefined;
    return record(JSON.parse(source));
  } catch {
    return undefined;
  }
}

function optionalText(value: unknown, maximum: number): string | null | undefined {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : undefined;
}

function requiredUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function optionalUUID(value: unknown): string | null | undefined {
  if (value === null || value === undefined) return null;
  return requiredUUID(value);
}

function optionalInteger(value: unknown, minimum: number, maximum: number) {
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
  return json({
    error: { code: "validation_failed", message: "The catalogue request is invalid." },
  }, 400);
}

function requestFailure(error: unknown) {
  if (error instanceof V1RequestError) {
    return json({ error: { code: error.code, message: error.message } }, error.status);
  }
  return json({
    error: { code: "internal_error", message: "The catalogue request could not be processed." },
  }, 500);
}
