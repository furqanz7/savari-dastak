import { afterEach, describe, expect, it, vi } from "vitest";
import {
  assertCheckoutProviderMode,
  completeV1CustomCheckout,
  createCheckoutSession,
  createV1CheckoutSession,
  discoverRazorpayMethods,
  launchRazorpayCustomUPI,
  launchRazorpayTestUPI,
  mobileUPIOptions,
  prepareV1TestRehearsal,
  processOrderRefund,
  processV1Refund,
  RAZORPAY_CUSTOM_CHECKOUT_SCRIPT,
  RAZORPAY_TEST_UPI_LIMITATION_MESSAGE,
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
  providerMode: "TEST" as const,
  amountPaise: 8_800,
  currency: "INR" as const,
  receipt: "dst_8a000000000040008000000000000080",
  testRehearsalAvailable: true,
};
const liveCheckout = {
  ...checkout,
  providerOrderId: "order_live123",
  keyId: "rzp_live_public",
  providerMode: "LIVE" as const,
  testRehearsalAvailable: false,
};
const customer = {
  email: "customer@example.test",
  phoneNumber: "+919500000000",
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
      () => Promise.resolve(new Response(JSON.stringify(liveCheckout), { status: 200 })),
    )).resolves.toMatchObject({ keyId: "rzp_live_public", entityType: "merchant_order" });
  });

  it("requires explicit mode for V1 and rejects Test/Live mixing", async () => {
    const attemptId = "8a000000-0000-4000-8000-000000000081";
    await expect(createV1CheckoutSession(
      { ...auth, orderId, idempotencyKey: "v1-missing-mode" },
      () => Promise.resolve(Response.json({ ...checkout, providerMode: undefined, attemptId })),
    )).rejects.toMatchObject({ code: "invalid_response" });
    await expect(createV1CheckoutSession(
      { ...auth, orderId, idempotencyKey: "v1-mixed-mode" },
      () => Promise.resolve(Response.json({ ...checkout, providerMode: "LIVE", attemptId })),
    )).rejects.toMatchObject({ code: "invalid_response" });
    expect(() => assertCheckoutProviderMode({ ...checkout, entityType: "dastak_v1_order" }, "LIVE"))
      .toThrowError("Payment configuration does not match this build.");
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

  it("requests a server-bound owner Test rehearsal without client-authored payment facts", async () => {
    const paymentAttemptId = "8a000000-0000-4000-8000-000000000081";
    let requestBody: Record<string, unknown> | undefined;
    const descriptor = await prepareV1TestRehearsal({
      ...auth,
      orderId,
      paymentAttemptId,
      outcome: "SUCCESS",
      idempotencyKey: "test-rehearsal-success",
    }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Promise.resolve(Response.json({
        testRehearsal: true,
        outcome: "SUCCESS",
        orderId,
        paymentAttemptId,
        providerMode: "TEST",
        providerOrderId: checkout.providerOrderId,
        amountPaise: checkout.amountPaise,
        currency: "INR",
        testVpa: "success@razorpay",
      }));
    });

    expect(requestBody).toEqual({
      operation: "prepareTestRehearsal",
      entityType: "dastak_v1_order",
      orderId,
      paymentAttemptId,
      testOutcome: "SUCCESS",
    });
    expect(JSON.stringify(requestBody)).not.toMatch(/amount|currency|providerOrder|vpa|key/i);
    expect(descriptor.testVpa).toBe("success@razorpay");
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
    installCustomCheckout({ methods: { upi: true }, upiApps: ["gpay", { app: "phonepe" }] });
    await expect(discoverRazorpayMethods(
      checkout.keyId,
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile",
    )).resolves.toEqual({
      upi: true,
      upiApps: [
        { id: "gpay", label: "Google Pay" },
        { id: "phonepe", label: "PhonePe" },
      ],
    });

    installCustomCheckout({ methods: { upi: false } });
    await expect(discoverRazorpayMethods(checkout.keyId)).resolves.toEqual({ upi: false, upiApps: [] });
  });

  it("does not present a mobile UPI app that Razorpay did not discover", async () => {
    installCustomCheckout({ methods: { upi: true }, upiApps: ["gpay", "unsupported-app"] });
    await expect(discoverRazorpayMethods(
      checkout.keyId,
      "Mozilla/5.0 (Linux; Android 15) Mobile",
    )).resolves.toEqual({ upi: true, upiApps: [{ id: "gpay", label: "Google Pay" }] });
  });

  it("launches mobile UPI Intent for the explicitly selected supported app", async () => {
    const custom = installCustomCheckout({
      completion: {
        razorpay_order_id: liveCheckout.providerOrderId,
        razorpay_payment_id: "pay_custom123",
        razorpay_signature: "b".repeat(64),
      },
    });
    const result = await launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order", attemptId: "8a000000-0000-4000-8000-000000000081" },
      customer,
      { kind: "intent", app: "gpay" },
    );

    expect(custom.constructorOptions).toEqual({ key: liveCheckout.keyId });
    expect(custom.payload).toMatchObject({
      order_id: liveCheckout.providerOrderId,
      amount: liveCheckout.amountPaise,
      currency: "INR",
      email: customer.email,
      contact: customer.phoneNumber,
      method: "upi",
    });
    expect(custom.createOptions).toEqual({ app: "gpay" });
    expect(custom.payload).not.toHaveProperty("_[flow]");
    expect(custom.payload).not.toHaveProperty("_[upiqr]");
    expect(custom.payload).not.toHaveProperty("vpa");
    expect(result).toEqual({
      status: "success",
      completion: {
        razorpay_order_id: liveCheckout.providerOrderId,
        razorpay_payment_id: "pay_custom123",
        razorpay_signature: "b".repeat(64),
      },
    });
  });

  it("launches desktop Dynamic QR without a Collect or Intent-app fallback", async () => {
    const onQrCode = vi.fn();
    const custom = installCustomCheckout({
      qr: { qr_url: "upi://pay?pa=dastak%40razorpay&am=88.00&cu=INR", expires_on: 1_800_000_000 },
      completion: {
        razorpay_order_id: liveCheckout.providerOrderId,
        razorpay_payment_id: "pay_qr123",
        razorpay_signature: "e".repeat(64),
      },
    });
    const result = await launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order" },
      customer,
      { kind: "qr" },
      { onQrCode },
    );

    expect(custom.constructorOptions).toEqual({ key: liveCheckout.keyId });
    expect(custom.payload).toMatchObject({
      method: "upi",
    });
    expect(custom.createOptions).toEqual({ app: "any", flow: "qr" });
    expect(custom.payload).not.toHaveProperty("_[flow]");
    expect(custom.payload).not.toHaveProperty("_[upiqr]");
    expect(custom.payload).not.toHaveProperty("vpa");
    expect(onQrCode).toHaveBeenCalledWith({
      uri: "upi://pay?pa=dastak%40razorpay&am=88.00&cu=INR",
      expiresAt: 1_800_000_000,
    });
    expect(result.status).toBe("success");
  });

  it("exposes only documented mobile-Web UPI Intent targets", () => {
    expect(mobileUPIOptions(
      ["google_pay", "phonepe", "paytm", "any", "not-supported"],
      "Mozilla/5.0 (Linux; Android 15) Mobile",
    ).map(({ id }) => id))
      .toEqual(["gpay", "phonepe", "paytm", "any"]);
    expect(mobileUPIOptions(
      { apps: ["gpay", "phonepe", "paytm", "any"] },
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
    ).map(({ id }) => id))
      .toEqual(["gpay", "phonepe", "paytm"]);
    expect(mobileUPIOptions(
      ["gpay"],
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
    )).toEqual([]);
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
      { ...liveCheckout, entityType: "dastak_v1_order" }, customer, { kind: "intent", app: "gpay" },
    )).resolves.toMatchObject({ status: "failed" });
  });

  it("uses razorpay.js Custom Checkout and never invokes Standard Checkout open", async () => {
    const custom = installCustomCheckout({
      completion: {
        razorpay_order_id: liveCheckout.providerOrderId,
        razorpay_payment_id: "pay_noopen123",
        razorpay_signature: "d".repeat(64),
      },
    });
    await launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order" }, customer, { kind: "intent", app: "gpay" },
    );
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
      { ...liveCheckout, entityType: "dastak_v1_order" }, customer, { kind: "intent", app: "gpay" },
    )).resolves.toEqual({
      status: "cancelled",
      message: "Payment was cancelled. Your secured basket remains reserved.",
    });
  });

  it("maps an explicit chooser close to cancellation and never fabricates confirmation from browser focus", async () => {
    const custom = installCustomCheckout({ deferCompletion: true });
    let launched = 0;
    let settled = false;
    const result = launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order" },
      customer,
      { kind: "intent", app: "gpay" },
      { onLaunched: () => { launched += 1; } },
    ).then((value) => {
      settled = true;
      return value;
    });

    // Mobile Safari permits the external UPI-app handoff only while the
    // original user activation is still live. The provider launch therefore
    // must happen synchronously, before even one microtask is yielded.
    expect(custom.payload).toMatchObject({ method: "upi" });
    expect(custom.createOptions).toEqual({ app: "gpay" });
    expect(launched).toBe(1);
    await new Promise<void>((resolve) => queueMicrotask(resolve));
    expect(launched).toBe(1);
    expect(settled).toBe(false);

    // Regaining browser focus is deliberately not a payment-success input.
    await Promise.resolve();
    expect(settled).toBe(false);

    custom.emit("payment.cancel", {});
    await expect(result).resolves.toEqual({
      status: "cancelled",
      message: "Payment was cancelled. Your secured basket remains reserved.",
    });
  });

  it("returns ready-safe not_launched when the UPI surface cannot open", async () => {
    const custom = installCustomCheckout({ throwOnCreate: true });
    let launched = false;
    await expect(launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order" },
      customer,
      { kind: "intent", app: "gpay" },
      { onLaunched: () => { launched = true; } },
    )).resolves.toEqual({
      status: "not_launched",
      message: "The selected UPI app could not be opened. Choose it again to retry.",
    });
    expect(launched).toBe(false);
    expect(custom.payload).toBeUndefined();
  });

  it("rejects missing OAuth contact data before invoking Razorpay", async () => {
    const custom = installCustomCheckout({});

    await expect(launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order" },
      { phoneNumber: customer.phoneNumber },
      { kind: "intent", app: "gpay" },
    )).resolves.toEqual({
      status: "failed",
      message: "Your signed-in email is unavailable. Sign out and sign in again before payment.",
    });
    expect(custom.payload).toBeUndefined();

    await expect(launchRazorpayCustomUPI(
      { ...liveCheckout, entityType: "dastak_v1_order" },
      { email: customer.email },
      { kind: "intent", app: "gpay" },
    )).resolves.toEqual({
      status: "failed",
      message: "Add a delivery phone number to your Dastak profile before payment.",
    });
    expect(custom.payload).toBeUndefined();
  });

  it("keeps real UPI Intent and Dynamic QR disabled for Test orders", async () => {
    const custom = installCustomCheckout({});
    await expect(launchRazorpayCustomUPI(
      { ...checkout, entityType: "dastak_v1_order" },
      customer,
      { kind: "intent", app: "gpay" },
    )).resolves.toEqual({
      status: "not_launched",
      message: RAZORPAY_TEST_UPI_LIMITATION_MESSAGE,
    });
    await expect(launchRazorpayCustomUPI(
      { ...checkout, entityType: "dastak_v1_order" },
      customer,
      { kind: "qr" },
    )).resolves.toEqual({
      status: "not_launched",
      message: RAZORPAY_TEST_UPI_LIMITATION_MESSAGE,
    });
    expect(custom.constructorOptions).toBeUndefined();
    expect(custom.payload).toBeUndefined();
  });

  it("uses the server-selected official fixture for the owner Test success path", async () => {
    const paymentAttemptId = "8a000000-0000-4000-8000-000000000081";
    const custom = installCustomCheckout({
      completion: {
        razorpay_order_id: checkout.providerOrderId,
        razorpay_payment_id: "pay_test_success",
        razorpay_signature: "f".repeat(64),
      },
    });
    const result = await launchRazorpayTestUPI(
      { ...checkout, entityType: "dastak_v1_order", attemptId: paymentAttemptId },
      customer,
      {
        testRehearsal: true,
        outcome: "SUCCESS",
        orderId,
        paymentAttemptId,
        providerMode: "TEST",
        providerOrderId: checkout.providerOrderId,
        amountPaise: checkout.amountPaise,
        currency: "INR",
        testVpa: "success@razorpay",
      },
    );

    expect(custom.payload).toEqual({
      amount: checkout.amountPaise,
      currency: "INR",
      order_id: checkout.providerOrderId,
      email: customer.email,
      contact: customer.phoneNumber,
      method: "upi",
      vpa: "success@razorpay",
    });
    expect(custom.opened).toBe(false);
    expect(result).toMatchObject({ status: "success" });
  });

  it("uses the failure fixture without changing the payment amount or order", async () => {
    const paymentAttemptId = "8a000000-0000-4000-8000-000000000081";
    const custom = installCustomCheckout({
      failure: { error: { description: "Test payment failed" } },
    });
    const result = await launchRazorpayTestUPI(
      { ...checkout, entityType: "dastak_v1_order", attemptId: paymentAttemptId },
      customer,
      {
        testRehearsal: true,
        outcome: "FAILURE",
        orderId,
        paymentAttemptId,
        providerMode: "TEST",
        providerOrderId: checkout.providerOrderId,
        amountPaise: checkout.amountPaise,
        currency: "INR",
        testVpa: "failure@razorpay",
      },
    );

    expect(custom.payload).toMatchObject({
      order_id: checkout.providerOrderId,
      amount: checkout.amountPaise,
      vpa: "failure@razorpay",
    });
    expect(result).toEqual({ status: "failed", message: "Test payment failed" });
  });

  it("cannot invoke the owner Test harness with a Live checkout session", async () => {
    const custom = installCustomCheckout({});
    await expect(launchRazorpayTestUPI(
      { ...liveCheckout, entityType: "dastak_v1_order", attemptId: "8a000000-0000-4000-8000-000000000081" },
      customer,
      {
        testRehearsal: true,
        outcome: "SUCCESS",
        orderId,
        paymentAttemptId: "8a000000-0000-4000-8000-000000000081",
        providerMode: "TEST",
        providerOrderId: checkout.providerOrderId,
        amountPaise: checkout.amountPaise,
        currency: "INR",
        testVpa: "success@razorpay",
      },
    )).resolves.toMatchObject({ status: "failed" });
    expect(custom.constructorOptions).toBeUndefined();
    expect(custom.payload).toBeUndefined();
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
  upiApps?: unknown;
  completion?: Record<string, unknown>;
  failure?: Record<string, unknown>;
  qr?: Record<string, unknown>;
  deferCompletion?: boolean;
  throwOnCreate?: boolean;
}) {
  const handlers = new Map<string, (response: unknown) => void>();
  const custom = {
    payload: undefined as Record<string, unknown> | undefined,
    createOptions: undefined as Record<string, unknown> | undefined,
    constructorOptions: undefined as Record<string, unknown> | undefined,
    opened: false,
    emit: (event: string, response: unknown) => handlers.get(event)?.(response),
  };
  class RazorpayCustomMock {
    constructor(options: Record<string, unknown>) {
      custom.constructorOptions = options;
    }
    once(_event: string, handler: (response: unknown) => void) {
      queueMicrotask(() => handler({ methods: input.methods ?? { upi: true } }));
    }
    getSupportedUpiIntentApps() { return Promise.resolve(input.upiApps ?? []); }
    on(event: string, handler: (response: unknown) => void) { handlers.set(event, handler); }
    createPayment(payload: Record<string, unknown>, options?: Record<string, unknown>) {
      if (input.throwOnCreate) throw new Error("launch failed");
      custom.payload = payload;
      custom.createOptions = options;
      if (input.deferCompletion) return;
      queueMicrotask(() => {
        if (input.qr) handlers.get("payment.upi.qr")?.(input.qr);
        if (input.failure) handlers.get("payment.error")?.(input.failure);
        else handlers.get("payment.success")?.(input.completion);
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
