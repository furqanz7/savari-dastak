import type { SupabaseClient } from "@supabase/supabase-js";
import type { MerchantOrderStatus, OrderLocation } from "./orders";

export type DeliveryMethod =
  | "walking"
  | "bicycle"
  | "retired"
  | "bike"
  | "motorbike"
  | "scooter"
  | "auto"
  | "goods_vehicle";
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
export type V1TransportType =
  | "WALKING"
  | "BICYCLE"
  | "MOTORBIKE"
  | "SCOOTER"
  | "AUTO"
  | "CAR";
export type V1OrderLoad = {
  totalWeightGrams: number;
  totalVolumeCubicMillimetres: number;
  longestSideMillimetres: number;
  containsBulky: boolean;
  eligibleTransportTypes: V1TransportType[];
};
export type V1ArrivalEligibility = {
  eligible: boolean;
  reason: string;
  distanceMeters: number | null;
  radiusMeters: number;
  validUntil: string | null;
};

export function canArriveAtDestination(arrival: V1ArrivalEligibility | null | undefined, now = Date.now()) {
  return arrival?.eligible === true && arrival.validUntil !== null &&
    Date.parse(arrival.validUntil) > now;
}

export type V1PickupStop = {
  id: string;
  sequence: number;
  status?: "PENDING" | "ARRIVED" | "COMPLETED";
  ready: boolean;
  runningLate: boolean;
  estimatedReadyAt: string;
  actualReadyAt: string | null;
  packageCount: number | null;
  arrivedAt: string | null;
  waitingSeconds: number;
  arrival?: V1ArrivalEligibility | null;
  branch: {
    id: string | null;
    displayName: string;
    address: string;
    location: OrderLocation | null;
  };
};
export type V1RiderOffer = {
  id: string;
  missionId: string;
  displayOrderNumber: string;
  status: "OFFERED";
  poolRound: number;
  transportType: V1TransportType;
  distanceMeters: number;
  offeredAt: string;
  respondBy: string;
  secondsRemaining: number;
  pickupCount: number;
  orderLoad: V1OrderLoad;
  pickupStops: V1PickupStop[];
};
export type V1DeliveryMission = {
  id: string;
  displayOrderNumber: string;
  status:
    | "ASSIGNED"
    | "EN_ROUTE_TO_PICKUPS"
    | "PICKUP_IN_PROGRESS"
    | "ALL_PACKAGES_PICKED_UP"
    | "OUT_FOR_DELIVERY"
    | "ARRIVED"
    | "DELIVERY_RECOVERY";
  version: number;
  transportType: V1TransportType;
  pickupCount: number;
  assignedAt: string;
  firstPackagePickedUpAt: string | null;
  allPackagesPickedUpAt: string | null;
  canCancelBeforePickup: boolean;
  mustUseDeliveryRecovery: boolean;
  orderLoad: V1OrderLoad;
  pickupStops: V1PickupStop[];
  customerDestination: {
    address: string;
    location: OrderLocation | null;
    recipientName: string | null;
    recipientPhoneNumber: string | null;
  } | null;
  outForDeliveryAt: string | null;
  arrivedCustomerAt: string | null;
  deliveredAt: string | null;
  finalVerification: {
    status: "INACTIVE" | "ACTIVE" | "CONSUMED" | "BLOCKED" | "OVERRIDDEN";
    failedAttempts: number;
    activatedAt: string | null;
    blockedAt: string | null;
    evidenceRequired: true;
    evidencePresent: boolean;
    pinVerified?: boolean;
  } | null;
  deliveryEvidence: Array<{
    id: string;
    objectPath: string;
    contentType: "image/jpeg" | "image/png" | "image/heic";
    capturedAt: string;
    packageCount: number;
  }>;
  launchCollection?: {
    required: boolean;
    state: "NOT_REQUIRED" | "PAYMENT_DUE_AT_DELIVERY" |
      "COLLECTION_RETRY_NEEDED" | "PAYMENT_COLLECTED";
    amountPaise?: number;
    currencyCode?: "INR";
    methods: Array<"CASH" | "UPI">;
    canRecord: boolean;
    lastOutcome?: "COLLECTED" | "FAILED";
    lastMethod?: "CASH" | "UPI";
    failureReason?: string;
    attemptedAt?: string;
    collectedAt?: string;
  };
  canStartFinalDelivery: boolean;
  canArriveCustomer: boolean;
  canCaptureDeliveryEvidence: boolean;
  canVerifyDelivery: boolean;
  canVerifyCustomerPIN?: boolean;
  canCompleteDelivery?: boolean;
  customerArrival?: V1ArrivalEligibility | null;
  riderSafety: {
    lastContactAt: string;
    lastProgressAt: string;
    stallDetectedAt: string | null;
    unresponsiveDetectedAt: string | null;
    escalationState: "NONE" | "STALLED" | "UNRESPONSIVE" |
      "RELEASED_PRE_CUSTODY" | "DELIVERY_RECOVERY";
    escalatedAt: string | null;
    escalationReason: string | null;
  };
};
export type V1CompletedMission = {
  id: string;
  orderId: string;
  status: "DELIVERED";
  verificationStatus: "CONSUMED" | "OVERRIDDEN";
  packageCount: number;
  deliveredAt: string;
};
export type V1ReturnStop = {
  id: string;
  sequence: number;
  status: "PENDING" | "ARRIVED" | "COMPLETED";
  packageCount: number;
  arrivedAt: string | null;
  completedAt: string | null;
  verificationStatus: "INACTIVE" | "ACTIVE" | "CONSUMED" | "BLOCKED";
  failedAttempts: number;
  branch: { id: string; displayName: string; address: string };
};
export type V1ReturnMission = {
  id: string;
  returnId: string;
  orderId: string;
  status: "ASSIGNED" | "AT_CUSTOMER" | "RETURNING_TO_MERCHANTS";
  transportType: V1TransportType;
  assignedAt: string;
  arrivedCustomerAt: string | null;
  pickupCompletedAt: string | null;
  completedAt: string | null;
  version: number;
  customerDestination: {
    address: string;
    location: OrderLocation | null;
    recipientName: string | null;
    recipientPhoneNumber: string | null;
  };
  packageCount: number;
  pickupVerification: {
    status: "INACTIVE" | "ACTIVE" | "CONSUMED" | "BLOCKED";
    failedAttempts: number;
  };
  evidence: Array<{
    id: string; objectPath: string; contentType: string; capturedAt: string;
  }>;
  stops: V1ReturnStop[];
  canArriveCustomer: boolean;
  canCaptureEvidence: boolean;
  canVerifyPickup: boolean;
  canCompleteReturnStops: boolean;
};
export type V1DeliveryDispatchSnapshot = {
  offer: V1RiderOffer | null;
  currentMission: V1DeliveryMission | null;
  completedMission: V1CompletedMission | null;
  returnMission: V1ReturnMission | null;
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
const deliveryEvidenceExtensions = new Map([
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
  ["image/heic", "heic"],
]);
const maximumEvidenceBytes = 10 * 1024 * 1024;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const deliveryMethods = new Set<DeliveryMethod>([
  "walking", "bicycle",
  "retired", "bike", "motorbike", "scooter", "auto", "goods_vehicle",
]);
const selectableDeliveryMethods = new Set<DeliveryMethod>([
  "walking", "bicycle",
  "bike", "motorbike", "scooter", "auto", "goods_vehicle",
]);
const motorVehicleMethods = new Set<DeliveryMethod>([
  "bike", "motorbike", "scooter", "auto", "goods_vehicle",
]);
const v1TransportTypes = new Set<V1TransportType>([
  "WALKING", "BICYCLE", "MOTORBIKE", "SCOOTER", "AUTO", "CAR",
]);
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

export async function uploadV1DeliveryEvidence(
  client: SupabaseClient,
  accountId: string,
  file: File,
) {
  const extension = deliveryEvidenceExtensions.get(file.type);
  if (!uuidPattern.test(accountId) || !extension || file.size < 1 || file.size > maximumEvidenceBytes) {
    throw validationError("Capture a JPG, PNG or HEIC package photo up to 10 MB.");
  }
  const objectPath = `rider-delivery/${accountId.toLowerCase()}/${crypto.randomUUID()}.${extension}`;
  const { error } = await client.storage.from("dastak-evidence").upload(objectPath, file, {
    cacheControl: "3600",
    contentType: file.type,
    upsert: false,
  });
  if (error) {
    throw new DeliveryRequestError(
      "evidence_upload_failed",
      "The package photo could not be uploaded.",
      0,
    );
  }
  return objectPath;
}

export async function uploadV1ReturnEvidence(
  client: SupabaseClient,
  accountId: string,
  file: File,
) {
  const extension = deliveryEvidenceExtensions.get(file.type);
  if (!uuidPattern.test(accountId) || !extension || file.size < 1 || file.size > maximumEvidenceBytes) {
    throw validationError("Capture a JPG, PNG or HEIC return-package photo up to 10 MB.");
  }
  const objectPath = `return-pickup/${accountId.toLowerCase()}/${crypto.randomUUID()}.${extension}`;
  const { error } = await client.storage.from("dastak-evidence").upload(objectPath, file, {
    cacheControl: "3600",
    contentType: file.type,
    upsert: false,
  });
  if (error) throw new DeliveryRequestError(
    "evidence_upload_failed", "The return-package photo could not be uploaded.", 0,
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
  if (!selectableDeliveryMethods.has(input.deliveryMethod) || !input.identityEvidenceObjectPath) throw validationError();
  const deliveryMethod = input.deliveryMethod === "bike" ? "motorbike" : input.deliveryMethod;
  const vehicleRequired = requiresVehicleVerification(deliveryMethod);
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
    deliveryMethod,
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

export async function getV1DeliveryDispatch(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
) {
  return parseV1Dispatch(await call(
    "courier-dispatch",
    input,
    { operation: "v1PartnerSnapshot" },
    undefined,
    fetcher,
  ));
}

export async function publishV1MissionLocation(
  input: AuthenticatedInput & {
    missionId: string; latitude: number; longitude: number;
    accuracyMeters: number; recordedAt: string;
  },
  fetcher: Fetcher = fetch,
) {
  if (!uuidPattern.test(input.missionId) ||
    !Number.isFinite(input.latitude) || Math.abs(input.latitude) > 90 ||
    !Number.isFinite(input.longitude) || Math.abs(input.longitude) > 180 ||
    !Number.isFinite(input.accuracyMeters) || input.accuracyMeters < 0 ||
    input.accuracyMeters > 200 || !Number.isFinite(Date.parse(input.recordedAt))) {
    throw validationError("An accurate current location is required.");
  }
  return parseV1Dispatch(await call("courier-dispatch", input, {
    operation: "v1PublishLocation", missionId: input.missionId,
    latitude: input.latitude, longitude: input.longitude,
    accuracyMeters: input.accuracyMeters, recordedAt: input.recordedAt,
  }, undefined, fetcher));
}

export async function acceptV1DeliveryOffer(
  input: AuthenticatedInput & { offerId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return v1DispatchMutation(input, {
    operation: "v1AcceptOffer",
    offerId: input.offerId,
  }, fetcher);
}

export async function declineV1DeliveryOffer(
  input: AuthenticatedInput & { offerId: string; reason?: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return v1DispatchMutation(input, {
    operation: "v1DeclineOffer",
    offerId: input.offerId,
    reason: input.reason?.trim() || null,
  }, fetcher);
}

export async function heartbeatV1DeliveryMission(
  input: AuthenticatedInput & { missionId: string; expectedVersion: number },
  fetcher: Fetcher = fetch,
) {
  if (!uuidPattern.test(input.missionId) || !Number.isSafeInteger(input.expectedVersion) ||
    input.expectedVersion < 1) throw validationError("The active mission changed. Refresh first.");
  return call("courier-dispatch", input, {
    operation: "v1Heartbeat",
    missionId: input.missionId,
    expectedVersion: input.expectedVersion,
  }, undefined, fetcher);
}

export type V1DeliveryMissionOperation =
  | "v1StartPickups"
  | "v1ArriveAtPickup"
  | "v1VerifyPickup"
  | "v1CancelBeforePickup"
  | "v1ReportDeliveryProblem"
  | "v1ReportCustomerUnreachable"
  | "v1StartFinalDelivery"
  | "v1ArriveAtCustomer"
  | "v1AddDeliveryEvidence"
  | "v1VerifyCustomerPIN"
  | "v1CompleteDelivery"
  | "v1VerifyDelivery";

export async function advanceV1DeliveryMission(
  input: AuthenticatedInput & {
    missionId: string;
    operation: V1DeliveryMissionOperation;
    stopId?: string;
    accountedPackageCount?: number;
    verificationCode?: string;
    objectPath?: string;
    reason?: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  if (input.operation === "v1VerifyPickup" && (
    !/^\d{6}$/.test(input.verificationCode ?? "") ||
    !Number.isSafeInteger(input.accountedPackageCount) ||
    (input.accountedPackageCount ?? 0) < 1
  )) {
    throw validationError("Account for every package and enter the six-digit pickup code.");
  }
  if (
    input.operation === "v1AddDeliveryEvidence" &&
    !input.objectPath?.startsWith("rider-delivery/")
  ) throw validationError("Capture the package photo before continuing.");
  if (["v1VerifyDelivery", "v1VerifyCustomerPIN"].includes(input.operation) && !/^\d{6}$/.test(input.verificationCode ?? "")) {
    throw validationError("Enter the six-digit customer delivery code.");
  }
  return v1DispatchMutation(input, {
    operation: input.operation,
    missionId: input.missionId,
    ...(input.stopId ? { stopId: input.stopId } : {}),
    ...(input.accountedPackageCount !== undefined
      ? { accountedPackageCount: input.accountedPackageCount }
      : {}),
    ...(input.verificationCode ? { verificationCode: input.verificationCode } : {}),
    ...(input.objectPath ? { objectPath: input.objectPath } : {}),
    ...(input.reason ? { reason: input.reason.trim() } : {}),
  }, fetcher);
}

export async function recordV1LaunchCollection(
  input: AuthenticatedInput & {
    missionId: string;
    outcome: "COLLECTED" | "FAILED";
    method: "CASH" | "UPI";
    collectionReference?: string;
    failureReason?: string;
    expectedMissionVersion: number;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  if (!uuidPattern.test(input.missionId) || !Number.isSafeInteger(input.expectedMissionVersion) ||
    input.expectedMissionVersion < 1 ||
    (input.outcome === "FAILED" && input.failureReason !== undefined &&
      input.failureReason.trim().length < 3)) {
    throw validationError("Refresh the mission and record a valid collection result.");
  }
  return v1DispatchMutation(input, {
    operation: "v1RecordLaunchCollection",
    missionId: input.missionId,
    outcome: input.outcome,
    method: input.method,
    collectionReference: input.collectionReference?.trim() || null,
    failureReason: input.outcome === "FAILED" ? input.failureReason?.trim() || null : null,
    expectedMissionVersion: input.expectedMissionVersion,
  }, fetcher);
}

export type V1ReturnMissionOperation =
  | "v1ReturnArriveAtCustomer"
  | "v1AddReturnEvidence"
  | "v1VerifyReturnPickup"
  | "v1ArriveAtReturnStop"
  | "v1VerifyReturnReceipt";

export async function advanceV1ReturnMission(
  input: AuthenticatedInput & {
    returnMissionId: string;
    operation: V1ReturnMissionOperation;
    returnStopId?: string;
    objectPath?: string;
    verificationCode?: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  const needsStop = input.operation === "v1ArriveAtReturnStop" ||
    input.operation === "v1VerifyReturnReceipt";
  const needsCode = input.operation === "v1VerifyReturnPickup" ||
    input.operation === "v1VerifyReturnReceipt";
  if (!uuidPattern.test(input.returnMissionId) ||
    (needsStop && !uuidPattern.test(input.returnStopId ?? "")) ||
    (needsCode && !/^\d{6}$/.test(input.verificationCode ?? "")) ||
    (input.operation === "v1AddReturnEvidence" &&
      !input.objectPath?.startsWith("return-pickup/"))) {
    throw validationError("Complete the required return handoff details.");
  }
  return parseV1Dispatch(await call("courier-dispatch", input, {
    operation: input.operation,
    returnMissionId: input.returnMissionId,
    ...(input.returnStopId ? { returnStopId: input.returnStopId } : {}),
    ...(input.objectPath ? { objectPath: input.objectPath } : {}),
    ...(input.verificationCode ? { verificationCode: input.verificationCode } : {}),
  }, input.idempotencyKey, fetcher));
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

async function v1DispatchMutation(
  input: AuthenticatedInput & { idempotencyKey: string },
  body: unknown,
  fetcher: Fetcher,
) {
  return parseV1Dispatch(await call(
    "courier-dispatch",
    input,
    body,
    input.idempotencyKey,
    fetcher,
  ));
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

function parseV1Dispatch(value: unknown): V1DeliveryDispatchSnapshot {
  const source = record(value);
  if (!source || !("offer" in source) || !("currentMission" in source)) invalid();
  return {
    offer: source.offer === null ? null : v1Offer(source.offer),
    currentMission: source.currentMission === null ? null : v1Mission(source.currentMission),
    completedMission: source.completedMission === null || source.completedMission === undefined
      ? null
      : v1CompletedMission(source.completedMission),
    returnMission: source.returnMission === null || source.returnMission === undefined
      ? null
      : v1ReturnMission(source.returnMission),
  };
}

function v1ReturnMission(value: unknown): V1ReturnMission {
  const source = record(value);
  const statuses = ["ASSIGNED", "AT_CUSTOMER", "RETURNING_TO_MERCHANTS"] as const;
  const destination = record(source?.customerDestination);
  const address = record(destination?.address);
  const recipient = destination?.recipient === null ? undefined : record(destination?.recipient);
  const verification = record(source?.pickupVerification);
  if (!source || !statuses.includes(source.status as typeof statuses[number]) ||
    !destination || !address || !verification || !Array.isArray(source.evidence) ||
    !Array.isArray(source.stops)) invalid();
  return {
    id: requiredUUID(source.id), returnId: requiredUUID(source.returnId),
    orderId: requiredUUID(source.orderId),
    status: source.status as V1ReturnMission["status"],
    transportType: requiredV1Transport(source.transportType),
    assignedAt: timestamp(source.assignedAt),
    arrivedCustomerAt: nullableTimestamp(source.arrivedCustomerAt),
    pickupCompletedAt: nullableTimestamp(source.pickupCompletedAt),
    completedAt: nullableTimestamp(source.completedAt), version: positiveInteger(source.version),
    customerDestination: {
      address: addressLabel(address),
      location: typeof address.latitude === "number" && typeof address.longitude === "number"
        ? location(address) : null,
      recipientName: nullableText(recipient?.name, 160),
      recipientPhoneNumber: nullableText(recipient?.phoneNumber, 40),
    },
    packageCount: positiveInteger(source.packageCount),
    pickupVerification: {
      status: requiredReturnVerificationStatus(verification.status),
      failedAttempts: nonNegativeInteger(verification.failedAttempts),
    },
    evidence: source.evidence.map((item) => {
      const evidence = record(item);
      if (!evidence) invalid();
      return {
        id: requiredUUID(evidence.id), objectPath: requiredText(evidence.objectPath, 500),
        contentType: requiredText(evidence.contentType, 100), capturedAt: timestamp(evidence.capturedAt),
      };
    }),
    stops: source.stops.map(v1ReturnStop),
    canArriveCustomer: requiredBoolean(source.canArriveCustomer),
    canCaptureEvidence: requiredBoolean(source.canCaptureEvidence),
    canVerifyPickup: requiredBoolean(source.canVerifyPickup),
    canCompleteReturnStops: requiredBoolean(source.canCompleteReturnStops),
  };
}

function v1ReturnStop(value: unknown): V1ReturnStop {
  const source = record(value);
  const branch = record(source?.branch);
  if (!source || !branch || !["PENDING", "ARRIVED", "COMPLETED"].includes(String(source.status))) {
    invalid();
  }
  return {
    id: requiredUUID(source.id), sequence: positiveInteger(source.sequence),
    status: source.status as V1ReturnStop["status"],
    packageCount: positiveInteger(source.packageCount),
    arrivedAt: nullableTimestamp(source.arrivedAt), completedAt: nullableTimestamp(source.completedAt),
    verificationStatus: requiredReturnVerificationStatus(source.verificationStatus),
    failedAttempts: nonNegativeInteger(source.failedAttempts),
    branch: {
      id: requiredUUID(branch.id), displayName: requiredText(branch.displayName, 160),
      address: addressLabel(branch.address),
    },
  };
}

function requiredReturnVerificationStatus(value: unknown) {
  if (!["INACTIVE", "ACTIVE", "CONSUMED", "BLOCKED"].includes(String(value))) invalid();
  return value as V1ReturnStop["verificationStatus"];
}

function v1Offer(value: unknown): V1RiderOffer {
  const source = record(value);
  if (!source || source.status !== "OFFERED" || !Array.isArray(source.pickupStops)) invalid();
  return {
    id: requiredUUID(source.id),
    missionId: requiredUUID(source.missionId),
    displayOrderNumber: requiredText(source.displayOrderNumber, 40),
    status: "OFFERED",
    poolRound: positiveInteger(source.poolRound),
    transportType: requiredV1Transport(source.transportType),
    distanceMeters: nonNegativeNumber(source.distanceMeters),
    offeredAt: timestamp(source.offeredAt),
    respondBy: timestamp(source.respondBy),
    secondsRemaining: nonNegativeInteger(source.secondsRemaining),
    pickupCount: positiveInteger(source.pickupCount),
    orderLoad: v1OrderLoad(source.orderLoad),
    pickupStops: source.pickupStops.map((stop) => v1PickupStop(stop, false)),
  };
}

function v1Mission(value: unknown): V1DeliveryMission {
  const source = record(value);
  const riderSafety = record(source?.riderSafety);
  const status = source?.status;
  const statuses = [
    "ASSIGNED",
    "EN_ROUTE_TO_PICKUPS",
    "PICKUP_IN_PROGRESS",
    "ALL_PACKAGES_PICKED_UP",
    "OUT_FOR_DELIVERY",
    "ARRIVED",
    "DELIVERY_RECOVERY",
  ] as const;
  if (!source || !riderSafety || !statuses.includes(status as typeof statuses[number]) ||
    !Array.isArray(source.pickupStops) || typeof source.canCancelBeforePickup !== "boolean" ||
    typeof source.mustUseDeliveryRecovery !== "boolean") invalid();
  return {
    id: requiredUUID(source.id),
    displayOrderNumber: requiredText(source.displayOrderNumber, 40),
    status: status as V1DeliveryMission["status"],
    version: positiveInteger(source.version),
    transportType: requiredV1Transport(source.transportType),
    pickupCount: positiveInteger(source.pickupCount),
    assignedAt: timestamp(source.assignedAt),
    firstPackagePickedUpAt: nullableTimestamp(source.firstPackagePickedUpAt),
    allPackagesPickedUpAt: nullableTimestamp(source.allPackagesPickedUpAt),
    canCancelBeforePickup: source.canCancelBeforePickup,
    mustUseDeliveryRecovery: source.mustUseDeliveryRecovery,
    orderLoad: v1OrderLoad(source.orderLoad),
    pickupStops: source.pickupStops.map((stop) => v1PickupStop(stop, true)),
    customerDestination: source.customerDestination === null
      ? null
      : v1CustomerDestination(source.customerDestination),
    outForDeliveryAt: nullableTimestamp(source.outForDeliveryAt),
    arrivedCustomerAt: nullableTimestamp(source.arrivedCustomerAt),
    deliveredAt: nullableTimestamp(source.deliveredAt),
    finalVerification: source.finalVerification === null
      ? null
      : v1FinalVerification(source.finalVerification),
    deliveryEvidence: requiredArray(source.deliveryEvidence).map(v1DeliveryEvidence),
    launchCollection: source.launchCollection === null || source.launchCollection === undefined
      ? undefined
      : v1LaunchCollection(source.launchCollection),
    canStartFinalDelivery: requiredBoolean(source.canStartFinalDelivery),
    canArriveCustomer: requiredBoolean(source.canArriveCustomer),
    canCaptureDeliveryEvidence: requiredBoolean(source.canCaptureDeliveryEvidence),
    canVerifyDelivery: requiredBoolean(source.canVerifyDelivery),
    canVerifyCustomerPIN: source.canVerifyCustomerPIN === true,
    canCompleteDelivery: source.canCompleteDelivery === true,
    customerArrival: v1Arrival(source.customerArrival),
    riderSafety: {
      lastContactAt: timestamp(riderSafety.lastContactAt),
      lastProgressAt: timestamp(riderSafety.lastProgressAt),
      stallDetectedAt: nullableTimestamp(riderSafety.stallDetectedAt),
      unresponsiveDetectedAt: nullableTimestamp(riderSafety.unresponsiveDetectedAt),
      escalationState: requiredRiderEscalationState(riderSafety.escalationState),
      escalatedAt: nullableTimestamp(riderSafety.escalatedAt),
      escalationReason: nullableText(riderSafety.escalationReason, 500),
    },
  };
}

function v1LaunchCollection(value: unknown): NonNullable<V1DeliveryMission["launchCollection"]> {
  const source = record(value);
  const states = ["NOT_REQUIRED", "PAYMENT_DUE_AT_DELIVERY", "COLLECTION_RETRY_NEEDED",
    "PAYMENT_COLLECTED"] as const;
  const state = source?.state;
  const methods = requiredArray(source?.methods).map((method) => {
    if (method !== "CASH" && method !== "UPI") invalid();
    return method;
  });
  const lastOutcome = nullableText(source?.lastOutcome, 20) ?? undefined;
  const lastMethod = nullableText(source?.lastMethod, 10) ?? undefined;
  if (!source || !states.includes(state as typeof states[number]) ||
    (lastOutcome !== undefined && lastOutcome !== "COLLECTED" && lastOutcome !== "FAILED") ||
    (lastMethod !== undefined && lastMethod !== "CASH" && lastMethod !== "UPI")) invalid();
  const currencyCode = nullableText(source.currencyCode, 3) ?? undefined;
  if (currencyCode !== undefined && currencyCode !== "INR") invalid();
  return {
    required: requiredBoolean(source.required),
    state: state as NonNullable<V1DeliveryMission["launchCollection"]>["state"],
    amountPaise: source.amountPaise === null || source.amountPaise === undefined
      ? undefined : positiveInteger(source.amountPaise),
    currencyCode,
    methods,
    canRecord: requiredBoolean(source.canRecord),
    lastOutcome: lastOutcome as NonNullable<V1DeliveryMission["launchCollection"]>["lastOutcome"],
    lastMethod: lastMethod as NonNullable<V1DeliveryMission["launchCollection"]>["lastMethod"],
    failureReason: nullableText(source.failureReason, 500) ?? undefined,
    attemptedAt: source.attemptedAt === null || source.attemptedAt === undefined
      ? undefined : timestamp(source.attemptedAt),
    collectedAt: source.collectedAt === null || source.collectedAt === undefined
      ? undefined : timestamp(source.collectedAt),
  };
}

function requiredRiderEscalationState(value: unknown): V1DeliveryMission["riderSafety"]["escalationState"] {
  if (![
    "NONE", "STALLED", "UNRESPONSIVE", "RELEASED_PRE_CUSTODY", "DELIVERY_RECOVERY",
  ].includes(String(value))) invalid();
  return value as V1DeliveryMission["riderSafety"]["escalationState"];
}

function v1CompletedMission(value: unknown): V1CompletedMission {
  const source = record(value);
  if (!source || source.status !== "DELIVERED" ||
    !["CONSUMED", "OVERRIDDEN"].includes(String(source.verificationStatus))) invalid();
  return {
    id: requiredUUID(source.id),
    orderId: requiredUUID(source.orderId),
    status: "DELIVERED",
    verificationStatus: source.verificationStatus as V1CompletedMission["verificationStatus"],
    packageCount: positiveInteger(source.packageCount),
    deliveredAt: timestamp(source.deliveredAt),
  };
}

function v1CustomerDestination(value: unknown): NonNullable<V1DeliveryMission["customerDestination"]> {
  const source = record(value);
  const address = record(source?.address);
  const recipient = source?.recipient === null ? undefined : record(source?.recipient);
  if (!source || !address || (source.recipient !== null && !recipient)) invalid();
  const hasLocation = typeof address.latitude === "number" && typeof address.longitude === "number";
  return {
    address: addressLabel(address),
    location: hasLocation ? location(address) : null,
    recipientName: nullableText(recipient?.name, 160),
    recipientPhoneNumber: nullableText(recipient?.phoneNumber, 40),
  };
}

function v1FinalVerification(value: unknown): NonNullable<V1DeliveryMission["finalVerification"]> {
  const source = record(value);
  const status = source?.status;
  if (!source || !["INACTIVE", "ACTIVE", "CONSUMED", "BLOCKED", "OVERRIDDEN"].includes(String(status)) ||
    source.evidenceRequired !== true || typeof source.evidencePresent !== "boolean") invalid();
  return {
    status: status as NonNullable<V1DeliveryMission["finalVerification"]>["status"],
    failedAttempts: nonNegativeInteger(source.failedAttempts),
    activatedAt: nullableTimestamp(source.activatedAt),
    blockedAt: nullableTimestamp(source.blockedAt),
    evidenceRequired: true,
    evidencePresent: source.evidencePresent,
    pinVerified: source.pinVerified === true,
  };
}

function v1DeliveryEvidence(value: unknown): V1DeliveryMission["deliveryEvidence"][number] {
  const source = record(value);
  if (!source || !["image/jpeg", "image/png", "image/heic"].includes(String(source.contentType))) invalid();
  return {
    id: requiredUUID(source.id),
    objectPath: requiredText(source.objectPath, 500),
    contentType: source.contentType as V1DeliveryMission["deliveryEvidence"][number]["contentType"],
    capturedAt: timestamp(source.capturedAt),
    packageCount: positiveInteger(source.packageCount),
  };
}

function v1PickupStop(value: unknown, includeState: boolean): V1PickupStop {
  const source = record(value);
  const branch = record(source?.branch);
  const status = source?.status;
  if (!source || !branch || typeof source.ready !== "boolean" ||
    (includeState && !["PENDING", "ARRIVED", "COMPLETED"].includes(String(status)))) invalid();
  return {
    id: requiredUUID(source.id),
    sequence: positiveInteger(source.sequence),
    ...(includeState ? { status: status as V1PickupStop["status"] } : {}),
    ready: source.ready,
    runningLate: includeState && source.runningLate === true,
    estimatedReadyAt: timestamp(source.estimatedReadyAt),
    actualReadyAt: includeState ? nullableTimestamp(source.actualReadyAt) : null,
    packageCount: includeState && source.packageCount !== null
      ? positiveInteger(source.packageCount)
      : null,
    arrivedAt: includeState ? nullableTimestamp(source.arrivedAt) : null,
    waitingSeconds: includeState ? nonNegativeInteger(source.waitingSeconds) : 0,
    arrival: v1Arrival(source.arrival),
    branch: {
      id: includeState ? requiredUUID(branch.id) : null,
      displayName: requiredText(branch.displayName, 160),
      address: addressLabel(branch.address),
      location: branch.location === null ? null : location(branch.location),
    },
  };
}

function v1Arrival(value: unknown): V1ArrivalEligibility | null {
  if (value === null || value === undefined) return null;
  const source = record(value);
  if (!source) invalid();
  return {
    eligible: requiredBoolean(source.eligible),
    reason: requiredText(source.reason, 80),
    distanceMeters: source.distanceMeters === null ? null : nonNegativeNumber(source.distanceMeters),
    radiusMeters: nonNegativeNumber(source.radiusMeters),
    validUntil: nullableTimestamp(source.validUntil),
  };
}

function v1OrderLoad(value: unknown): V1OrderLoad {
  const source = record(value);
  if (!source || typeof source.containsBulky !== "boolean" ||
    !Array.isArray(source.eligibleTransportTypes)) invalid();
  return {
    totalWeightGrams: nonNegativeInteger(source.totalWeightGrams),
    totalVolumeCubicMillimetres: nonNegativeInteger(source.totalVolumeCubicMillimetres),
    longestSideMillimetres: nonNegativeInteger(source.longestSideMillimetres),
    containsBulky: source.containsBulky,
    eligibleTransportTypes: source.eligibleTransportTypes.map(requiredV1Transport),
  };
}

function addressLabel(value: unknown) {
  const source = record(value);
  if (!source) invalid();
  const parts = [source.line1, source.line2, source.landmark, source.city, source.postalCode]
    .filter((part): part is string => typeof part === "string" && part.trim().length > 0)
    .map((part) => part.trim());
  if (parts.length === 0) invalid();
  return parts.join(", ");
}

function requiredV1Transport(value: unknown) {
  if (!v1TransportTypes.has(value as V1TransportType)) invalid();
  return value as V1TransportType;
}

function positiveInteger(value: unknown) {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) invalid();
  return value;
}

function nonNegativeInteger(value: unknown) {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) invalid();
  return value;
}

function nonNegativeNumber(value: unknown) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) invalid();
  return value;
}

function requiredBoolean(value: unknown) {
  if (typeof value !== "boolean") invalid();
  return value;
}

function requiredArray(value: unknown) {
  if (!Array.isArray(value)) invalid();
  return value;
}

function nullableTimestamp(value: unknown) {
  return value === null ? null : timestamp(value);
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
  if (value === "car") return "goods_vehicle" as const;
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
