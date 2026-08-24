import { afterEach, describe, expect, it, vi } from "vitest";
import {
  completeV1CustomCheckout,
  createCheckoutSession,
  createV1CheckoutSession,
  discoverRazorpayMethods,
  launchRazorpayCustomUPI,
  processOrderRefund,
  processV1Refund,
  RAZORPAY_CUSTOM_CHECKOUT_SCRIPT,
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
  currency: "INR" as const,
  receipt: "dst_8a000000000040008000000000000080",
};

describe("Dastak payments", () => {
  afterEach(() => vi.unstubAllGlobals());

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

  it("submits a provider completion without a client-authored amount", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const paymentAttemptId = "8a000000-0000-4000-8000-000000000081";
    const result = await completeV1CustomCheckout({
      ...auth,
      orderId,
      paymentAttemptId,
      completion: {
        razorpay_order_id: checkout.providerOrderId,
        razorpay_payment_id: "pay_verified123",
        razorpay_signature: "a".repeat(64),
      },
      idempotencyKey: "custom-return-1",
    }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Promise.resolve(Response.json({
        orderId,
        paymentAttemptId,
        providerPaymentId: "pay_verified123",
        state: "AWAITING_PROVIDER_CONFIRMATION",
        duplicate: false,
      }, { status: 202 }));
    });

    expect(requestBody).toEqual({
      operation: "completeCustomCheckout",
      entityType: "dastak_v1_order",
      orderId,
      paymentAttemptId,
      razorpay_order_id: checkout.providerOrderId,
      razorpay_payment_id: "pay_verified123",
      razorpay_signature: "a".repeat(64),
    });
    expect(JSON.stringify(requestBody)).not.toMatch(/amount|currency|key_secret/i);
    expect(result.state).toBe("AWAITING_PROVIDER_CONFIRMATION");
  });

  it("discovers UPI availability from Razorpay ready rather than a static list", async () => {
    installCustomCheckout({ methods: { upi: true } });
    await expect(discoverRazorpayMethods(checkout.keyId)).resolves.toEqual({ upi: true });

    installCustomCheckout({ methods: { upi: false } });
    await expect(discoverRazorpayMethods(checkout.keyId)).resolves.toEqual({ upi: false });
  });

  it.each(["intent", "qr"] as const)("launches only the selected Custom Checkout UPI %s flow", async (flow) => {
    const custom = installCustomCheckout({
      completion: {
        razorpay_order_id: checkout.providerOrderId,
        razorpay_payment_id: "pay_custom123",
        razorpay_signature: "b".repeat(64),
      },
    });
    const result = await launchRazorpayCustomUPI(
      { ...checkout, entityType: "dastak_v1_order", attemptId: "8a000000-0000-4000-8000-000000000081" },
      { email: "customer@example.test", phoneNumber: "+919500000000" },
      flow,
    );

    expect(custom.payload).toMatchObject({
      order_id: checkout.providerOrderId,
      amount: checkout.amountPaise,
      currency: "INR",
      method: "upi",
      "_[flow]": flow,
    });
    expect(result).toEqual({
      status: "success",
      completion: {
        razorpay_order_id: checkout.providerOrderId,
        razorpay_payment_id: "pay_custom123",
        razorpay_signature: "b".repeat(64),
      },
    });
  });

  it("rejects a provider completion replayed from another Razorpay order", async () => {
    installCustomCheckout({
      completion: {
        razorpay_order_id: "order_other123",
        razorpay_payment_id: "pay_other123",
        razorpay_signature: "c".repeat(64),
      },
    });
    await expect(launchRazorpayCustomUPI(
      { ...checkout, entityType: "dastak_v1_order" }, {}, "intent",
    )).resolves.toMatchObject({ status: "failed" });
  });

  it("uses razorpay.js Custom Checkout and never invokes Standard Checkout open", async () => {
    const custom = installCustomCheckout({
      completion: {
        razorpay_order_id: checkout.providerOrderId,
        razorpay_payment_id: "pay_noopen123",
        razorpay_signature: "d".repeat(64),
      },
    });
    await launchRazorpayCustomUPI({ ...checkout, entityType: "dastak_v1_order" }, {}, "intent");
    expect(RAZORPAY_CUSTOM_CHECKOUT_SCRIPT).toBe("https://checkout.razorpay.com/v1/razorpay.js");
    expect(custom.opened).toBe(false);
    expect(custom.payload?.method).toBe("upi");
  });

  it("returns a retryable customer cancellation without fabricating success", async () => {
    installCustomCheckout({
      failure: {
        error: {
          reason: "payment_cancelled",
          description: "Customer closed the selected UPI authorization",
        },
      },
    });
    await expect(launchRazorpayCustomUPI(
      { ...checkout, entityType: "dastak_v1_order" }, {}, "intent",
    )).resolves.toEqual({
      status: "failed",
      message: "Payment was cancelled. Your secured basket remains reserved.",
    });
  });

  it("processes only an approved V1 refund identity with no client-authored amount", async () => {
    const refundId = "8a000000-0000-4000-8000-000000000082";
    let requestBody: unknown;
    const result = await processV1Refund({
      ...auth, orderId, refundId, idempotencyKey: "v1-refund",
    }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(Response.json({ refundId, refundState: "pending" }));
    });
    expect(requestBody).toEqual({
      operation: "processRefund", entityType: "dastak_v1_order", orderId, refundId,
    });
    expect(JSON.stringify(requestBody)).not.toMatch(/amount|destination/);
    expect(result).toEqual({ refundId, refundState: "pending" });
  });
});

function installCustomCheckout(input: {
  methods?: Record<string, unknown>;
  completion?: Record<string, unknown>;
  failure?: Record<string, unknown>;
}) {
  const custom = { payload: undefined as Record<string, unknown> | undefined, opened: false };
  class RazorpayCustomMock {
    private handlers = new Map<string, (response: unknown) => void>();
    once(_event: string, handler: (response: unknown) => void) {
      queueMicrotask(() => handler({ methods: input.methods ?? { upi: true } }));
    }
    on(event: string, handler: (response: unknown) => void) { this.handlers.set(event, handler); }
    createPayment(payload: Record<string, unknown>) {
      custom.payload = payload;
      queueMicrotask(() => {
        if (input.failure) this.handlers.get("payment.error")?.(input.failure);
        else this.handlers.get("payment.success")?.(input.completion);
      });
    }
  }
  vi.stubGlobal("window", {
    Razorpay: RazorpayCustomMock,
    setTimeout,
    clearTimeout,
  });
  return custom;
}
