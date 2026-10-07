// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { webcrypto } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { V1Order } from "./dastakV1";
import type { CheckoutClients } from "./reimaginedCheckout";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { cartStorageFixture, checkoutLocksFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { acknowledgeFoodCheckout, loadCustomerCart, saveCustomerCart } from "./customerCartPersistence";
import { foodRecoveryJournal, ReimaginedFoodRecovery } from "./reimaginedFoodRecovery";
import { ReimaginedFoodCounter } from "./ReimaginedFoodCounter";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
function setup(enabled = false, online = true, canEdit = true) {
  const menu = foodMenuFixture(); const item = menu.categories[0].items[0];
  const food = [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [item.optionGroups[0].options[0].id], quantity: 2 }];
  const input = { food, menus: [menu], online, canEdit, addressesReady: true, recipient: { name: "Test", phoneNumber: "+919876543210" }, address: { addressId: "home", label: "Home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" } };
  const reserved = { id: fixtureId(70), createdAt: "2026-09-30", updatedAt: "2026-09-30", displayOrderNumber: "TEST", orderType: "FOOD_ONLY", restaurant: menu.restaurant, version: 3, status: "AWAITING_PAYMENT", lines: [{ id: fixtureId(71), name: "Dish", unitPricePaise: 18000, lineTotalPaise: 36000, status: "SECURED", lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, foodSelection: { options: [{ ...item.optionGroups[0].options[0], groupId: fixtureId(34), groupName: "Size" }] } }], price: { snapshotKind: "FINAL", subtotalPaise: 36000, deliveryFeePaise: 1000, platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 37000, currencyCode: "INR" }, launchPayment: { optionLabel: "Pay via UPI/Cash on Delivery", reservationSecondsRemaining: 60, state: "READY_TO_CONFIRM", reservationState: "ACTIVE", reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: true, noChargeNow: true, payAtDoorstep: true } } as V1Order;
  const committed = { ...reserved, version: 4, status: "PREPARING", launchPayment: { ...reserved.launchPayment!, state: "PAYMENT_DUE_AT_DELIVERY", reservationState: "COMMITTED", canCommit: false } } as V1Order;
  const storage = cartStorageFixture(); saveCustomerCart("a", { food, retail: { [fixtureId(1)]: 3 } }, storage);
  const api = { submit: vi.fn<CheckoutClients["submit"]>().mockResolvedValue(reserved), read: vi.fn<CheckoutClients["read"]>().mockResolvedValue(reserved), commit: vi.fn<CheckoutClients["commit"]>().mockResolvedValue(committed) };
  const journal = foodRecoveryJournal("a", "https://example.supabase.co", storage);
  const make = () => new ReimaginedFoodRecovery({ accessToken: "test", supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, api, journal);
  const checkout = make(); const dispatch = vi.fn(action => { if (action.type === "checkoutSucceeded") acknowledgeFoodCheckout("a", action.orderId, action.purchased.food, storage); });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  const render = (coordinator = checkout, gate = enabled) => act(() => root.render(<ReimaginedFoodCounter key={gate ? "on" : "off"} checkout={coordinator} input={input} enabled={gate} dispatch={dispatch} onSessionExpired={vi.fn()} ordersUrl="/#orders" />));
  render(); return { api, checkout, make, input, storage, render, dispatch, reserved, committed };
}
function button(label: string) { return [...host.querySelectorAll("button")].find(element => element.textContent === label)!; }
async function click(label: string) { await act(async () => { button(label).click(); await new Promise(resolve => setTimeout(resolve, 10)); }); }
beforeEach(() => { vi.stubGlobal("crypto", webcrypto); vi.stubGlobal("navigator", { locks: checkoutLocksFixture() }); });
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.unstubAllGlobals(); });
describe("Food counter using fake clients", () => {
  it("keeps all requests off by default, including persisted recovery", async () => {
    const s = setup(); expect(button("Food checkout integration pending").disabled).toBe(true);
    expect(s.api.submit).not.toHaveBeenCalled(); expect(s.api.read).not.toHaveBeenCalled();
    await s.checkout.reserve(s.input); s.api.submit.mockClear(); s.render(s.make());
    expect(button("Food checkout integration pending").disabled).toBe(true); expect(s.api.read).not.toHaveBeenCalled(); expect(s.api.commit).not.toHaveBeenCalled();
  });
  it.each([[false, true], [true, false]])("blocks offline or non-owning cart (%s, %s)", (online, canEdit) => {
    const s = setup(true, online, canEdit); expect(button("Reserve Food order").disabled).toBe(true); expect(s.api.submit).not.toHaveBeenCalled();
  });
  it("reserves, displays server total, then confirms on a separate click and preserves Grocery", async () => {
    const s = setup(true); await click("Reserve Food order"); expect(host.textContent).toContain("Server order total: ₹370.00"); expect(s.api.commit).not.toHaveBeenCalled();
    await click("Confirm Food order"); expect(s.api.commit).toHaveBeenCalledOnce(); expect(s.dispatch).toHaveBeenCalledOnce();
    expect(loadCustomerCart("a", s.storage)).toEqual({ food: [], retail: { [fixtureId(1)]: 3 } });
    await click("Recover confirmed Food cart"); expect(s.dispatch).toHaveBeenCalledOnce(); expect(s.api.commit).toHaveBeenCalledOnce();
  });
  it("reads a persisted reservation without resubmission and reconciles a lost commitment", async () => {
    const s = setup(true); await click("Reserve Food order"); s.render(s.make(), false); s.api.read.mockResolvedValue(s.committed); s.render(s.make(), true);
    await click("Recover Food reservation"); expect(s.api.read).toHaveBeenCalledOnce(); expect(s.api.submit).toHaveBeenCalledOnce(); expect(s.api.commit).not.toHaveBeenCalled(); expect(s.dispatch).toHaveBeenCalledOnce();
  });
  it("invalidates confirmation after a failed refresh", async () => {
    const s = setup(true); await click("Reserve Food order"); s.api.read.mockRejectedValue(new Error("timeout")); await click("Refresh Food order status");
    expect(host.textContent).toContain("timeout"); expect(button("Confirm Food order")).toBeUndefined(); expect(s.api.commit).not.toHaveBeenCalled();
  });
  it("retries ambiguous submit with its original key", async () => {
    const s = setup(true); s.api.submit.mockRejectedValueOnce(new Error("timeout")); await click("Reserve Food order"); await click("Reserve Food order");
    expect(s.api.submit.mock.calls[0][0].idempotencyKey).toBe(s.api.submit.mock.calls[1][0].idempotencyKey); expect(s.api.commit).not.toHaveBeenCalled();
  });
  it("only restarts after the server proves an unpaid reservation is closed", async () => {
    const s = setup(true); await click("Reserve Food order"); const expired = { ...s.reserved, version: 4, status: "PAYMENT_EXPIRED", launchPayment: { ...s.reserved.launchPayment!, state: "RESERVATION_EXPIRED", reservationState: "EXPIRED", canCommit: false } } as V1Order;
    s.api.read.mockResolvedValue(expired); await click("Refresh Food order status"); expect(button("Confirm Food order").disabled).toBe(true);
    await click("Recheck closed Food reservation"); expect(button("Reserve Food order")).toBeTruthy(); expect(s.api.submit).toHaveBeenCalledOnce(); expect(s.dispatch).not.toHaveBeenCalled();
  });
  it("retries a failed cart acknowledgement without committing twice", async () => {
    const s = setup(true); await click("Reserve Food order"); s.dispatch.mockImplementationOnce(() => { throw new Error("storage unavailable"); });
    await click("Confirm Food order"); expect(host.textContent).toContain("storage unavailable"); expect(loadCustomerCart("a", s.storage).food).toHaveLength(1);
    await click("Recover confirmed Food cart"); expect(s.api.commit).toHaveBeenCalledOnce(); expect(loadCustomerCart("a", s.storage).food).toEqual([]);
  });
  it("does not acknowledge a late commitment after unmount", async () => {
    const s = setup(true); await click("Reserve Food order"); let resolve!: (order: V1Order) => void;
    s.api.commit.mockImplementation(() => new Promise<V1Order>(done => { resolve = done; }));
    await click("Confirm Food order"); act(() => root.unmount());
    await act(async () => { resolve(s.committed); await new Promise(done => setTimeout(done, 10)); });
    expect(s.dispatch).not.toHaveBeenCalled(); expect(loadCustomerCart("a", s.storage).food).toHaveLength(1);
    root = createRoot(host);
  });
});
