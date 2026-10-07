import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { V1Order } from "./dastakV1";
import type { CheckoutClients } from "./reimaginedCheckout";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { cartStorageFixture, checkoutLocksFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { acknowledgeFoodCheckout, loadCustomerCart, saveCustomerCart, saveCustomerCartStrict } from "./customerCartPersistence";
import { foodRecoveryJournal, ReimaginedFoodRecovery } from "./reimaginedFoodRecovery";

const auth = { accessToken: "secret-test-token", supabaseUrl: "https://example.supabase.co", publishableKey: "public" };
function draft() {
  const menu = foodMenuFixture(); const item = menu.categories[0].items[0];
  return { food: [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [item.optionGroups[0].options[0].id], quantity: 2 }], menus: [menu], online: true, canEdit: true, addressesReady: true, recipient: { name: "Private customer", phoneNumber: "+919876543210" }, address: { addressId: "home", label: "Home", address: "Private street", building: "1", details: "", displayAddress: "Private street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-09-30" } };
}
function order(paid = false): V1Order {
  const input = draft(); const menu = input.menus[0];
  return { id: fixtureId(70), displayOrderNumber: "TEST", createdAt: "2026-09-30", updatedAt: "2026-09-30", orderType: "FOOD_ONLY", version: paid ? 4 : 3, status: paid ? "PREPARING" : "AWAITING_PAYMENT", restaurant: menu.restaurant,
    lines: [{ id: fixtureId(71), lineType: "FOOD_MENU_ITEM", menuItemId: input.food[0].itemId, name: "Dish", quantity: 2, unitPricePaise: 18000, lineTotalPaise: 36000, status: "SECURED", foodSelection: { options: [{ ...menu.categories[0].items[0].optionGroups[0].options[0], groupId: fixtureId(34), groupName: "Size" }] } }],
    price: { snapshotKind: "FINAL", subtotalPaise: 36000, deliveryFeePaise: 1000, platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 37000, currencyCode: "INR" },
    launchPayment: { optionLabel: "Pay via UPI/Cash on Delivery", state: paid ? "PAYMENT_DUE_AT_DELIVERY" : "READY_TO_CONFIRM", reservationState: paid ? "COMMITTED" : "ACTIVE", reservationSecondsRemaining: 60, reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: !paid, noChargeNow: true, payAtDoorstep: true } } as V1Order;
}
function setup(storage = cartStorageFixture()) {
  const journal = foodRecoveryJournal("a", auth.supabaseUrl, storage);
  const api = { submit: vi.fn<CheckoutClients["submit"]>().mockResolvedValue(order()), commit: vi.fn<CheckoutClients["commit"]>().mockResolvedValue(order(true)), read: vi.fn<CheckoutClients["read"]>().mockResolvedValue(order()) };
  let key = 80; const make = () => new ReimaginedFoodRecovery(auth, api, journal, () => fixtureId(key++));
  return { storage, journal, api, make, checkout: make() };
}
beforeEach(() => vi.stubGlobal("navigator", { locks: checkoutLocksFixture() }));
afterEach(() => vi.unstubAllGlobals());
describe("Food reservation and recovery using fake clients", () => {
  it("saves safe identifiers before requests and retries a lost submission with the same key", async () => {
    const { checkout, api, make, storage } = setup(); const writes = vi.spyOn(storage, "setItem"); api.submit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.reserve(draft())).rejects.toThrow("timeout");
    const restored = make(); await restored.reserve(draft());
    expect(api.submit.mock.calls.map(([input]) => input.idempotencyKey)).toEqual([fixtureId(80), fixtureId(80)]);
    expect(api.commit).not.toHaveBeenCalled();
    const saved = JSON.stringify(writes.mock.calls);
    for (const secret of [auth.accessToken, "Private customer", "Private street", "+919876543210"]) expect(saved).not.toContain(secret);
  });
  it("blocks changed intent after a lost response", async () => {
    const { checkout, api } = setup(); api.submit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.reserve(draft())).rejects.toThrow(); const changed = draft(); changed.food[0].quantity = 3;
    await expect(checkout.reserve(changed)).rejects.toThrow("unresolved"); expect(api.submit).toHaveBeenCalledOnce();
  });
  it("recovers a known reservation by read rather than submitting another order", async () => {
    const { checkout, api, make } = setup(); await checkout.reserve(draft()); const restored = make();
    await expect(restored.confirm(() => {})).rejects.toThrow("Refresh"); await restored.refresh();
    expect(api.submit).toHaveBeenCalledOnce(); expect(restored.order?.id).toBe(fixtureId(70));
  });
  it.each(["branch", "options", "quantity", "retail", "duplicate", "order", "version"])("rejects a mismatched %s snapshot", async mismatch => {
    const { checkout, api } = setup(); await checkout.reserve(draft()); const wrong = order();
    if (mismatch === "branch") wrong.restaurant!.branchId = fixtureId(99);
    if (mismatch === "options") wrong.lines[0].foodSelection!.options = [];
    if (mismatch === "quantity") wrong.lines[0].quantity = 1;
    if (mismatch === "retail") wrong.lines[0].lineType = "RETAIL_SKU";
    if (mismatch === "duplicate") wrong.lines.push(wrong.lines[0]);
    if (mismatch === "order") wrong.id = fixtureId(99);
    if (mismatch === "version") wrong.version = 2;
    api.read.mockResolvedValue(wrong); await expect(checkout.refresh()).rejects.toThrow("match"); expect(api.commit).not.toHaveBeenCalled();
  });
  it("keeps confirmation key/version after timeout and acknowledges exact quantities once", async () => {
    const { checkout, api, make, storage } = setup(); await checkout.reserve(draft());
    saveCustomerCart("a", { retail: { rice: 5 }, food: [{ ...draft().food[0], quantity: 4 }, { ...draft().food[0], optionIds: [], quantity: 1 }] }, storage);
    const acknowledge = (action: Parameters<Parameters<ReimaginedFoodRecovery["confirm"]>[0]>[0]) => { if (action.type === "checkoutSucceeded") acknowledgeFoodCheckout("a", action.orderId, action.purchased.food, storage); };
    api.commit.mockRejectedValueOnce(new Error("timeout")); await expect(checkout.confirm(acknowledge)).rejects.toThrow("timeout");
    const restored = make(); await restored.refresh(); await restored.confirm(acknowledge); await restored.confirm(acknowledge);
    expect(api.commit.mock.calls.map(([input]) => [input.idempotencyKey, input.expectedVersion])).toEqual([[fixtureId(81), 3], [fixtureId(81), 3]]);
    expect(loadCustomerCart("a", storage)).toEqual({ retail: { rice: 5 }, food: [{ ...draft().food[0], quantity: 2 }, { ...draft().food[0], optionIds: [], quantity: 1 }] });
    const cart = loadCustomerCart("a", storage); saveCustomerCartStrict("a", cart, storage); saveCustomerCart("a", cart, storage);
    expect(acknowledgeFoodCheckout("a", fixtureId(70), draft().food, storage)).toBe(false);
  });
  it("handles lost commitment via authoritative refresh without a second commit", async () => {
    const { checkout, api, storage } = setup(); await checkout.reserve(draft()); api.commit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.confirm(() => {})).rejects.toThrow(); api.read.mockResolvedValue(order(true)); await checkout.refresh();
    const acknowledge = vi.fn((action: Parameters<Parameters<ReimaginedFoodRecovery["confirm"]>[0]>[0]) => { if (action.type === "checkoutSucceeded") acknowledgeFoodCheckout("a", action.orderId, action.purchased.food, storage); });
    await checkout.confirm(acknowledge); expect(acknowledge).toHaveBeenCalledOnce(); expect(api.commit).toHaveBeenCalledOnce();
  });
  it("recovers failed cart acknowledgement without committing twice", async () => {
    const { checkout, api, storage } = setup(); saveCustomerCart("a", { retail: { rice: 1 }, food: draft().food }, storage); await checkout.reserve(draft());
    await expect(checkout.confirm(() => { throw new Error("cart quota"); })).rejects.toThrow("cart quota");
    expect(loadCustomerCart("a", storage).food).toEqual(draft().food);
    await checkout.confirm(action => { if (action.type === "checkoutSucceeded") acknowledgeFoodCheckout("a", action.orderId, action.purchased.food, storage); });
    expect(api.commit).toHaveBeenCalledOnce(); expect(loadCustomerCart("a", storage)).toEqual({ retail: { rice: 1 }, food: [] });
  });
  it("writes Food acknowledgement and quantity changes atomically", () => {
    const storage = cartStorageFixture(); saveCustomerCart("a", { retail: { rice: 1 }, food: draft().food }, storage);
    const before = loadCustomerCart("a", storage);
    const write = vi.spyOn(storage, "setItem").mockImplementation(() => { throw new Error("cart quota"); });
    expect(() => acknowledgeFoodCheckout("a", fixtureId(70), draft().food, storage)).toThrow("cart quota");
    expect(loadCustomerCart("a", storage)).toEqual(before); write.mockRestore();
    expect(acknowledgeFoodCheckout("a", fixtureId(70), draft().food, storage)).toBe(true);
    expect(acknowledgeFoodCheckout("a", fixtureId(70), draft().food, storage)).toBe(false);
  });
  it("isolates journal accounts/projects and excludes a concurrent tab", async () => {
    const { checkout, api, storage, make } = setup(); let finish!: (value: V1Order) => void;
    api.submit.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
    const pending = checkout.reserve(draft()); await vi.waitFor(() => expect(api.submit).toHaveBeenCalledOnce());
    expect(foodRecoveryJournal("b", auth.supabaseUrl, storage).read()).toBeUndefined();
    expect(foodRecoveryJournal("a", "https://other.supabase.co", storage).read()).toBeUndefined();
    await expect(make().reserve(draft())).rejects.toThrow(); finish(order()); await pending; expect(api.submit).toHaveBeenCalledOnce();
  });
  it("fails closed on storage errors and invalid recovery data", async () => {
    const storage = cartStorageFixture(); const { checkout, api } = setup(storage); vi.spyOn(storage, "setItem").mockImplementation(() => { throw new Error("quota"); });
    await expect(checkout.reserve(draft())).rejects.toThrow("quota"); expect(api.submit).not.toHaveBeenCalled();
    const invalid = cartStorageFixture(); vi.spyOn(invalid, "getItem").mockReturnValue('{"version":99}'); const broken = setup(invalid);
    await expect(broken.checkout.reserve(draft())).rejects.toThrow("invalid"); expect(broken.api.submit).not.toHaveBeenCalled();
  });
  it("rejects late responses after cancellation and concurrent requests", async () => {
    const { checkout, api } = setup(); let finish!: (value: V1Order) => void;
    api.submit.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
    const pending = checkout.reserve(draft()); await vi.waitFor(() => expect(api.submit).toHaveBeenCalledOnce());
    await expect(checkout.reserve(draft())).rejects.toThrow("already running"); checkout.cancelRequests(); finish(order());
    await expect(pending).rejects.toMatchObject({ name: "AbortError" }); expect(checkout.order).toBeUndefined();
  });
  it("only forgets a server-proven expired reservation, never a local timer", async () => {
    const { checkout, api, journal } = setup(); await checkout.reserve(draft());
    await expect(checkout.restartAfterTerminalReservation()).rejects.toThrow("not closed");
    const expired = order(); expired.status = "PAYMENT_EXPIRED"; expired.launchPayment!.reservationState = "EXPIRED"; expired.launchPayment!.state = "RESERVATION_EXPIRED";
    api.read.mockResolvedValue(expired); await checkout.restartAfterTerminalReservation(); expect(journal.read()).toBeUndefined(); expect(api.submit).toHaveBeenCalledOnce();
  });
});
