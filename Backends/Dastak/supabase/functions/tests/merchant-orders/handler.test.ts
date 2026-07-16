import { assert, assertEquals } from "jsr:@std/assert";
import {
  type CreateMerchantOrderInput,
  type CustomerCancelOrderInput,
  handleMerchantOrders,
  type MerchantOrderDependencies,
  type MerchantOrderMutationInput,
  type MerchantOrderSnapshot,
  type MerchantRejectOrderInput,
  type QuoteMerchantOrderInput,
} from "../../merchant-orders/handler.ts";

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
    getMerchantOrders: overrides.getMerchantOrders ??
      (() => Promise.resolve({ responseBody: snapshot, responseStatus: 200 })),
    merchantAccept: overrides.merchantAccept ??
      (() => Promise.resolve({ responseBody: acceptedOrder, responseStatus: 200 })),
    merchantReject: overrides.merchantReject ??
      (() => Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 })),
    merchantMarkReady: overrides.merchantMarkReady ??
      (() => Promise.resolve({ responseBody: readyOrder, responseStatus: 200 })),
    customerCancel: overrides.customerCancel ??
      (() => Promise.resolve({ responseBody: cancelledOrder, responseStatus: 200 })),
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
