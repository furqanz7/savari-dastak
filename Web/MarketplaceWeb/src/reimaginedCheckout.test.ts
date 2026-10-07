import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { V1Order } from "./dastakV1";
import { ReimaginedGroceryCheckout, groceryOrderSubmission, type GroceryCheckoutDraft, type CheckoutClients } from "./reimaginedCheckout";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { checkoutJournal, type CheckoutJournal } from "./reimaginedCheckoutJournal";
import { cartStorageFixture, checkoutLocksFixture } from "./reimaginedCatalogue.testFixtures";
import { acknowledgeGroceryCheckout, loadCustomerCart, saveCustomerCart } from "./customerCartPersistence";

const skuId = "11111111-1111-4111-8111-111111111111";
const auth = { accessToken: "test", supabaseUrl: "https://example.supabase.co", publishableKey: "public" };
beforeEach(() => vi.stubGlobal("navigator", { locks: checkoutLocksFixture() }));
afterEach(() => vi.unstubAllGlobals());
const draft: GroceryCheckoutDraft = { retail: { [skuId]: 2 }, recipient: { name: "Customer", phoneNumber: "+919876543210" }, address: { addressId: "home", label: "Home", address: "Test address", building: "1", details: "", displayAddress: "Test address", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-09-30" } };
function order(committed = false): V1Order {
  return { id: "22222222-2222-4222-8222-222222222222", displayOrderNumber: "TEST-1", orderType: "GROCERY", status: committed ? "PREPARING" : "AWAITING_PAYMENT", version: committed ? 4 : 3,
    lines: [{ id: "line", lineType: "RETAIL_SKU", skuId, name: "Test SKU", quantity: 2, unitPricePaise: 10000, lineTotalPaise: 20000, status: "SECURED" }],
    price: { snapshotKind: "FINAL", subtotalPaise: 20000, deliveryFeePaise: 1000, platformFeePaise: 200, discountPaise: 0, taxPaise: 0, totalPaise: 21200, currencyCode: "INR" },
    launchPayment: { optionLabel: "Pay via UPI/Cash on Delivery", state: committed ? "PAYMENT_DUE_AT_DELIVERY" : "READY_TO_CONFIRM", reservationState: committed ? "COMMITTED" : "ACTIVE", reservationSecondsRemaining: 60, reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: !committed, noChargeNow: true, payAtDoorstep: true },
  } as V1Order;
}
function setup(journal?: CheckoutJournal) {
  const api = { submit: vi.fn<CheckoutClients["submit"]>().mockResolvedValue(order()), commit: vi.fn<CheckoutClients["commit"]>().mockResolvedValue(order(true)), read: vi.fn<CheckoutClients["read"]>().mockResolvedValue(order()) };
  let key = 0; const checkout = new ReimaginedGroceryCheckout(auth, api, () => `key-${++key}`, undefined, journal);
  return { api, checkout };
}
describe("Grocery-only reservation and commitment", () => {
  it("sends only exact Grocery SKUs, without client totals or Food branch fields", () => {
    const submission = groceryOrderSubmission(draft);
    expect(submission.lines).toEqual([{ lineType: "RETAIL_SKU", skuId, quantity: 2 }]);
    expect(submission).not.toHaveProperty("restaurantBranchId"); expect(submission).not.toHaveProperty("price");
    expect(submission.deliveryAddress.line1).toBe("Test address");
  });
  it("rejects empty/invalid quantities, incomplete recipients and invalid locations before requests", async () => {
    const { api, checkout } = setup();
    for (const invalid of [{ ...draft, retail: {} }, { ...draft, retail: { [skuId]: 1.5 } }, { ...draft, retail: { invalid: 1 } }, { ...draft, recipient: { name: "", phoneNumber: "" } }, { ...draft, address: { ...draft.address, location: { latitude: 99, longitude: 77 } } }]) await expect(checkout.reserve(invalid)).rejects.toThrow();
    expect(api.submit).not.toHaveBeenCalled();
  });
  it("reserves without confirmation, then removes only the submitted Grocery quantities", async () => {
    const { api, checkout } = setup(); await checkout.reserve(draft); expect(api.commit).not.toHaveBeenCalled();
    let state = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "a", shopping: { retail: { [skuId]: 3, other: 1 }, food: [{ branchId: "branch", itemId: "meal", optionIds: [], quantity: 2 }] } });
    const action = await checkout.confirm(); expect(action?.type).toBe("checkoutSucceeded");
    if (action) state = reimaginedReducer(state, action);
    expect(state.shopping.retail).toEqual({ [skuId]: 1, other: 1 }); expect(state.shopping.food[0].quantity).toBe(2);
    expect(state.activeOrder).toEqual({ id: order().id, service: "grocery" });
    expect(api.commit.mock.calls[0][0]).toMatchObject({ expectedVersion: 3, idempotencyKey: "key-2" });
    expect(await checkout.confirm()).toBeUndefined(); expect(api.commit).toHaveBeenCalledOnce();
  });
  it("keeps the submission key and frozen intent when a response is lost", async () => {
    const { api, checkout } = setup(); api.submit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.reserve(draft)).rejects.toThrow("timeout");
    await expect(checkout.reserve({ ...draft, retail: { [skuId]: 3 } })).rejects.toThrow("unresolved");
    await checkout.reserve(draft); expect(api.submit.mock.calls.map(([input]) => input.idempotencyKey)).toEqual(["key-1", "key-1"]);
    expect(api.commit).not.toHaveBeenCalled();
  });
  it("retries confirmation with the same key, order and expected version", async () => {
    const { api, checkout } = setup(); await checkout.reserve(draft); api.commit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.confirm()).rejects.toThrow("timeout"); expect(checkout.committed).toBe(false);
    await checkout.confirm(); expect(api.commit.mock.calls.map(([input]) => [input.orderId, input.expectedVersion, input.idempotencyKey])).toEqual([[order().id, 3, "key-2"], [order().id, 3, "key-2"]]);
    expect(api.submit).toHaveBeenCalledOnce();
  });
  it("recovers a lost confirmation response by reading the server order, without committing twice", async () => {
    const { api, checkout } = setup(); await checkout.reserve(draft); api.commit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.confirm()).rejects.toThrow(); api.read.mockResolvedValueOnce(order(true));
    await checkout.refresh(); expect(checkout.committed).toBe(true);
    expect((await checkout.confirm())?.type).toBe("checkoutSucceeded"); expect(api.commit).toHaveBeenCalledOnce();
  });
  it("blocks expired or unavailable reservations", async () => {
    const { api, checkout } = setup(); const expired = order(); expired.launchPayment!.reservationExpiresAt = "2000-01-01T00:00:00Z"; api.submit.mockResolvedValueOnce(expired);
    await checkout.reserve(draft); await expect(checkout.confirm()).rejects.toThrow("expired"); expect(api.commit).not.toHaveBeenCalled();
  });
  it("waits for the full basket to become ready instead of confirming a matching order", async () => {
    const { api, checkout } = setup(); api.submit.mockResolvedValueOnce({ ...order(), status: "MATCHING", launchPayment: undefined });
    await checkout.reserve(draft); await expect(checkout.confirm()).rejects.toThrow("not ready"); expect(api.commit).not.toHaveBeenCalled();
    await checkout.refresh(); expect((await checkout.confirm())?.type).toBe("checkoutSucceeded");
  });
  it("does not change an ambiguous commit request body after a version refresh", async () => {
    const { api, checkout } = setup(); await checkout.reserve(draft); api.commit.mockRejectedValueOnce(new Error("timeout"));
    await expect(checkout.confirm()).rejects.toThrow(); api.read.mockResolvedValueOnce({ ...order(), version: 4 });
    await checkout.refresh(); await checkout.confirm();
    expect(api.commit.mock.calls.map(([input]) => [input.expectedVersion, input.idempotencyKey])).toEqual([[3, "key-2"], [3, "key-2"]]);
  });
  it("does not acknowledge an unconfirmed or mismatched server order", async () => {
    const { api, checkout } = setup(); await checkout.reserve(draft); api.commit.mockResolvedValueOnce(order());
    await expect(checkout.confirm()).rejects.toThrow("not confirmed");
    const mismatch = order(true); mismatch.lines = [{ ...mismatch.lines[0], quantity: 1 }]; api.commit.mockResolvedValueOnce(mismatch);
    await expect(checkout.confirm()).rejects.toThrow("does not match"); expect(checkout.committed).toBe(false);
  });
  it("rejects late responses after abort and prevents overlapping requests", async () => {
    const { api, checkout } = setup(); let resolve!: (value: V1Order) => void;
    api.submit.mockReturnValueOnce(new Promise(yes => { resolve = yes; })); const pending = checkout.reserve(draft);
    await expect(checkout.reserve(draft)).rejects.toThrow("already running");
    checkout.cancelRequests(); expect(api.submit.mock.calls[0][0].signal?.aborted).toBe(true); resolve(order());
    await expect(pending).rejects.toMatchObject({ name: "AbortError" }); expect(checkout.order).toBeUndefined();
  });
});

describe("durable Grocery checkout recovery", () => {
  it("blocks a competing tab and reloads the journal before retrying", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const { api, checkout } = setup(journal);
    const other = new ReimaginedGroceryCheckout(auth, api, () => "other-key", undefined, journal);
    let resolve!: (value: V1Order) => void;
    api.submit.mockReturnValueOnce(new Promise(yes => { resolve = yes; }));
    const pending = checkout.reserve(draft);
    await vi.waitFor(() => expect(api.submit).toHaveBeenCalledOnce());
    await expect(other.reserve(draft)).rejects.toThrow("another tab");
    resolve(order()); await pending;
    await other.reserve(draft);
    expect(api.submit).toHaveBeenCalledOnce(); expect(api.read).toHaveBeenCalledOnce();
    await other.confirm(action => { if (action.type === "checkoutSucceeded") acknowledgeGroceryCheckout("a", action.orderId, action.purchased.retail, storage); });
    await expect(checkout.confirm()).rejects.toThrow("Refresh"); // Its displayed quote is now stale.
    api.read.mockResolvedValueOnce(order(true)); await checkout.refresh();
    expect(await checkout.confirm()).toBeUndefined(); expect(api.commit).toHaveBeenCalledOnce();
  });
  it("fails closed without browser locking", async () => {
    vi.stubGlobal("navigator", {});
    const { api, checkout } = setup(checkoutJournal("a", auth.supabaseUrl, cartStorageFixture()));
    await expect(checkout.reserve(draft)).rejects.toThrow("coordinate checkout tabs");
    expect(api.submit).not.toHaveBeenCalled();
  });
  it("holds the lock through cart acknowledgement and releases it after an error", async () => {
    const journal = checkoutJournal("a", auth.supabaseUrl, cartStorageFixture());
    const { api, checkout } = setup(journal); await checkout.reserve(draft);
    const other = new ReimaginedGroceryCheckout(auth, api, undefined, undefined, journal);
    let competing: Promise<unknown> | undefined;
    await expect(checkout.confirm(() => {
      competing = other.refresh();
      throw new Error("cart storage failure");
    })).rejects.toThrow("cart storage failure");
    await expect(competing).rejects.toThrow("another tab");
    api.read.mockResolvedValueOnce(order(true)); await other.refresh();
    expect((await other.confirm())?.type).toBe("checkoutSucceeded");
    expect(api.commit).toHaveBeenCalledOnce();
  });
  it.each(["PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT"] as const)("rechecks %s before discarding only the closed attempt", async status => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    saveCustomerCart("a", { retail: draft.retail, food: [] }, storage);
    const { api, checkout } = setup(journal); await checkout.reserve(draft);
    const terminal = { ...order(), status, version: 4, launchPayment: { ...order().launchPayment!, state: "RESERVATION_EXPIRED" as const, reservationState: "EXPIRED" as const, canCommit: false } };
    api.read.mockResolvedValueOnce(terminal);
    await checkout.restartAfterTerminalReservation();
    expect(journal.read()).toBeUndefined(); expect(loadCustomerCart("a", storage).retail).toEqual(draft.retail);
    expect(api.submit).toHaveBeenCalledOnce(); expect(api.commit).not.toHaveBeenCalled();
    await checkout.reserve(draft); expect(api.submit.mock.calls[1][0].idempotencyKey).toBe("key-3");
  });
  it("retains an attempt when terminal recheck fails or the server still reports active", async () => {
    const journal = checkoutJournal("a", auth.supabaseUrl, cartStorageFixture());
    const { api, checkout } = setup(journal); await checkout.reserve(draft);
    api.read.mockRejectedValueOnce(new Error("offline"));
    await expect(checkout.restartAfterTerminalReservation()).rejects.toThrow("offline");
    await expect(checkout.restartAfterTerminalReservation()).rejects.toThrow("not closed");
    expect(journal.read()?.orderId).toBe(order().id); expect(api.submit).toHaveBeenCalledOnce();
  });
  it("persists before submission and reuses its key after reload/token renewal without storing personal data", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const { api, checkout } = setup(journal); api.submit.mockRejectedValueOnce(new Error("lost response"));
    await expect(checkout.reserve(draft)).rejects.toThrow("lost response");
    const saved = journal.read()!;
    expect(saved.submitKey).toBe("key-1"); expect(saved.fingerprint).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(saved)).not.toMatch(/Customer|Test address|9876543210|accessToken|recipient|deliveryAddress/);
    const renewed = new ReimaginedGroceryCheckout({ ...auth, accessToken: "renewed" }, api, () => "new-key", undefined, journal);
    await renewed.reserve(draft);
    expect(api.submit.mock.calls.map(([input]) => input.idempotencyKey)).toEqual(["key-1", "key-1"]);
    expect(api.submit.mock.calls[1][0].accessToken).toBe("renewed");
  });
  it("recovers an existing reservation by order ID instead of submitting it again", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const { api, checkout } = setup(journal); await checkout.reserve(draft);
    const recovered = new ReimaginedGroceryCheckout(auth, api, () => "unused", undefined, journal);
    expect(recovered.order).toBeUndefined(); expect(recovered.recoverableOrderId).toBe(order().id);
    await recovered.refresh(); await recovered.confirm();
    expect(api.submit).toHaveBeenCalledOnce(); expect(api.commit.mock.calls[0][0]).toMatchObject({ expectedVersion: 3, idempotencyKey: "key-2" });
  });
  it("keeps the original commit key/version after a crash during confirmation", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const { api, checkout } = setup(journal); await checkout.reserve(draft); api.commit.mockRejectedValueOnce(new Error("lost response"));
    await expect(checkout.confirm()).rejects.toThrow();
    const recovered = new ReimaginedGroceryCheckout(auth, api, () => "unused", undefined, journal);
    await recovered.refresh(); await recovered.confirm();
    expect(api.commit.mock.calls.map(([input]) => [input.idempotencyKey, input.expectedVersion])).toEqual([["key-2", 3], ["key-2", 3]]);
  });
  it("records cart subtraction and its marker together, and never subtracts twice after reload", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const food = [{ branchId: "b", itemId: "meal", optionIds: [], quantity: 2 }];
    saveCustomerCart("a", { retail: { [skuId]: 3 }, food }, storage);
    const { api, checkout } = setup(journal); await checkout.reserve(draft); const action = await checkout.confirm();
    expect(action?.type).toBe("checkoutSucceeded");
    expect(acknowledgeGroceryCheckout("a", order().id, draft.retail, storage)).toBe(true);
    expect(loadCustomerCart("a", storage)).toEqual({ retail: { [skuId]: 1 }, food });
    saveCustomerCart("a", { retail: { [skuId]: 2 }, food }, storage); // Existing UI edits must retain marker.
    const recovered = new ReimaginedGroceryCheckout(auth, api, () => "unused", undefined, journal);
    api.read.mockResolvedValueOnce(order(true)); await recovered.refresh();
    expect(await recovered.confirm()).toBeUndefined(); expect(api.commit).toHaveBeenCalledOnce();
    expect(acknowledgeGroceryCheckout("a", order().id, draft.retail, storage)).toBe(false);
    expect(loadCustomerCart("a", storage).retail[skuId]).toBe(2);
  });
  it("fails closed when storage cannot save the attempt or acknowledgement", async () => {
    const storage = { getItem: () => null, setItem: () => { throw new Error("storage full"); } };
    const { api, checkout } = setup(checkoutJournal("a", auth.supabaseUrl, storage));
    await expect(checkout.reserve(draft)).rejects.toThrow("storage full"); expect(api.submit).not.toHaveBeenCalled();
    expect(() => acknowledgeGroceryCheckout("a", order().id, draft.retail, storage)).toThrow("storage full");
  });
  it("isolates account/project journals and blocks malformed recovery data", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const { checkout } = setup(journal); await checkout.reserve(draft);
    expect(checkoutJournal("b", auth.supabaseUrl, storage).read()).toBeUndefined();
    expect(checkoutJournal("a", "https://other.supabase.co", storage).read()).toBeUndefined();
    const corrupt = { getItem: () => '{"version":7}', setItem: vi.fn() };
    const { api, checkout: broken } = setup(checkoutJournal("a", auth.supabaseUrl, corrupt));
    expect(broken.recoveryIssue).toContain("invalid"); await expect(broken.reserve(draft)).rejects.toThrow("invalid"); expect(api.submit).not.toHaveBeenCalled();
  });
  it("rejects a changed recipient or address after restarting an ambiguous attempt", async () => {
    const storage = cartStorageFixture(); const journal = checkoutJournal("a", auth.supabaseUrl, storage);
    const { api, checkout } = setup(journal); api.submit.mockRejectedValueOnce(new Error("lost")); await expect(checkout.reserve(draft)).rejects.toThrow();
    const recovered = new ReimaginedGroceryCheckout(auth, api, () => "unused", undefined, journal);
    await expect(recovered.reserve({ ...draft, recipient: { ...draft.recipient, name: "Someone else" } })).rejects.toThrow("unresolved");
    await expect(recovered.reserve({ ...draft, address: { ...draft.address, address: "Other address" } })).rejects.toThrow("unresolved");
    expect(api.submit).toHaveBeenCalledOnce();
  });
});
