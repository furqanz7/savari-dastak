import { corsPreflight, json } from "../_shared/http.ts";
import { V1RequestError } from "../_shared/v1-rpc.ts";
import type { V1Actor } from "../dastak-v1-catalogue/handler.ts";

export type V1OrderDependencies = {
  authenticateBearer: (authorization: string) => Promise<V1Actor>;
  submitOrder: (input: {
    accessToken: string;
    idempotencyKey: string;
    expectedVersion: number;
    order: Record<string, unknown>;
  }) => Promise<unknown>;
  listOrders: (input: {
    accessToken: string;
    limit: number;
    beforeCreatedAt: string | null;
    beforeOrderId: string | null;
  }) => Promise<unknown>;
  getOrder: (input: { accessToken: string; orderId: string }) => Promise<unknown>;
  cancelOrder: (input: {
    accessToken: string;
    orderId: string;
    idempotencyKey: string;
    expectedVersion: number;
  }) => Promise<unknown>;
  commitLaunchPayment: (input: {
    accessToken: string;
    orderId: string;
    idempotencyKey: string;
    expectedVersion: number;
  }) => Promise<unknown>;
  listMerchantOpportunities: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  listRestaurantRequests: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  respondRestaurantRequest: (input: {
    accessToken: string;
    requestId: string;
    response: "CONFIRM" | "DECLINE";
    promisedPrepMinutes: number | null;
    reason: string | null;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  acceptMerchantOpportunity: (input: {
    accessToken: string;
    opportunityId: string;
    requestScope: "FULL_BASKET" | "REQUESTED_SUBSET";
    expectedVersion: number;
    promisedPrepMinutes: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  declineMerchantOpportunity: (input: {
    accessToken: string;
    opportunityId: string;
    requestScope: "FULL_BASKET" | "REQUESTED_SUBSET";
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  listMerchantFulfilments: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  declareFulfilmentPackages: (input: {
    accessToken: string;
    fulfilmentId: string;
    packageCount: number;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  addFulfilmentReadyEvidence: (input: {
    accessToken: string;
    fulfilmentId: string;
    packageId: string | null;
    objectPath: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  markFulfilmentReady: (input: {
    accessToken: string;
    fulfilmentId: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  reportFulfilmentProblem: (input: {
    accessToken: string;
    fulfilmentId: string;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  listAdminExecutionOrders: (input: {
    accessToken: string;
    limit: number;
  }) => Promise<unknown>;
  getAdminExecutionTrace: (input: {
    accessToken: string;
    orderId: string;
  }) => Promise<unknown>;
  getAdminAccess: (input: { accessToken: string }) => Promise<unknown>;
  setExecutiveAdmin: (input: {
    accessToken: string;
    slot: 1 | 2;
    email: string | null;
    expectedVersion: number;
    reason: string;
  }) => Promise<unknown>;
  getAdminSystemHealth: (input: { accessToken: string }) => Promise<unknown>;
  getAdminOperationalSafety: (input: { accessToken: string }) => Promise<unknown>;
  manageRiderEscalation: (input: {
    accessToken: string;
    missionId: string;
    action: "RELEASE_REMATCH" | "ENTER_DELIVERY_RECOVERY";
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  setOperationalPause: (input: {
    accessToken: string;
    scope: "ZONE_RETAIL" | "ZONE_FOOD" | "ZONE_MIXED" | "MERCHANT_BRANCH" | "RIDER_ASSIGNMENTS";
    targetId: string;
    active: boolean;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  authorizeExceptionalDeliveryHandoff: (input: {
    accessToken: string;
    missionId: string;
    deliveryEvidenceId: string;
    reason: string;
    expectedMissionVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  reportExactSkuFailure: (input: {
    accessToken: string;
    fulfilmentId: string;
    orderLineId: string;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  createExactSkuRecoveryOffer: (input: {
    accessToken: string;
    recoveryCaseId: string;
    branchId: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  respondExactSkuRecoveryOffer: (input: {
    accessToken: string;
    recoveryOpportunityId: string;
    response: "ACCEPT" | "UNAVAILABLE";
    promisedPrepMinutes: number | null;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  failExactSkuRecovery: (input: {
    accessToken: string;
    recoveryCaseId: string;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  reportCustomerIssue: (input: {
    accessToken: string;
    orderId: string;
    orderLineId: string | null;
    category: string;
    description: string;
    objectPath: string | null;
    contentType: string | null;
    idempotencyKey: string;
  }) => Promise<unknown>;
  decideCustomerIssue: (input: {
    accessToken: string;
    issueId: string;
    decision: string;
    refundAmountPaise: number | null;
    faultSource: string | null;
    returnPackageCount: number | null;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  assignReturnRider: (input: {
    accessToken: string;
    returnMissionId: string;
    riderId: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  manageDeliveryRecovery: (input: {
    accessToken: string;
    recoveryCaseId: string;
    action: string;
    faultSource: string;
    refundAmountPaise: number | null;
    correctedAddress: Record<string, unknown> | null;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  finalizeSettlementCalculation: (input: {
    accessToken: string;
    settlementEntryId: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  settleEntry: (input: {
    accessToken: string;
    settlementEntryId: string;
    settlementReference: string;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleV1Orders(request: Request, dependencies: V1OrderDependencies) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();
  let actor: V1Actor;
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await parseBody(request);
  if (!body || typeof body.operation !== "string") return validationError();

  try {
    switch (body.operation) {
      case "submit": {
        const idempotencyKey = requiredIdempotencyKey(request);
        const expectedVersion = integer(body.expectedVersion, 0, 0);
        const order = record(body.order);
        if (!idempotencyKey || expectedVersion === undefined || !order) return validationError();
        const result = await dependencies.submitOrder({
          accessToken: actor.accessToken,
          idempotencyKey,
          expectedVersion,
          order,
        });
        return json(result, 201);
      }
      case "list": {
        const parsedLimit = integer(body.limit, 1, 100);
        if (body.limit !== null && body.limit !== undefined && parsedLimit === undefined) {
          return validationError();
        }
        const limit = parsedLimit ?? 20;
        const cursor = record(body.cursor);
        const beforeCreatedAt = cursor && validTimestamp(cursor.createdAt)
          ? cursor.createdAt as string
          : null;
        const beforeOrderId = cursor ? requiredUUID(cursor.orderId) ?? null : null;
        if (
          (body.cursor !== null && body.cursor !== undefined && cursor === undefined) ||
          (cursor !== undefined && (!beforeCreatedAt || !beforeOrderId))
        ) return validationError();
        return json(
          await dependencies.listOrders({
            accessToken: actor.accessToken,
            limit,
            beforeCreatedAt,
            beforeOrderId,
          }),
        );
      }
      case "get": {
        const orderId = requiredUUID(body.orderId);
        if (!orderId) return validationError();
        return json(await dependencies.getOrder({ accessToken: actor.accessToken, orderId }));
      }
      case "cancel": {
        const orderId = requiredUUID(body.orderId);
        const idempotencyKey = requiredIdempotencyKey(request);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        if (!orderId || !idempotencyKey || !expectedVersion) return validationError();
        return json(
          await dependencies.cancelOrder({
            accessToken: actor.accessToken,
            orderId,
            idempotencyKey,
            expectedVersion,
          }),
        );
      }
      case "commitLaunchPayment": {
        const orderId = requiredUUID(body.orderId);
        const idempotencyKey = requiredIdempotencyKey(request);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        if (!orderId || !idempotencyKey || !expectedVersion) return validationError();
        return json(
          await dependencies.commitLaunchPayment({
            accessToken: actor.accessToken,
            orderId,
            idempotencyKey,
            expectedVersion,
          }),
        );
      }
      case "merchantOpportunities": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) {
          return validationError();
        }
        return json(
          await dependencies.listMerchantOpportunities({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "restaurantRequests": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) return validationError();
        return json(
          await dependencies.listRestaurantRequests({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "respondRestaurantRequest": {
        const requestId = requiredUUID(body.requestId);
        const response = body.response === "CONFIRM" || body.response === "DECLINE"
          ? body.response
          : undefined;
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const promisedPrepMinutes = body.promisedPrepMinutes === null ||
            body.promisedPrepMinutes === undefined
          ? null
          : integer(body.promisedPrepMinutes, 1, 240) ?? undefined;
        const reason = body.reason === null || body.reason === undefined
          ? null
          : requiredText(body.reason, 500);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !requestId || !response || !expectedVersion || !idempotencyKey ||
          (response === "CONFIRM" && typeof promisedPrepMinutes !== "number") ||
          (response === "DECLINE" && (!reason || reason.length < 3)) ||
          promisedPrepMinutes === undefined
        ) {
          return validationError();
        }
        return json(
          await dependencies.respondRestaurantRequest({
            accessToken: actor.accessToken,
            requestId,
            response,
            promisedPrepMinutes: response === "CONFIRM" ? promisedPrepMinutes : null,
            reason: response === "DECLINE" ? reason ?? null : null,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "acceptMerchantOpportunity": {
        const opportunityId = requiredUUID(body.opportunityId);
        const requestScope = merchantRequestScope(body.requestScope);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const promisedPrepMinutes = integer(body.promisedPrepMinutes, 1, 24 * 60);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !opportunityId || !requestScope || !expectedVersion || !promisedPrepMinutes ||
          !idempotencyKey
        ) {
          return validationError();
        }
        return json(
          await dependencies.acceptMerchantOpportunity({
            accessToken: actor.accessToken,
            opportunityId,
            requestScope,
            expectedVersion,
            promisedPrepMinutes,
            idempotencyKey,
          }),
        );
      }
      case "declineMerchantOpportunity": {
        const opportunityId = requiredUUID(body.opportunityId);
        const requestScope = merchantRequestScope(body.requestScope);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!opportunityId || !requestScope || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.declineMerchantOpportunity({
            accessToken: actor.accessToken,
            opportunityId,
            requestScope,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "merchantFulfilments": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) return validationError();
        return json(
          await dependencies.listMerchantFulfilments({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "declareFulfilmentPackages": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const packageCount = integer(body.packageCount, 1, 1000);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!fulfilmentId || !packageCount || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.declareFulfilmentPackages({
            accessToken: actor.accessToken,
            fulfilmentId,
            packageCount,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "addFulfilmentReadyEvidence": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const parsedPackageId = body.packageId === null || body.packageId === undefined
          ? null
          : requiredUUID(body.packageId);
        const objectPath = requiredText(body.objectPath, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !fulfilmentId || !objectPath || !expectedVersion || !idempotencyKey ||
          (body.packageId !== null && body.packageId !== undefined && !parsedPackageId)
        ) return validationError();
        const packageId = parsedPackageId ?? null;
        return json(
          await dependencies.addFulfilmentReadyEvidence({
            accessToken: actor.accessToken,
            fulfilmentId,
            packageId,
            objectPath,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "markFulfilmentReady": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!fulfilmentId || !expectedVersion || !idempotencyKey) return validationError();
        return json(
          await dependencies.markFulfilmentReady({
            accessToken: actor.accessToken,
            fulfilmentId,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "reportFulfilmentProblem": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !fulfilmentId || !reason || reason.length < 3 || !expectedVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.reportFulfilmentProblem({
            accessToken: actor.accessToken,
            fulfilmentId,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "adminExecutionOrders": {
        const limit = integer(body.limit, 1, 100) ?? 50;
        if (
          body.limit !== null && body.limit !== undefined &&
          integer(body.limit, 1, 100) === undefined
        ) {
          return validationError();
        }
        return json(
          await dependencies.listAdminExecutionOrders({
            accessToken: actor.accessToken,
            limit,
          }),
        );
      }
      case "adminExecutionTrace": {
        const orderId = requiredUUID(body.orderId);
        if (!orderId) return validationError();
        return json(
          await dependencies.getAdminExecutionTrace({
            accessToken: actor.accessToken,
            orderId,
          }),
        );
      }
      case "adminAccess":
        return json(await dependencies.getAdminAccess({ accessToken: actor.accessToken }));
      case "setExecutiveAdmin": {
        const slot = body.slot === 1 || body.slot === 2 ? body.slot : undefined;
        const email = body.email === null || body.email === undefined
          ? null
          : requiredText(body.email, 320);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const reason = requiredText(body.reason, 500);
        if (
          !slot || email === undefined || !expectedVersion || !reason || reason.length < 3
        ) return validationError();
        return json(
          await dependencies.setExecutiveAdmin({
            accessToken: actor.accessToken,
            slot,
            email,
            expectedVersion,
            reason,
          }),
        );
      }
      case "adminSystemHealth":
        return json(
          await dependencies.getAdminSystemHealth({ accessToken: actor.accessToken }),
        );
      case "adminOperationalSafety":
        return json(
          await dependencies.getAdminOperationalSafety({ accessToken: actor.accessToken }),
        );
      case "manageRiderEscalation": {
        const missionId = requiredUUID(body.missionId);
        const action = body.action === "RELEASE_REMATCH" ||
            body.action === "ENTER_DELIVERY_RECOVERY"
          ? body.action
          : undefined;
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !missionId || !action || !reason || reason.length < 10 ||
          !expectedVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.manageRiderEscalation({
            accessToken: actor.accessToken,
            missionId,
            action,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "setOperationalPause": {
        const scope = operationalPauseScope(body.scope);
        const targetId = requiredUUID(body.targetId);
        const active = typeof body.active === "boolean" ? body.active : undefined;
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 0, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !scope || !targetId || active === undefined || !reason ||
          expectedVersion === undefined || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.setOperationalPause({
            accessToken: actor.accessToken,
            scope,
            targetId,
            active,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "authorizeExceptionalDeliveryHandoff": {
        const missionId = requiredUUID(body.missionId);
        const deliveryEvidenceId = requiredUUID(body.deliveryEvidenceId);
        const reason = requiredText(body.reason, 500);
        const expectedMissionVersion = integer(
          body.expectedMissionVersion,
          1,
          Number.MAX_SAFE_INTEGER,
        );
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !missionId || !deliveryEvidenceId || !reason || reason.length < 10 ||
          !expectedMissionVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.authorizeExceptionalDeliveryHandoff({
            accessToken: actor.accessToken,
            missionId,
            deliveryEvidenceId,
            reason,
            expectedMissionVersion,
            idempotencyKey,
          }),
        );
      }
      case "reportExactSkuFailure": {
        const fulfilmentId = requiredUUID(body.fulfilmentId);
        const orderLineId = requiredUUID(body.orderLineId);
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !fulfilmentId || !orderLineId || !reason || reason.length < 3 ||
          !expectedVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.reportExactSkuFailure({
            accessToken: actor.accessToken,
            fulfilmentId,
            orderLineId,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "createExactSkuRecoveryOffer": {
        const recoveryCaseId = requiredUUID(body.recoveryCaseId);
        const branchId = requiredUUID(body.branchId);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!recoveryCaseId || !branchId || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.createExactSkuRecoveryOffer({
            accessToken: actor.accessToken,
            recoveryCaseId,
            branchId,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "respondExactSkuRecoveryOffer": {
        const recoveryOpportunityId = requiredUUID(body.recoveryOpportunityId);
        const response = body.response === "ACCEPT" || body.response === "UNAVAILABLE"
          ? body.response
          : undefined;
        const promisedPrepMinutes = response === "ACCEPT"
          ? integer(body.promisedPrepMinutes, 1, 24 * 60) ?? null
          : null;
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !recoveryOpportunityId || !response ||
          (response === "ACCEPT" && !promisedPrepMinutes) ||
          !expectedVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.respondExactSkuRecoveryOffer({
            accessToken: actor.accessToken,
            recoveryOpportunityId,
            response,
            promisedPrepMinutes,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "failExactSkuRecovery": {
        const recoveryCaseId = requiredUUID(body.recoveryCaseId);
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !recoveryCaseId || !reason || reason.length < 3 ||
          !expectedVersion || !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.failExactSkuRecovery({
            accessToken: actor.accessToken,
            recoveryCaseId,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "reportCustomerIssue": {
        const orderId = requiredUUID(body.orderId);
        const orderLineId = body.orderLineId === null || body.orderLineId === undefined
          ? null
          : requiredUUID(body.orderLineId) ?? null;
        const category = issueCategory(body.category);
        const description = requiredText(body.description, 1000);
        const objectPath = body.objectPath === null || body.objectPath === undefined
          ? null
          : requiredText(body.objectPath, 500) ?? null;
        const contentType = body.contentType === null || body.contentType === undefined
          ? null
          : issueContentType(body.contentType) ?? null;
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !orderId || !category || !description || description.length < 3 ||
          !idempotencyKey ||
          ((body.orderLineId !== null && body.orderLineId !== undefined) && !orderLineId) ||
          ((body.objectPath === null || body.objectPath === undefined) !==
            (body.contentType === null || body.contentType === undefined)) ||
          (body.objectPath !== null && body.objectPath !== undefined &&
            (!objectPath || !contentType))
        ) return validationError();
        return json(
          await dependencies.reportCustomerIssue({
            accessToken: actor.accessToken,
            orderId,
            orderLineId,
            category,
            description,
            objectPath,
            contentType,
            idempotencyKey,
          }),
          201,
        );
      }
      case "decideCustomerIssue": {
        const issueId = requiredUUID(body.issueId);
        const decision = issueDecision(body.decision);
        const refundAmountPaise = nullableMoney(body.refundAmountPaise);
        const faultSource = nullableFaultSource(body.faultSource);
        const returnPackageCount = body.returnPackageCount === null ||
            body.returnPackageCount === undefined
          ? null
          : integer(body.returnPackageCount, 1, 1000) ?? null;
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !issueId || !decision || !reason || reason.length < 3 ||
          !expectedVersion || !idempotencyKey ||
          (body.refundAmountPaise !== null && body.refundAmountPaise !== undefined &&
            refundAmountPaise === undefined) ||
          (body.faultSource !== null && body.faultSource !== undefined &&
            faultSource === undefined) ||
          (body.returnPackageCount !== null && body.returnPackageCount !== undefined &&
            !returnPackageCount)
        ) return validationError();
        return json(
          await dependencies.decideCustomerIssue({
            accessToken: actor.accessToken,
            issueId,
            decision,
            refundAmountPaise: refundAmountPaise ?? null,
            faultSource: faultSource ?? null,
            returnPackageCount,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "assignReturnRider": {
        const returnMissionId = requiredUUID(body.returnMissionId);
        const riderId = requiredUUID(body.riderId);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!returnMissionId || !riderId || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.assignReturnRider({
            accessToken: actor.accessToken,
            returnMissionId,
            riderId,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "manageDeliveryRecovery": {
        const recoveryCaseId = requiredUUID(body.recoveryCaseId);
        const action = deliveryRecoveryAction(body.action);
        const faultSource = recoveryFaultSource(body.faultSource);
        const refundAmountPaise = nullableMoney(body.refundAmountPaise);
        const correctedAddress = body.correctedAddress === null ||
            body.correctedAddress === undefined
          ? null
          : record(body.correctedAddress) ?? null;
        const reason = requiredText(body.reason, 500);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !recoveryCaseId || !action || !faultSource || !reason || reason.length < 10 ||
          !expectedVersion || !idempotencyKey ||
          (body.refundAmountPaise !== null && body.refundAmountPaise !== undefined &&
            refundAmountPaise === undefined) ||
          (body.correctedAddress !== null && body.correctedAddress !== undefined &&
            !correctedAddress) ||
          (action === "RETURN_TO_ORIGIN" && correctedAddress !== null) ||
          (action === "RESUME_DELIVERY" && refundAmountPaise !== null) ||
          (faultSource === "CUSTOMER" && refundAmountPaise !== null)
        ) return validationError();
        return json(
          await dependencies.manageDeliveryRecovery({
            accessToken: actor.accessToken,
            recoveryCaseId,
            action,
            faultSource,
            refundAmountPaise: refundAmountPaise ?? null,
            correctedAddress,
            reason,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "finalizeSettlementCalculation": {
        const settlementEntryId = requiredUUID(body.settlementEntryId);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!settlementEntryId || !expectedVersion || !idempotencyKey) {
          return validationError();
        }
        return json(
          await dependencies.finalizeSettlementCalculation({
            accessToken: actor.accessToken,
            settlementEntryId,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      case "settleEntry": {
        const settlementEntryId = requiredUUID(body.settlementEntryId);
        const settlementReference = requiredText(body.settlementReference, 200);
        const expectedVersion = integer(body.expectedVersion, 1, Number.MAX_SAFE_INTEGER);
        const idempotencyKey = requiredIdempotencyKey(request);
        if (
          !settlementEntryId || !settlementReference || !expectedVersion ||
          !idempotencyKey
        ) return validationError();
        return json(
          await dependencies.settleEntry({
            accessToken: actor.accessToken,
            settlementEntryId,
            settlementReference,
            expectedVersion,
            idempotencyKey,
          }),
        );
      }
      default:
        return validationError();
    }
  } catch (error) {
    return requestFailure(error);
  }
}

async function parseBody(request: Request): Promise<Record<string, unknown> | undefined> {
  try {
    const source = await request.text();
    if (source.length === 0 || source.length > 250_000) return undefined;
    return record(JSON.parse(source));
  } catch {
    return undefined;
  }
}

function requiredUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function requiredText(value: unknown, maximum: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : undefined;
}

function validTimestamp(value: unknown) {
  return typeof value === "string" && value.length <= 40 && Number.isFinite(Date.parse(value));
}

function operationalPauseScope(value: unknown) {
  return typeof value === "string" && [
      "ZONE_RETAIL",
      "ZONE_FOOD",
      "ZONE_MIXED",
      "MERCHANT_BRANCH",
      "RIDER_ASSIGNMENTS",
    ].includes(value)
    ? value as "ZONE_RETAIL" | "ZONE_FOOD" | "ZONE_MIXED" | "MERCHANT_BRANCH" | "RIDER_ASSIGNMENTS"
    : undefined;
}

function merchantRequestScope(value: unknown) {
  return value === "FULL_BASKET" || value === "REQUESTED_SUBSET" ? value : undefined;
}

function issueCategory(value: unknown) {
  return typeof value === "string" && [
      "WRONG_SKU",
      "WRONG_QUANTITY",
      "DAMAGED",
      "DEFECTIVE",
      "EXPIRED",
      "TAMPERED_OR_BROKEN_SEAL",
      "INCORRECT_PACKAGE",
      "SUSPECTED_MERCHANT_MISFULFILMENT",
      "DELIVERY_PROBLEM",
      "OTHER",
    ].includes(value)
    ? value
    : undefined;
}

function issueContentType(value: unknown) {
  return value === "image/jpeg" || value === "image/png" || value === "image/heic"
    ? value
    : undefined;
}

function issueDecision(value: unknown) {
  return typeof value === "string" && [
      "REJECT",
      "RESOLVE_NO_REFUND",
      "REFUND_WITHOUT_RETURN",
      "PHYSICAL_RETURN",
    ].includes(value)
    ? value
    : undefined;
}

function nullableFaultSource(value: unknown) {
  if (value === null || value === undefined) return null;
  return typeof value === "string" && [
      "MERCHANT",
      "RIDER",
      "DASTAK",
      "CUSTOMER",
      "NONE",
      "UNKNOWN",
    ].includes(value)
    ? value
    : undefined;
}

function recoveryFaultSource(value: unknown) {
  return typeof value === "string" && [
      "MERCHANT",
      "RIDER",
      "DASTAK",
      "CUSTOMER",
    ].includes(value)
    ? value
    : undefined;
}

function deliveryRecoveryAction(value: unknown) {
  return value === "RESUME_DELIVERY" || value === "RETURN_TO_ORIGIN" ? value : undefined;
}

function nullableMoney(value: unknown) {
  if (value === null || value === undefined) return null;
  return typeof value === "number" && Number.isSafeInteger(value) &&
      value > 0 && value <= 100_000_000
    ? value
    : undefined;
}

function integer(value: unknown, minimum: number, maximum: number) {
  if (value === null || value === undefined) return undefined;
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum &&
      value <= maximum
    ? value
    : undefined;
}

function requiredIdempotencyKey(request: Request) {
  const key = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  return key.length >= 1 && key.length <= 200 ? key : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json(
    { error: { code: "validation_failed", message: "The order request is invalid." } },
    400,
  );
}

function requestFailure(error: unknown) {
  if (error instanceof V1RequestError) {
    return json({ error: { code: error.code, message: error.message } }, error.status);
  }
  return json({
    error: { code: "internal_error", message: "The order request could not be processed." },
  }, 500);
}
