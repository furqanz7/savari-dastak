import { assertEquals } from "jsr:@std/assert";
import { prepareRazorpayTestRehearsal, type RazorpayTestRehearsalContext } from "./rehearsal.ts";

const context: RazorpayTestRehearsalContext = {
  orderId: "8a000000-0000-4000-8000-000000000080",
  attemptId: "8a000000-0000-4000-8000-000000000081",
  providerOrderId: "order_test123",
  providerMode: "TEST",
  amountPaise: 7_500,
  currency: "INR",
};

Deno.test("owner Test rehearsal selects only official Razorpay success and failure fixtures", () => {
  const success = prepareRazorpayTestRehearsal("TEST", true, context, "SUCCESS");
  const failure = prepareRazorpayTestRehearsal("TEST", true, context, "FAILURE");

  assertEquals(success.responseStatus, 200);
  assertEquals(success.responseBody, {
    testRehearsal: true,
    outcome: "SUCCESS",
    orderId: context.orderId,
    paymentAttemptId: context.attemptId,
    providerMode: "TEST",
    providerOrderId: context.providerOrderId,
    amountPaise: context.amountPaise,
    currency: "INR",
    testVpa: "success@razorpay",
  });
  assertEquals(failure.responseStatus, 200);
  assertEquals(failure.responseBody, {
    testRehearsal: true,
    outcome: "FAILURE",
    orderId: context.orderId,
    paymentAttemptId: context.attemptId,
    providerMode: "TEST",
    providerOrderId: context.providerOrderId,
    amountPaise: context.amountPaise,
    currency: "INR",
    testVpa: "failure@razorpay",
  });
});

Deno.test("Test rehearsal is structurally unavailable in Live mode", () => {
  const result = prepareRazorpayTestRehearsal(
    "LIVE",
    true,
    { ...context, providerMode: "LIVE", providerOrderId: "order_live123" },
    "SUCCESS",
  );

  assertEquals(result.responseStatus, 404);
  assertEquals(result.responseBody, {
    error: {
      code: "test_rehearsal_disabled",
      message: "Test payment rehearsal is not enabled.",
    },
  });
});

Deno.test("Test rehearsal requires owner entitlement and exact provider mode", () => {
  const nonOwner = prepareRazorpayTestRehearsal("TEST", false, context, "SUCCESS");
  const mixedMode = prepareRazorpayTestRehearsal(
    "TEST",
    true,
    { ...context, providerMode: "LIVE", providerOrderId: "order_live123" },
    "SUCCESS",
  );

  assertEquals(nonOwner.responseStatus, 403);
  assertEquals(nonOwner.responseBody, {
    error: {
      code: "test_rehearsal_forbidden",
      message: "This account cannot use payment rehearsal.",
    },
  });
  assertEquals(mixedMode.responseStatus, 409);
  assertEquals(mixedMode.responseBody, {
    error: {
      code: "test_rehearsal_mode_mismatch",
      message: "The payment attempt does not belong to the Test provider environment.",
    },
  });
});
