import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type GeoPoint = { latitude: number; longitude: number };
export type RidePoint = GeoPoint & { label: string; address?: string };
export type DestinationResult = GeoPoint & { label: string; address: string };
export type RideRoute = { distanceMeters: number; durationSeconds: number };
export type ServiceArea = { center: GeoPoint; radiusMeters: number };
export type FareRate = {
  minimumFarePaise: number;
  baseFarePaise: number;
  perKilometrePaise: number;
};
export type RideRateCards = { auto: FareRate; bike: FareRate };

export type RideQuoteClaims = {
  version: 1;
  accountId: string;
  pickup: RidePoint;
  destination: RidePoint;
  distanceMeters: number;
  durationSeconds: number;
  autoFarePaise: number;
  bikeFarePaise: number;
  expiresAtEpochSeconds: number;
};

export type RideCreateInput = {
  rideId: string;
  accountId: string;
  vehicleType: "Auto" | "Bike";
  pickup: RidePoint;
  destination: RidePoint;
  distanceMeters: number;
  durationSeconds: number;
  farePaise: number;
};

type ApiResult = { responseBody: unknown; responseStatus: number };
type SnapshotInput = { accountId: string; rideId: string | null };
type CancellationInput = {
  accountId: string;
  rideId: string;
  reason: string;
  idempotencyKey: string;
};

export type PassengerRideDependencies = {
  authenticateBearer: AuthenticateBearer;
  searchPlaces: (input: { query: string; userLocation: GeoPoint }) => Promise<DestinationResult[]>;
  routeRide: (input: { pickup: GeoPoint; destination: GeoPoint }) => Promise<RideRoute>;
  signQuote: (claims: RideQuoteClaims) => Promise<string>;
  verifyQuote: (token: string) => Promise<RideQuoteClaims>;
  createRide: (input: RideCreateInput) => Promise<ApiResult>;
  getRideSnapshot: (input: SnapshotInput) => Promise<ApiResult>;
  cancelRide: (input: CancellationInput) => Promise<ApiResult>;
  now: () => Date;
  serviceArea: ServiceArea;
  rateCards: RideRateCards;
};

export class MapsUnavailableError extends Error {
  constructor(public readonly reference: string) {
    super("Maps provider unavailable");
    this.name = "MapsUnavailableError";
  }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handlePassengerRides(
  request: Request,
  dependencies: PassengerRideDependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) {
    return errorResponse("authentication_required", "A valid bearer token is required.", 401);
  }

  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return errorResponse("authentication_required", "A valid bearer token is required.", 401);
  }

  const body = await parseBody(request);
  if (!body || typeof body.operation !== "string") return validationError();

  try {
    switch (body.operation) {
      case "searchDestination":
        return await searchDestination(body, dependencies);
      case "quote":
        return await quoteRide(body, actor.accountId, dependencies);
      case "requestRide":
        return await requestRide(request, body, actor.accountId, dependencies);
      case "snapshot":
        return await snapshot(body, actor.accountId, dependencies);
      case "cancelRide":
        return await cancelRide(request, body, actor.accountId, dependencies);
      default:
        return validationError();
    }
  } catch (error) {
    if (error instanceof MapsUnavailableError) {
      console.error(`[passenger-rides] ${error.reference}`);
      return json({
        error: {
          code: "maps_unavailable",
          message: "Map search or routing is temporarily unavailable.",
          reference: error.reference,
        },
      }, 503);
    }
    return errorResponse("internal_error", "The ride request could not be processed.", 500);
  }
}

async function searchDestination(
  body: Record<string, unknown>,
  dependencies: PassengerRideDependencies,
) {
  const query = normalizedText(body.query, 2, 120);
  const userLocation = geoPoint(body.userLocation);
  if (!query || !userLocation || !insideServiceArea(userLocation, dependencies.serviceArea)) {
    return validationError();
  }

  const results = await dependencies.searchPlaces({ query, userLocation });
  const safeResults = results
    .map(destinationResult)
    .filter((result): result is DestinationResult => result !== undefined)
    .filter((result) => insideServiceArea(result, dependencies.serviceArea))
    .slice(0, 8);
  return json({ results: safeResults });
}

async function quoteRide(
  body: Record<string, unknown>,
  accountId: string,
  dependencies: PassengerRideDependencies,
) {
  const pickup = ridePoint(body.pickup);
  const destination = ridePoint(body.destination);
  if (!pickup || !destination) return validationError();
  if (
    !insideServiceArea(pickup, dependencies.serviceArea) ||
    !insideServiceArea(destination, dependencies.serviceArea)
  ) {
    return errorResponse(
      "outside_service_area",
      "Pickup and destination must be inside the Vaniyambadi service area.",
      422,
    );
  }

  const route = await dependencies.routeRide({ pickup, destination });
  if (!positiveInteger(route.distanceMeters) || !positiveInteger(route.durationSeconds)) {
    throw new MapsUnavailableError("directions-invalid-response");
  }
  const expiresAtEpochSeconds = Math.floor(dependencies.now().getTime() / 1_000) + 300;
  const claims: RideQuoteClaims = {
    version: 1,
    accountId,
    pickup,
    destination,
    distanceMeters: route.distanceMeters,
    durationSeconds: route.durationSeconds,
    autoFarePaise: calculateFarePaise(route.distanceMeters, dependencies.rateCards.auto),
    bikeFarePaise: calculateFarePaise(route.distanceMeters, dependencies.rateCards.bike),
    expiresAtEpochSeconds,
  };
  const quoteToken = await dependencies.signQuote(claims);
  return json({
    quoteToken,
    expiresAt: new Date(expiresAtEpochSeconds * 1_000).toISOString(),
    pickup,
    destination,
    distanceMeters: claims.distanceMeters,
    durationSeconds: claims.durationSeconds,
    fares: {
      auto: { paise: claims.autoFarePaise },
      bike: { paise: claims.bikeFarePaise },
    },
  });
}

async function requestRide(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: PassengerRideDependencies,
) {
  const idempotencyKey = validUUID(request.headers.get("X-Idempotency-Key"));
  const quoteToken = normalizedText(body.quoteToken, 20, 8_000);
  const vehicleType = body.vehicleType === "auto"
    ? "Auto"
    : body.vehicleType === "bike"
    ? "Bike"
    : undefined;
  if (!idempotencyKey || !quoteToken || !vehicleType) return validationError();

  let claims: RideQuoteClaims;
  try {
    claims = await dependencies.verifyQuote(quoteToken);
  } catch {
    return errorResponse("quote_invalid", "The fare quote is invalid or has expired.", 409);
  }
  if (claims.accountId !== accountId) {
    return errorResponse("access_denied", "This fare quote belongs to another account.", 403);
  }
  if (claims.expiresAtEpochSeconds <= Math.floor(dependencies.now().getTime() / 1_000)) {
    return errorResponse("quote_expired", "The fare quote has expired. Request a new quote.", 409);
  }

  const farePaise = vehicleType === "Auto" ? claims.autoFarePaise : claims.bikeFarePaise;
  return apiResult(
    await dependencies.createRide({
      rideId: idempotencyKey,
      accountId,
      vehicleType,
      pickup: claims.pickup,
      destination: claims.destination,
      distanceMeters: claims.distanceMeters,
      durationSeconds: claims.durationSeconds,
      farePaise,
    }),
  );
}

async function snapshot(
  body: Record<string, unknown>,
  accountId: string,
  dependencies: PassengerRideDependencies,
) {
  const rideId = body.rideId === undefined || body.rideId === null ? null : validUUID(body.rideId);
  if (rideId === undefined) return validationError();
  return apiResult(await dependencies.getRideSnapshot({ accountId, rideId }));
}

async function cancelRide(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: PassengerRideDependencies,
) {
  const idempotencyKey = validUUID(request.headers.get("X-Idempotency-Key"));
  const rideId = validUUID(body.rideId);
  const reason = body.reason === undefined
    ? "Passenger cancelled before pickup"
    : normalizedText(body.reason, 1, 300);
  if (!idempotencyKey || !rideId || !reason) return validationError();
  return apiResult(await dependencies.cancelRide({ accountId, rideId, reason, idempotencyKey }));
}

export function calculateFarePaise(distanceMeters: number, rate: FareRate) {
  const distanceFare = rate.baseFarePaise +
    Math.ceil(distanceMeters * rate.perKilometrePaise / 1_000);
  return Math.max(rate.minimumFarePaise, distanceFare);
}

function insideServiceArea(point: GeoPoint, area: ServiceArea) {
  return distanceMeters(point, area.center) <= area.radiusMeters;
}

function distanceMeters(from: GeoPoint, to: GeoPoint) {
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const lat = radians(to.latitude - from.latitude);
  const lon = radians(to.longitude - from.longitude);
  const value = Math.sin(lat / 2) ** 2 + Math.cos(radians(from.latitude)) *
      Math.cos(radians(to.latitude)) * Math.sin(lon / 2) ** 2;
  return 6_371_000 * 2 * Math.asin(Math.sqrt(value));
}

function geoPoint(value: unknown): GeoPoint | undefined {
  const source = record(value);
  const latitude = source?.latitude;
  const longitude = source?.longitude;
  return typeof latitude === "number" && Number.isFinite(latitude) && latitude >= -90 &&
      latitude <= 90 &&
      typeof longitude === "number" && Number.isFinite(longitude) && longitude >= -180 &&
      longitude <= 180
    ? { latitude, longitude }
    : undefined;
}

function ridePoint(value: unknown): RidePoint | undefined {
  const point = geoPoint(value);
  const source = record(value);
  const label = normalizedText(source?.label, 1, 200);
  const hasAddress = source?.address !== undefined;
  const address = hasAddress ? normalizedText(source?.address, 1, 300) : undefined;
  if (!point || !label || (hasAddress && !address)) return undefined;
  return { ...point, label, ...(address ? { address } : {}) };
}

function destinationResult(value: unknown): DestinationResult | undefined {
  const point = geoPoint(value);
  const source = record(value);
  const label = normalizedText(source?.label, 1, 200);
  const address = normalizedText(source?.address, 1, 300);
  return point && label && address ? { ...point, label, address } : undefined;
}

function normalizedText(value: unknown, minimum: number, maximum: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= minimum && normalized.length <= maximum ? normalized : undefined;
}

function validUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function positiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    const value = await request.json();
    return record(value);
  } catch {
    return undefined;
  }
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function apiResult(result: ApiResult) {
  return json(result.responseBody, result.responseStatus);
}

function validationError() {
  return errorResponse("validation_failed", "The ride request is invalid.", 400);
}

function errorResponse(code: string, message: string, status: number) {
  return json({ error: { code, message } }, status);
}
