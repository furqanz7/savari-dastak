import { describe, expect, it } from "vitest";
import {
  createCheckoutSession,
  createV1CheckoutSession,
  processOrderRefund,
  reportV1CheckoutFailure,
} from "./payments";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};
const orderId = "8a000000-0000-4000-8000-000000000080";
const checkout = {
  orderId,
  providerOrderId: "order_test123",
  keyId: "rzp_test_public",
  amountPaise: 8_800,
  currency: "INR",
  receipt: "dst_8a000000000040008000000000000080",
};

describe("Dastak payments", () => {
  it("creates a server-authoritative checkout session", async () => {
    let requestBody: unknown;
    const result = await createCheckoutSession(
      { ...auth, orderId, idempotencyKey: "checkout-1" },
      (_input, init) => {
        requestBody = JSON.parse(String(init?.body));
        return Promise.resolve(new Response(JSON.stringify(checkout), { status: 200 }));
      },
    );

    expect(requestBody).toEqual({ operation: "createCheckout", orderId });
    expect(result).toEqual({ ...checkout, entityType: "merchant_order" });
  });

  it("accepts provider-issued test and live publishable keys", async () => {
    await expect(createCheckoutSession(
      { ...auth, orderId, idempotencyKey: "checkout-2" },
      () => Promise.resolve(new Response(JSON.stringify({ ...checkout, keyId: "rzp_live_public" }), { status: 200 })),
    )).resolves.toMatchObject({ keyId: "rzp_live_public", entityType: "merchant_order" });
  });

  it("requests an eligible provider refund without accepting client amounts", async () => {
    let requestBody: unknown;
    const result = await processOrderRefund(
      { ...auth, orderId, idempotencyKey: "refund-1" },
      (_input, init) => {
        requestBody = JSON.parse(String(init?.body));
        return Promise.resolve(new Response(JSON.stringify({ orderId, refundState: "pending" }), { status: 202 }));
      },
    );

    expect(requestBody).toEqual({ operation: "processRefund", orderId });
    expect(result).toEqual({ orderId, refundState: "pending" });
  });

  it("starts V1 checkout only after reservation and preserves its attempt", async () => {
    let requestBody: unknown;
    const attemptId = "8a000000-0000-4000-8000-000000000081";
    const result = await createV1CheckoutSession(
      { ...auth, orderId, idempotencyKey: "v1-checkout" },
      (_input, init) => {
        requestBody = JSON.parse(String(init?.body));
        return Promise.resolve(new Response(JSON.stringify({ ...checkout, attemptId }), { status: 200 }));
      },
    );
    expect(requestBody).toEqual({
      operation: "createCheckout",
      entityType: "dastak_v1_order",
      orderId,
    });
    expect(result).toMatchObject({ entityType: "dastak_v1_order", attemptId });
  });

  it("reports a dismissed V1 attempt without releasing its reservation", async () => {
    let requestBody: unknown;
    const paymentAttemptId = "8a000000-0000-4000-8000-000000000081";
    await reportV1CheckoutFailure(
      {
        ...auth,
        orderId,
        paymentAttemptId,
        failureCode: "CHECKOUT_DISMISSED",
        idempotencyKey: "v1-failed",
      },
      (_input, init) => {
        requestBody = JSON.parse(String(init?.body));
        return Promise.resolve(new Response(JSON.stringify({ status: "FAILED" }), { status: 200 }));
      },
    );
    expect(requestBody).toEqual({
      operation: "reportPaymentFailure",
      entityType: "dastak_v1_order",
      orderId,
      paymentAttemptId,
      failureCode: "CHECKOUT_DISMISSED",
    });
  });
});
