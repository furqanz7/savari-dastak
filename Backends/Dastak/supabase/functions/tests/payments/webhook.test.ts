import { assertEquals } from "jsr:@std/assert";
import {
  handleRazorpayWebhook,
  type RazorpayWebhookDependencies,
  type RazorpayWebhookEvent,
} from "../../razorpay-webhook/handler.ts";

Deno.test("Razorpay webhook verifies raw-body signature and maps captured payment", async () => {
  const body = JSON.stringify(capturedFixture);
  let recorded: RazorpayWebhookEvent | undefined;
  const response = await handleRazorpayWebhook(
    await signedRequest(body, "event-payment-1"),
    dependencies({
      recordEvent: (event) => {
        recorded = event;
        return Promise.resolve({ responseBody: { processed: true }, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.providerEventId, "event-payment-1");
  assertEquals(recorded?.providerMode, "TEST");
  assertEquals(recorded?.eventType, "payment_captured");
  assertEquals(recorded?.providerOrderReference, "order_test123");
  assertEquals(recorded?.providerPaymentReference, "pay_test123");
  assertEquals(recorded?.amountPaise, 8_800);
  assertEquals(recorded?.occurredAt, "2026-07-22T02:40:00.000Z");
});

Deno.test("Razorpay webhook rejects a modified body with the old signature", async () => {
  const original = JSON.stringify(capturedFixture);
  const request = await signedRequest(original, "event-payment-2");
  const response = await handleRazorpayWebhook(
    new Request(request.url, {
      method: "POST",
      headers: request.headers,
      body: original.replace("8800", "8900"),
    }),
    dependencies(),
  );

  assertEquals(response.status, 401);
  assertEquals((await response.json()).error.code, "invalid_webhook_signature");
});

Deno.test("Razorpay webhook keeps live and test signatures isolated", async () => {
  const body = JSON.stringify(capturedFixture);
  let recorded: RazorpayWebhookEvent | undefined;
  const liveResponse = await handleRazorpayWebhook(
    await signedRequest(body, "event-live-1", liveWebhookSecret),
    dependencies({
      recordEvent: (event) => {
        recorded = event;
        return Promise.resolve({ responseBody: { processed: true }, responseStatus: 200 });
      },
    }),
  );
  assertEquals(liveResponse.status, 200);
  assertEquals(recorded?.providerMode, "LIVE");

  const ambiguousResponse = await handleRazorpayWebhook(
    await signedRequest(body, "event-ambiguous-1", testWebhookSecret),
    dependencies({ liveWebhookSecret: testWebhookSecret }),
  );
  assertEquals(ambiguousResponse.status, 503);
  assertEquals((await ambiguousResponse.json()).error.code, "provider_configuration_invalid");
});

Deno.test("Razorpay webhook maps processed refunds and ignores unsupported events", async () => {
  let recorded: RazorpayWebhookEvent | undefined;
  const refundBody = JSON.stringify(refundFixture);
  const refundResponse = await handleRazorpayWebhook(
    await signedRequest(refundBody, "event-refund-1"),
    dependencies({
      recordEvent: (event) => {
        recorded = event;
        return Promise.resolve({ responseBody: { processed: true }, responseStatus: 200 });
      },
    }),
  );
  const ignoredBody = JSON.stringify({ ...capturedFixture, event: "payment.failed" });
  const ignoredResponse = await handleRazorpayWebhook(
    await signedRequest(ignoredBody, "event-failed-1"),
    dependencies(),
  );

  assertEquals(refundResponse.status, 200);
  assertEquals(recorded?.eventType, "refund_succeeded");
  assertEquals(recorded?.providerPaymentReference, "pay_test123");
  assertEquals(recorded?.providerRefundReference, "rfnd_test123");
  assertEquals(ignoredResponse.status, 200);
  assertEquals((await ignoredResponse.json()).processed, false);
});

const testWebhookSecret = "test-webhook-secret";
const liveWebhookSecret = "live-webhook-secret";
const capturedFixture = {
  entity: "event",
  event: "payment.captured",
  created_at: 1784688000,
  payload: {
    payment: {
      entity: {
        id: "pay_test123",
        entity: "payment",
        amount: 8_800,
        currency: "INR",
        status: "captured",
        captured: true,
        order_id: "order_test123",
      },
    },
  },
};
const refundFixture = {
  entity: "event",
  event: "refund.processed",
  created_at: 1784688060,
  payload: {
    refund: {
      entity: {
        id: "rfnd_test123",
        entity: "refund",
        amount: 8_800,
        currency: "INR",
        status: "processed",
        payment_id: "pay_test123",
      },
    },
    payment: { entity: { id: "pay_test123", order_id: "order_test123" } },
  },
};

function dependencies(
  overrides: Partial<RazorpayWebhookDependencies> = {},
): RazorpayWebhookDependencies {
  return {
    liveWebhookSecret: overrides.liveWebhookSecret ?? liveWebhookSecret,
    testWebhookSecret: overrides.testWebhookSecret ?? testWebhookSecret,
    recordEvent: overrides.recordEvent ??
      (() => Promise.resolve({ responseBody: { processed: true }, responseStatus: 200 })),
  };
}

async function signedRequest(body: string, eventId: string, secret = testWebhookSecret) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(body),
      ),
    ),
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return new Request("http://localhost/functions/v1/razorpay-webhook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-razorpay-event-id": eventId,
      "x-razorpay-signature": signature,
    },
    body,
  });
}
