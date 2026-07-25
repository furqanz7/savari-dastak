import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";
import { RazorpayApiError, RazorpayTestClient } from "../../_shared/razorpay.ts";

Deno.test("Razorpay client accepts test and live credentials", () => {
  new RazorpayTestClient("rzp_test_public", "test-secret");
  new RazorpayTestClient("rzp_live_public", "live-secret");
  assertThrows(() => new RazorpayTestClient("invalid_public", "live-secret"));
});

Deno.test("Razorpay order creation uses the server amount and recovers by receipt", async () => {
  const requests: Array<{ url: string; body?: unknown }> = [];
  const fetcher = (input: RequestInfo | URL, init?: RequestInit) => {
    requests.push({
      url: String(input),
      body: init?.body ? JSON.parse(String(init.body)) : undefined,
    });
    if (requests.length === 1) return Promise.resolve(json({ entity: "collection", items: [] }));
    return Promise.resolve(json(order));
  };
  const client = new RazorpayTestClient("rzp_test_public", "sandbox-secret", fetcher);
  const result = await client.resolveOrder({
    amountPaise: 8_800,
    currency: "INR",
    receipt,
    orderId,
  });

  assertEquals(result.id, "order_test123");
  assertEquals(requests[0].url.includes(`receipt=${encodeURIComponent(receipt)}`), true);
  assertEquals(requests[1].body, {
    amount: 8_800,
    currency: "INR",
    receipt,
    partial_payment: false,
    notes: { dastak_order_id: orderId },
  });
});

Deno.test("Razorpay recovery rejects an order with a different amount", async () => {
  const client = new RazorpayTestClient(
    "rzp_test_public",
    "sandbox-secret",
    () => Promise.resolve(json({ entity: "collection", items: [{ ...order, amount: 8_801 }] })),
  );

  await assertRejects(
    () => client.resolveOrder({ amountPaise: 8_800, currency: "INR", receipt, orderId }),
    RazorpayApiError,
  );
});

const orderId = "8a000000-0000-4000-8000-000000000080";
const receipt = "dst_8a000000000040008000000000000080";
const order = {
  id: "order_test123",
  entity: "order",
  amount: 8_800,
  currency: "INR",
  receipt,
  status: "created",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
