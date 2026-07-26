import { assertEquals, assertMatch } from "jsr:@std/assert";
import {
  type DastakPaymentDependencies,
  handleDastakPayments,
  type PaymentActionInput,
} from "../../dastak-payments/handler.ts";

Deno.test("Dastak payments serve browser preflight without authentication", async () => {
  let authenticationAttempts = 0;
  const response = await handleDastakPayments(
    new Request("http://localhost/functions/v1/dastak-payments", { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(response.status, 204);
  assertEquals(authenticationAttempts, 0);
});

Deno.test("checkout uses only the authenticated customer and order", async () => {
  let recorded: PaymentActionInput | undefined;
  const response = await handleDastakPayments(
    request(
      { operation: "createCheckout", orderId, accountId: otherAccountId, amountPaise: 1 },
      "Bearer customer-session",
      "checkout-attempt-1",
    ),
    dependencies({
      createCheckout: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: checkout, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.entityType, "merchant_order");
  assertEquals(recorded?.idempotencyKey, "checkout-attempt-1");
  assertMatch(recorded?.requestDigest ?? "", /^[0-9a-f]{64}$/);
  assertEquals("amountPaise" in (recorded ?? {}), false);
});

Deno.test("refund processing uses the authenticated actor and idempotency", async () => {
  let recorded: PaymentActionInput | undefined;
  const response = await handleDastakPayments(
    request({ operation: "processRefund", orderId }, "Bearer actor-session", "refund-attempt-1"),
    dependencies({
      processRefund: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: { orderId, refundState: "pending" },
          responseStatus: 202,
        });
      },
    }),
  );

  assertEquals(response.status, 202);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.entityType, "merchant_order");
  assertEquals(recorded?.idempotencyKey, "refund-attempt-1");
});

Deno.test("parcel checkout selects the parcel payment contract", async () => {
  let recorded: PaymentActionInput | undefined;
  const response = await handleDastakPayments(
    request(
      { operation: "createCheckout", entityType: "parcel", parcelId: orderId },
      "Bearer session",
      "parcel-checkout",
    ),
    dependencies({
      createCheckout: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: checkout, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.entityType, "parcel");
  assertEquals(recorded?.orderId, orderId);
});

Deno.test("payment actions reject missing auth and malformed input", async () => {
  const unauthenticated = await handleDastakPayments(
    request({ operation: "createCheckout", orderId }, undefined, "attempt"),
    dependencies(),
  );
  const malformed = await handleDastakPayments(
    request({ operation: "createCheckout", orderId: "not-an-id" }, "Bearer session", "attempt"),
    dependencies(),
  );

  assertEquals(unauthenticated.status, 401);
  assertEquals(malformed.status, 400);
});

const accountId = "8a000000-0000-4000-8000-000000000001";
const otherAccountId = "8a000000-0000-4000-8000-000000000002";
const orderId = "8a000000-0000-4000-8000-000000000080";
const checkout = {
  orderId,
  providerOrderId: "order_test123",
  keyId: "rzp_test_public",
  amountPaise: 8_800,
  currency: "INR",
  receipt: "dst_8a000000000040008000000000000080",
};

function dependencies(
  overrides: Partial<DastakPaymentDependencies> = {},
): DastakPaymentDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId })),
    createCheckout: overrides.createCheckout ??
      (() => Promise.resolve({ responseBody: checkout, responseStatus: 200 })),
    processRefund: overrides.processRefund ??
      (() => Promise.resolve({ responseBody: { orderId }, responseStatus: 202 })),
  };
}

function request(body: unknown, authorization?: string, idempotencyKey?: string) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request("http://localhost/functions/v1/dastak-payments", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}
