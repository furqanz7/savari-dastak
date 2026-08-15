import { describe, expect, it, vi } from "vitest";
import {
  acceptDeliveryOffer,
  advanceDeliveryJob,
  declineDeliveryOffer,
  deliveryPartnerVerificationState,
  getDeliveryDispatch,
  getDeliveryPartnerSnapshot,
  isAcceptedPartnerEvidence,
  isValidVehicleRegistration,
  normalizeVehicleRegistration,
  partnerEvidenceObjectPath,
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
        deliveryMethod: "bike",
      }), { status: 200 }));
    });

    expect(body).toEqual({
      operation: "submit",
      deliveryMethod: "bike",
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
});
