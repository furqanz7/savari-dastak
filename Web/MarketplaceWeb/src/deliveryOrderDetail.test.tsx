// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { getDeliveryOrderDetail } from "./delivery";
import { DeliveryOrderDetailPanel } from "./DeliveryOrderDetail";

const workId = "11111111-1111-4111-8111-111111111111";
const auth = { supabaseUrl: "https://example.supabase.co", publishableKey: "publishable", accessToken: "actor-token" };
const fixture = () => ({ kind: "V1_DELIVERY", workId, missionStatus: "ARRIVED", terminal: false,
  order: { id: workId, displayOrderNumber: "DSK-TEST", orderType: "RETAIL", status: "OUT_FOR_DELIVERY",
    createdAt: "2026-10-15T00:00:00Z", updatedAt: "2026-10-15T00:05:00Z",
    lines: [{ id: workId, name: "Milk", quantity: 2, packSize: "500 ml", lineTotalPaise: 4800 }],
    price: { subtotalPaise: 4800, deliveryFeePaise: 1500, platformFeePaise: 126, discountPaise: 0, taxPaise: 0, totalPaise: 6426, currencyCode: "INR" },
    deliveryAddress: { line1: "Customer Road" }, recipient: { name: "Recipient", phoneNumber: "+919700000001" } },
  pickupStops: [{ id: workId, sequence: 1, status: "COMPLETED", packageCount: 1, branch: { displayName: "Local merchant", address: { line1: "Store Road" } } }],
  collection: { state: "PAYMENT_DUE_AT_DELIVERY", amountPaise: 6426 } });
afterEach(() => { vi.unstubAllGlobals(); });
describe("Delivery full order", () => {
  it("requests rider-owned work, never a caller-supplied actor", async () => {
    const fetcher = vi.fn(async (...args: [RequestInfo | URL, RequestInit?]) => {
      expect(args[0]).toBeTruthy();
      return new Response(JSON.stringify(fixture()), { status: 200 });
    });
    await getDeliveryOrderDetail({ ...auth, kind: "V1_DELIVERY", workId }, fetcher);
    const init = fetcher.mock.calls[0]?.[1] as RequestInit | undefined;
    expect(JSON.parse(String(init?.body))).toEqual({ operation: "partnerOrderDetail", kind: "V1_DELIVERY", workId });
  });
  it("rejects wrong work identity, malformed options, negative money and historical contact leaks", async () => {
    for (const change of [
      (v: ReturnType<typeof fixture>) => { v.workId = "other"; },
      (v: ReturnType<typeof fixture>) => { v.order.price.totalPaise = -1; },
      (v: ReturnType<typeof fixture>) => { v.terminal = true; },
      (v: ReturnType<typeof fixture>) => { Object.assign(v.order.lines[0], { foodSelection: { options: null } }); },
    ]) {
      const value = fixture(); change(value);
      await expect(getDeliveryOrderDetail({ ...auth, kind: "V1_DELIVERY", workId }, async () => new Response(JSON.stringify(value)))).rejects.toThrow("could not be verified");
    }
  });
  it("loads on demand and presents the items, pickup, bill and active contact", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify(fixture()))); vi.stubGlobal("fetch", fetcher);
    (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    const host = document.createElement("div"); document.body.append(host); const root = createRoot(host);
    try {
      await act(async () => root.render(<DeliveryOrderDetailPanel auth={auth} kind="V1_DELIVERY" workId={workId} />));
      expect(fetcher).not.toHaveBeenCalled();
      await act(async () => host.querySelector("button")!.click());
      expect(host.textContent).toContain("2 × Milk");
      expect(host.textContent).toContain("Store Road");
      expect(host.querySelector("a")?.getAttribute("href")).toBe("tel:+919700000001");
      expect(host.textContent).toContain("₹64.26");
    } finally { await act(async () => root.unmount()); host.remove(); }
  });
});
