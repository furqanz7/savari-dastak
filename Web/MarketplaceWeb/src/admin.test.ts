import { describe, expect, it } from "vitest";
import {
  getAdminOrders,
  getEvidenceUrl,
  getMerchantApplications,
  getPartnerApplications,
  reviewMerchantApplication,
  reviewOrderRefund,
  reviewPartnerApplication,
} from "./admin";

const accountId = "11111111-1111-4111-8111-111111111111";
const applicationId = "22222222-2222-4222-8222-222222222222";
const orderId = "33333333-3333-4333-8333-333333333333";
const storeId = "44444444-4444-4444-8444-444444444444";
const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

describe("Dastak Admin client", () => {
  it("loads merchant and delivery-partner review queues", async () => {
    const merchant = {
      applicationId,
      accountId,
      businessName: "Town Store",
      businessAddress: "Main Road",
      evidenceObjectPath: `merchant/${accountId}/proof.pdf`,
      status: "pending",
    };
    const partner = {
      applicationId,
      accountId,
      displayName: "Partner One",
      phoneNumber: "+919999999999",
      deliveryMethod: "bike",
      identityEvidenceObjectPath: `dastak-partner/${accountId}/identity.jpg`,
      vehicleRegistrationNumber: "TN 23 AB 1234",
      vehicleMakeModel: "Bajaj Pulsar 150",
      vehicleEvidenceObjectPath: `dastak-partner/${accountId}/vehicle-rc.pdf`,
      status: "pending",
      submittedAt: "2026-07-22T06:00:00Z",
    };

    expect(await getMerchantApplications(auth, response({ applications: [merchant] }))).toEqual([merchant]);
    expect(await getPartnerApplications(auth, response({ applications: [partner] }))).toEqual([partner]);
  });

  it("sends owner review decisions with normalized reasons and idempotency", async () => {
    const requests: Array<{ body: unknown; key: string | null }> = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({ body: JSON.parse(String(init?.body)), key: new Headers(init?.headers).get("X-Idempotency-Key") });
      return Promise.resolve(new Response(JSON.stringify({ status: "ok" }), { status: 200 }));
    };

    await reviewMerchantApplication({ ...auth, applicationId, decision: "approve", idempotencyKey: "merchant-key" }, fetcher);
    await reviewPartnerApplication({ ...auth, applicationId, decision: "reject", reason: "  Invalid   identity  ", idempotencyKey: "partner-key" }, fetcher);

    expect(requests).toEqual([
      { body: { operation: "review", applicationId, decision: "approve", reason: null }, key: "merchant-key" },
      { body: { operation: "review", applicationId, decision: "reject", reason: "Invalid identity" }, key: "partner-key" },
    ]);
  });

  it("requires a reason before rejecting", async () => {
    await expect(reviewPartnerApplication({
      ...auth,
      applicationId,
      decision: "reject",
      idempotencyKey: "partner-key",
    })).rejects.toThrow("admin request is invalid");
  });

  it("requests a short-lived HTTPS evidence link", async () => {
    let requestBody: unknown;
    const objectPath = `merchant/${accountId}/proof.pdf`;
    const url = await getEvidenceUrl({ ...auth, objectPath }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({ signedUrl: "https://files.example.test/proof", expiresIn: 300 }), { status: 200 }));
    });

    expect(url).toBe("https://files.example.test/proof");
    expect(requestBody).toEqual({ operation: "download", bucket: "dastak-evidence", objectPath });
  });

  it("loads the bounded owner order feed", async () => {
    let requestBody: unknown;
    const order = {
      orderId,
      store: { storeId, name: "Town Store" },
      status: "ready",
      paymentState: "paid",
      itemSubtotal: { paise: 20_000 },
      deliveryFee: { paise: 4_000 },
      total: { paise: 24_000 },
      itemCount: 2,
      assignmentStatus: "offered",
      controlledScope: "general",
      createdAt: "2026-07-22T06:00:00Z",
      updatedAt: "2026-07-22T06:05:00Z",
    };
    const orders = await getAdminOrders({ ...auth, limit: 25 }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({ orders: [order] }), { status: 200 }));
    });

    expect(requestBody).toEqual({ operation: "ownerSnapshot", limit: 25 });
    expect(orders).toEqual([{ ...order, refundDecision: null }]);
  });

  it("sends an owner refund decision without accepting client amounts", async () => {
    let requestBody: unknown;
    const reviewedOrder = {
      orderId,
      storeId,
      status: "cancelled",
      paymentState: "refund_pending",
      lines: [{
        productId: "55555555-5555-4555-8555-555555555555",
        name: "Water",
        unitLabel: "1 litre",
        unitPrice: { paise: 2_000 },
        quantity: 1,
        lineSubtotal: { paise: 2_000 },
      }],
      itemSubtotal: { paise: 2_000 },
      deliveryFee: { paise: 3_500 },
      deliveryDistanceMeters: 2_000,
      total: { paise: 5_500 },
      dropoff: { latitude: 12.6819, longitude: 78.6201 },
      stateVersion: 4,
      handoffCode: null,
      refundDecision: {
        eligibility: "full_refund",
        decisionStatus: "eligible",
        itemRefund: { paise: 2_000 },
        deliveryFeeRefund: { paise: 3_500 },
        reason: "Merchant could not fulfil",
      },
      createdAt: "2026-07-22T06:00:00Z",
      updatedAt: "2026-07-22T06:05:00Z",
    };
    const result = await reviewOrderRefund({
      ...auth,
      orderId,
      outcome: "approve_full",
      faultSource: null,
      reason: "  Merchant   could not fulfil  ",
      idempotencyKey: "refund-key",
    }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify(reviewedOrder), { status: 200 }));
    });

    expect(result.paymentState).toBe("refund_pending");
    expect(requestBody).toEqual({
      operation: "ownerReviewRefund",
      orderId,
      outcome: "approve_full",
      faultSource: null,
      reason: "Merchant could not fulfil",
    });
  });

  it("preserves owner access errors", async () => {
    await expect(getAdminOrders(auth, () => Promise.resolve(new Response(JSON.stringify({
      error: { code: "access_denied", message: "An active Dastak owner account is required." },
    }), { status: 403 })))).rejects.toMatchObject({ code: "access_denied", status: 403 });
  });
});

function response(body: unknown) {
  return () => Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
}
