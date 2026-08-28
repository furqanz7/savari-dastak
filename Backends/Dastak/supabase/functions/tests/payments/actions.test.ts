import { assertEquals, assertMatch } from "jsr:@std/assert";
import {
  type DastakPaymentDependencies,
  handleDastakPayments,
  type PaymentActionInput,
  type PaymentCompletionInput,
  type PaymentFailureInput,
  type PaymentTestRehearsalInput,
} from "../../dastak-payments/handler.ts";
import {
  constantTimeHexEqual,
  hmacSHA256Hex,
  verifyRazorpayPaymentSignature,
} from "../../dastak-payments/verification.ts";

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

Deno.test("V1 checkout and approved original-method refund are explicit", async () => {
  let recorded: PaymentActionInput | undefined;
  const response = await handleDastakPayments(
    request(
      { operation: "createCheckout", entityType: "dastak_v1_order", orderId },
      "Bearer session",
      "v1-checkout",
    ),
    dependencies({
      createCheckout: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: checkout, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.entityType, "dastak_v1_order");
  assertEquals(recorded?.orderId, orderId);

  let recordedRefund: PaymentActionInput | undefined;
  const refund = await handleDastakPayments(
    request(
      {
        operation: "processRefund",
        entityType: "dastak_v1_order",
        orderId,
        refundId: otherAccountId,
      },
      "Bearer session",
      "v1-refund",
    ),
    dependencies({
      processRefund: (input) => {
        recordedRefund = input;
        return Promise.resolve({ responseBody: { refundState: "pending" }, responseStatus: 200 });
      },
    }),
  );
  assertEquals(refund.status, 200);
  assertEquals(recordedRefund?.refundId, otherAccountId);
  assertEquals(recordedRefund?.entityType, "dastak_v1_order");
});

Deno.test("V1 checkout failure is recorded against the authenticated reservation", async () => {
  let recorded: PaymentFailureInput | undefined;
  const response = await handleDastakPayments(
    request(
      {
        operation: "reportPaymentFailure",
        entityType: "dastak_v1_order",
        orderId,
        paymentAttemptId: otherAccountId,
        failureCode: "CHECKOUT_DISMISSED",
      },
      "Bearer session",
      "v1-failure",
    ),
    dependencies({
      reportPaymentFailure: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: { status: "FAILED" }, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.attemptId, otherAccountId);
  assertEquals(recorded?.failureCode, "CHECKOUT_DISMISSED");
});

Deno.test("Custom Checkout completion accepts only authenticated V1 provider values", async () => {
  let recorded: PaymentCompletionInput | undefined;
  const response = await handleDastakPayments(
    request(
      {
        operation: "completeCustomCheckout",
        entityType: "dastak_v1_order",
        orderId,
        paymentAttemptId: otherAccountId,
        razorpay_order_id: "order_custom123",
        razorpay_payment_id: "pay_custom456",
        razorpay_signature: "a".repeat(64),
        amountPaise: 1,
      },
      "Bearer session",
      "v1-custom-completion",
    ),
    dependencies({
      completeCustomCheckout: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: { state: "AWAITING_PROVIDER_CONFIRMATION" },
          responseStatus: 202,
        });
      },
    }),
  );

  assertEquals(response.status, 202);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.attemptId, otherAccountId);
  assertEquals(recorded?.providerOrderId, "order_custom123");
  assertEquals(recorded?.providerPaymentId, "pay_custom456");
  assertEquals("amountPaise" in (recorded ?? {}), false);
});

Deno.test("Custom Checkout completion rejects malformed or non-V1 responses", async () => {
  const malformed = await handleDastakPayments(
    request(
      {
        operation: "completeCustomCheckout",
        entityType: "dastak_v1_order",
        orderId,
        paymentAttemptId: otherAccountId,
        razorpay_order_id: "order_custom123",
        razorpay_payment_id: "pay_custom456",
        razorpay_signature: "not-a-signature",
      },
      "Bearer session",
      "bad-completion",
    ),
    dependencies(),
  );
  const legacy = await handleDastakPayments(
    request(
      {
        operation: "completeCustomCheckout",
        orderId,
        paymentAttemptId: otherAccountId,
        razorpay_order_id: "order_custom123",
        razorpay_payment_id: "pay_custom456",
        razorpay_signature: "a".repeat(64),
      },
      "Bearer session",
      "legacy-completion",
    ),
    dependencies(),
  );
  assertEquals(malformed.status, 400);
  assertEquals(legacy.status, 400);
});

Deno.test("owner Test rehearsal uses only authenticated order, attempt, and closed outcome", async () => {
  let recorded: PaymentTestRehearsalInput | undefined;
  const response = await handleDastakPayments(
    request(
      {
        operation: "prepareTestRehearsal",
        entityType: "dastak_v1_order",
        orderId,
        paymentAttemptId: otherAccountId,
        testOutcome: "SUCCESS",
        accountId: otherAccountId,
        amountPaise: 1,
        razorpay_order_id: "order_client_supplied",
        vpa: "attacker@example",
      },
      "Bearer owner-session",
      "test-rehearsal-success",
    ),
    dependencies({
      prepareTestRehearsal: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: { testRehearsal: true, outcome: "SUCCESS" },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.orderId, orderId);
  assertEquals(recorded?.attemptId, otherAccountId);
  assertEquals(recorded?.outcome, "SUCCESS");
  assertEquals(recorded?.entityType, "dastak_v1_order");
  assertEquals("amountPaise" in (recorded ?? {}), false);
  assertEquals("providerOrderId" in (recorded ?? {}), false);
  assertEquals("vpa" in (recorded ?? {}), false);
});

Deno.test("Test rehearsal rejects invalid outcomes and non-V1 entities", async () => {
  const invalidOutcome = await handleDastakPayments(
    request(
      {
        operation: "prepareTestRehearsal",
        entityType: "dastak_v1_order",
        orderId,
        paymentAttemptId: otherAccountId,
        testOutcome: "CAPTURED",
      },
      "Bearer owner-session",
      "test-rehearsal-invalid",
    ),
    dependencies(),
  );
  const legacy = await handleDastakPayments(
    request(
      {
        operation: "prepareTestRehearsal",
        orderId,
        paymentAttemptId: otherAccountId,
        testOutcome: "FAILURE",
      },
      "Bearer owner-session",
      "test-rehearsal-legacy",
    ),
    dependencies(),
  );

  assertEquals(invalidOutcome.status, 400);
  assertEquals(legacy.status, 400);
});

Deno.test("Razorpay completion signature verification is HMAC-SHA256 and timing-safe", async () => {
  const secret = "test-secret";
  const signature = await hmacSHA256Hex(secret, "order_custom123|pay_custom456");
  assertEquals(
    await verifyRazorpayPaymentSignature(secret, "order_custom123", "pay_custom456", signature),
    true,
  );
  assertEquals(
    await verifyRazorpayPaymentSignature(secret, "order_other", "pay_custom456", signature),
    false,
  );
  const tampered = `${signature[0] === "0" ? "1" : "0"}${signature.slice(1)}`;
  assertEquals(constantTimeHexEqual(signature, tampered), false);
  assertEquals(constantTimeHexEqual(signature, signature.slice(2)), false);
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
    reportPaymentFailure: overrides.reportPaymentFailure ??
      (() => Promise.resolve({ responseBody: { status: "FAILED" }, responseStatus: 200 })),
    completeCustomCheckout: overrides.completeCustomCheckout ??
      (() =>
        Promise.resolve({
          responseBody: { state: "AWAITING_PROVIDER_CONFIRMATION" },
          responseStatus: 202,
        })),
    prepareTestRehearsal: overrides.prepareTestRehearsal ??
      (() =>
        Promise.resolve({
          responseBody: { testRehearsal: true, outcome: "SUCCESS" },
          responseStatus: 200,
        })),
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
