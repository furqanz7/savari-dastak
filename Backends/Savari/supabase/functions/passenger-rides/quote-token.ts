import type { RideQuoteClaims } from "./handler.ts";

export async function signRideQuote(claims: RideQuoteClaims, secret: string) {
  const payload = new TextEncoder().encode(JSON.stringify(claims));
  const signature = await crypto.subtle.sign("HMAC", await signingKey(secret), payload);
  return `${base64UrlEncode(payload)}.${base64UrlEncode(new Uint8Array(signature))}`;
}

export async function verifyRideQuote(
  token: string,
  secret: string,
  nowEpochSeconds = Math.floor(Date.now() / 1_000),
) {
  const parts = token.split(".");
  if (parts.length !== 2) throw new Error("Invalid quote token");
  const payload = base64UrlDecode(parts[0]);
  const signature = base64UrlDecode(parts[1]);
  const valid = await crypto.subtle.verify("HMAC", await signingKey(secret), signature, payload);
  if (!valid) throw new Error("Invalid quote signature");

  const claims = parseClaims(JSON.parse(new TextDecoder().decode(payload)));
  if (claims.expiresAtEpochSeconds <= nowEpochSeconds) throw new Error("Quote expired");
  return claims;
}

async function signingKey(secret: string) {
  if (secret.length < 32) throw new Error("Quote signing secret is too short");
  return await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function parseClaims(value: unknown): RideQuoteClaims {
  const source = record(value);
  const pickup = ridePoint(source?.pickup);
  const destination = ridePoint(source?.destination);
  if (
    source?.version !== 1 || !uuid(source.accountId) || !pickup || !destination ||
    !positiveInteger(source.distanceMeters) || !positiveInteger(source.durationSeconds) ||
    !positiveInteger(source.autoFarePaise) || !positiveInteger(source.bikeFarePaise) ||
    !positiveInteger(source.expiresAtEpochSeconds)
  ) {
    throw new Error("Invalid quote claims");
  }
  return {
    version: 1,
    accountId: source.accountId as string,
    pickup,
    destination,
    distanceMeters: source.distanceMeters as number,
    durationSeconds: source.durationSeconds as number,
    autoFarePaise: source.autoFarePaise as number,
    bikeFarePaise: source.bikeFarePaise as number,
    expiresAtEpochSeconds: source.expiresAtEpochSeconds as number,
  };
}

function ridePoint(value: unknown) {
  const source = record(value);
  const latitude = source?.latitude;
  const longitude = source?.longitude;
  const label = source?.label;
  const address = source?.address;
  if (
    typeof latitude !== "number" || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) || longitude < -180 ||
    longitude > 180 ||
    typeof label !== "string" || label.length < 1 || label.length > 200 ||
    (address !== undefined &&
      (typeof address !== "string" || address.length < 1 || address.length > 300))
  ) return undefined;
  return { latitude, longitude, label, ...(typeof address === "string" ? { address } : {}) };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function uuid(value: unknown) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function positiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function base64UrlEncode(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(value: string) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(
    Math.ceil(value.length / 4) * 4,
    "=",
  );
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
