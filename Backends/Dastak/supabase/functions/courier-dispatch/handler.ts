import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type CourierDispatchMutationInput = {
  accountId: string;
  assignmentId: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type CourierDispatchDeclineInput = CourierDispatchMutationInput & {
  reason: string | null;
};

export type V1RiderOfferMutationInput = {
  accountId: string;
  offerId: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type V1RiderOfferDeclineInput = V1RiderOfferMutationInput & {
  reason: string | null;
};

export type V1RiderHeartbeatInput = {
  accountId: string;
  missionId: string;
  expectedVersion: number;
};

export type V1DeliveryMissionAction =
  | "START_PICKUPS"
  | "ARRIVE_PICKUP"
  | "VERIFY_PICKUP"
  | "CANCEL_BEFORE_PICKUP"
  | "REPORT_DELIVERY_PROBLEM"
  | "REPORT_CUSTOMER_UNREACHABLE";

export type V1DeliveryMissionMutationInput = {
  accountId: string;
  missionId: string;
  action: V1DeliveryMissionAction;
  stopId: string | null;
  accountedPackageCount: number | null;
  verificationCode: string | null;
  reason: string | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type V1FinalDeliveryAction =
  | "START_FINAL_DELIVERY"
  | "ARRIVE_CUSTOMER"
  | "ADD_DELIVERY_EVIDENCE"
  | "VERIFY_DELIVERY"
  | "VERIFY_CUSTOMER_PIN"
  | "COMPLETE_DELIVERY";

export type V1MissionLocationInput = {
  accountId: string;
  missionId: string;
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  recordedAt: string;
};

export type V1FinalDeliveryMutationInput = {
  accountId: string;
  missionId: string;
  action: V1FinalDeliveryAction;
  objectPath: string | null;
  verificationCode: string | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type V1LaunchCollectionInput = {
  accountId: string;
  missionId: string;
  outcome: "COLLECTED" | "FAILED";
  method: "CASH" | "UPI";
  collectionReference: string | null;
  failureReason: string | null;
  expectedMissionVersion: number;
  idempotencyKey: string;
};

export type V1ReturnMissionAction =
  | "ARRIVE_CUSTOMER"
  | "ADD_RETURN_EVIDENCE"
  | "VERIFY_RETURN_PICKUP"
  | "ARRIVE_RETURN_STOP"
  | "VERIFY_RETURN_RECEIPT";

export type V1ReturnMissionMutationInput = {
  accountId: string;
  returnMissionId: string;
  action: V1ReturnMissionAction;
  returnStopId: string | null;
  objectPath: string | null;
  verificationCode: string | null;
  idempotencyKey: string;
  requestDigest: string;
};

export type CourierJobAction =
  | "start_to_store"
  | "arrive_at_store"
  | "confirm_pickup"
  | "start_delivery"
  | "complete_delivery";

export type CourierJobMutationInput = CourierDispatchMutationInput & {
  action: CourierJobAction;
  verificationCode: string | null;
};

export type CourierDispatchDependencies = {
  authenticateBearer: AuthenticateBearer;
  getPartnerSnapshot: (accountId: string) => Promise<RpcResult>;
  getAssignmentControlledScope: (
    accountId: string,
    assignmentId: string,
  ) => Promise<"general" | "medicine" | "tobacco" | null>;
  acceptOffer: (input: CourierDispatchMutationInput) => Promise<RpcResult>;
  declineOffer: (input: CourierDispatchDeclineInput) => Promise<RpcResult>;
  advanceJob: (input: CourierJobMutationInput) => Promise<RpcResult>;
  getV1PartnerSnapshot: (accountId: string) => Promise<RpcResult>;
  acceptV1Offer: (input: V1RiderOfferMutationInput) => Promise<RpcResult>;
  declineV1Offer: (input: V1RiderOfferDeclineInput) => Promise<RpcResult>;
  heartbeatV1Mission: (input: V1RiderHeartbeatInput) => Promise<unknown>;
  publishV1Location: (input: V1MissionLocationInput) => Promise<unknown>;
  advanceV1Mission: (input: V1DeliveryMissionMutationInput) => Promise<RpcResult>;
  advanceV1FinalDelivery: (input: V1FinalDeliveryMutationInput) => Promise<RpcResult>;
  recordV1LaunchCollection: (input: V1LaunchCollectionInput) => Promise<RpcResult>;
  advanceV1ReturnMission: (input: V1ReturnMissionMutationInput) => Promise<RpcResult>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleCourierDispatch(
  request: Request,
  dependencies: CourierDispatchDependencies,
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
      case "partnerSnapshot": {
        const result = await dependencies.getPartnerSnapshot(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "v1PartnerSnapshot": {
        const result = await dependencies.getV1PartnerSnapshot(actor.accountId);
        return json(result.responseBody, result.responseStatus);
      }
      case "v1Heartbeat": {
        const missionId = validUUID(body.missionId);
        const expectedVersion = validPositiveInteger(body.expectedVersion);
        if (!missionId || !expectedVersion) return validationError();
        return json(
          await dependencies.heartbeatV1Mission({
            accountId: actor.accountId,
            missionId,
            expectedVersion,
          }),
        );
      }
      case "v1AcceptOffer":
        return await v1OfferMutation(
          request,
          body,
          actor.accountId,
          dependencies.acceptV1Offer,
        );
      case "v1DeclineOffer":
        return await v1DeclineMutation(request, body, actor.accountId, dependencies);
      case "v1StartPickups":
        return await v1MissionMutation(
          request,
          body,
          actor.accountId,
          "START_PICKUPS",
          dependencies.advanceV1Mission,
        );
      case "v1ArriveAtPickup":
        return await v1MissionMutation(
          request,
          body,
          actor.accountId,
          "ARRIVE_PICKUP",
          dependencies.advanceV1Mission,
        );
      case "v1VerifyPickup":
        return await v1MissionMutation(
          request,
          body,
          actor.accountId,
          "VERIFY_PICKUP",
          dependencies.advanceV1Mission,
        );
      case "v1CancelBeforePickup":
        return await v1MissionMutation(
          request,
          body,
          actor.accountId,
          "CANCEL_BEFORE_PICKUP",
          dependencies.advanceV1Mission,
        );
      case "v1ReportDeliveryProblem":
        return await v1MissionMutation(
          request,
          body,
          actor.accountId,
          "REPORT_DELIVERY_PROBLEM",
          dependencies.advanceV1Mission,
        );
      case "v1ReportCustomerUnreachable":
        return await v1MissionMutation(
          request,
          body,
          actor.accountId,
          "REPORT_CUSTOMER_UNREACHABLE",
          dependencies.advanceV1Mission,
        );
      case "v1StartFinalDelivery":
        return await v1FinalDeliveryMutation(
          request,
          body,
          actor.accountId,
          "START_FINAL_DELIVERY",
          dependencies.advanceV1FinalDelivery,
        );
      case "v1PublishLocation": {
        const missionId = validUUID(body.missionId);
        const { latitude, longitude, accuracyMeters, recordedAt } = body;
        if (
          !missionId || typeof latitude !== "number" || !Number.isFinite(latitude) ||
          Math.abs(latitude) > 90 || typeof longitude !== "number" || !Number.isFinite(longitude) ||
          Math.abs(longitude) > 180 || typeof accuracyMeters !== "number" ||
          !Number.isFinite(accuracyMeters) || accuracyMeters < 0 || accuracyMeters > 200 ||
          typeof recordedAt !== "string" || !Number.isFinite(Date.parse(recordedAt))
        ) return validationError();
        return json(
          await dependencies.publishV1Location({
            accountId: actor.accountId,
            missionId,
            latitude,
            longitude,
            accuracyMeters,
            recordedAt,
          }),
          200,
        );
      }
      case "v1VerifyCustomerPIN":
      case "v1CompleteDelivery":
        return await v1FinalDeliveryMutation(
          request,
          body,
          actor.accountId,
          body.operation === "v1VerifyCustomerPIN" ? "VERIFY_CUSTOMER_PIN" : "COMPLETE_DELIVERY",
          dependencies.advanceV1FinalDelivery,
        );
      case "v1ArriveAtCustomer":
        return await v1FinalDeliveryMutation(
          request,
          body,
          actor.accountId,
          "ARRIVE_CUSTOMER",
          dependencies.advanceV1FinalDelivery,
        );
      case "v1AddDeliveryEvidence":
        return await v1FinalDeliveryMutation(
          request,
          body,
          actor.accountId,
          "ADD_DELIVERY_EVIDENCE",
          dependencies.advanceV1FinalDelivery,
        );
      case "v1VerifyDelivery":
        return await v1FinalDeliveryMutation(
          request,
          body,
          actor.accountId,
          "VERIFY_DELIVERY",
          dependencies.advanceV1FinalDelivery,
        );
      case "v1RecordLaunchCollection":
        return await v1LaunchCollectionMutation(
          request,
          body,
          actor.accountId,
          dependencies.recordV1LaunchCollection,
        );
      case "v1ReturnArriveAtCustomer":
        return await v1ReturnMissionMutation(
          request,
          body,
          actor.accountId,
          "ARRIVE_CUSTOMER",
          dependencies.advanceV1ReturnMission,
        );
      case "v1AddReturnEvidence":
        return await v1ReturnMissionMutation(
          request,
          body,
          actor.accountId,
          "ADD_RETURN_EVIDENCE",
          dependencies.advanceV1ReturnMission,
        );
      case "v1VerifyReturnPickup":
        return await v1ReturnMissionMutation(
          request,
          body,
          actor.accountId,
          "VERIFY_RETURN_PICKUP",
          dependencies.advanceV1ReturnMission,
        );
      case "v1ArriveAtReturnStop":
        return await v1ReturnMissionMutation(
          request,
          body,
          actor.accountId,
          "ARRIVE_RETURN_STOP",
          dependencies.advanceV1ReturnMission,
        );
      case "v1VerifyReturnReceipt":
        return await v1ReturnMissionMutation(
          request,
          body,
          actor.accountId,
          "VERIFY_RETURN_RECEIPT",
          dependencies.advanceV1ReturnMission,
        );
      case "acceptOffer":
        return await assignmentMutation(
          request,
          body,
          actor.accountId,
          dependencies.acceptOffer,
        );
      case "declineOffer":
        return await declineMutation(request, body, actor.accountId, dependencies);
      case "startToStore":
        return await jobMutation(
          request,
          body,
          actor.accountId,
          "start_to_store",
          false,
          dependencies.advanceJob,
        );
      case "arriveAtStore":
        return await jobMutation(
          request,
          body,
          actor.accountId,
          "arrive_at_store",
          false,
          dependencies.advanceJob,
        );
      case "confirmPickup":
        return await jobMutation(
          request,
          body,
          actor.accountId,
          "confirm_pickup",
          true,
          dependencies.advanceJob,
        );
      case "startDelivery":
        return await jobMutation(
          request,
          body,
          actor.accountId,
          "start_delivery",
          false,
          dependencies.advanceJob,
        );
      case "completeDelivery":
        return await jobMutation(
          request,
          body,
          actor.accountId,
          "complete_delivery",
          true,
          dependencies.advanceJob,
          dependencies.getAssignmentControlledScope,
        );
      default:
        return validationError();
    }
  } catch (error) {
    // Only expose allowlisted domain errors, never raw SQL/internal details.
    const message = error && typeof error === "object" && "message" in error
      ? String(error.message)
      : "";
    const known: Record<string, string> = {
      ARRIVAL_LOCATION_REQUIRED:
        "Move within 50 metres and wait for a fresh, accurate location before arriving.",
      RETURN_ARRIVAL_LOCATION_REQUIRED:
        "Move within 50 metres and wait for a fresh, accurate location before confirming this return stop.",
      RIDER_ACTIVE_WORK_CONFLICT: "Complete your active delivery before accepting another job.",
      DELIVERY_PIN_REQUIRED: "Verify the customer PIN before taking the delivery photo.",
      DELIVERY_PHOTO_REQUIRED:
        "Take the package photo after PIN verification before collecting payment.",
      DELIVERY_HANDOFF_SEQUENCE_REQUIRED:
        "Complete arrival, PIN verification, photo and payment in order.",
      LAUNCH_PAYMENT_COLLECTION_REQUIRED: "Confirm doorstep payment before completing delivery.",
      STALE_MISSION_VERSION: "This delivery was updated. Refresh and try again.",
      "stale mission version": "This delivery was updated. Refresh and try again.",
      INVALID_LOCATION_SAMPLE: "Waiting for a fresh GPS location.",
      MISSION_NOT_ASSIGNED: "This delivery is no longer assigned to you.",
      RETURN_CUSTOMER_ARRIVAL_NOT_ALLOWED: "This return pickup is no longer ready for arrival.",
      RETURN_STOP_ARRIVAL_NOT_ALLOWED: "This merchant return stop is no longer ready for arrival.",
      RETURN_EVIDENCE_NOT_ALLOWED: "Return evidence cannot be added in the current state.",
      RETURN_PICKUP_VERIFICATION_INACTIVE: "Return pickup verification is not active.",
      RETURN_PICKUP_EVIDENCE_REQUIRED: "Capture every return package before verifying pickup.",
      RETURN_RECEIPT_VERIFICATION_INACTIVE: "Merchant return receipt verification is not active.",
      "return mission not found": "This return mission is no longer assigned to you.",
    };
    if (known[message]) {
      return json({ error: { code: message.toLowerCase(), message: known[message] } }, 409);
    }
    return internalError();
  }
}

async function v1LaunchCollectionMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: V1LaunchCollectionInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const missionId = validUUID(body.missionId);
  const outcome = body.outcome === "COLLECTED" || body.outcome === "FAILED"
    ? body.outcome
    : undefined;
  const method = body.method === "CASH" || body.method === "UPI" ? body.method : undefined;
  const collectionReference = normalizeOptionalText(body.collectionReference, 200);
  const failureReason = normalizeOptionalText(body.failureReason, 500);
  const expectedMissionVersion = validPositiveInteger(body.expectedMissionVersion);
  if (
    !idempotencyKey || !missionId || !outcome || !method || !expectedMissionVersion ||
    collectionReference === undefined || failureReason === undefined ||
    (outcome === "COLLECTED" && failureReason !== null) ||
    (failureReason !== null && failureReason.length < 3)
  ) return validationError();
  const result = await dependency({
    accountId,
    missionId,
    outcome,
    method,
    collectionReference,
    failureReason: outcome === "FAILED" ? failureReason : null,
    expectedMissionVersion,
    idempotencyKey,
  });
  return json(result.responseBody, result.responseStatus);
}

async function v1FinalDeliveryMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  action: V1FinalDeliveryAction,
  dependency: (input: V1FinalDeliveryMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const missionId = validUUID(body.missionId);
  const objectPath = action === "ADD_DELIVERY_EVIDENCE"
    ? validRiderDeliveryEvidencePath(body.objectPath, accountId)
    : null;
  const needsCode = action === "VERIFY_DELIVERY" || action === "VERIFY_CUSTOMER_PIN";
  const verificationCode = needsCode ? validV1VerificationCode(body.verificationCode) : null;
  if (
    !idempotencyKey || !missionId ||
    (action === "ADD_DELIVERY_EVIDENCE" && !objectPath) ||
    (needsCode && !verificationCode)
  ) return validationError();

  const normalized = { missionId, action, objectPath, verificationCode };
  const result = await dependency({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function v1ReturnMissionMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  action: V1ReturnMissionAction,
  dependency: (input: V1ReturnMissionMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const returnMissionId = validUUID(body.returnMissionId);
  const needsStop = action === "ARRIVE_RETURN_STOP" || action === "VERIFY_RETURN_RECEIPT";
  const returnStopId = needsStop ? validUUID(body.returnStopId) ?? null : null;
  const objectPath = action === "ADD_RETURN_EVIDENCE"
    ? validReturnEvidencePath(body.objectPath, accountId)
    : null;
  const needsCode = action === "VERIFY_RETURN_PICKUP" || action === "VERIFY_RETURN_RECEIPT";
  const verificationCode = needsCode ? validV1VerificationCode(body.verificationCode) : null;
  if (
    !idempotencyKey || !returnMissionId || (needsStop && !returnStopId) ||
    (action === "ADD_RETURN_EVIDENCE" && !objectPath) ||
    (needsCode && !verificationCode)
  ) return validationError();
  const normalized = {
    returnMissionId,
    action,
    returnStopId,
    objectPath,
    verificationCode,
  };
  const result = await dependency({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function v1OfferMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: V1RiderOfferMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const offerId = validUUID(body.offerId);
  if (!idempotencyKey || !offerId) return validationError();

  const normalized = { offerId };
  const result = await dependency({
    accountId,
    offerId,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function v1DeclineMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CourierDispatchDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const offerId = validUUID(body.offerId);
  const reason = normalizeOptionalText(body.reason, 300);
  if (!idempotencyKey || !offerId || reason === undefined) return validationError();

  const normalized = { offerId, reason };
  const result = await dependencies.declineV1Offer({
    accountId,
    offerId,
    reason,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function v1MissionMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  action: V1DeliveryMissionAction,
  dependency: (input: V1DeliveryMissionMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const missionId = validUUID(body.missionId);
  const needsStop = action === "ARRIVE_PICKUP" || action === "VERIFY_PICKUP";
  const stopId = needsStop ? validUUID(body.stopId) : null;
  const accountedPackageCount = action === "VERIFY_PICKUP"
    ? validPositiveInteger(body.accountedPackageCount)
    : null;
  const verificationCode = action === "VERIFY_PICKUP"
    ? validV1VerificationCode(body.verificationCode)
    : null;
  const needsReason = action === "CANCEL_BEFORE_PICKUP" ||
    action === "REPORT_DELIVERY_PROBLEM" ||
    action === "REPORT_CUSTOMER_UNREACHABLE";
  const reason = needsReason ? normalizeRequiredText(body.reason, 500) : null;
  if (
    !idempotencyKey || !missionId || (needsStop && !stopId) ||
    (action === "VERIFY_PICKUP" && (!accountedPackageCount || !verificationCode)) ||
    (needsReason && !reason)
  ) {
    return validationError();
  }

  const normalized = {
    missionId,
    action,
    stopId: stopId ?? null,
    accountedPackageCount: accountedPackageCount ?? null,
    verificationCode,
    reason: reason ?? null,
  };
  const result = await dependency({
    accountId,
    ...normalized,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function jobMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  action: CourierJobAction,
  verificationRequired: boolean,
  dependency: (input: CourierJobMutationInput) => Promise<RpcResult>,
  getAssignmentControlledScope?: CourierDispatchDependencies["getAssignmentControlledScope"],
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  const verificationCode = verificationRequired
    ? validVerificationCode(body.verificationCode)
    : null;
  if (!idempotencyKey || !assignmentId || (verificationRequired && !verificationCode)) {
    return validationError();
  }

  if (
    action === "complete_delivery" && getAssignmentControlledScope &&
    await getAssignmentControlledScope(accountId, assignmentId) === "tobacco"
  ) {
    return json({
      error: {
        code: "restricted_handoff_required",
        message: "Use restricted handoff with a visual age check for this order.",
      },
    }, 409);
  }

  const normalized = verificationRequired
    ? { assignmentId, action, verificationCode }
    : { assignmentId, action };
  const result = await dependency({
    accountId,
    assignmentId,
    action,
    verificationCode,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

function validVerificationCode(value: unknown) {
  return typeof value === "string" && /^[0-9]{4}$/.test(value) ? value : null;
}

function validV1VerificationCode(value: unknown) {
  return typeof value === "string" && /^[0-9]{6}$/.test(value) ? value : null;
}

function validRiderDeliveryEvidencePath(value: unknown, accountId: string) {
  if (typeof value !== "string") return null;
  const escapedAccountId = accountId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    `^rider-delivery/${escapedAccountId}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(?:jpg|jpeg|png|heic)$`,
    "i",
  );
  return pattern.test(value) ? value.toLowerCase() : null;
}

function validReturnEvidencePath(value: unknown, accountId: string) {
  if (typeof value !== "string") return null;
  const escapedAccountId = accountId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    `^return-pickup/${escapedAccountId}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(?:jpg|jpeg|png|heic)$`,
    "i",
  );
  return pattern.test(value) ? value.toLowerCase() : null;
}

function validPositiveInteger(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : undefined;
}

async function assignmentMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependency: (input: CourierDispatchMutationInput) => Promise<RpcResult>,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  if (!idempotencyKey || !assignmentId) return validationError();

  const normalized = { assignmentId };
  const result = await dependency({
    accountId,
    assignmentId,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function declineMutation(
  request: Request,
  body: Record<string, unknown>,
  accountId: string,
  dependencies: CourierDispatchDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const assignmentId = validUUID(body.assignmentId);
  const reason = normalizeOptionalText(body.reason, 300);
  if (!idempotencyKey || !assignmentId || reason === undefined) return validationError();

  const normalized = { assignmentId, reason };
  const result = await dependencies.declineOffer({
    accountId,
    assignmentId,
    reason,
    idempotencyKey,
    requestDigest: await canonicalDigest(normalized),
  });
  return json(result.responseBody, result.responseStatus);
}

async function parseBody(
  request: Request,
): Promise<Record<string, unknown> | undefined> {
  try {
    const body = await request.json();
    return record(body);
  } catch {
    return undefined;
  }
}

function normalizeOptionalText(value: unknown, maximumLength: number) {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximumLength ? normalized : undefined;
}

function normalizeRequiredText(value: unknown, maximumLength: number) {
  const normalized = normalizeOptionalText(value, maximumLength);
  return typeof normalized === "string" ? normalized : undefined;
}

function validUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : undefined;
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
      message: "The courier dispatch request is invalid.",
    },
  }, 400);
}

function internalError() {
  return json({
    error: {
      code: "internal_error",
      message: "The courier dispatch request could not be completed.",
    },
  }, 500);
}
