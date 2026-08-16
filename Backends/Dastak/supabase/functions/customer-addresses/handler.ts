import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type SaveCustomerAddressInput = {
  accountId: string;
  addressId?: string;
  label: string;
  address: string;
  building: string;
  floor?: string;
  landmark?: string;
  deliveryNotes?: string;
  latitude: number;
  longitude: number;
  makeDefault: boolean;
  idempotencyKey: string;
  requestDigest: string;
};

export type AddressActionInput = {
  accountId: string;
  addressId: string;
  idempotencyKey: string;
  requestDigest: string;
};

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  snapshot: (accountId: string) => Promise<RpcResult>;
  save: (input: SaveCustomerAddressInput) => Promise<RpcResult>;
  setDefault: (input: AddressActionInput) => Promise<RpcResult>;
  deleteAddress: (input: AddressActionInput) => Promise<RpcResult>;
};

export async function handleCustomerAddresses(request: Request, dependencies: Dependencies) {
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

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  if (!body) return validationError();
  if (body.operation === "snapshot") {
    return runRpc(() => dependencies.snapshot(actor.accountId), "Saved addresses could not be loaded.");
  }

  const idempotencyKey = request.headers.get("x-idempotency-key")?.trim() ?? "";
  if (!idempotencyKey) return validationError();

  if (body.operation === "save" || body.operation === "saveDefault") {
    const normalized = body.operation === "saveDefault"
      ? normalizeLegacyAddress(body)
      : normalizeAddress(body);
    if (!normalized) return validationError();
    return runRpc(
      async () => dependencies.save({
        accountId: actor.accountId,
        ...normalized,
        idempotencyKey,
        requestDigest: await canonicalDigest(normalized),
      }),
      "The delivery address could not be saved.",
    );
  }

  if (body.operation === "setDefault" || body.operation === "delete") {
    const addressId = uuid(body.addressId);
    if (!addressId) return validationError();
    const input = {
      accountId: actor.accountId,
      addressId,
      idempotencyKey,
      requestDigest: await canonicalDigest({ addressId }),
    };
    return runRpc(
      () => body.operation === "setDefault"
        ? dependencies.setDefault(input)
        : dependencies.deleteAddress(input),
      body.operation === "setDefault"
        ? "The checkout address could not be selected."
        : "The saved address could not be removed.",
    );
  }

  return validationError();
}

export async function canonicalDigest(input: unknown) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(input)),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeAddress(body: Record<string, unknown>) {
  const label = requiredText(body.label, 40);
  const address = requiredText(body.address, 300);
  const building = requiredText(body.building, 180);
  const floor = optionalText(body.floor, 80);
  const landmark = optionalText(body.landmark, 110);
  const deliveryNotes = optionalText(body.deliveryNotes, 240);
  const addressId = body.addressId === undefined || body.addressId === null
    ? undefined
    : uuid(body.addressId);
  const location = coordinates(body.location);
  if (!label || !address || !building || !location ||
    ((body.addressId !== undefined && body.addressId !== null) && !addressId) ||
    (body.floor !== undefined && body.floor !== null && floor === null) ||
    (body.landmark !== undefined && body.landmark !== null && landmark === null) ||
    (body.deliveryNotes !== undefined && body.deliveryNotes !== null && deliveryNotes === null) ||
    (body.makeDefault !== undefined && typeof body.makeDefault !== "boolean")) return null;
  return {
    addressId,
    label,
    address,
    building,
    floor: floor ?? undefined,
    landmark: landmark ?? undefined,
    deliveryNotes: deliveryNotes ?? undefined,
    ...location,
    makeDefault: body.makeDefault !== false,
  };
}

function normalizeLegacyAddress(body: Record<string, unknown>) {
  const label = requiredText(body.label, 40);
  const address = requiredText(body.address, 300);
  const building = requiredText(body.details, 180);
  const location = coordinates(body.location);
  if (!label || !address || !building || !location) return null;
  return { label, address, building, ...location, makeDefault: true };
}

function coordinates(value: unknown) {
  if (!value || typeof value !== "object") return null;
  const latitude = "latitude" in value ? value.latitude : null;
  const longitude = "longitude" in value ? value.longitude : null;
  if (typeof latitude !== "number" || typeof longitude !== "number" ||
    !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
    latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}

function requiredText(value: unknown, maximum: number) {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : null;
}

function optionalText(value: unknown, maximum: number) {
  if (value === undefined || value === null || value === "") return undefined;
  return requiredText(value, maximum);
}

function uuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
}

async function runRpc(operation: () => Promise<RpcResult>, fallback: string) {
  try {
    return rpcResponse(await operation());
  } catch {
    return json({ error: { code: "internal_error", message: fallback } }, 500);
  }
}

function rpcResponse(result: RpcResult) {
  return json(result.responseBody, result.responseStatus);
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "A complete delivery address is required." },
  }, 400);
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
