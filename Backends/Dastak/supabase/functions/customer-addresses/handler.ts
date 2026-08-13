import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type SaveCustomerAddressInput = {
  accountId: string;
  label: string;
  address: string;
  details: string;
  latitude: number;
  longitude: number;
  idempotencyKey: string;
  requestDigest: string;
};

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  snapshot: (accountId: string) => Promise<RpcResult>;
  saveDefault: (input: SaveCustomerAddressInput) => Promise<RpcResult>;
};

export async function handleCustomerAddresses(
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

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  if (body?.operation === "snapshot") {
    try {
      return rpcResponse(await dependencies.snapshot(actor.accountId));
    } catch {
      return json({
        error: { code: "internal_error", message: "Saved addresses could not be loaded." },
      }, 500);
    }
  }
  if (body?.operation !== "saveDefault") return validationError();

  const normalized = normalizeAddress(body);
  const idempotencyKey = request.headers.get("x-idempotency-key")?.trim() ?? "";
  if (!normalized || !idempotencyKey) return validationError();

  try {
    return rpcResponse(
      await dependencies.saveDefault({
        accountId: actor.accountId,
        ...normalized,
        idempotencyKey,
        requestDigest: await canonicalAddressDigest(normalized),
      }),
    );
  } catch {
    return json({
      error: { code: "internal_error", message: "The delivery address could not be saved." },
    }, 500);
  }
}

export async function canonicalAddressDigest(
  input: Omit<SaveCustomerAddressInput, "accountId" | "idempotencyKey" | "requestDigest">,
) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(input)),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeAddress(body: Record<string, unknown>) {
  const clean = (value: unknown, maximum: number) => {
    if (typeof value !== "string") return null;
    const normalized = value.trim().replace(/\s+/g, " ");
    return normalized.length >= 1 && normalized.length <= maximum ? normalized : null;
  };
  const label = clean(body.label, 40);
  const address = clean(body.address, 300);
  const details = clean(body.details, 300);
  const location = body.location;
  if (!location || typeof location !== "object") return null;
  const latitude = "latitude" in location ? location.latitude : null;
  const longitude = "longitude" in location ? location.longitude : null;
  if (
    !label || !address || !details || typeof latitude !== "number" ||
    typeof longitude !== "number" || !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) || latitude < -90 || latitude > 90 ||
    longitude < -180 || longitude > 180
  ) return null;
  return { label, address, details, latitude, longitude };
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
