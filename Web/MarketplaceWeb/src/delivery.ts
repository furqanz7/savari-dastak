import type { SupabaseClient } from "@supabase/supabase-js";
import type { MerchantOrderStatus, OrderLocation } from "./orders";

export type DeliveryMethod = "walking" | "bicycle" | "bike" | "auto" | "car";
export type PartnerAvailability = {
  status: "online" | "offline";
  location: OrderLocation | null;
  serviceZoneId: string | null;
  availableUntil: string | null;
  stateVersion: number;
};
export type DeliveryPartnerSnapshot = {
  onboardingState: "not_applied" | "pending" | "approved" | "rejected";
  applicationId: string | null;
  deliveryMethod: DeliveryMethod | null;
  vehicleRegistrationNumber: string | null;
  vehicleMakeModel: string | null;
  vehicleEvidenceObjectPath: string | null;
  reviewReason: string | null;
  availability: PartnerAvailability | null;
};
export type DeliveryPartnerVerificationState =
  | "unverified"
  | "identity_verified"
  | "identity_and_vehicle_verified"
  | "vehicle_review_required";
export type DeliveryAssignment = {
  assignmentId: string;
  orderId: string;
  assignmentStatus: "offered" | "accepted";
  orderStatus: MerchantOrderStatus;
  offeredAt: string;
  respondBy: string;
  acceptedAt: string | null;
  distanceMeters: number;
  courierPayout: { paise: number };
  store: {
    storeId: string;
    name: string;
    address: string;
    pickup: OrderLocation;
  };
  dropoff: OrderLocation;
  items: Array<{ productId: string; name: string; unitLabel: string; quantity: number }>;
};
export type DeliveryDispatchSnapshot = {
  offer: DeliveryAssignment | null;
  currentJob: DeliveryAssignment | null;
};

type AuthenticatedInput = { supabaseUrl: string; publishableKey: string; accessToken: string };
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
type EvidenceFile = { type: string; size: number };

export class DeliveryRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "DeliveryRequestError";
  }
}

const evidenceExtensions = new Map([
  ["application/pdf", "pdf"],
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
]);
const maximumEvidenceBytes = 10 * 1024 * 1024;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const deliveryMethods = new Set<DeliveryMethod>(["walking", "bicycle", "bike", "auto", "car"]);
const motorVehicleMethods = new Set<DeliveryMethod>(["bike", "auto", "car"]);
const orderStatuses = new Set<MerchantOrderStatus>([
  "payment_pending", "paid", "merchant_accepted", "ready", "assigned", "en_route_to_pickup",
  "at_store", "picked_up", "in_transit", "delivered", "cancelled", "returning_to_merchant",
]);

export function isAcceptedPartnerEvidence(file: EvidenceFile) {
  return evidenceExtensions.has(file.type) && file.size > 0 && file.size <= maximumEvidenceBytes;
}

export function requiresVehicleVerification(method: DeliveryMethod) {
  return motorVehicleMethods.has(method);
}

export function deliveryPartnerVerificationState(
  partner: Pick<
    DeliveryPartnerSnapshot,
    "onboardingState" | "deliveryMethod" | "vehicleRegistrationNumber" |
    "vehicleMakeModel" | "vehicleEvidenceObjectPath"
  >,
): DeliveryPartnerVerificationState {
  if (partner.onboardingState !== "approved" || !partner.deliveryMethod) return "unverified";
  if (!requiresVehicleVerification(partner.deliveryMethod)) return "identity_verified";
  return [
    partner.vehicleRegistrationNumber,
    partner.vehicleMakeModel,
    partner.vehicleEvidenceObjectPath,
  ].every((value) => Boolean(value?.trim()))
    ? "identity_and_vehicle_verified"
    : "vehicle_review_required";
}

export function normalizeVehicleRegistration(value: string) {
  return value.trim().replace(/\s+/g, " ").toUpperCase();
}

export function isValidVehicleRegistration(value: string) {
  const normalized = normalizeVehicleRegistration(value);
  return normalized.length >= 4 && normalized.length <= 20 && /^[A-Z0-9 -]+$/.test(normalized);
}

export function partnerEvidenceObjectPath(
  accountId: string,
  contentType: string,
  uniqueId: string,
  kind: "identity" | "vehicle" = "identity",
) {
  const extension = evidenceExtensions.get(contentType);
  if (!uuidPattern.test(accountId) || !uuidPattern.test(uniqueId) || !extension) throw validationError();
  return `dastak-partner/${accountId.toLowerCase()}/${kind}-${uniqueId.toLowerCase()}.${extension}`;
}

export async function uploadPartnerEvidence(
  client: SupabaseClient,
  accountId: string,
  file: File,
  kind: "identity" | "vehicle" = "identity",
) {
  if (!isAcceptedPartnerEvidence(file)) throw validationError("Choose a PDF, JPG or PNG file up to 10 MB.");
  const objectPath = partnerEvidenceObjectPath(accountId, file.type, crypto.randomUUID(), kind);
  const { error } = await client.storage.from("dastak-evidence").upload(objectPath, file, {
    cacheControl: "3600",
    contentType: file.type,
    upsert: false,
  });
  if (error) throw new DeliveryRequestError(
    "evidence_upload_failed",
    kind === "vehicle" ? "The vehicle document could not be uploaded." : "The identity document could not be uploaded.",
    0,
  );
  return objectPath;
}

export async function submitDeliveryPartnerApplication(
  input: AuthenticatedInput & {
    deliveryMethod: DeliveryMethod;
    identityEvidenceObjectPath: string;
    vehicleRegistrationNumber?: string | null;
    vehicleMakeModel?: string | null;
    vehicleEvidenceObjectPath?: string | null;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  if (!deliveryMethods.has(input.deliveryMethod) || !input.identityEvidenceObjectPath) throw validationError();
  const vehicleRequired = requiresVehicleVerification(input.deliveryMethod);
  const registration = input.vehicleRegistrationNumber
    ? normalizeVehicleRegistration(input.vehicleRegistrationNumber)
    : null;
  const makeModel = input.vehicleMakeModel?.trim().replace(/\s+/g, " ") || null;
  const vehicleEvidence = input.vehicleEvidenceObjectPath || null;
  if (vehicleRequired && (
    !registration || !isValidVehicleRegistration(registration) ||
    !makeModel || makeModel.length < 2 || makeModel.length > 80 ||
    !vehicleEvidence || vehicleEvidence === input.identityEvidenceObjectPath
  )) {
    throw validationError("Add valid vehicle details and registration proof.");
  }
  if (!vehicleRequired && (registration || makeModel || vehicleEvidence)) throw validationError();
  const payload = record(await call("delivery-partners", input, {
    operation: "submit",
    deliveryMethod: input.deliveryMethod,
    identityEvidenceObjectPath: input.identityEvidenceObjectPath,
    vehicleRegistrationNumber: vehicleRequired ? registration : null,
    vehicleMakeModel: vehicleRequired ? makeModel : null,
    vehicleEvidenceObjectPath: vehicleRequired ? vehicleEvidence : null,
  }, input.idempotencyKey, fetcher));
  if (!payload || payload.status !== "pending") invalid();
  return {
    applicationId: requiredUUID(payload.applicationId),
    status: "pending" as const,
    deliveryMethod: requiredDeliveryMethod(payload.deliveryMethod),
  };
}

export async function getDeliveryPartnerSnapshot(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  return parsePartnerSnapshot(await call(
    "delivery-partners",
    input,
    { operation: "selfSnapshot" },
    undefined,
    fetcher,
  ));
}

export async function setDeliveryPartnerAvailability(
  input: AuthenticatedInput & { online: boolean; location?: OrderLocation; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  if (input.online && !input.location) throw validationError("Current location is required to go online.");
  return parseAvailability(await call("delivery-partners", input, {
    operation: "setAvailability",
    online: input.online,
    ...(input.online ? { location: input.location } : {}),
  }, input.idempotencyKey, fetcher));
}

export async function publishDeliveryPartnerLocation(
  input: AuthenticatedInput & { location: OrderLocation; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseAvailability(await call("delivery-partners", input, {
    operation: "publishLocation",
    location: input.location,
  }, input.idempotencyKey, fetcher));
}

export async function getDeliveryDispatch(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  return parseDispatch(await call("courier-dispatch", input, { operation: "partnerSnapshot" }, undefined, fetcher));
}

export async function acceptDeliveryOffer(
  input: AuthenticatedInput & { assignmentId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return dispatchMutation(input, { operation: "acceptOffer", assignmentId: input.assignmentId }, fetcher);
}

export async function declineDeliveryOffer(
  input: AuthenticatedInput & { assignmentId: string; reason?: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return dispatchMutation(input, {
    operation: "declineOffer",
    assignmentId: input.assignmentId,
    reason: input.reason?.trim() || null,
  }, fetcher);
}

export type DeliveryJobOperation =
  | "startToStore"
  | "arriveAtStore"
  | "confirmPickup"
  | "startDelivery"
  | "completeDelivery";

export async function advanceDeliveryJob(
  input: AuthenticatedInput & {
    assignmentId: string;
    operation: DeliveryJobOperation;
    verificationCode?: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  const needsCode = input.operation === "confirmPickup" || input.operation === "completeDelivery";
  if (needsCode && !/^\d{4}$/.test(input.verificationCode ?? "")) {
    throw validationError("Enter the four-digit handoff code.");
  }
  return dispatchMutation(input, {
    operation: input.operation,
    assignmentId: input.assignmentId,
    ...(needsCode ? { verificationCode: input.verificationCode } : {}),
  }, fetcher);
}

async function dispatchMutation(
  input: AuthenticatedInput & { idempotencyKey: string },
  body: unknown,
  fetcher: Fetcher,
) {
  return parseDispatch(await call("courier-dispatch", input, body, input.idempotencyKey, fetcher));
}

async function call(
  service: "delivery-partners" | "courier-dispatch",
  auth: AuthenticatedInput,
  body: unknown,
  idempotencyKey: string | undefined,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/${service}`, {
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
    throw new DeliveryRequestError("network_error", "Dastak could not reach the delivery service.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new DeliveryRequestError(
      optionalText(error?.code, 80) ?? "delivery_unavailable",
      optionalText(error?.message, 300) ?? "The delivery request is unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function parsePartnerSnapshot(value: unknown): DeliveryPartnerSnapshot {
  const source = record(value);
  const onboardingState = source?.onboardingState;
  if (!source || !["not_applied", "pending", "approved", "rejected"].includes(String(onboardingState))) invalid();
  return {
    onboardingState: onboardingState as DeliveryPartnerSnapshot["onboardingState"],
    applicationId: source.applicationId === null ? null : requiredUUID(source.applicationId),
    deliveryMethod: source.deliveryMethod === null ? null : requiredDeliveryMethod(source.deliveryMethod),
    vehicleRegistrationNumber: nullableText(source.vehicleRegistrationNumber, 20),
    vehicleMakeModel: nullableText(source.vehicleMakeModel, 80),
    vehicleEvidenceObjectPath: nullableText(source.vehicleEvidenceObjectPath, 500),
    reviewReason: source.reviewReason === null || source.reviewReason === undefined
      ? null
      : requiredText(source.reviewReason, 500),
    availability: source.availability === null ? null : parseAvailability(source.availability),
  };
}

function parseAvailability(value: unknown): PartnerAvailability {
  const source = record(value);
  const status = source?.status;
  const stateVersion = source?.stateVersion;
  if (!source || (status !== "online" && status !== "offline") ||
    typeof stateVersion !== "number" || !Number.isSafeInteger(stateVersion) || stateVersion < 1) invalid();
  if (status === "offline") {
    if (source.location !== null || source.serviceZoneId !== null || source.availableUntil !== null) invalid();
    return { status, location: null, serviceZoneId: null, availableUntil: null, stateVersion };
  }
  return {
    status,
    location: location(source.location),
    serviceZoneId: requiredUUID(source.serviceZoneId),
    availableUntil: timestamp(source.availableUntil),
    stateVersion,
  };
}

function parseDispatch(value: unknown): DeliveryDispatchSnapshot {
  const source = record(value);
  if (!source || !("offer" in source) || !("currentJob" in source)) invalid();
  return {
    offer: source.offer === null ? null : assignment(source.offer),
    currentJob: source.currentJob === null ? null : assignment(source.currentJob),
  };
}

function assignment(value: unknown): DeliveryAssignment {
  const source = record(value);
  const assignmentStatus = source?.assignmentStatus;
  const orderStatus = source?.orderStatus;
  const store = record(source?.store);
  const items = source?.items;
  const distanceMeters = source?.distanceMeters;
  if (!source || ["customerAccountId", "merchantAccountId", "partnerAccountId", "courierAccountId"].some((key) => key in source) ||
    !store || !Array.isArray(items) || items.length > 50 ||
    (assignmentStatus !== "offered" && assignmentStatus !== "accepted") ||
    !orderStatuses.has(orderStatus as MerchantOrderStatus) ||
    typeof distanceMeters !== "number" || !Number.isFinite(distanceMeters) || distanceMeters < 0) invalid();
  return {
    assignmentId: requiredUUID(source.assignmentId),
    orderId: requiredUUID(source.orderId),
    assignmentStatus,
    orderStatus: orderStatus as MerchantOrderStatus,
    offeredAt: timestamp(source.offeredAt),
    respondBy: timestamp(source.respondBy),
    acceptedAt: source.acceptedAt === null ? null : timestamp(source.acceptedAt),
    distanceMeters,
    courierPayout: money(source.courierPayout),
    store: {
      storeId: requiredUUID(store.storeId),
      name: requiredText(store.name, 160),
      address: requiredText(store.address, 500),
      pickup: location(store.pickup),
    },
    dropoff: location(source.dropoff),
    items: items.map((value) => {
      const item = record(value);
      const quantity = item?.quantity;
      if (!item || typeof quantity !== "number" || !Number.isInteger(quantity) || quantity < 1 || quantity > 99) invalid();
      return {
        productId: requiredUUID(item.productId),
        name: requiredText(item.name, 160),
        unitLabel: requiredText(item.unitLabel, 40),
        quantity,
      };
    }),
  };
}

function money(value: unknown) {
  const source = record(value);
  const paise = source?.paise;
  if (typeof paise !== "number" || !Number.isSafeInteger(paise) || paise < 0 || paise > 100_000_000) invalid();
  return { paise };
}

function location(value: unknown): OrderLocation {
  const source = record(value);
  const latitude = source?.latitude;
  const longitude = source?.longitude;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) invalid();
  return { latitude, longitude };
}

function requiredDeliveryMethod(value: unknown) {
  if (!deliveryMethods.has(value as DeliveryMethod)) invalid();
  return value as DeliveryMethod;
}
function requiredUUID(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}
function timestamp(value: unknown) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) invalid();
  return value;
}
function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}
function nullableText(value: unknown, maximum: number) {
  return value === null || value === undefined ? null : requiredText(value, maximum);
}
function requiredText(value: unknown, maximum: number) {
  const text = optionalText(value, maximum);
  if (!text) invalid();
  return text;
}
function validationError(message = "The delivery request is invalid.") {
  return new DeliveryRequestError("validation_failed", message, 400);
}
function invalid(): never {
  throw new DeliveryRequestError("invalid_response", "Dastak received an invalid delivery response.", 502);
}
