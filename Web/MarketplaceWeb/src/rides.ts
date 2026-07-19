export type RidePoint = {
  label: string;
  address?: string;
  latitude: number;
  longitude: number;
};

export type DestinationResult = Required<RidePoint>;
export type VehicleChoice = "auto" | "bike";

export type RideQuote = {
  quoteToken: string;
  expiresAt: string;
  pickup: RidePoint;
  destination: DestinationResult;
  distanceMeters: number;
  durationSeconds: number;
  fares: { auto: { paise: number }; bike: { paise: number } };
};

export type RideSnapshot = {
  rideId: string;
  status: string;
  vehicleType: "Auto" | "Bike";
  pickup: RidePoint;
  destination: DestinationResult;
  distanceMeters: number;
  durationSeconds: number;
  fare: { paise: number };
  boardingCode: string | null;
  driver: { displayName: string; phoneNumber: string } | null;
  createdAt: string;
};

type AuthenticatedInput = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class RideRequestError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number,
    public readonly ride: RideSnapshot | null = null,
  ) {
    super(message);
    this.name = "RideRequestError";
  }
}

export async function searchDestinations(
  input: AuthenticatedInput & { query: string; userLocation: RidePoint },
  fetcher: Fetcher = fetch,
) {
  return parseDestinationResults(await call(input, {
    operation: "searchDestination",
    query: input.query,
    userLocation: input.userLocation,
  }, undefined, fetcher));
}

export async function quoteRide(
  input: AuthenticatedInput & { pickup: RidePoint; destination: DestinationResult },
  fetcher: Fetcher = fetch,
) {
  return parseRideQuote(await call(input, {
    operation: "quote",
    pickup: input.pickup,
    destination: input.destination,
  }, undefined, fetcher));
}

export async function requestRide(
  input: AuthenticatedInput & { quoteToken: string; vehicleType: VehicleChoice; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = await call(input, {
    operation: "requestRide",
    quoteToken: input.quoteToken,
    vehicleType: input.vehicleType,
  }, input.idempotencyKey, fetcher);
  const ride = parseRideSnapshot(payload);
  if (!ride) invalid();
  return ride;
}

export async function getRideSnapshot(
  input: AuthenticatedInput & { rideId?: string },
  fetcher: Fetcher = fetch,
) {
  return parseRideSnapshot(await call(input, {
    operation: "snapshot",
    ...(input.rideId ? { rideId: input.rideId } : {}),
  }, undefined, fetcher));
}

export async function cancelRide(
  input: AuthenticatedInput & { rideId: string; reason: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = await call(input, {
    operation: "cancelRide",
    rideId: input.rideId,
    reason: input.reason,
  }, input.idempotencyKey, fetcher);
  const ride = parseRideSnapshot(payload);
  if (!ride) invalid();
  return ride;
}

export function parseDestinationResults(value: unknown) {
  const source = record(value);
  if (!source || !Array.isArray(source.results)) invalid();
  return source.results.map(destinationResult);
}

export function parseRideQuote(value: unknown): RideQuote {
  const source = record(value);
  const fares = record(source?.fares);
  const auto = money(record(fares?.auto));
  const bike = money(record(fares?.bike));
  if (!source || !auto || !bike) invalid();
  return {
    quoteToken: requiredText(source.quoteToken, 8_000),
    expiresAt: timestamp(source.expiresAt),
    pickup: ridePoint(source.pickup),
    destination: destinationResult(source.destination),
    distanceMeters: requiredPositiveInteger(source.distanceMeters),
    durationSeconds: requiredPositiveInteger(source.durationSeconds),
    fares: { auto, bike },
  };
}

export function parseRideSnapshot(value: unknown): RideSnapshot | null {
  const envelope = record(value);
  if (!envelope || !("ride" in envelope)) invalid();
  if (envelope.ride === null) return null;
  const source = record(envelope.ride);
  if (!source || "passengerId" in source || "driverId" in source || "assignedDriverId" in source) invalid();
  const vehicleType = source.vehicleType === "Auto" || source.vehicleType === "Bike" ? source.vehicleType : undefined;
  const boardingCode = source.boardingCode === null || source.boardingCode === undefined
    ? null
    : requiredText(source.boardingCode, 12);
  const driverSource = source.driver === null || source.driver === undefined ? null : record(source.driver);
  const driver = driverSource
    ? {
      displayName: requiredText(driverSource.displayName, 120),
      phoneNumber: optionalText(driverSource.phoneNumber, 20) ?? "",
    }
    : null;
  if (!vehicleType) invalid();
  return {
    rideId: requiredUUID(source.rideId),
    status: requiredText(source.status, 80),
    vehicleType,
    pickup: ridePoint(source.pickup),
    destination: destinationResult(source.destination),
    distanceMeters: requiredNonnegativeInteger(source.distanceMeters),
    durationSeconds: requiredNonnegativeInteger(source.durationSeconds),
    fare: requiredMoney(source.fare),
    boardingCode,
    driver,
    createdAt: timestamp(source.createdAt),
  };
}

export function formatDistance(distanceMeters: number) {
  if (distanceMeters < 1_000) return `${distanceMeters} m`;
  const kilometres = Math.round(distanceMeters / 100) / 10;
  return `${kilometres.toLocaleString("en-IN", { maximumFractionDigits: 1 })} km`;
}

export function formatDuration(durationSeconds: number) {
  return `${Math.max(1, Math.ceil(durationSeconds / 60))} min`;
}

export function formatFare(paise: number) {
  const fraction = paise % 100 !== 0;
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: fraction ? 2 : 0,
    maximumFractionDigits: fraction ? 2 : 0,
  }).format(paise / 100);
}

export function rideStatusLabel(status: string) {
  switch (status) {
    case "requested": return "Finding a rider";
    case "assigned":
    case "en_route_to_pickup": return "Rider assigned";
    case "arrived":
    case "driver_arrived": return "Rider has arrived";
    case "in_progress": return "Trip in progress";
    case "completed":
    case "completed_awaiting_payment":
    case "payment_due":
    case "passenger_cancelled_in_trip": return "Payment due";
    case "payment_collected": return "Ride completed";
    case "cancelled": return "Ride cancelled";
    default: return status.replace(/_/g, " ");
  }
}

export function isCancellableRide(status: string) {
  return ["requested", "assigned", "arrived", "driver_arrived", "en_route_to_pickup"].includes(status);
}

export function isFinishedRide(status: string) {
  return ["cancelled", "payment_collected"].includes(status);
}

async function call(
  auth: AuthenticatedInput,
  body: unknown,
  idempotencyKey: string | undefined,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/passenger-rides`, {
      method: "POST",
      headers: {
        apikey: auth.publishableKey,
        authorization: `Bearer ${auth.accessToken}`,
        "content-type": "application/json",
        ...(idempotencyKey ? { "X-Idempotency-Key": idempotencyKey } : {}),
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new RideRequestError("network_error", "Savari could not reach the ride service.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    const ride = tryRide(payload);
    throw new RideRequestError(
      optionalText(error?.code, 80) ?? "ride_unavailable",
      optionalText(error?.message, 300) ?? "The ride request is unavailable right now.",
      response.status,
      ride,
    );
  }
  return payload;
}

function tryRide(value: unknown) {
  try {
    return parseRideSnapshot(value);
  } catch {
    return null;
  }
}

function destinationResult(value: unknown): DestinationResult {
  const source = record(value);
  if (!source) invalid();
  return {
    label: requiredText(source.label, 200),
    address: requiredText(source.address, 300),
    latitude: coordinate(source.latitude, -90, 90),
    longitude: coordinate(source.longitude, -180, 180),
  };
}

function ridePoint(value: unknown): RidePoint {
  const source = record(value);
  if (!source) invalid();
  const address = source.address === undefined ? undefined : requiredText(source.address, 300);
  return {
    label: requiredText(source.label, 200),
    ...(address ? { address } : {}),
    latitude: coordinate(source.latitude, -90, 90),
    longitude: coordinate(source.longitude, -180, 180),
  };
}

function requiredMoney(value: unknown) {
  const result = money(record(value));
  if (!result) invalid();
  return result;
}

function money(value: Record<string, unknown> | undefined) {
  const paise = value?.paise;
  return typeof paise === "number" && Number.isInteger(paise) && paise >= 0 && paise <= 100_000_000
    ? { paise }
    : undefined;
}

function coordinate(value: unknown, minimum: number, maximum: number) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) invalid();
  return value;
}

function requiredPositiveInteger(value: unknown) {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) invalid();
  return value;
}

function requiredNonnegativeInteger(value: unknown) {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) invalid();
  return value;
}

function requiredUUID(value: unknown) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) invalid();
  return value;
}

function timestamp(value: unknown) {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) invalid();
  return value;
}

function requiredText(value: unknown, maximum: number) {
  const result = optionalText(value, maximum);
  if (result === undefined || result.length === 0) invalid();
  return result;
}

function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length <= maximum ? value : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}

function invalid(): never {
  throw new RideRequestError("invalid_response", "Savari received an invalid ride response.", 502);
}
