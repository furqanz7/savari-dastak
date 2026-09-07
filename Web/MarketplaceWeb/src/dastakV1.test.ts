import { describe, expect, it } from "vitest";
import {
  DastakV1RequestError,
  adminCancelV1Order,
  addV1FulfilmentReadyEvidence,
  authorizeV1ExceptionalDeliveryHandoff,
  declareV1FulfilmentPackages,
  getV1AdminAccess,
  getV1AdminCatalogue,
  getV1AdminCataloguePage,
  getV1AdminCommandCenter,
  getV1AdminExecutionTrace,
  getV1AdminNetworkPage,
  getV1AdminSystemHealth,
  getV1AdminOperationalSafety,
  getV1Catalogue,
  getV1Orders,
  getV1Restaurants,
  getV1MerchantCanonicalCatalogue,
  getV1MerchantRestaurantMenu,
  getV1MerchantFulfilments,
  getV1MerchantOpportunities,
  markV1FulfilmentReady,
  manageV1DeliveryRecovery,
  manageV1RiderEscalation,
  merchantReadyEvidenceObjectPath,
  parseV1Catalogue,
  parseV1MerchantFulfilment,
  parseV1Order,
  reportV1CustomerIssue,
  respondV1ExactSkuRecoveryOffer,
  respondV1RestaurantRequest,
  respondToV1MerchantOpportunity,
  submitV1Order,
  setV1OperationalPause,
  setV1ExecutiveAdmin,
  updateV1AdminSku,
  updateV1MerchantBranchState,
  updateV1MerchantSkuSelection,
  updateV1MerchantSkuSelections,
  upsertV1RestaurantMenuEntity,
} from "./dastakV1";
import { isV1OrderActive, orderJourneyStep, statusTitle, statusMessage, canReorderV1Order } from "./v1OrderPresentation";

const auth = {
  supabaseUrl: "http://127.0.0.1:54321",
  publishableKey: "publishable",
  accessToken: "customer-token",
};
const categoryId = "11111111-1111-4111-8111-111111111111";
const accountId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const subcategoryId = "22222222-2222-4222-8222-222222222222";
const skuId = "33333333-3333-4333-8333-333333333333";
const orderId = "44444444-4444-4444-8444-444444444444";
const lineId = "55555555-5555-4555-8555-555555555555";
const fulfilmentId = "66666666-6666-4666-8666-666666666666";
const packageId = "99999999-9999-4999-8999-999999999999";

describe("Dastak V1 web contract", () => {
  it("sends an audited admin cancellation with optimistic version and retry identity", async () => {
    let body: unknown;
    const result = await adminCancelV1Order({ ...auth, orderId,
      reason: "  Owner requested cancellation  ", expectedVersion: 5, idempotencyKey: "cancel-once",
    }, async (_url, init) => {
      body = JSON.parse(String(init?.body));
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("cancel-once");
      return Response.json({ orderId, status: "CANCELLED", version: 6 });
    });
    expect(body).toEqual({ operation: "adminCancelOrder", orderId, reason: "Owner requested cancellation", expectedVersion: 5 });
    expect(result).toMatchObject({ status: "CANCELLED", version: 6 });
  });

  it("decodes cancellation as terminal without a delivery journey or payment due message", () => {
    const order = parseV1Order({ ...orderFixture(), status: "CANCELLED" });
    expect(isV1OrderActive(order.status)).toBe(false);
    expect(orderJourneyStep(order.status)).toBeUndefined();
    expect(statusTitle(order.status)).toBe("Order cancelled");
    expect(statusMessage(order.status)).toContain("No payment is due");
    expect(canReorderV1Order(order.status)).toBe(true);
  });
  it("requests a canonical customer projection without merchant discovery fields", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await getV1Catalogue({
      ...auth,
      query: "rice",
      categoryId,
      cursor: { name: "Rice", skuId },
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json(catalogueFixture());
    });

    expect(requestBody).toEqual({
      operation: "customerCatalogue", query: "rice", categoryId,
      subcategoryId: null, limit: 250, cursor: { name: "Rice", skuId },
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

  it("discovers a visible restaurant and submits one mixed parent basket without client prices", async () => {
    const branchId = "88888888-8888-4888-8888-888888888888";
    const menuItemId = "99999999-9999-4999-8999-999999999999";
    const optionId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    let discoveryBody: Record<string, unknown> | undefined;
    const restaurants = await getV1Restaurants(auth, async (_url, init) => {
      discoveryBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({ restaurants: [restaurantFixture(branchId, menuItemId, optionId)] });
    });
    expect(discoveryBody).toEqual({ operation: "customerRestaurants", query: null, limit: 50 });
    expect(restaurants[0].restaurant.name).toBe("Dastak Cafe");

    let submitBody: Record<string, unknown> | undefined;
    const mixedOrder = orderFixture();
    mixedOrder.orderType = "MIXED";
    await submitV1Order({
      ...auth, idempotencyKey: "mixed-once",
      order: {
        deliveryAddress: { line1: "12 Market Road", countryCode: "IN", latitude: 12.68, longitude: 78.62 },
        recipient: { name: "A Customer", phoneNumber: "+919876543210" },
        restaurantBranchId: branchId,
        lines: [
          { lineType: "RETAIL_SKU", skuId, quantity: 1 },
          { lineType: "FOOD_MENU_ITEM", menuItemId, optionIds: [optionId], quantity: 2 },
        ],
      },
    }, async (_url, init) => {
      submitBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json(mixedOrder, { status: 201 });
    });
    expect(submitBody).toMatchObject({ operation: "submit", order: { restaurantBranchId: branchId } });
    expect(JSON.stringify(submitBody)).not.toMatch(/pricePaise|merchantId|storeId/);
  });

  it("uses stale-safe restaurant menu and direct confirmation commands", async () => {
    const branchId = "88888888-8888-4888-8888-888888888888";
    const menuItemId = "99999999-9999-4999-8999-999999999999";
    const optionId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const requestId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    const fixture = restaurantFixture(branchId, menuItemId, optionId);
    const menu = await getV1MerchantRestaurantMenu(auth, async () => Response.json(fixture));
    expect(menu.restaurant.softActiveOrderThreshold).toBe(5);

    const calls: Record<string, unknown>[] = [];
    await upsertV1RestaurantMenuEntity({
      ...auth, branchId, entityType: "ITEM", entityId: menuItemId, expectedVersion: 1,
      payload: { categoryId, name: "Filter Coffee", basePricePaise: 5000, status: "ACTIVE" },
      idempotencyKey: "menu-update",
    }, async (_url, init) => {
      calls.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Response.json({ entityId: menuItemId, entityType: "ITEM", menu: fixture });
    });
    await respondV1RestaurantRequest({
      ...auth, requestId, response: "CONFIRM", promisedPrepMinutes: 15,
      expectedVersion: 1, idempotencyKey: "food-confirm",
    }, async (_url, init) => {
      calls.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Response.json({
        id: requestId, orderId, displayOrderNumber: "DV1-0001", status: "CONFIRMED",
        version: 2, offeredAt: "2026-08-24T00:00:00Z", respondedAt: "2026-08-24T00:01:00Z",
        promisedPrepMinutes: 15, responseReason: null, softActiveOrderThreshold: 5,
        activeOrderCount: 6, softThresholdWarning: true, softThresholdIsBlocking: false,
        branch: { id: branchId, displayName: "Dastak Cafe", isOpen: true, acceptingOrders: true, operationalVersion: 1 },
        lines: [{ orderLineId: lineId, menuItemId, name: "Filter Coffee", variant: null, quantity: 1, unitPricePaise: 5000, selection: {} }],
        fulfilmentId,
      });
    });
    expect(calls[0]).toMatchObject({ operation: "upsertRestaurantMenuEntity", expectedVersion: 1 });
    expect(calls[1]).toEqual({ operation: "respondRestaurantRequest", requestId, response: "CONFIRM", promisedPrepMinutes: 15, reason: null, expectedVersion: 1 });
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

  it("keeps retail Merchant Web on canonical selection and audited branch controls", async () => {
    const branchId = "88888888-8888-4888-8888-888888888888";
    const organizationId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const catalogue = await getV1MerchantCanonicalCatalogue(auth, async () => Response.json({
      branch: {
        branchId, branchName: "Dastak Convenience Store", branchStatus: "ACTIVE",
        branchVersion: 1, organizationId, organizationName: "Dastak", merchantType: "RETAIL",
        operationalState: { isOpen: true, acceptingOrders: true, version: 2, updatedAt: null },
        capacity: { limit: 5, held: 1, available: 4 },
      },
      categories: [{ categoryId, name: "Grocery", slug: "grocery", sortOrder: 1 }],
      subcategories: [{ subcategoryId, categoryId, name: "Staples", slug: "staples", sortOrder: 1 }],
      skus: [{
        skuId, categoryId, subcategoryId, brandName: null, name: "Rice", variant: null,
        packSize: "1 kg", description: null, imageKey: null, listPricePaise: 10000,
        sellingPricePaise: 9500, currencyCode: "INR", catalogueStatus: "ACTIVE",
        selected: true, selectionState: "SELECTED", selectionVersion: 3, stockQuantity: 24, stockReservedQuantity: 3,
        selectionUpdatedAt: "2026-08-24T00:00:00Z",
      }],
      truncated: false,
    }));
    expect(catalogue.skus[0]).toMatchObject({ selected: true, sellingPricePaise: 9500, stockQuantity: 24, stockReservedQuantity: 3 });

    const calls: Record<string, unknown>[] = [];
    const command = async (_url: RequestInfo | URL, init?: RequestInit) => {
      calls.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBeTruthy();
      return Response.json({ ok: true });
    };
    await updateV1MerchantSkuSelection({
      ...auth, branchId, skuId, selected: false, expectedVersion: 3,
      idempotencyKey: "merchant-sku-1",
    }, command);
    await updateV1MerchantSkuSelections({
      ...auth, branchId,
      selections: [{ skuId, selected: true, expectedVersion: 4, stockQuantity: 12 }],
      idempotencyKey: "merchant-skus-1",
    }, command);
    await updateV1MerchantBranchState({
      ...auth, branchId, isOpen: true, acceptingOrders: false, expectedVersion: 2,
      idempotencyKey: "merchant-branch-1",
    }, command);
    expect(calls).toEqual([
      {
        operation: "updateMerchantSelection", branchId, skuId,
        selected: false, expectedVersion: 3,
      },
      {
        operation: "updateMerchantSelections", branchId,
        selections: [{ skuId, selected: true, expectedVersion: 4, stockQuantity: 12 }],
      },
      {
        operation: "updateBranchOperationalState", branchId,
        isOpen: true, acceptingOrders: false, expectedVersion: 2,
      },
    ]);
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
        outForDeliveryAt: "2026-08-22T00:30:00Z",
        deliveredAt: null,
        recipientAccountRequired: false,
        riderLocation: { latitude: 12.681, longitude: 78.621 },
        riderLocationUpdatedAt: "2026-08-22T00:31:00Z",
        distanceToDestinationMeters: 725,
      },
    });
    const order = parseV1Order(fixture);
    expect(order.delivery).toMatchObject({
      deliveryCode: "654321",
      recipientAccountRequired: false,
      riderLocation: { latitude: 12.681, longitude: 78.621 },
      distanceToDestinationMeters: 725,
    });
    expect(order.deliveryAddress).toMatchObject({ line1: "12 Market Road", instructions: "Call at gate" });
    expect(order.recipient).toEqual({ name: "A Customer", phoneNumber: "+919876543210" });
    expect(JSON.stringify(order)).not.toMatch(/merchant|branch|store/i);
  });

  it("paginates order history with the opaque order cursor", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const cursor = { createdAt: "2026-08-21T23:59:00Z", orderId };
    const result = await getV1Orders({ ...auth, limit: 25, cursor }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({ orders: [orderFixture()], nextCursor: cursor });
    });

    expect(requestBody).toEqual({ operation: "list", limit: 25, cursor });
    expect(result.orders).toHaveLength(1);
    expect(result.nextCursor).toEqual(cursor);
  });

  it("decodes mixed food selections and authoritative preparation timing", () => {
    const fixture = orderFixture();
    Object.assign(fixture, {
      orderType: "MIXED",
      status: "PREPARING",
      fulfilmentProgress: {
        state: "PREPARING",
        estimatedReadyAt: "2026-08-22T00:20:00Z",
        runningLate: false,
      },
      restaurant: {
        organizationId: categoryId,
        branchId: subcategoryId,
        name: "Dastak Cafe",
        branchName: "Main Road",
        imageKey: null,
      },
    });
    (fixture.lines as Array<Record<string, unknown>>).push({
      id: packageId,
      lineType: "FOOD_MENU_ITEM",
      skuId: null,
      menuItemId: fulfilmentId,
      name: "Filter Coffee",
      variant: null,
      packSize: null,
      quantity: 1,
      unitPricePaise: 5000,
      lineTotalPaise: 5000,
      status: "SECURED",
      foodSelection: {
        options: [{
          id: lineId,
          groupId: orderId,
          groupName: "Size",
          name: "Large",
          priceDeltaPaise: 500,
        }],
      },
    });

    const order = parseV1Order(fixture);
    expect(order.restaurant?.name).toBe("Dastak Cafe");
    expect(order.lines[1].foodSelection?.options[0]).toMatchObject({ groupName: "Size", name: "Large" });
    expect(order.fulfilmentProgress).toMatchObject({
      estimatedReadyAt: "2026-08-22T00:20:00Z",
      runningLate: false,
    });
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
          id: orderId, displayOrderNumber: "DV1-0001", orderType: "RETAIL_ONLY",
          status: "AWAITING_PAYMENT", version: 4,
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

  it("loads fixed Admin slots and submits only an Executive email assignment", async () => {
    const bodies: unknown[] = [];
    const access = await getV1AdminAccess(auth, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({
        role: "SUPERADMIN",
        canManageAdmins: true,
        slots: [
          { slot: 0, role: "SUPERADMIN", email: "super@example.com", linked: true, version: 1 },
          { slot: 1, role: "EXECUTIVE_ADMIN", email: null, linked: false, version: 1 },
          { slot: 2, role: "EXECUTIVE_ADMIN", email: "pending@example.com", linked: false, version: 3 },
        ],
      });
    });
    const assigned = await setV1ExecutiveAdmin({
      ...auth,
      slot: 1,
      email: "  Executive@Example.com ",
      expectedVersion: 1,
      reason: "Updated from protected Admin access settings.",
    }, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({
        slot: 1,
        role: "EXECUTIVE_ADMIN",
        email: "executive@example.com",
        linked: true,
        version: 2,
      });
    });
    expect(access).toMatchObject({
      role: "SUPERADMIN",
      canManageAdmins: true,
      slots: [{ slot: 0 }, { slot: 1 }, { slot: 2, linked: false }],
    });
    expect(assigned).toMatchObject({ slot: 1, email: "executive@example.com", linked: true });
    expect(bodies).toEqual([
      { operation: "adminAccess" },
      {
        operation: "setExecutiveAdmin",
        slot: 1,
        email: "executive@example.com",
        expectedVersion: 1,
        reason: "Updated from protected Admin access settings.",
      },
    ]);
  });

  it("loads the cross-system Admin command center and connected identity directory", async () => {
    const bodies: unknown[] = [];
    const commandCenter = await getV1AdminCommandCenter(auth, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({
        observedAt: "2026-08-31T12:34:56Z",
        actionQueue: { merchantApplications: 2, deliveryApplications: 1, openIncidents: 0, riderEscalations: 1, activePauses: 0 },
        identities: { activeAccounts: 10, customers: 8, merchants: 3, deliveryPartners: 4, deletedPersonas: 1, recoveryEligiblePhones: 1 },
        commerce: { activeOrders: 7, awaitingPayment: 1, preparingFulfilments: 2, readyFulfilments: 1, activeMissions: 3, deliveredToday: 5 },
        network: { activeOrganizations: 3, activeBranches: 4, onlineRiders: 2, assignedRiders: 1 },
        catalogue: { total: 3637, active: 3000, draft: 637, needsReview: 20, missingPrimaryImage: 12 },
      });
    });
    const network = await getV1AdminNetworkPage({
      ...auth,
      query: "  Furqan  ",
      persona: "MERCHANT",
      state: "ACTIVE",
      limit: 40,
      cursor: { updatedAt: "2026-08-31T12:00:00Z", accountId },
    }, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({
        people: [{
          id: accountId,
          displayName: "Furqan",
          email: "furqan@example.com",
          phoneNumber: "+919000000000",
          phoneVerified: true,
          accountState: "ACTIVE",
          adminRole: "EXECUTIVE_ADMIN",
          createdAt: "2026-08-01T10:00:00Z",
          updatedAt: "2026-08-31T12:00:00Z",
          lastSignInAt: "2026-08-31T11:00:00Z",
          personas: [{ persona: "MERCHANT", state: "ACTIVE", activatedAt: "2026-08-02T10:00:00Z", deletedAt: null, version: 1 }],
          customer: { orderCount: 4, activeOrderCount: 1 },
          merchant: { applicationStatus: "approved", businessName: "Dastak Store", submittedAt: "2026-08-02T10:00:00Z", reviewedAt: "2026-08-03T10:00:00Z", organizationName: "Dastak Store", organizationStatus: "ACTIVE", branchCount: 2 },
          delivery: null,
        }],
        hasMore: true,
        nextCursor: { updatedAt: "2026-08-31T12:00:00Z", accountId },
      });
    });

    expect(commandCenter.actionQueue).toMatchObject({ merchantApplications: 2, deliveryApplications: 1 });
    expect(commandCenter.catalogue.total).toBe(3637);
    expect(network.people[0]).toMatchObject({
      displayName: "Furqan",
      adminRole: "EXECUTIVE_ADMIN",
      merchant: { businessName: "Dastak Store", branchCount: 2 },
    });
    expect(bodies).toEqual([
      { operation: "adminCommandCenter" },
      {
        operation: "adminNetworkPage",
        query: "Furqan",
        persona: "MERCHANT",
        state: "ACTIVE",
        limit: 40,
        cursor: { updatedAt: "2026-08-31T12:00:00Z", accountId },
      },
    ]);
  });

  it("loads the paginated exact-SKU Admin catalogue without raw import data", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const catalogue = await getV1AdminCataloguePage({
      ...auth,
      query: "  Whole Wheat  ",
      status: "ACTIVE",
      qaStatus: "VERIFIED",
      limit: 50,
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({
        skus: [{
          id: skuId,
          categoryTypeId: packageId,
          categoryTypeName: "Groceries",
          categoryId,
          categoryName: "Staples",
          subcategoryId,
          subcategoryName: "Flours",
          brandId: null,
          brandName: "Dastak",
          name: "Whole Wheat Atta",
          slug: "whole-wheat-atta",
          variant: null,
          packSize: "1 kg",
          description: "Whole wheat flour",
          imageKey: "catalogue/atta.webp",
          barcode: null,
          listPricePaise: 8000,
          sellingPricePaise: 7500,
          currencyCode: "INR",
          logisticsAttributes: {},
          taxRateBps: 0,
          status: "ACTIVE",
          selectionCount: 2,
          version: 4,
          updatedAt: "2026-08-31T12:00:00Z",
          qaStatus: "VERIFIED",
          activationReady: true,
          activationBlockers: [],
          imageCount: 1,
          aliasCount: 2,
          identifierCount: 1,
          primaryImage: {
            id: "88888888-8888-4888-8888-888888888888",
            imageKey: "catalogue/atta-primary.webp",
            status: "VERIFIED",
            rightsStatus: "CLEARED",
            sourceType: "ADMIN_UPLOAD",
          },
          quantityValue: 1,
          quantityUnit: "kg",
          packCount: 1,
          manufacturerName: "Dastak Foods",
          countryOfOriginCode: "IN",
          hsnCode: "11010000",
          dietType: "VEGETARIAN",
          shelfLifeDays: 180,
          attributes: {},
        }, {
          id: "99999999-9999-4999-8999-999999999999",
          categoryTypeId: packageId,
          categoryTypeName: "Groceries",
          categoryId,
          categoryName: "Staples",
          subcategoryId,
          subcategoryName: "Flours",
          brandId: null,
          brandName: null,
          name: "Unpriced Draft",
          slug: "unpriced-draft",
          variant: null,
          packSize: "1 pack",
          description: null,
          imageKey: null,
          barcode: null,
          listPricePaise: null,
          sellingPricePaise: null,
          currencyCode: "INR",
          logisticsAttributes: {},
          taxRateBps: 0,
          status: "DRAFT",
          selectionCount: 0,
          version: 1,
          updatedAt: "2026-08-31T12:00:00Z",
          qaStatus: "NEEDS_REVIEW",
          activationReady: false,
          activationBlockers: ["DASTAK_PRICING_REQUIRED"],
          imageCount: 0,
          aliasCount: 0,
          identifierCount: 0,
          primaryImage: null,
          quantityValue: null,
          quantityUnit: null,
          packCount: null,
          manufacturerName: null,
          countryOfOriginCode: null,
          hsnCode: null,
          dietType: "UNSPECIFIED",
          shelfLifeDays: null,
          attributes: {},
        }],
        hasMore: false,
        nextCursor: null,
      });
    });

    expect(requestBody).toEqual({
      operation: "adminCataloguePage",
      query: "Whole Wheat",
      categoryTypeId: null,
      categoryId: null,
      subcategoryId: null,
      status: "ACTIVE",
      qaStatus: "VERIFIED",
      limit: 50,
      cursor: null,
    });
    expect(catalogue.skus[0]).toMatchObject({
      name: "Whole Wheat Atta",
      categoryTypeName: "Groceries",
      categoryName: "Staples",
      subcategoryName: "Flours",
      sellingPricePaise: 7500,
      qaStatus: "VERIFIED",
      activationReady: true,
      activationBlockers: [],
      identifierCount: 1,
      primaryImage: { rightsStatus: "CLEARED" },
    });
    expect(catalogue.skus[0]).not.toHaveProperty("sourcePayload");
    expect(catalogue.skus[1]).toMatchObject({
      name: "Unpriced Draft",
      listPricePaise: undefined,
      sellingPricePaise: undefined,
      activationReady: false,
      activationBlockers: ["DASTAK_PRICING_REQUIRED"],
    });
  });

  it("loads the Admin taxonomy hierarchy with refresh-safe entity metadata", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const updatedAt = "2026-09-01T10:00:00Z";
    const snapshot = await getV1AdminCatalogue(auth, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({
        categoryTypes: [{
          id: packageId, name: "Groceries", slug: "groceries", imageKey: null,
          previewImageKeys: ["catalogue/rice.webp", "catalogue/atta.webp"],
          navigationSection: { key: "grocery-kitchen", name: "Grocery & Kitchen", sortOrder: 10 },
          sortOrder: 1, status: "ACTIVE", version: 2, updatedAt,
        }],
        categories: [{
          id: categoryId, categoryTypeId: packageId, name: "Staples", slug: "staples",
          imageKey: null, sortOrder: 1, status: "ACTIVE", version: 3, updatedAt,
        }],
        subcategories: [{
          id: subcategoryId, categoryId, name: "Flours", slug: "flours", imageKey: null,
          sortOrder: 1, status: "ACTIVE", version: 4, updatedAt,
        }],
        brands: [], skus: [], skuCount: 1, truncated: false, configuration: [], branches: [],
      });
    });

    expect(requestBody).toEqual({ operation: "adminSnapshot", skuLimit: 1000 });
    expect(snapshot.categoryTypes[0]).toMatchObject({
      name: "Groceries",
      previewImageKeys: ["catalogue/rice.webp", "catalogue/atta.webp"],
      navigationSection: { key: "grocery-kitchen", name: "Grocery & Kitchen", sortOrder: 10 },
      updatedAt,
    });
    expect(snapshot.categories[0]).toMatchObject({ categoryTypeId: packageId, name: "Staples" });
    expect(snapshot.subcategories[0]).toMatchObject({ categoryId, name: "Flours" });
  });

  it("decodes the audited minimum system health projection", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await getV1AdminSystemHealth(auth, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({
        healthy: false,
        workerConfigured: true,
        openCriticalIncidentCount: 1,
        incidents: [{
          id: categoryId,
          invariantKey: "ORDER_MULTIPLE_ACTIVE_MISSIONS",
          entityType: "ORDER",
          entityId: orderId,
          details: { missionCount: 2 },
          firstDetectedAt: "2026-08-23T00:00:00Z",
          lastDetectedAt: "2026-08-23T00:01:00Z",
          occurrenceCount: 2,
        }],
        lastMonitorRun: {
          id: subcategoryId,
          findingCount: 1,
          startedAt: "2026-08-23T00:01:00Z",
          completedAt: "2026-08-23T00:01:01Z",
        },
        outbox: {
          pending: 3,
          deadLetter: 0,
          oldestPendingSeconds: 12,
          staleThresholdSeconds: 300,
        },
        notifications: { pending: 2, inFlight: 1, deadLetter: 0 },
        paymentReconciliationOpen: 1,
        operationalAlerts: {
          breached: true,
          counts: {
            outboxPendingCount: 3, notificationPendingCount: 2,
            paymentReconciliationOpenCount: 1, riderEscalationOpenCount: 1,
            merchantUnreachableBranchCount: 0, customerUnreachableDueCount: 0,
          },
          thresholds: {
            outboxPendingCount: 10, notificationPendingCount: 10,
            paymentReconciliationOpenCount: 0, riderEscalationOpenCount: 0,
            merchantUnreachableBranchCount: 0, customerUnreachableDueCount: 0,
          },
        },
        observedAt: "2026-08-23T00:01:02Z",
      });
    });
    expect(requestBody).toEqual({ operation: "adminSystemHealth" });
    expect(result).toMatchObject({
      healthy: false,
      openCriticalIncidentCount: 1,
      outbox: { pending: 3 },
      notifications: { inFlight: 1 },
    });
    expect(result.incidents[0].invariantKey).toBe("ORDER_MULTIPLE_ACTIVE_MISSIONS");
  });

  it("decodes and operates only named V1 safety controls", async () => {
    const bodies: unknown[] = [];
    const safety = await getV1AdminOperationalSafety(auth, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({
        permissions: { canManageRiderEscalations: true, canManageOperationalPauses: true },
        pauses: [{
          id: categoryId, scope: "ZONE_RETAIL", targetId: subcategoryId,
          active: true, reason: "Weather safety", activatedAt: "2026-08-24T00:00:00Z",
          clearedAt: null, version: 1,
        }],
        riderEscalations: [{
          missionId: fulfilmentId, orderId, displayOrderNumber: "DV1-0001",
          status: "ASSIGNED", riderId: skuId, transportType: "MOTORBIKE",
          lastContactAt: "2026-08-24T00:00:00Z", lastProgressAt: "2026-08-24T00:00:00Z",
          stallDetectedAt: "2026-08-24T00:01:00Z", unresponsiveDetectedAt: null,
          escalationState: "STALLED", escalatedAt: "2026-08-24T00:01:00Z",
          escalationReason: "RIDER_PROGRESS_STALLED", custodyStarted: false, version: 4,
        }],
      });
    });
    expect(safety.pauses[0].scope).toBe("ZONE_RETAIL");
    expect(safety.riderEscalations[0].custodyStarted).toBe(false);

    await manageV1RiderEscalation({
      ...auth, missionId: fulfilmentId, action: "RELEASE_REMATCH",
      reason: "Operations released an unresponsive rider.", expectedVersion: 4,
      idempotencyKey: "release-rider",
    }, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({ missionId: fulfilmentId, status: "SEARCHING_RIDER" });
    });
    await setV1OperationalPause({
      ...auth, scope: "ZONE_MIXED", targetId: subcategoryId, active: true,
      reason: "Severe weather", expectedVersion: 0, idempotencyKey: "pause-mixed",
    }, async (_url, init) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({ id: categoryId, active: true });
    });
    expect(bodies).toEqual([
      { operation: "adminOperationalSafety" },
      {
        operation: "manageRiderEscalation", missionId: fulfilmentId,
        action: "RELEASE_REMATCH", reason: "Operations released an unresponsive rider.",
        expectedVersion: 4,
      },
      {
        operation: "setOperationalPause", scope: "ZONE_MIXED",
        targetId: subcategoryId, active: true, reason: "Severe weather", expectedVersion: 0,
      },
    ]);
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

  it("parses a Restaurant/Cafe fulfilment without requiring a retail SKU", () => {
    const result = parseV1MerchantFulfilment({
      ...fulfilmentFixture(),
      fulfilmentType: "FOOD",
      capacity: null,
      lines: [{
        orderLineId: lineId,
        menuItemId: skuId,
        name: "Masala dosa",
        variant: "Mild",
        packSize: null,
        quantity: 2,
        selection: { options: [{ name: "Mild" }] },
      }],
    });

    expect(result.fulfilmentType).toBe("FOOD");
    expect(result.capacity).toBeUndefined();
    expect(result.lines[0]).toMatchObject({ menuItemId: skuId, skuId: undefined, quantity: 2 });
  });

  it("parses private customer recovery truth and reports an evidence-linked issue", async () => {
    const fixture = orderFixture();
    Object.assign(fixture, {
      support: {
        canReportIssue: true,
        recovery: [{
          id: categoryId, type: "EXACT_SKU", status: "RECOVERED", orderLineId: lineId,
          openedAt: "2026-08-22T00:10:00Z", resolvedAt: "2026-08-22T00:11:00Z",
          customerMessage: "We secured the exact item.",
        }],
        issues: [{
          id: subcategoryId, orderLineId: lineId, category: "DAMAGED", status: "OPEN",
          description: "Seal damaged", reportedAt: "2026-08-22T00:20:00Z",
          resolution: null, resolvedAt: null, version: 1,
          evidence: [{
            id: packageId, objectPath: `customer-issue/${categoryId}/${packageId}.jpg`,
            contentType: "image/jpeg", capturedAt: "2026-08-22T00:20:00Z",
          }],
        }],
        returns: [],
        refunds: [{
          id: fulfilmentId, orderLineId: lineId, status: "PROCESSING",
          destination: "ORIGINAL_PAYMENT_METHOD", amountPaise: 900, currency: "INR",
          reason: "Approved issue", createdAt: "2026-08-22T00:21:00Z", completedAt: null,
        }],
      },
    });
    const parsed = parseV1Order(fixture);
    expect(parsed.support?.recovery[0].customerMessage).toBe("We secured the exact item.");
    expect(parsed.support?.refunds[0]).toMatchObject({
      destination: "ORIGINAL_PAYMENT_METHOD", amountPaise: 900,
    });
    expect(JSON.stringify(parsed.support)).not.toMatch(/Secret|merchantId|branchId/);

    let requestBody: Record<string, unknown> | undefined;
    await reportV1CustomerIssue({
      ...auth, orderId, orderLineId: lineId, category: "DAMAGED",
      description: "Seal damaged",
      objectPath: `customer-issue/${categoryId}/${packageId}.jpg`,
      contentType: "image/jpeg", idempotencyKey: "issue-once",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({ issueId: subcategoryId });
    });
    expect(requestBody).toEqual({
      operation: "reportCustomerIssue", orderId, orderLineId: lineId,
      category: "DAMAGED", description: "Seal damaged",
      objectPath: `customer-issue/${categoryId}/${packageId}.jpg`, contentType: "image/jpeg",
    });
  });

  it("accepts an exact recovery offer without a client price or quantity override", async () => {
    let requestBody: Record<string, unknown> | undefined;
    await respondV1ExactSkuRecoveryOffer({
      ...auth, recoveryOpportunityId: orderId, response: "ACCEPT",
      promisedPrepMinutes: 10, expectedVersion: 1, idempotencyKey: "recovery-accept",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({ status: "RECOVERED" });
    });
    expect(requestBody).toEqual({
      operation: "respondExactSkuRecoveryOffer", recoveryOpportunityId: orderId,
      response: "ACCEPT", promisedPrepMinutes: 10, expectedVersion: 1,
    });
    expect(JSON.stringify(requestBody)).not.toMatch(/price|quantity|substitut/i);
  });

  it("resumes delivery recovery with an audited minor address correction", async () => {
    let requestBody: Record<string, unknown> | undefined;
    await manageV1DeliveryRecovery({
      ...auth, recoveryCaseId: orderId, action: "RESUME_DELIVERY",
      faultSource: "CUSTOMER", reason: "Customer confirmed the corrected address.",
      correctedAddress: { line1: "3A Recovery Road", latitude: 12.68, longitude: 78.62 },
      expectedVersion: 2, idempotencyKey: "resume-delivery",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({ recoveryStatus: "RESOLVED", missionStatus: "OUT_FOR_DELIVERY" });
    });
    expect(requestBody).toEqual({
      operation: "manageDeliveryRecovery", recoveryCaseId: orderId,
      action: "RESUME_DELIVERY", faultSource: "CUSTOMER", refundAmountPaise: null,
      correctedAddress: { line1: "3A Recovery Road", latitude: 12.68, longitude: 78.62 },
      reason: "Customer confirmed the corrected address.", expectedVersion: 2,
    });
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

function restaurantFixture(branchId: string, menuItemId: string, optionId: string) {
  return {
    restaurant: {
      organizationId: categoryId, branchId, name: "Dastak Cafe", branchName: "Main Road",
      imageKey: null, description: "Fresh food", serviceZoneId: subcategoryId,
      acceptingOrders: true, isOpen: true, operationalVersion: 1,
      branchStatus: "ACTIVE", merchantType: "RESTAURANT_CAFE",
      softActiveOrderThreshold: 5, activeOrderCount: 6,
    },
    categories: [{
      id: categoryId, name: "Drinks", description: null, sortOrder: 1, status: "ACTIVE", version: 1,
      items: [{
        id: menuItemId, name: "Filter Coffee", description: null, imageKey: null,
        basePricePaise: 4500, currencyCode: "INR", taxRateBps: 0,
        logisticsAttributes: {}, status: "ACTIVE", version: 1,
        optionGroups: [{
          id: subcategoryId, name: "Size", selectionType: "SINGLE",
          minimumSelections: 1, maximumSelections: 1, sortOrder: 1,
          status: "ACTIVE", version: 1,
          options: [{ id: optionId, name: "Large", priceDeltaPaise: 500, sortOrder: 1, status: "ACTIVE", version: 1 }],
        }],
      }],
    }],
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
    deliveryAddress: {
      label: "Home", line1: "12 Market Road", line2: null, landmark: null,
      city: "Vaniyambadi", state: "Tamil Nadu", postalCode: "635751",
      countryCode: "IN", latitude: 12.68, longitude: 78.62,
      instructions: "Call at gate",
    },
    recipient: { name: "A Customer", phoneNumber: "+919876543210" },
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
