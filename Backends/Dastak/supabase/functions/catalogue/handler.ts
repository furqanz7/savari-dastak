import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type CatalogueAvailability = "in_stock" | "out_of_stock";
export type CatalogueKind =
  | "general"
  | "otc_medicine"
  | "prescription_medicine"
  | "paan_corner";
export type RestrictedApprovalState =
  | "not_applicable"
  | "pending"
  | "approved"
  | "rejected"
  | "suspended";

export type CatalogueStore = {
  storeId: string;
  name: string;
  address: string;
  location: { latitude: number; longitude: number };
  serviceZoneId: string;
  isPublished: boolean;
  acceptingOrders: boolean;
};

export type CatalogueCategory = {
  categoryId: string;
  storeId: string;
  name: string;
  displayOrder: number;
  isActive: boolean;
};

export type CatalogueProduct = {
  productId: string;
  storeId: string;
  categoryId: string;
  name: string;
  description: string | null;
  unitLabel: string;
  price: { paise: number };
  imageObjectPath: string | null;
  availability: CatalogueAvailability;
  catalogueKind: CatalogueKind;
  restrictedApprovalState: RestrictedApprovalState;
  isActive: boolean;
};

export type CatalogueSnapshot = {
  serviceZoneId: string | null;
  discoveryRadiusMeters: number;
  stores: CatalogueStore[];
  categories: CatalogueCategory[];
  products: CatalogueProduct[];
};

type RpcResult = { responseBody: unknown; responseStatus: number };

export type UpsertStoreInput = {
  accountId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  isPublished: boolean;
  acceptingOrders: boolean;
  idempotencyKey: string;
  requestDigest: string;
};

export type UpsertCategoryInput = {
  accountId: string;
  categoryId: string | null;
  name: string;
  displayOrder: number;
  isActive: boolean;
  idempotencyKey: string;
  requestDigest: string;
};

export type UpsertProductInput = {
  accountId: string;
  productId: string | null;
  categoryId: string;
  name: string;
  description: string | null;
  unitLabel: string;
  pricePaise: number;
  imageObjectPath: string | null;
  availability: CatalogueAvailability;
  catalogueKind: CatalogueKind;
  isActive: boolean;
  idempotencyKey: string;
  requestDigest: string;
};

export type CatalogueDependencies = {
  authenticateBearer: AuthenticateBearer;
  upsertStore: (input: UpsertStoreInput) => Promise<RpcResult>;
  upsertCategory: (input: UpsertCategoryInput) => Promise<RpcResult>;
  upsertProduct: (input: UpsertProductInput) => Promise<RpcResult>;
  getMerchantCatalogue: (accountId: string) => Promise<RpcResult>;
  browseCatalogue: (input: {
    accountId: string;
    latitude: number;
    longitude: number;
    discoveryRadiusMeters: number;
  }) => Promise<RpcResult>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const availabilityValues = new Set<CatalogueAvailability>(["in_stock", "out_of_stock"]);
const catalogueKindValues = new Set<CatalogueKind>([
  "general",
  "otc_medicine",
  "prescription_medicine",
  "paan_corner",
]);

export async function handleCatalogue(
  request: Request,
  dependencies: CatalogueDependencies,
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
      case "upsertStore":
        return await upsertStore(request, body, actor.accountId, dependencies);
      case "upsertCategory":
        return await upsertCategory(request, body, actor.accountId, dependencies);
      case "upsertProduct":
        return await upsertProduct(request, body, actor.accountId, dependencies);
      case "merchantSnapshot": {
        const result = await dependencies.getMerchantCatalogue(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "browse":
        return await browse(body, actor.accountId, dependencies);
      default:
        return validationError();
    }
  } catch {
    return internalError();
  }
}

async function upsertStore(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const name = normalizeRequiredText(body.name, 120);
  const address = normalizeRequiredText(body.address, 300);
  const location = parseLocation(body.location);
  if (
    !idempotencyKey || !name || !address || !location ||
    typeof body.isPublished !== "boolean" || typeof body.acceptingOrders !== "boolean" ||
    (body.acceptingOrders && !body.isPublished)
  ) {
    return validationError();
  }

  const normalized = {
    name,
    address,
    latitude: location.latitude,
    longitude: location.longitude,
    isPublished: body.isPublished,
    acceptingOrders: body.acceptingOrders,
  };
  const result = await dependencies.upsertStore({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function upsertCategory(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const categoryId = optionalUUID(body.categoryId);
  const name = normalizeRequiredText(body.name, 80);
  if (
    !idempotencyKey || categoryId === undefined || !name ||
    typeof body.displayOrder !== "number" || !Number.isInteger(body.displayOrder) ||
    body.displayOrder < 0 || body.displayOrder > 10_000 ||
    typeof body.isActive !== "boolean"
  ) {
    return validationError();
  }

  const normalized = {
    categoryId,
    name,
    displayOrder: body.displayOrder,
    isActive: body.isActive,
  };
  const result = await dependencies.upsertCategory({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function upsertProduct(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const productId = optionalUUID(body.productId);
  const categoryId = typeof body.categoryId === "string" && uuidPattern.test(body.categoryId)
    ? body.categoryId
    : undefined;
  const name = normalizeRequiredText(body.name, 160);
  const description = normalizeOptionalText(body.description, 1_000);
  const unitLabel = normalizeRequiredText(body.unitLabel, 40);
  const price = record(body.price);
  const pricePaise = price?.paise;
  const imageObjectPath = optionalImagePath(body.imageObjectPath, accountId);
  const availability = availabilityValues.has(body.availability as CatalogueAvailability)
    ? body.availability as CatalogueAvailability
    : undefined;
  const catalogueKind = catalogueKindValues.has(body.catalogueKind as CatalogueKind)
    ? body.catalogueKind as CatalogueKind
    : undefined;
  if (
    !idempotencyKey || productId === undefined || !categoryId || !name ||
    description === undefined || !unitLabel ||
    typeof pricePaise !== "number" || !Number.isInteger(pricePaise) || pricePaise < 1 ||
    pricePaise > 100_000_000 || imageObjectPath === undefined ||
    !availability || !catalogueKind || typeof body.isActive !== "boolean"
  ) {
    return validationError();
  }

  const normalized = {
    productId,
    categoryId,
    name,
    description,
    unitLabel,
    pricePaise,
    imageObjectPath,
    availability,
    catalogueKind,
    isActive: body.isActive,
  };
  const result = await dependencies.upsertProduct({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function browse(
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CatalogueDependencies,
) {
  const location = parseLocation(body.location);
  const discoveryRadiusMeters = body.discoveryRadiusMeters ?? 10000;
  if (
    !location || typeof discoveryRadiusMeters !== "number" ||
    !Number.isInteger(discoveryRadiusMeters) ||
    discoveryRadiusMeters < 10000 || discoveryRadiusMeters > 30000
  ) {
    return validationError();
  }
  const result = await dependencies.browseCatalogue({
    accountId,
    ...location,
    discoveryRadiusMeters,
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

function normalizeRequiredText(value: unknown, maximumLength: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximumLength ? normalized : undefined;
}

function normalizeOptionalText(value: unknown, maximumLength: number): string | null | undefined {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length === 0) return null;
  return normalized.length <= maximumLength ? normalized : undefined;
}

function optionalUUID(value: unknown): string | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function optionalImagePath(value: unknown, accountId: string): string | null | undefined {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return undefined;
  const segments = value.split("/");
  const filename = segments[2] ?? "";
  return segments.length === 3 && segments[0] === "merchant" &&
      segments[1] === accountId && filename.trim().length > 0 &&
      filename !== "." && filename !== ".."
    ? value
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
      message: "The catalogue request is invalid.",
    },
  }, 400);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The catalogue request could not be processed.",
    },
  }, 500);
}
