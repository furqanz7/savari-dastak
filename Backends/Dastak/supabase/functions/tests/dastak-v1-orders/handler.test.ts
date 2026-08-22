import { assertEquals } from "jsr:@std/assert";
import { V1RequestError } from "../../_shared/v1-rpc.ts";
import { handleV1Orders, type V1OrderDependencies } from "../../dastak-v1-orders/handler.ts";

Deno.test("V1 orders serves CORS preflight before authentication", async () => {
  let authCalls = 0;
  const response = await handleV1Orders(
    new Request(url, { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authCalls += 1;
        return Promise.resolve(actor);
      },
    }),
  );
  assertEquals(response.status, 204);
  assertEquals(authCalls, 0);
});

Deno.test("V1 submit forwards no client price or merchant identity", async () => {
  let recorded: unknown;
  const order = {
    deliveryAddress: { line1: "1 Launch Road", countryCode: "IN" },
    lines: [{ lineType: "RETAIL_SKU", skuId, quantity: 2 }],
  };
  const response = await handleV1Orders(
    request({ operation: "submit", expectedVersion: 0, order }, "submit-1"),
    dependencies({
      submitOrder: (input) => {
        recorded = input;
        return Promise.resolve(orderSnapshot);
      },
    }),
  );
  assertEquals(response.status, 201);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    idempotencyKey: "submit-1",
    expectedVersion: 0,
    order,
  });
});

Deno.test("V1 submit requires expected version zero and idempotency", async () => {
  let calls = 0;
  const deps = dependencies({
    submitOrder: () => {
      calls += 1;
      return Promise.resolve(orderSnapshot);
    },
  });
  const missingKey = await handleV1Orders(
    request({ operation: "submit", expectedVersion: 0, order: {} }),
    deps,
  );
  const wrongVersion = await handleV1Orders(
    request({ operation: "submit", expectedVersion: 1, order: {} }, "submit-2"),
    deps,
  );
  assertEquals(missingKey.status, 400);
  assertEquals(wrongVersion.status, 400);
  assertEquals(calls, 0);
});

Deno.test("V1 customer order list forwards a complete keyset cursor", async () => {
  let recorded: unknown;
  const response = await handleV1Orders(
    request({
      operation: "list",
      limit: 30,
      cursor: { createdAt: "2026-08-22T10:00:00Z", orderId },
    }),
    dependencies({
      listOrders: (input) => {
        recorded = input;
        return Promise.resolve({ orders: [], nextCursor: null });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    limit: 30,
    beforeCreatedAt: "2026-08-22T10:00:00Z",
    beforeOrderId: orderId,
  });
});

Deno.test("V1 customer order list rejects malformed cursors and limits", async () => {
  let calls = 0;
  const deps = dependencies({
    listOrders: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const cursor = await handleV1Orders(
    request({ operation: "list", cursor: { createdAt: "not-a-date", orderId } }),
    deps,
  );
  const limit = await handleV1Orders(request({ operation: "list", limit: 101 }), deps);
  assertEquals(cursor.status, 400);
  assertEquals(limit.status, 400);
  assertEquals(calls, 0);
});

Deno.test("V1 get and cancel accept only validated order identity", async () => {
  let getInput: unknown;
  let cancelInput: unknown;
  const deps = dependencies({
    getOrder: (input) => {
      getInput = input;
      return Promise.resolve(orderSnapshot);
    },
    cancelOrder: (input) => {
      cancelInput = input;
      return Promise.resolve({ ...orderSnapshot, status: "CANCELLED_PREPAYMENT" });
    },
  });
  const getResponse = await handleV1Orders(request({ operation: "get", orderId }), deps);
  const cancelResponse = await handleV1Orders(
    request({ operation: "cancel", orderId, expectedVersion: 2 }, "cancel-1"),
    deps,
  );
  assertEquals(getResponse.status, 200);
  assertEquals(cancelResponse.status, 200);
  assertEquals(getInput, { accessToken: actor.accessToken, orderId });
  assertEquals(cancelInput, {
    accessToken: actor.accessToken,
    orderId,
    idempotencyKey: "cancel-1",
    expectedVersion: 2,
  });
});

Deno.test("V1 orders maps stale state without leaking database details", async () => {
  const response = await handleV1Orders(
    request({ operation: "get", orderId }),
    dependencies({
      getOrder: () =>
        Promise.reject(
          new V1RequestError(
            409,
            "stale_version",
            "This information changed. Refresh and try again.",
          ),
        ),
    }),
  );
  assertEquals(response.status, 409);
  assertEquals((await body(response)).error.code, "stale_version");
});

Deno.test("V1 orders rejects missing bearer authorization", async () => {
  const response = await handleV1Orders(
    request({ operation: "list" }, undefined, ""),
    dependencies(),
  );
  assertEquals(response.status, 401);
});

const url = "http://localhost/functions/v1/dastak-v1-orders";
const skuId = "11111111-1111-4111-8111-111111111111";
const orderId = "22222222-2222-4222-8222-222222222222";
const actor = {
  accountId: "33333333-3333-4333-8333-333333333333",
  accessToken: "verified-access-token",
};
const orderSnapshot = { id: orderId, status: "MATCHING", version: 2 };

function dependencies(overrides: Partial<V1OrderDependencies> = {}): V1OrderDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ?? (() => Promise.resolve(actor)),
    submitOrder: overrides.submitOrder ?? (() => Promise.resolve(orderSnapshot)),
    listOrders: overrides.listOrders ?? (() => Promise.resolve({ orders: [], nextCursor: null })),
    getOrder: overrides.getOrder ?? (() => Promise.resolve(orderSnapshot)),
    cancelOrder: overrides.cancelOrder ?? (() => Promise.resolve(orderSnapshot)),
  };
}

function request(payload: unknown, idempotencyKey?: string, authorization = "Bearer session") {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request(url, { method: "POST", headers, body: JSON.stringify(payload) });
}

async function body(response: Response) {
  return await response.json();
}
