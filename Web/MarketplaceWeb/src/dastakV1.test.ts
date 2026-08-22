import { describe, expect, it } from "vitest";
import {
  DastakV1RequestError,
  addV1FulfilmentReadyEvidence,
  authorizeV1ExceptionalDeliveryHandoff,
  declareV1FulfilmentPackages,
  getV1AdminExecutionTrace,
  getV1Catalogue,
  getV1MerchantFulfilments,
  getV1MerchantOpportunities,
  markV1FulfilmentReady,
  merchantReadyEvidenceObjectPath,
  parseV1Catalogue,
  parseV1MerchantFulfilment,
  parseV1Order,
  respondToV1MerchantOpportunity,
  submitV1Order,
  updateV1AdminSku,
} from "./dastakV1";

const auth = {
  supabaseUrl: "http://127.0.0.1:54321",
  publishableKey: "publishable",
  accessToken: "customer-token",
};
const categoryId = "11111111-1111-4111-8111-111111111111";
const subcategoryId = "22222222-2222-4222-8222-222222222222";
const skuId = "33333333-3333-4333-8333-333333333333";
const orderId = "44444444-4444-4444-8444-444444444444";
const lineId = "55555555-5555-4555-8555-555555555555";
const fulfilmentId = "66666666-6666-4666-8666-666666666666";
const packageId = "99999999-9999-4999-8999-999999999999";

describe("Dastak V1 web contract", () => {
  it("requests a canonical customer projection without merchant discovery fields", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await getV1Catalogue({ ...auth, query: "rice" }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json(catalogueFixture());
    });

    expect(requestBody).toEqual({
      operation: "customerCatalogue", query: "rice", categoryId: null,
      subcategoryId: null, limit: 250, cursor: null,
    });
    expect(JSON.stringify(requestBody)).not.toMatch(/merchant|store|price/i);
    expect(result.skus[0]).not.toHaveProperty("merchantId");
    expect(result.skus[0]).not.toHaveProperty("storeId");
  });

  it("submits SKU and quantity only, with no client-authored price or merchant", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await submitV1Order({
      ...auth,
      idempotencyKey: "submit-once",
      order: {
        deliveryAddress: {
          line1: "12 Market Road", countryCode: "IN", latitude: 28.61, longitude: 77.2,
        },
        recipient: { name: "A Customer", phoneNumber: "+919876543210" },
        lines: [{ lineType: "RETAIL_SKU", skuId, quantity: 2 }],
      },
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("submit-once");
      return Response.json(orderFixture(), { status: 201 });
    });

    expect(result.status).toBe("MATCHING");
    expect(JSON.stringify(requestBody)).not.toMatch(/merchant|store|sellingPrice|listPrice|totalPaise/);
    expect(requestBody).toMatchObject({ operation: "submit", expectedVersion: 0 });
  });

  it("rejects a customer SKU whose selling price exceeds MRP", () => {
    const fixture = catalogueFixture();
    fixture.skus[0].sellingPricePaise = 11001;
    expect(() => parseV1Catalogue(fixture)).toThrow(DastakV1RequestError);
  });

  it("sends optimistic SKU management commands with explicit idempotency", async () => {
    let requestBody: Record<string, unknown> | undefined;
    await updateV1AdminSku({
      ...auth, skuId, expectedVersion: 7,
      patch: { sellingPricePaise: 9400, status: "ACTIVE" }, idempotencyKey: "admin-update",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("admin-update");
      return Response.json({ id: skuId, version: 8 });
    });
    expect(requestBody).toEqual({
      operation: "updateSku", skuId, expectedVersion: 7,
      patch: { sellingPricePaise: 9400, status: "ACTIVE" },
    });
  });

  it("decodes the secured payment window without exposing matching internals", () => {
    const fixture = orderFixture();
    fixture.status = "AWAITING_PAYMENT";
    Object.assign(fixture, {
      customerState: "PAYMENT_READY",
      payment: {
        status: "RESERVED", amountPaise: 19000, currencyCode: "INR",
        reservedAt: "2026-08-22T00:01:00Z", expiresAt: "2026-08-22T00:06:00Z",
        secondsRemaining: 299, canAttempt: true, canRetry: true,
        latestAttempt: {
          id: "66666666-6666-4666-8666-666666666666", status: "FAILED",
          failureCode: "CHECKOUT_FAILED", createdAt: "2026-08-22T00:02:00Z",
          failedAt: "2026-08-22T00:02:30Z",
        },
      },
    });

    const order = parseV1Order(fixture);

    expect(order.payment).toMatchObject({ amountPaise: 19000, canRetry: true });
    expect(order.payment?.latestAttempt?.status).toBe("FAILED");
    expect(JSON.stringify(order)).not.toMatch(/merchant|wave|provisional/i);
  });

  it("decodes only the parent delivery code and keeps retail merchant identity private", () => {
    const fixture = orderFixture();
    fixture.status = "OUT_FOR_DELIVERY";
    Object.assign(fixture, {
      customerState: "ON_THE_WAY",
      delivery: {
        state: "ON_THE_WAY",
        verificationStatus: "ACTIVE",
        deliveryCode: "654321",
        riderArrivedAt: null,
        deliveredAt: null,
        recipientAccountRequired: false,
      },
    });
    const order = parseV1Order(fixture);
    expect(order.delivery).toMatchObject({ deliveryCode: "654321", recipientAccountRequired: false });
    expect(JSON.stringify(order)).not.toMatch(/merchant|branch|store/i);
  });

  it("preserves exact Wave 2 subset identity in merchant responses", async () => {
    const opportunity = opportunityFixture();
    const listed = await getV1MerchantOpportunities(auth, async () => Response.json({ opportunities: [opportunity] }));
    let requestBody: Record<string, unknown> | undefined;
    const accepted = await respondToV1MerchantOpportunity({
      ...auth,
      opportunityId: listed[0].id,
      requestScope: listed[0].requestScope,
      expectedVersion: listed[0].version,
      action: "accept",
      promisedPrepMinutes: 15,
      idempotencyKey: "accept-exact-subset",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("accept-exact-subset");
      return Response.json({ ...opportunity, status: "ACCEPTED", reservationState: "PROVISIONAL_HELD", version: 2 });
    });

    expect(requestBody).toMatchObject({
      operation: "acceptMerchantOpportunity",
      opportunityId: opportunity.id,
      requestScope: "REQUESTED_SUBSET",
      promisedPrepMinutes: 15,
    });
    expect(accepted.lines).toMatchObject([{
      orderLineId: lineId, skuId, quantity: 2,
    }]);
  });

  it("requests the permission-checked execution trace by order identity", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await getV1AdminExecutionTrace({ ...auth, orderId }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({
        order: {
          id: orderId, displayOrderNumber: "DV1-0001", status: "AWAITING_PAYMENT", version: 4,
          submittedAt: "2026-08-22T00:00:00Z", fullySecuredAt: "2026-08-22T00:01:00Z",
          paymentExpiresAt: "2026-08-22T00:06:00Z", paidAt: null, updatedAt: "2026-08-22T00:01:00Z",
        },
        matchingAttempts: [], provisionalHolds: [], plans: [], capacity: [],
        payment: { status: "RESERVED" }, reconciliationCases: [],
        preparation: {
          riderMatchEligibility: { eligible: false }, fulfilments: [], packages: [],
          evidence: [], problems: [], history: [],
        },
        delivery: {
          mission: { id: fulfilmentId, status: "ASSIGNED", pickupCount: 1 },
          offers: [], pickupStops: [], verification: [], custody: [], problems: [],
          deliveryEvidence: [], exceptionalHandoffs: [],
          canAuthorizeExceptionalHandoff: true,
        },
      });
    });

    expect(requestBody).toEqual({ operation: "adminExecutionTrace", orderId });
    expect(result.payment?.status).toBe("RESERVED");
    expect(result.preparation?.fulfilments).toEqual([]);
    expect(result.delivery?.mission?.status).toBe("ASSIGNED");
  });

  it("sends a separate evidence-backed Operations override command", async () => {
    let requestBody: Record<string, unknown> | undefined;
    await authorizeV1ExceptionalDeliveryHandoff({
      ...auth,
      missionId: fulfilmentId,
      deliveryEvidenceId: packageId,
      reason: "Operations reviewed rider evidence at the customer address.",
      expectedMissionVersion: 9,
      idempotencyKey: "override-once",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("override-once");
      return Response.json({ verificationStatus: "OVERRIDDEN" });
    });
    expect(requestBody).toEqual({
      operation: "authorizeExceptionalDeliveryHandoff",
      missionId: fulfilmentId,
      deliveryEvidenceId: packageId,
      reason: "Operations reviewed rider evidence at the customer address.",
      expectedMissionVersion: 9,
    });
  });

  it("uses optimistic, idempotent preparation commands and immutable evidence paths", async () => {
    const listed = await getV1MerchantFulfilments(auth, async () => Response.json({
      fulfilments: [fulfilmentFixture()],
    }));
    expect(listed[0]).toMatchObject({ status: "PREPARING", promisedPrepMinutes: 10 });
    expect(merchantReadyEvidenceObjectPath(categoryId, "image/jpeg", subcategoryId))
      .toBe(`merchant-ready/${categoryId}/${subcategoryId}.jpg`);

    const calls: Array<{ body: Record<string, unknown>; key: string | null }> = [];
    const command = async (_url: RequestInfo | URL, init?: RequestInit) => {
      calls.push({
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
        key: new Headers(init?.headers).get("x-idempotency-key"),
      });
      return Response.json({ ...fulfilmentFixture(), version: calls.length + 1 });
    };
    await declareV1FulfilmentPackages({
      ...auth, fulfilmentId, packageCount: 2, expectedVersion: 1, idempotencyKey: "packages-once",
    }, command);
    await addV1FulfilmentReadyEvidence({
      ...auth, fulfilmentId, packageId,
      objectPath: `merchant-ready/${categoryId}/${subcategoryId}.jpg`,
      expectedVersion: 2, idempotencyKey: "evidence-once",
    }, command);
    await markV1FulfilmentReady({
      ...auth, fulfilmentId, expectedVersion: 3, idempotencyKey: "ready-once",
    }, command);

    expect(calls.map((call) => call.body.operation)).toEqual([
      "declareFulfilmentPackages", "addFulfilmentReadyEvidence", "markFulfilmentReady",
    ]);
    expect(calls.map((call) => call.key)).toEqual(["packages-once", "evidence-once", "ready-once"]);
    expect(calls[1].body).toMatchObject({ fulfilmentId, packageId, expectedVersion: 2 });
  });

  it("parses merchant pickup code and completed package custody state", () => {
    const result = parseV1MerchantFulfilment({
      ...fulfilmentFixture(),
      orderStatus: "PICKUP_IN_PROGRESS",
      status: "PICKED_UP",
      actualReadyAt: "2026-08-22T00:10:00Z",
      packageCount: 1,
      packages: [{
        id: packageId, packageNumber: 1, status: "PICKED_UP", custodyOwnerType: "RIDER",
        declaredAt: "2026-08-22T00:09:00Z", readyAt: "2026-08-22T00:10:00Z", version: 3,
      }],
      delivery: {
        missionId: categoryId,
        missionStatus: "PICKUP_IN_PROGRESS",
        riderAssigned: true,
        rider: { id: subcategoryId, displayName: "Founder Rider" },
        transportType: "MOTORBIKE",
        stopId: skuId,
        stopStatus: "COMPLETED",
        riderArrivedAt: "2026-08-22T00:11:00Z",
        waitingSeconds: 30,
        verificationStatus: "CONSUMED",
        pickupCode: null,
        pickedUpAt: "2026-08-22T00:12:00Z",
      },
    });

    expect(result.status).toBe("PICKED_UP");
    expect(result.delivery).toMatchObject({
      stopStatus: "COMPLETED",
      verificationStatus: "CONSUMED",
      waitingSeconds: 30,
    });
    expect(result.delivery?.pickupCode).toBeUndefined();
  });
});

function catalogueFixture() {
  return {
    catalogueVersion: "2026-08-22T00:00:00Z",
    categories: [{ id: categoryId, name: "Grocery", slug: "grocery", imageKey: null, sortOrder: 1 }],
    subcategories: [{ id: subcategoryId, categoryId, name: "Staples", slug: "staples", imageKey: null, sortOrder: 1 }],
    skus: [{
      id: skuId, categoryId, subcategoryId, brand: null, name: "Rice", slug: "rice-1kg",
      variant: null, packSize: "1 kg", description: null, imageKey: null, barcode: null,
      listPricePaise: 10000, sellingPricePaise: 9500, currencyCode: "INR",
      logisticsAttributes: { weightGrams: 1000 },
    }],
    nextCursor: null,
  };
}

function orderFixture() {
  return {
    id: orderId, displayOrderNumber: "DV1-0001", orderType: "RETAIL_ONLY", status: "MATCHING",
    version: 1, fulfilmentProgress: { state: "MATCHING" },
    price: {
      snapshotKind: "SUBMISSION", subtotalPaise: 19000, deliveryFeePaise: 0,
      platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 19000, currencyCode: "INR",
    },
    lines: [{
      id: lineId, lineType: "RETAIL_SKU", skuId, name: "Rice", variant: null,
      packSize: "1 kg", quantity: 2, unitPricePaise: 9500, lineTotalPaise: 19000, status: "PENDING_MATCH",
    }],
    submittedAt: "2026-08-22T00:00:00Z", fullySecuredAt: null, paymentExpiresAt: null,
    paidAt: null, deliveredAt: null, createdAt: "2026-08-22T00:00:00Z", updatedAt: "2026-08-22T00:00:00Z",
  };
}

function opportunityFixture() {
  return {
    id: "77777777-7777-4777-8777-777777777777",
    displayOrderNumber: "DV1-0001",
    requestScope: "REQUESTED_SUBSET",
    status: "OPEN",
    reservationState: "NONE",
    version: 1,
    branch: { id: "88888888-8888-4888-8888-888888888888", displayName: "Convenience Store" },
    startedAt: "2026-08-22T00:00:00Z",
    expiresAt: "2026-08-22T00:02:00Z",
    secondsRemaining: 120,
    provisionalHoldExpiresAt: null,
    promisedPrepMinutes: null,
    prepTimeOptionsMinutes: [10, 15, 20],
    physicalConfirmationRequired: true,
    capacityConsumed: false,
    orderPaymentState: null,
    lines: [{
      orderLineId: lineId, skuId, name: "Rice", variant: null,
      packSize: "1 kg", quantity: 2,
    }],
  };
}

function fulfilmentFixture() {
  return {
    id: fulfilmentId,
    orderId,
    displayOrderNumber: "DV1-0001",
    orderStatus: "PREPARING",
    status: "PREPARING",
    version: 1,
    branch: { id: "88888888-8888-4888-8888-888888888888", displayName: "Convenience Store" },
    promisedPrepMinutes: 10,
    prepStartedAt: "2026-08-22T00:02:00Z",
    estimatedReadyAt: "2026-08-22T00:12:00Z",
    actualReadyAt: null,
    secondsRemaining: 600,
    runningLate: false,
    lateSeconds: 0,
    packageCount: null,
    packages: [],
    evidence: [],
    problemReports: [],
    capacity: { status: "HELD", heldAt: "2026-08-22T00:01:00Z", releasedAt: null, releaseReason: null },
    riderMatchEligibility: {
      eligible: false, evaluatedAt: "2026-08-22T00:02:00Z", thresholdSeconds: 300,
      requiredFulfilmentCount: 1, satisfiedFulfilmentCount: 0, nextEligibleAt: "2026-08-22T00:07:00Z",
    },
    canDeclarePackages: true,
    canAddEvidence: true,
    canMarkReady: false,
    readyIsIrreversible: true,
    lines: [{ orderLineId: lineId, skuId, name: "Rice", variant: null, packSize: "1 kg", quantity: 2 }],
  };
}
