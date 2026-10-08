import { describe, expect, it } from "vitest";
import { getV1ActiveOrders } from "./dastakV1";
const auth = { accessToken: "test", supabaseUrl: "https://example.invalid", publishableKey: "public" };
const order = { id: "11111111-1111-4111-8111-111111111111", kind: "merchant", service: "grocery", status: "merchant_accepted", version: 2, createdAt: "2026-10-08T00:00:00Z" };
describe("active order discovery adapter", () => {
  it("uses the authenticated read and retains legacy identity without accepting caller order IDs", async () => {
    let body: unknown;
    const result = await getV1ActiveOrders(auth, async (_url, init) => { body = JSON.parse(String(init?.body)); return Response.json({ totalCount: 1, orders: [order] }); });
    expect(body).toEqual({ operation: "customerActiveOrders" }); expect(result.orders[0]).toEqual(order);
  });
  it.each([
    { totalCount: 1, orders: [] }, { totalCount: -1, orders: [] },
    { totalCount: 1, orders: [{ ...order, kind: "admin" }] },
    { totalCount: 1, orders: [{ ...order, id: "bad" }] },
    { totalCount: 2, orders: [order, order] },
  ])("rejects incomplete or malformed discovery %#", async payload => {
    await expect(getV1ActiveOrders(auth, async () => Response.json(payload))).rejects.toThrow();
  });
});
