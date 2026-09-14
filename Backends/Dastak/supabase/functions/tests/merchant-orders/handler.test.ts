import { assert, assertEquals } from "jsr:@std/assert";
import {
  type CreateMerchantOrderInput,
  type CustomerCancelOrderInput,
  handleMerchantOrders,
  type MerchantConfirmReturnInput,
  type MerchantOrderDependencies,
  type MerchantOrderMutationInput,
  type MerchantOrderSnapshot,
  type MerchantRejectOrderInput,
  type OwnerResetHandoffInput,
  type OwnerResetParcelHandoffInput,
  type OwnerResolveSupportInput,
  type OwnerReviewRefundInput,
  type QuoteMerchantOrderInput,
} from "../../merchant-orders/handler.ts";

Deno.test("merchant orders serve browser preflight without authentication", async () => {
  let authenticationAttempts = 0;
  const response = await handleMerchantOrders(
    new Request("http://localhost/functions/v1/merchant-orders", { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("merchant orders reject missing authorization", async () => {
  let authenticationAttempts = 0;
  const response = await handleMerchantOrders(
    request({ operation: "customerSnapshot" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("merchant orders authenticate before validating the operation", async () => {
  const response = await handleMerchantOrders(
    request({ operation: "unsupported" }, "Bearer invalid-token"),
    dependencies({
      authenticateBearer: () => Promise.reject(new Error("invalid bearer")),
    }),
  );

  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("quote forwards product identities and quantities without client prices", async () => {
  let recorded: QuoteMerchantOrderInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "quote",
        accountId: otherAccountId,
        storeId,
        lines: [
          {
            productId,
            quantity: 2,
            unitPrice: { paise: 1 },
            lineSubtotal: { paise: 2 },
          },
        ],
        deliveryFee: { paise: 1 },
        total: { paise: 3 },
        dropoff: { latitude: 12.6819, longitude: 78.6201 },
      },
      "Bearer session-token",
      "quote-key-1",
    ),
    dependencies({
      quoteOrder: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: quote, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.storeId, storeId);
  assertEquals(recorded?.lines, [{ productId, quantity: 2 }]);
  assertEquals(recorded?.dropoffLatitude, 12.6819);
  assertEquals(recorded?.dropoffLongitude, 78.6201);
  assertEquals(recorded?.idempotencyKey, "quote-key-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
  assertEquals("deliveryFee" in (recorded ?? {}), false);
  assertEquals("total" in (recorded ?? {}), false);
});

Deno.test("quote rejects duplicate products and invalid quantities", async () => {
  let calls = 0;
  const duplicateResponse = await handleMerchantOrders(
    request(
      {
        operation: "quote",
        storeId,
        lines: [
          { productId, quantity: 1 },
          { productId: productId.toUpperCase(), quantity: 2 },
        ],
        dropoff: { latitude: 12.6819, longitude: 78.6201 },
      },
      "Bearer session-token",
      "quote-key-2",
    ),
    dependencies({
      quoteOrder: () => {
        calls += 1;
        return Promise.resolve({ responseBody: quote, responseStatus: 200 });
      },
    }),
  );
  const quantityResponse = await handleMerchantOrders(
    request(
      {
        operation: "quote",
        storeId,
        lines: [{ productId, quantity: 0 }],
        dropoff: { latitude: 12.6819, longitude: 78.6201 },
      },
      "Bearer session-token",
      "quote-key-3",
    ),
    dependencies({
      quoteOrder: () => {
        calls += 1;
        return Promise.resolve({ responseBody: quote, responseStatus: 200 });
      },
    }),
  );

  assertEquals(calls, 0);
  assertEquals(duplicateResponse.status, 400);
  assertEquals(quantityResponse.status, 400);
});

Deno.test("create forwards only the authenticated customer and server quote", async () => {
  let recorded: CreateMerchantOrderInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "create",
        accountId: otherAccountId,
        quoteId,
        itemSubtotal: { paise: 1 },
        paymentState: "paid",
      },
      "Bearer session-token",
      "create-key-1",
    ),
    dependencies({
      createOrder: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: order, responseStatus: 201 });
      },
    }),
  );

  assertEquals(response.status, 201);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.quoteId, quoteId);
  assertEquals(recorded?.idempotencyKey, "create-key-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
  assertEquals("itemSubtotal" in (recorded ?? {}), false);
  assertEquals("paymentState" in (recorded ?? {}), false);
});

Deno.test("customer and merchant snapshots use only the authenticated account", async () => {
  const requested: string[] = [];
  const customerResponse = await handleMerchantOrders(
    request(
      { operation: "customerSnapshot", accountId: otherAccountId },
      "Bearer session-token",
    ),
    dependencies({
      getCustomerOrders: (id) => {
        requested.push(`customer:${id}`);
        return Promise.resolve({ responseBody: snapshot, responseStatus: 200 });
      },
    }),
  );
  const merchantResponse = await handleMerchantOrders(
    request(
      { operation: "merchantSnapshot", accountId: otherAccountId },
      "Bearer session-token",
    ),
    dependencies({
      getMerchantOrders: (id) => {
        requested.push(`merchant:${id}`);
        return Promise.resolve({ responseBody: snapshot, responseStatus: 200 });
      },
    }),
  );

  assertEquals(customerResponse.status, 200);
  assertEquals(merchantResponse.status, 200);
  assertEquals(requested, [`customer:${accountId}`, `merchant:${accountId}`]);
  const customerOrder = ((await jsonBody(customerResponse)).orders as Array<Record<string, unknown>>)[0];
  const merchantOrder = ((await jsonBody(merchantResponse)).orders as Array<Record<string, unknown>>)[0];
  assertEquals("total" in customerOrder, true);
  assertEquals("deliveryFee" in customerOrder, true);
  assertEquals("total" in merchantOrder, false);
  assertEquals("deliveryFee" in merchantOrder, false);
  assertEquals("refundDecision" in merchantOrder, false);
  assertEquals(merchantOrder.itemSubtotal, { paise: 25000 });
});

Deno.test("customer detail and support use authenticated ownership", async () => {
  const requested: Array<Record<string, unknown>> = [];
  const detail = await handleMerchantOrders(
    request({ operation: "customerDetail", orderId, accountId: otherAccountId }, "Bearer valid"),
    dependencies({
      getCustomerOrder: (actor, requestedOrder) => {
        requested.push({ operation: "detail", actor, requestedOrder });
        return Promise.resolve({ responseBody: order, responseStatus: 200 });
      },
    }),
  );
  const support = await handleMerchantOrders(
    request(
      {
        operation: "customerSupport",
        orderId,
        category: "refund",
        message: "  Please   check my refund status. ",
      },
      "Bearer valid",
      "support-key-1",
    ),
    dependencies({
      createCustomerSupport: (input) => {
        requested.push({ operation: "support", ...input });
        return Promise.resolve({ responseBody: { supportCase: {} }, responseStatus: 201 });
      },
    }),
  );

  assertEquals(detail.status, 200);
  assertEquals(support.status, 201);
  assertEquals(requested[0], { operation: "detail", actor: accountId, requestedOrder: orderId });
  assertEquals(requested[1].accountId, accountId);
  assertEquals(requested[1].message, "Please check my refund status.");
  assertEquals(requested[1].category, "refund");
  assert((requested[1].requestDigest as string).match(/^[0-9a-f]{64}$/));
});

Deno.test("customer support rejects short messages and unknown categories", async () => {
  let calls = 0;
  const deps = dependencies({
    createCustomerSupport: () => {
      calls += 1;
      return Promise.resolve({ responseBody: {}, responseStatus: 201 });
    },
  });
  const short = await handleMerchantOrders(
    request(
      { operation: "customerSupport", orderId, category: "refund", message: "Help" },
      "Bearer valid",
      "support-key-2",
    ),
    deps,
  );
  const unknown = await handleMerchantOrders(
    request(
      { operation: "customerSupport", orderId, category: "unknown", message: "Please help me." },
      "Bearer valid",
      "support-key-3",
    ),
    deps,
  );
  assertEquals(short.status, 400);
  assertEquals(unknown.status, 400);
  assertEquals(calls, 0);
});

Deno.test("owner snapshot uses only the authenticated owner and a bounded limit", async () => {
  let requested: { accountId: string; limit: number } | undefined;
  const response = await handleMerchantOrders(
    request(
      { operation: "ownerSnapshot", accountId: otherAccountId, limit: 25 },
      "Bearer owner-session",
    ),
    dependencies({
      getOwnerOrders: (id, limit) => {
        requested = { accountId: id, limit };
        return Promise.resolve({ responseBody: { orders: [] }, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(requested, { accountId, limit: 25 });

  for (const limit of [0, 101, 1.5, "50"]) {
    const invalid = await handleMerchantOrders(
      request({ operation: "ownerSnapshot", limit }, "Bearer owner-session"),
      dependencies(),
    );
    assertEquals(invalid.status, 400);
  }
});

Deno.test("owner history page forwards authenticated search and opaque cursor", async () => {
  let requested: unknown;
  const response = await handleMerchantOrders(
    request({ operation: "ownerHistoryPage", query: " Town Store ", limit: 25, cursor: {
      createdAt: "2026-09-12T10:00:00Z", orderId,
    } }, "Bearer owner"),
    dependencies({ getOwnerOrdersPage: (input) => {
      requested = input;
      return Promise.resolve({ responseBody: { orders: [], hasMore: false, nextCursor: null }, responseStatus: 200 });
    } }),
  );
  assertEquals(response.status, 200);
  assertEquals(requested, { accountId, query: "Town Store", limit: 25,
    afterCreatedAt: "2026-09-12T10:00:00Z", afterOrderId: orderId });
});

Deno.test("merchant accept forwards an authenticated transition intent", async () => {
  let recorded: MerchantOrderMutationInput | undefined;
  const response = await handleMerchantOrders(
    request(
      { operation: "merchantAccept", orderId, merchantAccountId: otherAccountId },
      "Bearer session-token",
      "accept-key-1",
    ),
    dependencies({
      merchantAccept: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: acceptedOrder, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.idempotencyKey, "accept-key-1");
  assertEquals("merchantAccountId" in (recorded ?? {}), false);
  const responseOrder = await jsonBody(response) as Record<string, unknown>;
  assertEquals("total" in responseOrder, false);
  assertEquals("deliveryFee" in responseOrder, false);
  assertEquals(responseOrder.itemSubtotal, { paise: 25000 });
});

Deno.test("merchant reject normalizes the reason without accepting refund values", async () => {
  let recorded: MerchantRejectOrderInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "merchantReject",
        orderId,
        reason: "  Item   cannot be fulfilled  ",
        itemRefund: { paise: 1 },
        deliveryRefund: { paise: 1 },
      },
      "Bearer session-token",
      "reject-key-1",
    ),
    dependencies({
      merchantReject: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.reason, "Item cannot be fulfilled");
  assertEquals("itemRefund" in (recorded ?? {}), false);
  assertEquals("deliveryRefund" in (recorded ?? {}), false);
});

Deno.test("merchant ready forwards only the order transition", async () => {
  let recorded: MerchantOrderMutationInput | undefined;
  const response = await handleMerchantOrders(
    request(
      { operation: "merchantMarkReady", orderId, status: "ready" },
      "Bearer session-token",
      "ready-key-1",
    ),
    dependencies({
      merchantMarkReady: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: readyOrder, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals("status" in (recorded ?? {}), false);
});

Deno.test("customer cancellation sends no client refund decision", async () => {
  let recorded: CustomerCancelOrderInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "customerCancel",
        orderId,
        reason: "  Changed   my mind  ",
        eligibility: "full_refund",
        paymentState: "refunded",
      },
      "Bearer session-token",
      "cancel-key-1",
    ),
    dependencies({
      customerCancel: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.reason, "Changed my mind");
  assertEquals("eligibility" in (recorded ?? {}), false);
  assertEquals("paymentState" in (recorded ?? {}), false);
});

Deno.test("owner refund review forwards only the validated decision", async () => {
  let recorded: OwnerReviewRefundInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "ownerReviewRefund",
        orderId,
        outcome: "approve_full",
        faultSource: "merchant",
        reason: "  Merchant   could not fulfil  ",
        itemRefund: { paise: 1 },
      },
      "Bearer owner-session",
      "refund-review-key-1",
    ),
    dependencies({
      ownerReviewRefund: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.outcome, "approve_full");
  assertEquals(recorded?.faultSource, "merchant");
  assertEquals(recorded?.reason, "Merchant could not fulfil");
  assertEquals("itemRefund" in (recorded ?? {}), false);
});

Deno.test("merchant return confirmation forwards no refund amount", async () => {
  let recorded: MerchantConfirmReturnInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "merchantConfirmReturn",
        orderId,
        reason: "  Items   received back  ",
        refundAmount: 1,
      },
      "Bearer merchant-session",
      "return-key-1",
    ),
    dependencies({
      merchantConfirmReturn: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.reason, "Items received back");
  assertEquals("refundAmount" in (recorded ?? {}), false);
});

Deno.test("owner handoff recovery forwards only authenticated reset intent", async () => {
  let recorded: OwnerResetHandoffInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "ownerResetHandoff",
        accountId: otherAccountId,
        orderId,
        purpose: "pickup",
        reason: "  Merchant confirmed   the handoff.  ",
        verificationCode: "9999",
        failedAttempts: 0,
      },
      "Bearer session-token",
      "owner-reset-key-1",
    ),
    dependencies({
      ownerResetHandoff: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: order, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.purpose, "pickup");
  assertEquals(recorded?.reason, "Merchant confirmed the handoff.");
  assertEquals(recorded?.idempotencyKey, "owner-reset-key-1");
  assertEquals("verificationCode" in (recorded ?? {}), false);
  assertEquals("failedAttempts" in (recorded ?? {}), false);
});

Deno.test("owner handoff recovery validates purpose and reason", async () => {
  for (
    const body of [
      { operation: "ownerResetHandoff", orderId, purpose: "other", reason: "Review" },
      { operation: "ownerResetHandoff", orderId, purpose: "pickup", reason: "" },
      { operation: "ownerResetHandoff", orderId, purpose: "delivery" },
    ]
  ) {
    const response = await handleMerchantOrders(
      request(body, "Bearer session-token", "owner-reset-invalid"),
      dependencies(),
    );
    assertEquals(response.status, 400);
  }
});

Deno.test("owner operations use the authenticated owner and bounded limit", async () => {
  let requested: { accountId: string; limit: number } | undefined;
  const response = await handleMerchantOrders(
    request({ operation: "ownerOperations", accountId: otherAccountId, limit: 40 }, "Bearer owner"),
    dependencies({
      getOwnerOperations: (requestedAccountId, limit) => {
        requested = { accountId: requestedAccountId, limit };
        return Promise.resolve({ responseBody: { exceptions: [] }, responseStatus: 200 });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(requested, { accountId, limit: 40 });
});

Deno.test("owner exception page forwards only a complete validated cursor", async () => {
  let requested: unknown;
  const response = await handleMerchantOrders(
    request({ operation: "ownerExceptionsPage", limit: 40, cursor: {
      occurredAt: "2026-09-12T10:00:00Z", exceptionId: `support:${orderId}`,
    } }, "Bearer owner"),
    dependencies({ getOwnerExceptionsPage: (input) => {
      requested = input;
      return Promise.resolve({ responseBody: { exceptions: [], hasMore: false, nextCursor: null }, responseStatus: 200 });
    } }),
  );
  assertEquals(response.status, 200);
  assertEquals(requested, { accountId, limit: 40, afterOccurredAt: "2026-09-12T10:00:00Z",
    afterExceptionId: `support:${orderId}` });
  const invalid = await handleMerchantOrders(request({ operation: "ownerExceptionsPage", cursor: {
    occurredAt: "2026-09-12T10:00:00Z",
  } }, "Bearer owner"), dependencies());
  assertEquals(invalid.status, 400);
});

Deno.test("owner support resolution forwards normalized server intent", async () => {
  let recorded: OwnerResolveSupportInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "ownerResolveSupport",
        caseId: orderId,
        resolution: "  Customer   contacted and issue resolved. ",
      },
      "Bearer owner",
      "resolve-support-1",
    ),
    dependencies({
      ownerResolveSupport: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: { caseId: orderId }, responseStatus: 200 });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.caseId, orderId);
  assertEquals(recorded?.resolution, "Customer contacted and issue resolved.");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
});

Deno.test("owner parcel handoff recovery validates and forwards recovery intent", async () => {
  let recorded: OwnerResetParcelHandoffInput | undefined;
  const response = await handleMerchantOrders(
    request(
      {
        operation: "ownerResetParcelHandoff",
        parcelId,
        purpose: "delivery",
        reason: "Recipient identity confirmed.",
      },
      "Bearer owner",
      "reset-parcel-1",
    ),
    dependencies({
      ownerResetParcelHandoff: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: { parcelId }, responseStatus: 200 });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.parcelId, parcelId);
  assertEquals(recorded?.purpose, "delivery");
});

Deno.test("owner can request lifecycle reconciliation without client state", async () => {
  let requestedAccount: string | undefined;
  const response = await handleMerchantOrders(
    request({ operation: "ownerReconcile", status: "delivered" }, "Bearer owner"),
    dependencies({
      ownerReconcile: (requestedAccountId) => {
        requestedAccount = requestedAccountId;
        return Promise.resolve({
          responseBody: { merchantOrdersRecovered: 0 },
          responseStatus: 200,
        });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(requestedAccount, accountId);
});

Deno.test("payment confirmation is not exposed to authenticated app users", async () => {
  const response = await handleMerchantOrders(
    request(
      {
        operation: "confirmPayment",
        orderId,
        providerReference: "client-forged-payment",
      },
      "Bearer session-token",
      "payment-key-1",
    ),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "validation_failed");
});

Deno.test("merchant order dependency failures do not leak details", async () => {
  const response = await handleMerchantOrders(
    request({ operation: "customerSnapshot" }, "Bearer session-token"),
    dependencies({
      getCustomerOrders: () => Promise.reject(new Error("private order ledger unavailable")),
    }),
  );

  assertEquals(response.status, 500);
  assertEquals(await jsonBody(response), {
    error: {
      code: "internal_error",
      message: "The merchant order request could not be processed.",
    },
  });
});

const accountId = "22222222-2222-4222-8222-222222222222";
const otherAccountId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const storeId = "33333333-3333-4333-8333-333333333333";
const productId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const quoteId = "66666666-6666-4666-8666-666666666666";
const orderId = "77777777-7777-4777-8777-777777777777";
const parcelId = "99999999-9999-4999-8999-999999999999";

const line = {
  productId,
  name: "Lime Soda",
  unitLabel: "750 ml",
  unitPrice: { paise: 12_500 },
  quantity: 2,
  lineSubtotal: { paise: 25_000 },
};
const quote = {
  quoteId,
  storeId,
  lines: [line],
  itemSubtotal: { paise: 25_000 },
  deliveryFee: { paise: 4_000 },
  total: { paise: 29_000 },
  dropoff: { latitude: 12.6819, longitude: 78.6201 },
  expiresAt: "2026-07-16T15:00:00+00:00",
};
const order: MerchantOrderSnapshot = {
  orderId,
  storeId,
  status: "payment_pending",
  paymentState: "payment_pending",
  lines: [line],
  itemSubtotal: { paise: 25_000 },
  deliveryFee: { paise: 4_000 },
  total: { paise: 29_000 },
  dropoff: { latitude: 12.6819, longitude: 78.6201 },
  stateVersion: 1,
  refundDecision: null,
  createdAt: "2026-07-16T14:55:00+00:00",
  updatedAt: "2026-07-16T14:55:00+00:00",
};
const acceptedOrder: MerchantOrderSnapshot = {
  ...order,
  status: "merchant_accepted",
  paymentState: "paid",
  stateVersion: 3,
};
const readyOrder: MerchantOrderSnapshot = {
  ...acceptedOrder,
  status: "ready",
  stateVersion: 4,
};
const cancelledOrder: MerchantOrderSnapshot = {
  ...order,
  status: "cancelled",
  paymentState: "refund_pending",
  stateVersion: 3,
  refundDecision: {
    decisionId: "88888888-8888-4888-8888-888888888888",
    eligibility: "full_refund",
    decisionStatus: "eligible",
    itemRefund: { paise: 25_000 },
    deliveryFeeRefund: { paise: 4_000 },
    reason: "Item cannot be fulfilled",
    createdAt: "2026-07-16T15:05:00+00:00",
  },
};
const snapshot = { orders: [order] };

function dependencies(
  overrides: Partial<MerchantOrderDependencies> = {},
): MerchantOrderDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId })),
    quoteOrder: overrides.quoteOrder ??
      (() => Promise.resolve({ responseBody: quote, responseStatus: 200 })),
    createOrder: overrides.createOrder ??
      (() => Promise.resolve({ responseBody: order, responseStatus: 201 })),
    getCustomerOrders: overrides.getCustomerOrders ??
      (() => Promise.resolve({ responseBody: snapshot, responseStatus: 200 })),
    getCustomerOrder: overrides.getCustomerOrder ??
      (() => Promise.resolve({ responseBody: order, responseStatus: 200 })),
    createCustomerSupport: overrides.createCustomerSupport ??
      (() => Promise.resolve({ responseBody: { supportCase: {} }, responseStatus: 201 })),
    getMerchantOrders: overrides.getMerchantOrders ??
      (() => Promise.resolve({ responseBody: snapshot, responseStatus: 200 })),
    getOwnerOrders: overrides.getOwnerOrders ??
      (() => Promise.resolve({ responseBody: snapshot, responseStatus: 200 })),
    getOwnerOrdersPage: overrides.getOwnerOrdersPage ??
      (() => Promise.resolve({ responseBody: { ...snapshot, hasMore: false, nextCursor: null }, responseStatus: 200 })),
    getOwnerOperations: overrides.getOwnerOperations ??
      (() => Promise.resolve({ responseBody: { exceptions: [] }, responseStatus: 200 })),
    getOwnerExceptionsPage: overrides.getOwnerExceptionsPage ??
      (() => Promise.resolve({ responseBody: { exceptions: [], hasMore: false, nextCursor: null }, responseStatus: 200 })),
    merchantAccept: overrides.merchantAccept ??
      (() => Promise.resolve({ responseBody: acceptedOrder, responseStatus: 200 })),
    merchantReject: overrides.merchantReject ??
      (() => Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 })),
    merchantMarkReady: overrides.merchantMarkReady ??
      (() => Promise.resolve({ responseBody: readyOrder, responseStatus: 200 })),
    customerCancel: overrides.customerCancel ??
      (() => Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 })),
    merchantConfirmReturn: overrides.merchantConfirmReturn ??
      (() => Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 })),
    ownerReviewRefund: overrides.ownerReviewRefund ??
      (() => Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 })),
    ownerResetHandoff: overrides.ownerResetHandoff ??
      (() => Promise.resolve({ responseBody: order, responseStatus: 200 })),
    ownerResolveSupport: overrides.ownerResolveSupport ??
      (() => Promise.resolve({ responseBody: { caseId: orderId }, responseStatus: 200 })),
    ownerResetParcelHandoff: overrides.ownerResetParcelHandoff ??
      (() => Promise.resolve({ responseBody: { parcelId }, responseStatus: 200 })),
    ownerReconcile: overrides.ownerReconcile ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
  };
}

function request(
  body: unknown,
  authorization?: string,
  idempotencyKey?: string,
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request("http://localhost/functions/v1/merchant-orders", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function jsonBody(response: Response) {
  return await response.json();
}
