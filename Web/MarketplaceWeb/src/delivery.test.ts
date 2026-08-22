import { describe, expect, it, vi } from "vitest";
import {
  acceptV1DeliveryOffer,
  acceptDeliveryOffer,
  advanceV1DeliveryMission,
  advanceDeliveryJob,
  declineDeliveryOffer,
  deliveryPartnerVerificationState,
  getDeliveryDispatch,
  getDeliveryPartnerSnapshot,
  getV1DeliveryDispatch,
  isAcceptedPartnerEvidence,
  isValidVehicleRegistration,
  normalizeVehicleRegistration,
  partnerEvidenceObjectPath,
  publishDeliveryPartnerLocation,
  requiresVehicleVerification,
  setDeliveryPartnerAvailability,
  submitDeliveryPartnerApplication,
} from "./delivery";

const accountId = "11111111-1111-4111-8111-111111111111";
const applicationId = "22222222-2222-4222-8222-222222222222";
const assignmentId = "33333333-3333-4333-8333-333333333333";
const orderId = "44444444-4444-4444-8444-444444444444";
const storeId = "55555555-5555-4555-8555-555555555555";
const productId = "66666666-6666-4666-8666-666666666666";
const serviceZoneId = "77777777-7777-4777-8777-777777777777";
const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};
const location = { latitude: 12.6819, longitude: 78.6201 };
const availability = {
  status: "online",
  location,
  serviceZoneId,
  availableUntil: "2026-07-22T10:15:00Z",
  stateVersion: 2,
};
const offer = {
  assignmentId,
  orderId,
  assignmentStatus: "offered",
  orderStatus: "ready",
  offeredAt: "2026-07-22T10:00:00Z",
  respondBy: "2026-07-22T10:01:00Z",
  acceptedAt: null,
  distanceMeters: 850.5,
  courierPayout: { paise: 4200 },
  store: { storeId, name: "Town Store", address: "Main Road", pickup: location },
  dropoff: { latitude: 12.69, longitude: 78.63 },
  items: [{ productId, name: "Lime Soda", unitLabel: "750 ml", quantity: 2 }],
};

describe("delivery partner client", () => {
  it("accepts only supported evidence and creates an account-scoped object path", () => {
    expect(isAcceptedPartnerEvidence({ type: "application/pdf", size: 100 })).toBe(true);
    expect(isAcceptedPartnerEvidence({ type: "text/plain", size: 100 })).toBe(false);
    expect(isAcceptedPartnerEvidence({ type: "image/png", size: 10 * 1024 * 1024 + 1 })).toBe(false);
    expect(partnerEvidenceObjectPath(accountId, "image/jpeg", applicationId)).toBe(
      `dastak-partner/${accountId}/identity-${applicationId}.jpg`,
    );
  });

  it("requires valid vehicle verification for motor methods", async () => {
    expect(requiresVehicleVerification("walking")).toBe(false);
    expect(requiresVehicleVerification("bicycle")).toBe(false);
    expect(requiresVehicleVerification("bike")).toBe(true);
    expect(requiresVehicleVerification("motorbike")).toBe(true);
    expect(requiresVehicleVerification("scooter")).toBe(true);
    expect(normalizeVehicleRegistration(" tn 23  ab 1234 ")).toBe("TN 23 AB 1234");
    expect(isValidVehicleRegistration("TN 23 AB 1234")).toBe(true);
    expect(isValidVehicleRegistration("TN@23")).toBe(false);

    await expect(submitDeliveryPartnerApplication({
      ...auth,
      deliveryMethod: "auto",
      identityEvidenceObjectPath: `dastak-partner/${accountId}/identity-${applicationId}.pdf`,
      idempotencyKey: "submit-key",
    }, vi.fn())).rejects.toThrow("vehicle details");
  });

  it("does not overstate verification for legacy motor accounts", () => {
    const base = {
      onboardingState: "approved" as const,
      deliveryMethod: "bike" as const,
      vehicleRegistrationNumber: null,
      vehicleMakeModel: null,
      vehicleEvidenceObjectPath: null,
    };

    expect(deliveryPartnerVerificationState(base)).toBe("vehicle_review_required");
    expect(deliveryPartnerVerificationState({
      ...base,
      vehicleRegistrationNumber: "TN 23 AB 1234",
      vehicleMakeModel: "Honda Activa 6G",
      vehicleEvidenceObjectPath: `dastak-partner/${accountId}/vehicle-${applicationId}.pdf`,
    })).toBe("identity_and_vehicle_verified");
    expect(deliveryPartnerVerificationState({
      ...base,
      deliveryMethod: "walking",
    })).toBe("identity_verified");
  });

  it("submits motor vehicle details and proof", async () => {
    let body: unknown;
    const result = await submitDeliveryPartnerApplication({
      ...auth,
      deliveryMethod: "bike",
      identityEvidenceObjectPath: `dastak-partner/${accountId}/identity-${applicationId}.pdf`,
      vehicleRegistrationNumber: " tn 23 ab 1234 ",
      vehicleMakeModel: "  Bajaj   Pulsar 150 ",
      vehicleEvidenceObjectPath: `dastak-partner/${accountId}/vehicle-${applicationId}.pdf`,
      idempotencyKey: "submit-key",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({
        applicationId,
        status: "pending",
        deliveryMethod: "motorbike",
      }), { status: 200 }));
    });

    expect(body).toEqual({
      operation: "submit",
      deliveryMethod: "motorbike",
      identityEvidenceObjectPath: `dastak-partner/${accountId}/identity-${applicationId}.pdf`,
      vehicleRegistrationNumber: "TN 23 AB 1234",
      vehicleMakeModel: "Bajaj Pulsar 150",
      vehicleEvidenceObjectPath: `dastak-partner/${accountId}/vehicle-${applicationId}.pdf`,
    });
    expect(result.status).toBe("pending");
  });

  it("parses the approved partner snapshot", async () => {
    const snapshot = await getDeliveryPartnerSnapshot(auth, () => Promise.resolve(new Response(JSON.stringify({
      onboardingState: "approved",
      applicationId,
      deliveryMethod: "bike",
      reviewReason: null,
      availability,
    }), { status: 200 })));

    expect(snapshot.deliveryMethod).toBe("bike");
    expect(snapshot.availability?.serviceZoneId).toBe(serviceZoneId);
  });

  it("sends current location when going online", async () => {
    let body: unknown;
    let idempotencyKey: string | null = null;
    const result = await setDeliveryPartnerAvailability({
      ...auth,
      online: true,
      location,
      idempotencyKey: "availability-key",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      idempotencyKey = new Headers(init?.headers).get("X-Idempotency-Key");
      return Promise.resolve(new Response(JSON.stringify(availability), { status: 200 }));
    });

    expect(body).toEqual({ operation: "setAvailability", online: true, location });
    expect(idempotencyKey).toBe("availability-key");
    expect(result.status).toBe("online");
  });

  it("publishes live location without extending availability", async () => {
    let body: unknown;
    const result = await publishDeliveryPartnerLocation({
      ...auth,
      location,
      idempotencyKey: "location-key",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify(availability), { status: 200 }));
    });

    expect(body).toEqual({ operation: "publishLocation", location });
    expect(result.availableUntil).toBe(availability.availableUntil);
  });

  it("parses a ready-order offer without private account identities", async () => {
    const snapshot = await getDeliveryDispatch(auth, () =>
      Promise.resolve(new Response(JSON.stringify({ offer, currentJob: null }), { status: 200 })));
    expect(snapshot.offer?.store.name).toBe("Town Store");
    expect(snapshot.offer?.courierPayout.paise).toBe(4200);

    await expect(getDeliveryDispatch(auth, () => Promise.resolve(new Response(JSON.stringify({
      offer: { ...offer, customerAccountId: accountId },
      currentJob: null,
    }), { status: 200 })))).rejects.toThrow("invalid delivery response");
  });

  it("accepts and declines offers with idempotency", async () => {
    const requests: Array<{ body: unknown; key: string | null }> = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({
        body: JSON.parse(String(init?.body)),
        key: new Headers(init?.headers).get("X-Idempotency-Key"),
      });
      return Promise.resolve(new Response(JSON.stringify({ offer: null, currentJob: null }), { status: 200 }));
    };

    await acceptDeliveryOffer({ ...auth, assignmentId, idempotencyKey: "accept-key" }, fetcher);
    await declineDeliveryOffer({ ...auth, assignmentId, reason: "Too far", idempotencyKey: "decline-key" }, fetcher);

    expect(requests).toEqual([
      { body: { operation: "acceptOffer", assignmentId }, key: "accept-key" },
      { body: { operation: "declineOffer", assignmentId, reason: "Too far" }, key: "decline-key" },
    ]);
  });

  it("sends pickup and delivery handoff codes", async () => {
    const requests: unknown[] = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requests.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(JSON.stringify({ offer: null, currentJob: null }), { status: 200 }));
    };

    await advanceDeliveryJob({ ...auth, assignmentId, operation: "confirmPickup", verificationCode: "1234", idempotencyKey: "pickup-key" }, fetcher);
    await advanceDeliveryJob({ ...auth, assignmentId, operation: "completeDelivery", verificationCode: "5678", idempotencyKey: "delivery-key" }, fetcher);

    expect(requests).toEqual([
      { operation: "confirmPickup", assignmentId, verificationCode: "1234" },
      { operation: "completeDelivery", assignmentId, verificationCode: "5678" },
    ]);
  });

  it("rejects an invalid handoff code before calling the server", async () => {
    const fetcher = vi.fn();
    await expect(advanceDeliveryJob({
      ...auth,
      assignmentId,
      operation: "completeDelivery",
      verificationCode: "12",
      idempotencyKey: "delivery-key",
    }, fetcher)).rejects.toThrow("four-digit handoff code");
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("parses a multi-stop V1 mission offer and never needs customer identity", async () => {
    const pickupStop = {
      id: storeId,
      sequence: 1,
      ready: true,
      estimatedReadyAt: "2026-08-22T10:05:00Z",
      branch: {
        displayName: "Dastak Convenience Store",
        address: { line1: "1 Pickup Road", city: "Chennai" },
        location,
      },
    };
    const orderLoad = {
      totalWeightGrams: 1800,
      totalVolumeCubicMillimetres: 12_000_000,
      longestSideMillimetres: 300,
      containsBulky: false,
      eligibleTransportTypes: ["MOTORBIKE", "AUTO", "CAR"],
    };
    const snapshot = await getV1DeliveryDispatch(auth, () => Promise.resolve(new Response(
      JSON.stringify({
        offer: {
          id: assignmentId,
          missionId: orderId,
          displayOrderNumber: "DV1-1001",
          status: "OFFERED",
          poolRound: 1,
          transportType: "MOTORBIKE",
          distanceMeters: 850.5,
          offeredAt: "2026-08-22T10:00:00Z",
          respondBy: "2026-08-22T10:00:30Z",
          secondsRemaining: 24,
          pickupCount: 1,
          orderLoad,
          pickupStops: [pickupStop],
        },
        currentMission: null,
      }),
      { status: 200 },
    )));

    expect(snapshot.offer?.pickupStops[0].branch.address).toBe("1 Pickup Road, Chennai");
    expect(snapshot.offer?.transportType).toBe("MOTORBIKE");
    expect(JSON.stringify(snapshot)).not.toContain("customerAccountId");
  });

  it("sends V1 offer acceptance and all-package pickup verification", async () => {
    const requests: Array<{ body: unknown; key: string | null }> = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({
        body: JSON.parse(String(init?.body)),
        key: new Headers(init?.headers).get("X-Idempotency-Key"),
      });
      return Promise.resolve(new Response(JSON.stringify({ offer: null, currentMission: null }), {
        status: 200,
      }));
    };

    await acceptV1DeliveryOffer({
      ...auth,
      offerId: assignmentId,
      idempotencyKey: "v1-accept-key",
    }, fetcher);
    await advanceV1DeliveryMission({
      ...auth,
      missionId: orderId,
      operation: "v1VerifyPickup",
      stopId: storeId,
      accountedPackageCount: 2,
      verificationCode: "123456",
      idempotencyKey: "v1-pickup-key",
    }, fetcher);

    expect(requests).toEqual([
      {
        body: { operation: "v1AcceptOffer", offerId: assignmentId },
        key: "v1-accept-key",
      },
      {
        body: {
          operation: "v1VerifyPickup",
          missionId: orderId,
          stopId: storeId,
          accountedPackageCount: 2,
          verificationCode: "123456",
        },
        key: "v1-pickup-key",
      },
    ]);
  });

  it("rejects partial or malformed V1 pickup proof before the network", async () => {
    const fetcher = vi.fn();
    await expect(advanceV1DeliveryMission({
      ...auth,
      missionId: orderId,
      operation: "v1VerifyPickup",
      stopId: storeId,
      accountedPackageCount: 0,
      verificationCode: "1234",
      idempotencyKey: "v1-pickup-key",
    }, fetcher)).rejects.toThrow("every package");
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("parses final-delivery truth and sends evidence and customer verification commands", async () => {
    const evidenceId = "88888888-8888-4888-8888-888888888888";
    const objectPath = `rider-delivery/${accountId}/${evidenceId}.jpg`;
    const mission = {
      id: orderId,
      displayOrderNumber: "DV1-1002",
      status: "ARRIVED",
      version: 8,
      transportType: "MOTORBIKE",
      pickupCount: 1,
      assignedAt: "2026-08-22T10:00:00Z",
      firstPackagePickedUpAt: "2026-08-22T10:10:00Z",
      allPackagesPickedUpAt: "2026-08-22T10:12:00Z",
      canCancelBeforePickup: false,
      mustUseDeliveryRecovery: true,
      orderLoad: {
        totalWeightGrams: 500,
        totalVolumeCubicMillimetres: 1_000_000,
        longestSideMillimetres: 100,
        containsBulky: false,
        eligibleTransportTypes: ["MOTORBIKE"],
      },
      pickupStops: [{
        id: storeId,
        sequence: 1,
        status: "COMPLETED",
        ready: true,
        runningLate: false,
        estimatedReadyAt: "2026-08-22T10:05:00Z",
        actualReadyAt: "2026-08-22T10:04:00Z",
        packageCount: 1,
        arrivedAt: "2026-08-22T10:08:00Z",
        waitingSeconds: 120,
        branch: {
          id: storeId,
          displayName: "Operational Pickup",
          address: { line1: "1 Pickup Road" },
          location,
        },
      }],
      customerDestination: {
        address: { line1: "10 Customer Road", latitude: 12.69, longitude: 78.63 },
        recipient: { name: "Trusted Recipient", phoneNumber: "+919900000000" },
      },
      outForDeliveryAt: "2026-08-22T10:13:00Z",
      arrivedCustomerAt: "2026-08-22T10:20:00Z",
      deliveredAt: null,
      finalVerification: {
        status: "ACTIVE",
        failedAttempts: 0,
        activatedAt: "2026-08-22T10:13:00Z",
        blockedAt: null,
        evidenceRequired: true,
        evidencePresent: true,
      },
      deliveryEvidence: [{
        id: evidenceId,
        objectPath,
        contentType: "image/jpeg",
        capturedAt: "2026-08-22T10:21:00Z",
        packageCount: 1,
      }],
      canStartFinalDelivery: false,
      canArriveCustomer: false,
      canCaptureDeliveryEvidence: true,
      canVerifyDelivery: true,
    };
    const parsed = await getV1DeliveryDispatch(auth, () =>
      Promise.resolve(Response.json({ offer: null, currentMission: mission })));
    expect(parsed.currentMission?.customerDestination?.address).toBe("10 Customer Road");
    expect(parsed.currentMission?.finalVerification?.evidencePresent).toBe(true);

    const requests: Record<string, unknown>[] = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requests.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Promise.resolve(Response.json({ offer: null, currentMission: mission }));
    };
    await advanceV1DeliveryMission({
      ...auth,
      missionId: orderId,
      operation: "v1AddDeliveryEvidence",
      objectPath,
      idempotencyKey: "delivery-photo",
    }, fetcher);
    await advanceV1DeliveryMission({
      ...auth,
      missionId: orderId,
      operation: "v1VerifyDelivery",
      verificationCode: "654321",
      idempotencyKey: "delivery-code",
    }, fetcher);
    expect(requests).toEqual([
      { operation: "v1AddDeliveryEvidence", missionId: orderId, objectPath },
      { operation: "v1VerifyDelivery", missionId: orderId, verificationCode: "654321" },
    ]);
  });
});
