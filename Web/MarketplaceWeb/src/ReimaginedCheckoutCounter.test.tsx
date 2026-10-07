// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { V1Order } from "./dastakV1";
import { ReimaginedCheckoutCounter } from "./ReimaginedCheckoutCounter";
import { ReimaginedGroceryCheckout, type GroceryCheckoutDraft, type CheckoutClients } from "./reimaginedCheckout";
import { checkoutJournal } from "./reimaginedCheckoutJournal";
import { cartStorageFixture, checkoutLocksFixture } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const skuId = "11111111-1111-4111-8111-111111111111";
const draft: GroceryCheckoutDraft = { retail: { [skuId]: 1 }, recipient: { name: "Test", phoneNumber: "+919876543210" }, address: { addressId: "home", label: "Home", address: "Test", building: "1", details: "", displayAddress: "Test", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" } };
const reserved = { id: "22222222-2222-4222-8222-222222222222", displayOrderNumber: "TEST-1", status: "AWAITING_PAYMENT", version: 3, lines: [{ lineType: "RETAIL_SKU", skuId, quantity: 1 }], price: { snapshotKind: "SERVER", subtotalPaise: 10000, deliveryFeePaise: 2000, platformFeePaise: 500, discountPaise: 400, taxPaise: 200, totalPaise: 12300, currencyCode: "INR" }, launchPayment: { state: "READY_TO_CONFIRM", reservationState: "ACTIVE", reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: true, noChargeNow: true, payAtDoorstep: true } } as V1Order;
function setup(enabled = false, online = true, journal?: ReturnType<typeof checkoutJournal>) {
  const committed = { ...reserved, version: 4, status: "PREPARING", launchPayment: { ...reserved.launchPayment!, state: "PAYMENT_DUE_AT_DELIVERY", reservationState: "COMMITTED", canCommit: false } } as V1Order;
  const api = { submit: vi.fn<CheckoutClients["submit"]>().mockResolvedValue(reserved), commit: vi.fn<CheckoutClients["commit"]>().mockResolvedValue(committed), read: vi.fn<CheckoutClients["read"]>().mockResolvedValue(reserved) };
  const checkout = new ReimaginedGroceryCheckout({ accessToken: "test", supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, api, undefined, undefined, journal);
  const dispatch = vi.fn(); host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  act(() => root.render(<ReimaginedCheckoutCounter checkout={checkout} draft={draft} enabled={enabled} online={online} dispatch={dispatch} onSessionExpired={vi.fn()} ordersUrl="/#orders" />));
  return { api, dispatch };
}
function button(text: string) { return [...host.querySelectorAll("button")].find(element => element.textContent === text)!; }
beforeEach(() => vi.stubGlobal("navigator", { locks: checkoutLocksFixture() }));
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.unstubAllGlobals(); });
describe("Grocery counter controls", () => {
  it("keeps order writes disabled by default", () => {
    const { api } = setup(); expect(button("Checkout integration pending").disabled).toBe(true);
    expect(api.submit).not.toHaveBeenCalled(); expect(api.commit).not.toHaveBeenCalled();
  });
  it("shows the server total after reservation and requires a separate confirmation click", async () => {
    const { api, dispatch } = setup(true);
    await act(async () => button("Reserve Grocery order").click());
    expect(host.textContent).toContain("Server order total: ₹123.00"); expect(api.commit).not.toHaveBeenCalled(); expect(dispatch).not.toHaveBeenCalled();
    const bill = host.querySelector('[aria-label="Server-confirmed Grocery bill"]')!;
    expect(bill.textContent).toContain("Items₹100.00"); expect(bill.textContent).toContain("Delivery₹20.00"); expect(bill.textContent).toContain("Platform fee₹5.00"); expect(bill.textContent).toContain("Tax₹2.00"); expect(bill.textContent).toContain("Discount−₹4.00");
    await act(async () => button("Confirm Grocery order").click());
    expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({ type: "checkoutSucceeded", service: "grocery", purchased: { retail: { [skuId]: 1 }, food: [] } }));
    expect(button("Confirm Grocery order").disabled).toBe(true);
  });
  it("blocks reservation while offline even when explicitly enabled", () => {
    const { api } = setup(true, false); expect(button("Reserve Grocery order").disabled).toBe(true); expect(api.submit).not.toHaveBeenCalled();
  });
  it("recovers a saved reservation by reading its status without submitting another order", async () => {
    const journal = checkoutJournal("account", "https://example.supabase.co", cartStorageFixture());
    journal.write({ version: 1, fingerprint: "a".repeat(64), retail: { [skuId]: 1 }, submitKey: "submit", commitKey: "commit", orderId: reserved.id, orderVersion: reserved.version });
    const { api } = setup(true, true, journal);
    await act(async () => button("Recover Grocery reservation").click());
    expect(api.read).toHaveBeenCalledTimes(1);
    expect(api.submit).not.toHaveBeenCalled();
    expect(api.commit).not.toHaveBeenCalled();
    expect(host.textContent).toContain("Server order total: ₹123.00");
  });
  it("returns a server-closed reservation to the Bucket without creating a replacement", async () => {
    const { api, dispatch } = setup(true);
    await act(async () => button("Reserve Grocery order").click());
    const expired = { ...reserved, status: "PAYMENT_EXPIRED", version: 4, launchPayment: { ...reserved.launchPayment!, state: "RESERVATION_EXPIRED", reservationState: "EXPIRED", canCommit: false } } as V1Order;
    api.read.mockResolvedValue(expired);
    await act(async () => button("Refresh order status").click());
    expect(button("Confirm Grocery order").disabled).toBe(true);
    await act(async () => button("Recheck closed reservation and return to Bucket").click());
    expect(button("Reserve Grocery order")).toBeTruthy();
    expect(api.read).toHaveBeenCalledTimes(2);
    expect(api.submit).toHaveBeenCalledOnce(); expect(api.commit).not.toHaveBeenCalled(); expect(dispatch).not.toHaveBeenCalled();
  });
});
