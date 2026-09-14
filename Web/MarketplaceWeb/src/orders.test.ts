import { describe, expect, it } from "vitest";
import {
  acceptMerchantOrder,
  cancelMerchantOrder,
  confirmMerchantCancellationReturn,
  createMerchantOrder,
  formatDeliveryDistance,
  getCustomerOrders,
  getMerchantOrders,
  markMerchantOrderReady,
  parseMerchantOperationalOrder,
  parseMerchantOrder,
  quoteMerchantOrder,
  rejectMerchantOrder,
} from "./orders";
import { merchantOrderPresentation, paymentStateLabel } from "./customerLifecycle";

const storeId = "33333333-3333-4333-8333-333333333333";
const productId = "55555555-5555-4555-8555-555555555555";
const quoteId = "66666666-6666-4666-8666-666666666666";
const orderId = "77777777-7777-4777-8777-777777777777";
const line = {
  productId,
  name: "Lime Soda",
  unitLabel: "750 ml",
  unitPrice: { paise: 12_500 },
  quantity: 2,
  lineSubtotal: { paise: 25_000 },
};
const quote = {
  quoteId,
  storeId,
  lines: [line],
  itemSubtotal: { paise: 25_000 },
  deliveryFee: { paise: 4_000 },
  deliveryDistanceMeters: 3_500,
  total: { paise: 29_000 },
  dropoff: { latitude: 12.6819, longitude: 78.6201 },
  expiresAt: "2026-07-19T15:00:00Z",
};
const order = {
  orderId,
  storeId,
  status: "payment_pending",
  paymentState: "payment_pending",
  lines: [line],
  itemSubtotal: { paise: 25_000 },
  deliveryFee: { paise: 4_000 },
  deliveryDistanceMeters: 3_500,
  total: { paise: 29_000 },
  dropoff: { latitude: 12.6819, longitude: 78.6201 },
  stateVersion: 1,
  refundDecision: null,
  handoffCode: null,
  createdAt: "2026-07-19T14:55:00Z",
  updatedAt: "2026-07-19T14:55:00Z",
};
const paidOrder = { ...order, status: "paid", paymentState: "paid" };
const merchantOperationalOrder = {
  orderId,
  storeId,
  status: "paid",
  paymentState: "paid",
  lines: [line],
  itemSubtotal: { paise: 25_000 },
  dropoff: { latitude: 12.6819, longitude: 78.6201 },
  stateVersion: 1,
  handoffCode: null,
  createdAt: "2026-07-19T14:55:00Z",
  updatedAt: "2026-07-19T14:55:00Z",
};
const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

describe("customer orders", () => {
  it("maps every order state to one customer action", () => {
    const states = [
      ["payment_pending", "payment_pending", "pay"],
      ["paid", "paid", "cancel"],
      ["merchant_accepted", "paid", "request_cancellation"],
      ["ready", "paid", "request_cancellation"],
      ["assigned", "paid", "request_cancellation"],
      ["en_route_to_pickup", "paid", "request_cancellation"],
      ["at_store", "paid", "request_cancellation"],
      ["picked_up", "paid", "request_cancellation"],
      ["in_transit", "paid", "request_cancellation"],
      ["delivered", "paid", "none"],
      ["cancelled", "refunded", "none"],
      ["returning_to_merchant", "refund_pending", "none"],
    ] as const;

    for (const [status, paymentState, action] of states) {
      expect(merchantOrderPresentation(status, paymentState).primaryAction).toBe(action);
    }
    expect(paymentStateLabel("not_collected")).toBe("Not charged");
  });

  it("parses the saved address, store, courier, and timeline contract", () => {
    const parsed = parseMerchantOrder({
      ...paidOrder,
      deliveryAddress: {
        label: "Home",
        address: "CL Road, Vaniyambadi",
        details: "12, first floor",
        displayAddress: "12, first floor, CL Road, Vaniyambadi",
      },
      store: {
        name: "Dastak Mart",
        phoneNumber: "+919876543210",
        pickup: { latitude: 12.681, longitude: 78.621, address: "Market Road" },
      },
      courier: {
        displayName: "Aamir",
        phoneNumber: "+919812345678",
        deliveryMethod: "bike",
        location: { latitude: 12.682, longitude: 78.623 },
        lastSeenAt: "2026-08-13T10:05:00Z",
      },
      timeline: {
        createdAt: "2026-08-13T10:00:00Z",
        acceptedAt: "2026-08-13T10:01:00Z",
        assignedAt: "2026-08-13T10:03:00Z",
      },
    });

    expect(parsed.deliveryAddress?.label).toBe("Home");
    expect(parsed.store?.name).toBe("Dastak Mart");
    expect(parsed.courier?.location?.longitude).toBe(78.623);
    expect(parsed.timeline?.acceptedAt).toBe("2026-08-13T10:01:00Z");
  });

  it("requests a server-priced quote using only product IDs and quantities", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify(quote), { status: 200 }));
    };

    const result = await quoteMerchantOrder({
      ...auth,
      storeId,
      lines: [{ productId, quantity: 2 }],
      dropoff: quote.dropoff,
      idempotencyKey: "quote-key",
    }, fetcher);

    expect(result.total.paise).toBe(29_000);
    expect(requestBody).toEqual({
      operation: "quote",
      storeId,
      lines: [{ productId, quantity: 2 }],
      dropoff: quote.dropoff,
    });
  });

  it("creates and parses a payment-pending order", async () => {
    const result = await createMerchantOrder({ ...auth, quoteId, idempotencyKey: "create-key" }, () =>
      Promise.resolve(new Response(JSON.stringify(order), { status: 201 })));

    expect(result.orderId).toBe(orderId);
    expect(result.status).toBe("payment_pending");
  });

  it("loads authenticated customer orders", async () => {
    const result = await getCustomerOrders(auth, () =>
      Promise.resolve(new Response(JSON.stringify({ orders: [order] }), { status: 200 })));

    expect(result).toHaveLength(1);
    expect(result[0].total.paise).toBe(29_000);
  });

  it("loads only paid-or-later orders for the merchant", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await getMerchantOrders(auth, (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({ orders: [merchantOperationalOrder] }), { status: 200 }));
    });

    expect(result[0].status).toBe("paid");
    expect(result[0].itemSubtotal.paise).toBe(25_000);
    expect(result[0]).not.toHaveProperty("total");
    expect(requestBody).toEqual({ operation: "merchantSnapshot" });
  });

  it("excludes unpaid orders from a merchant snapshot", async () => {
    const result = await getMerchantOrders(auth, () =>
      Promise.resolve(new Response(JSON.stringify({ orders: [{ ...merchantOperationalOrder, status: "payment_pending", paymentState: "payment_pending" }] }), { status: 200 })));

    expect(result).toEqual([]);
  });

  it("sends merchant fulfilment transitions with idempotency", async () => {
    const requests: Array<{ body: unknown; key: string | null }> = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({
        body: JSON.parse(String(init?.body)),
        key: new Headers(init?.headers).get("X-Idempotency-Key"),
      });
      const operation = (requests.at(-1)?.body as { operation: string }).operation;
      const responseOrder = operation === "merchantAccept"
        ? { ...merchantOperationalOrder, status: "merchant_accepted", stateVersion: 2 }
        : operation === "merchantMarkReady"
          ? { ...merchantOperationalOrder, status: "ready", stateVersion: 3 }
          : { ...merchantOperationalOrder, status: "cancelled", paymentState: "refund_pending", stateVersion: 2 };
      return Promise.resolve(new Response(JSON.stringify(responseOrder), { status: 200 }));
    };

    await acceptMerchantOrder({ ...auth, orderId, idempotencyKey: "accept-key" }, fetcher);
    await markMerchantOrderReady({ ...auth, orderId, idempotencyKey: "ready-key" }, fetcher);
    await rejectMerchantOrder({ ...auth, orderId, reason: "Item unavailable", idempotencyKey: "reject-key" }, fetcher);

    expect(requests).toEqual([
      { body: { operation: "merchantAccept", orderId }, key: "accept-key" },
      { body: { operation: "merchantMarkReady", orderId }, key: "ready-key" },
      { body: { operation: "merchantReject", orderId, reason: "Item unavailable" }, key: "reject-key" },
    ]);
  });

  it("formats the server-measured delivery distance", () => {
    expect(formatDeliveryDistance(850)).toBe("850 m");
    expect(formatDeliveryDistance(3_500)).toBe("3.5 km");
  });

  it("rejects a quote without a server-measured delivery distance", async () => {
    const invalidQuote: Partial<typeof quote> = { ...quote };
    delete invalidQuote.deliveryDistanceMeters;

    await expect(quoteMerchantOrder({
      ...auth,
      storeId,
      lines: [{ productId, quantity: 2 }],
      dropoff: quote.dropoff,
      idempotencyKey: "quote-key",
    }, () => Promise.resolve(new Response(JSON.stringify(invalidQuote), { status: 200 })))).rejects.toThrow(
      "invalid order response",
    );
  });

  it("rejects responses that expose private account identities", () => {
    expect(() => parseMerchantOrder({ ...order, customerAccountId: "private" })).toThrow("invalid order response");
  });

  it("rejects whole-bill customer pricing from merchant operational responses", () => {
    expect(() => parseMerchantOperationalOrder(paidOrder)).toThrow("invalid order response");
    expect(parseMerchantOperationalOrder(merchantOperationalOrder)).toMatchObject({
      orderId,
      itemSubtotal: { paise: 25_000 },
    });
  });

  it("preserves safe cancellation errors", async () => {
    await expect(cancelMerchantOrder({
      ...auth,
      orderId,
      reason: "Changed my mind",
      idempotencyKey: "cancel-key",
    }, () => Promise.resolve(new Response(JSON.stringify({
      error: { code: "invalid_order_transition", message: "This order can no longer be cancelled." },
    }), { status: 409 })))).rejects.toMatchObject({ code: "invalid_order_transition", status: 409 });
  });

  it("confirms a returned cancellation without client refund values", async () => {
    let requestBody: unknown;
    const returned = { ...merchantOperationalOrder, status: "cancelled", paymentState: "refund_pending", stateVersion: 4 };
    const result = await confirmMerchantCancellationReturn({
      ...auth,
      orderId,
      reason: "Items received back",
      idempotencyKey: "return-key",
    }, (_input, init) => {
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify(returned), { status: 200 }));
    });

    expect(result.status).toBe("cancelled");
    expect(requestBody).toEqual({
      operation: "merchantConfirmReturn",
      orderId,
      reason: "Items received back",
    });
  });
});
