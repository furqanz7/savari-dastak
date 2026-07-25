import { describe, expect, it } from "vitest";
import { createCheckoutSession, processOrderRefund } from "./payments";

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
});
