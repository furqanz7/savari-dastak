import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type DestinationResult,
  type GeoPoint,
  handlePassengerRides,
  MapsUnavailableError,
  type RideCreateInput,
  type RideQuoteClaims,
  type RideRateCards,
  type ServiceArea,
} from "./handler.ts";
import { signRideQuote, verifyRideQuote } from "./quote-token.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

const serviceArea: ServiceArea = {
  center: {
    latitude: envNumber("SAVARI_SERVICE_CENTER_LATITUDE", 12.6819),
    longitude: envNumber("SAVARI_SERVICE_CENTER_LONGITUDE", 78.6201),
  },
  radiusMeters: envInteger("SAVARI_SERVICE_RADIUS_METERS", 12_000),
};

const rateCards: RideRateCards = {
  auto: {
    minimumFarePaise: envInteger("SAVARI_AUTO_MINIMUM_FARE_PAISE", 5_000),
    baseFarePaise: envInteger("SAVARI_AUTO_BASE_FARE_PAISE", 2_000),
    perKilometrePaise: envInteger("SAVARI_AUTO_PER_KILOMETRE_PAISE", 1_200),
  },
  bike: {
    minimumFarePaise: envInteger("SAVARI_BIKE_MINIMUM_FARE_PAISE", 3_000),
    baseFarePaise: envInteger("SAVARI_BIKE_BASE_FARE_PAISE", 1_000),
    perKilometrePaise: envInteger("SAVARI_BIKE_PER_KILOMETRE_PAISE", 800),
  },
};

let cachedMapsAccessToken: { value: string; expiresAtMilliseconds: number } | undefined;

Deno.serve((request) =>
  handlePassengerRides(request, {
    authenticateBearer: verifyBearerUser,
    searchPlaces,
    routeRide,
    signQuote: (claims) => signRideQuote(claims, quoteSecret()),
    verifyQuote: (token) => verifyRideQuote(token, quoteSecret()),
    createRide,
    getRideSnapshot,
    cancelRide,
    now: () => new Date(),
    serviceArea,
    rateCards,
  })
);

async function searchPlaces(input: { query: string; userLocation: GeoPoint }) {
  const url = new URL("https://maps-api.apple.com/v1/search");
  url.searchParams.set("q", input.query);
  url.searchParams.set("userLocation", coordinate(input.userLocation));
  url.searchParams.set("searchRegion", searchRegion(serviceArea));
  url.searchParams.set("searchRegionPriority", "required");
  url.searchParams.set("limitToCountries", "IN");
  url.searchParams.set("lang", "en-IN");

  const response = await appleMapsRequest(url, "search");
  const payload = record(await response.json().catch(() => undefined));
  if (!payload || !Array.isArray(payload.results)) {
    throw new MapsUnavailableError("search-invalid-response");
  }
  return payload.results.map(mapPlace).filter((place): place is DestinationResult =>
    Boolean(place)
  );
}

async function routeRide(input: { pickup: GeoPoint; destination: GeoPoint }) {
  const url = new URL("https://maps-api.apple.com/v1/directions");
  url.searchParams.set("origin", coordinate(input.pickup));
  url.searchParams.set("destination", coordinate(input.destination));
  url.searchParams.set("transportType", "Automobile");
  url.searchParams.set("lang", "en-IN");

  const response = await appleMapsRequest(url, "directions");
  const payload = record(await response.json().catch(() => undefined));
  const route = Array.isArray(payload?.routes) ? record(payload.routes[0]) : undefined;
  if (!route || !positiveInteger(route.distanceMeters) || !positiveInteger(route.durationSeconds)) {
    throw new MapsUnavailableError("directions-invalid-response");
  }
  return { distanceMeters: route.distanceMeters, durationSeconds: route.durationSeconds };
}

async function appleMapsRequest(url: URL, operation: "search" | "directions") {
  const token = await appleMapsAccessToken();
  let response: Response;
  try {
    response = await fetch(url, {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new MapsUnavailableError(`${operation}-network-error`);
  }
  if (!response.ok) {
    const responseText = await response.text().catch(() => "");
    const payload = record(parseJSON(responseText));
    const detail = redactedAppleError(payload, responseText, url);
    if (detail) console.error(`[passenger-rides] apple-${operation}-${response.status} ${detail}`);
    throw new MapsUnavailableError(`${operation}-http-${response.status}`);
  }
  return response;
}

async function appleMapsAccessToken() {
  const direct = Deno.env.get("APPLE_MAPS_ACCESS_TOKEN");
  if (direct) return direct;
  if (cachedMapsAccessToken && cachedMapsAccessToken.expiresAtMilliseconds > Date.now() + 60_000) {
    return cachedMapsAccessToken.value;
  }

  const authorizationToken = Deno.env.get("APPLE_MAPS_AUTH_TOKEN");
  if (!authorizationToken) throw new MapsUnavailableError("token-not-configured");
  let response: Response;
  try {
    response = await fetch("https://maps-api.apple.com/v1/token", {
      headers: { authorization: `Bearer ${authorizationToken}` },
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new MapsUnavailableError("token-network-error");
  }
  if (!response.ok) {
    throw new MapsUnavailableError(`token-http-${response.status}`);
  }
  const payload = record(await response.json().catch(() => undefined));
  const accessToken = string(payload?.accessToken);
  const expiresInSeconds = payload?.expiresInSeconds;
  if (!accessToken || !positiveInteger(expiresInSeconds)) {
    throw new MapsUnavailableError("token-invalid-response");
  }
  cachedMapsAccessToken = {
    value: accessToken,
    expiresAtMilliseconds: Date.now() + expiresInSeconds * 1_000,
  };
  return accessToken;
}

async function createRide(input: RideCreateInput) {
  if (!await isPassenger(input.accountId)) {
    return apiError("access_denied", "An active passenger profile is required.", 403);
  }

  const existing = await rideById(input.rideId);
  if (existing) {
    return existing.passenger_id === input.accountId
      ? { responseBody: { ride: await safeRide(existing) }, responseStatus: 200 }
      : apiError("idempotency_conflict", "This request identifier is already in use.", 409);
  }

  const active = await activeRide(input.accountId);
  if (active) {
    return {
      responseBody: {
        error: {
          code: "active_ride_exists",
          message: "Finish or cancel the current ride before requesting another.",
        },
        ride: await safeRide(active),
      },
      responseStatus: 409,
    };
  }

  const { data, error } = await serviceClient.from("rides").insert({
    id: input.rideId,
    passenger_id: input.accountId,
    pickup_lat: input.pickup.latitude,
    pickup_lon: input.pickup.longitude,
    drop_lat: input.destination.latitude,
    drop_lon: input.destination.longitude,
    vehicle_type: input.vehicleType,
    estimated_fare: input.farePaise / 100,
    estimated_distance_m: input.distanceMeters,
    estimated_eta_secs: input.durationSeconds,
    status: "requested",
  }).select(rideFields).single();
  if (error) {
    if (error.code === "23505") {
      const replay = await rideById(input.rideId);
      if (replay?.passenger_id === input.accountId) {
        return { responseBody: { ride: await safeRide(replay) }, responseStatus: 200 };
      }
    }
    throw error;
  }
  return { responseBody: { ride: await safeRide(data) }, responseStatus: 201 };
}

async function getRideSnapshot(input: { accountId: string; rideId: string | null }) {
  const ride = input.rideId ? await rideById(input.rideId) : await activeRide(input.accountId);
  if (!ride || ride.passenger_id !== input.accountId) {
    return { responseBody: { ride: null }, responseStatus: 200 };
  }
  return { responseBody: { ride: await safeRide(ride) }, responseStatus: 200 };
}

async function cancelRide(input: { accountId: string; rideId: string }) {
  const existing = await rideById(input.rideId);
  if (!existing || existing.passenger_id !== input.accountId) {
    return apiError("access_denied", "The ride is unavailable.", 403);
  }
  if (existing.status === "cancelled") {
    return { responseBody: { ride: await safeRide(existing) }, responseStatus: 200 };
  }
  if (!cancellableStatuses.includes(existing.status)) {
    return apiError(
      "ride_state_conflict",
      "This ride can no longer be cancelled from the web app.",
      409,
    );
  }

  const now = new Date().toISOString();
  const { data, error } = await serviceClient.from("rides").update({
    status: "cancelled",
    cancelled_at: now,
    cancelled_by: "passenger",
    ended_at: now,
  }).eq("id", input.rideId).eq("passenger_id", input.accountId)
    .in("status", cancellableStatuses).select(rideFields).maybeSingle();
  if (error) throw error;
  if (!data) {
    return apiError("ride_state_conflict", "The ride changed before cancellation completed.", 409);
  }
  return { responseBody: { ride: await safeRide(data) }, responseStatus: 200 };
}

async function isPassenger(accountId: string) {
  const { data, error } = await serviceClient.from("profiles")
    .select("role,has_user_profile").eq("id", accountId).maybeSingle();
  if (error) throw error;
  return data?.has_user_profile === true || data?.role?.toLowerCase() === "passenger";
}

async function rideById(rideId: string) {
  const { data, error } = await serviceClient.from("rides").select(rideFields).eq("id", rideId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function activeRide(accountId: string) {
  const { data, error } = await serviceClient.from("rides").select(rideFields)
    .eq("passenger_id", accountId).in("status", activeStatuses)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (error) throw error;
  return data;
}

async function safeRide(row: Record<string, unknown>) {
  const driverId = string(row.driver_id) ?? string(row.assigned_driver_id);
  let driver: { displayName: string; phoneNumber: string } | null = null;
  if (driverId) {
    const { data, error } = await serviceClient.from("profiles").select("name,phone").eq(
      "id",
      driverId,
    ).maybeSingle();
    if (error) throw error;
    if (data) {
      driver = {
        displayName: data.name?.trim() || "Savari rider",
        phoneNumber: data.phone?.trim() || "",
      };
    }
  }

  const fareRupees = numeric(row.fare) ?? numeric(row.cancellation_fare) ??
    numeric(row.estimated_fare);
  return {
    rideId: requiredString(row.id),
    status: requiredString(row.status),
    vehicleType: requiredString(row.vehicle_type),
    pickup: {
      label: "Pickup",
      latitude: requiredNumber(row.pickup_lat),
      longitude: requiredNumber(row.pickup_lon),
    },
    destination: {
      label: "Destination",
      address: "Selected destination",
      latitude: requiredNumber(row.drop_lat),
      longitude: requiredNumber(row.drop_lon),
    },
    distanceMeters: Math.round(numeric(row.estimated_distance_m) ?? 0),
    durationSeconds: Math.round(numeric(row.estimated_eta_secs) ?? 0),
    fare: { paise: Math.round((fareRupees ?? 0) * 100) },
    boardingCode: string(row.boarding_code),
    driver,
    createdAt: requiredString(row.created_at),
  };
}

function mapPlace(value: unknown): DestinationResult | undefined {
  const source = record(value);
  const point = record(source?.coordinate);
  const latitude = point?.latitude;
  const longitude = point?.longitude;
  const lines = Array.isArray(source?.formattedAddressLines)
    ? source.formattedAddressLines.filter((line): line is string =>
      typeof line === "string" && line.trim().length > 0
    )
    : [];
  const label = string(source?.name) ?? lines[0];
  const address = lines.join(", ");
  return label && address && typeof latitude === "number" && Number.isFinite(latitude) &&
      typeof longitude === "number" && Number.isFinite(longitude)
    ? { label, address, latitude, longitude }
    : undefined;
}

function coordinate(point: GeoPoint) {
  return `${point.latitude},${point.longitude}`;
}

function searchRegion(area: ServiceArea) {
  const latitudeDelta = area.radiusMeters / 111_320;
  const longitudeDelta = area.radiusMeters /
    (111_320 * Math.max(0.1, Math.cos(area.center.latitude * Math.PI / 180)));
  return [
    area.center.latitude + latitudeDelta,
    area.center.longitude + longitudeDelta,
    area.center.latitude - latitudeDelta,
    area.center.longitude - longitudeDelta,
  ].join(",");
}

function redactedAppleError(
  payload: Record<string, unknown> | undefined,
  responseText: string,
  url: URL,
) {
  const details = Array.isArray(payload?.details)
    ? payload.details.filter((value): value is string => typeof value === "string")
    : [];
  let summary = [string(payload?.message), ...details].filter(Boolean).join(" | ") || responseText;
  for (const value of url.searchParams.values()) {
    if (value) summary = summary.replaceAll(value, "[value]");
  }
  return summary.replace(/-?\d+(?:\.\d+)?/g, "[number]").slice(0, 300);
}

function parseJSON(value: string) {
  try {
    return JSON.parse(value);
  } catch {
    return undefined;
  }
}

function apiError(code: string, message: string, responseStatus: number) {
  return { responseBody: { error: { code, message } }, responseStatus };
}

function quoteSecret() {
  return requiredEnv("SAVARI_QUOTE_SIGNING_SECRET");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function envInteger(name: string, fallback: number) {
  const value = Deno.env.get(name);
  if (!value) return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

function envNumber(name: string, fallback: number) {
  const value = Deno.env.get(name);
  if (!value) return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`${name} must be a number`);
  return parsed;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function string(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function requiredString(value: unknown) {
  const result = string(value);
  if (!result) throw new Error("Ride row is missing text");
  return result;
}

function numeric(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function requiredNumber(value: unknown) {
  const result = numeric(value);
  if (result === undefined) throw new Error("Ride row is missing a number");
  return result;
}

function positiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

const rideFields =
  "id,passenger_id,pickup_lat,pickup_lon,drop_lat,drop_lon,vehicle_type,estimated_fare,estimated_distance_m,estimated_eta_secs,status,driver_id,assigned_driver_id,boarding_code,created_at,cancellation_fare,fare";
const cancellableStatuses = [
  "requested",
  "assigned",
  "arrived",
  "driver_arrived",
  "en_route_to_pickup",
];
const activeStatuses = [
  ...cancellableStatuses,
  "in_progress",
  "completed",
  "completed_awaiting_payment",
  "payment_due",
  "passenger_cancelled_in_trip",
];
