// @vitest-environment jsdom
import { act, useEffect } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { saveCustomerCart, loadCustomerCart } from "./customerCartPersistence";
import { groceryFixture, fixtureId, cartStorageFixture, checkoutLocksFixture } from "./reimaginedCatalogue.testFixtures";
import { ReimaginedCustomerRoot } from "./ReimaginedCustomerRoot";
import { useReimaginedCatalogue } from "./useReimaginedCatalogue";
import { useReimaginedAddresses } from "./useReimaginedAddresses";
import { useReimaginedActiveOrder } from "./useReimaginedActiveOrder";
import { useReimaginedFood } from "./useReimaginedFood";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { CustomerSection } from "./customerNavigation";
vi.mock("./useReimaginedWishlist", () => ({ useReimaginedWishlist: () => ({ items: [], ready: true, busy: false, error: undefined, retry: vi.fn(), saved: () => false, toggle: vi.fn() }) }));
vi.mock("./useDastakWebPush", () => ({ useDastakWebPush: () => ({ shouldPrompt: false }) }));
import { submitV1Order, commitV1LaunchPayment, getV1Order, type V1Order } from "./dastakV1";
vi.mock("./dastakV1", async importOriginal => ({ ...await importOriginal<typeof import("./dastakV1")>(), submitV1Order: vi.fn(), commitV1LaunchPayment: vi.fn(), getV1Order: vi.fn() }));
vi.mock("./DastakCustomerView", () => ({ ExistingDastakCustomerView: (props: { onSignOut: () => void; initialSection?: CustomerSection; initialOrderId?: string; initialMerchantOrderId?: string; embedded?: boolean; onViewChange?: (section: CustomerSection) => void; onReorder?: (order: V1Order) => void; onProfileChanged?: (profile: { displayName: string; phoneNumber: string }) => void }) => {
  const { initialSection, onViewChange } = props;
  useEffect(() => { if (initialSection) onViewChange?.(initialSection); }, [initialSection, onViewChange]);
  return <section aria-label="Operational account workspace" data-order-id={props.initialOrderId} data-merchant-order-id={props.initialMerchantOrderId}>{props.initialSection}<button type="button" onClick={() => props.onViewChange?.("payments")}>Fixture Payments</button><button type="button" onClick={props.onSignOut}>Sign out</button><button type="button" onClick={() => props.onReorder?.({ lines: [{ lineType: "RETAIL_SKU", skuId: "00000000-0000-4000-8000-000000000006", quantity: 2 }] } as V1Order)}>Fixture Order again</button><button type="button" onClick={() => props.onReorder?.(mixedOrderFixture())}>Fixture mixed order</button><button type="button" onClick={() => props.onProfileChanged?.({ displayName: "Updated recipient", phoneNumber: "+919876543210" })}>Fixture profile update</button></section>;
} }));
vi.mock("./useReimaginedCatalogue", () => ({ useReimaginedCatalogue: vi.fn() }));
vi.mock("./useReimaginedAddresses", () => ({ useReimaginedAddresses: vi.fn() }));
vi.mock("./useReimaginedFood", () => ({ useReimaginedFood: vi.fn() }));
vi.mock("./useReimaginedActiveOrder", () => ({ useReimaginedActiveOrder: vi.fn(() => ({ activeOrder: undefined, error: undefined, storageIssue: undefined, label: "", retry: vi.fn() })) }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const props = { accountId: "a", accessToken: "session-token", supabaseUrl: "https://example.supabase.co", publishableKey: "publishable", displayName: "Customer", onSignOut: vi.fn(), client: {} as SupabaseClient, legalLinks: { terms: "/terms", privacy: "/privacy", support: "/support" }, webPushPublicKey: "", deliveryPartnerUrl: "", merchantUrl: "" };
function mixedOrderFixture(): V1Order {
  const menu = foodMenuFixture(); const item = menu.categories[0].items[0]; const option = item.optionGroups[0].options[0];
  return { id: fixtureId(90), displayOrderNumber: "TEST", orderType: "MIXED", status: "DELIVERED", version: 1, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z", restaurant: menu.restaurant,
    price: { snapshotKind: "FINAL", subtotalPaise: 56000, deliveryFeePaise: 0, platformFeePaise: 0, taxPaise: 0, discountPaise: 0, totalPaise: 56000, currencyCode: "INR" },
    lines: [{ id: fixtureId(91), name: "Rice", lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity: 2, status: "DELIVERED", unitPricePaise: 10000, lineTotalPaise: 20000 }, { id: fixtureId(92), name: item.name, lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, status: "DELIVERED", unitPricePaise: 18000, lineTotalPaise: 36000, foodSelection: { options: [{ ...option, groupId: item.optionGroups[0].id, groupName: "Size" }] } }] };
}
function click(label: string) {
  const button = [...host.querySelectorAll("button")].find(element => (element.getAttribute("aria-label") ?? element.textContent) === label);
  if (!button) throw new Error(`Missing button ${label}`);
  act(() => button.click());
}
function mount() { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<ReimaginedCustomerRoot {...props} />)); }
beforeEach(() => {
  window.history.replaceState(null, "", "#/home");
  vi.stubGlobal("navigator", { locks: checkoutLocksFixture() });
  vi.mocked(useReimaginedFood).mockReturnValue({ data: [], error: undefined, status: "ready", retry: vi.fn() });
  vi.mocked(useReimaginedActiveOrder).mockReturnValue({ activeOrder: undefined, error: undefined, storageIssue: undefined, label: "", retry: vi.fn() });
});
beforeEach(() => { vi.stubGlobal("localStorage", cartStorageFixture()); vi.mocked(useReimaginedCatalogue).mockReturnValue({ data: groceryFixture, status: "ready", error: undefined, retry: vi.fn() }); vi.mocked(useReimaginedAddresses).mockReturnValue({ addresses: [], selected: undefined, error: undefined, status: "ready", select: vi.fn(), retry: vi.fn() }); });
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); localStorage.clear(); vi.clearAllMocks(); vi.unstubAllGlobals(); });
describe("authenticated local customer integration", () => {
  it("waits for saved locations on Food entry, then passes only address identity/version without cart writes", () => {
    const resource = { addresses: [], selected: undefined, error: undefined, status: "loading" as const, select: vi.fn(), retry: vi.fn() };
    vi.mocked(useReimaginedAddresses).mockReturnValue(resource);
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [] }; saveCustomerCart("a", shopping);
    mount(); click("Food");
    expect(useReimaginedAddresses).toHaveBeenLastCalledWith(expect.anything(), true);
    expect(useReimaginedFood).toHaveBeenLastCalledWith(expect.anything(), false, true, undefined, "", undefined);
    const selected = { addressId: fixtureId(70), updatedAt: "2026-10-08T00:00:00Z", label: "Home", address: "Private test street", building: "1", details: "", displayAddress: "Private test street", location: { latitude: 12, longitude: 77 }, isDefault: true };
    vi.mocked(useReimaginedAddresses).mockReturnValue({ ...resource, status: "ready", addresses: [selected], selected });
    act(() => root.render(<ReimaginedCustomerRoot {...props} />));
    expect(useReimaginedFood).toHaveBeenLastCalledWith(expect.anything(), true, true, undefined, "", { addressId: selected.addressId, updatedAt: selected.updatedAt });
    expect(loadCustomerCart("a")).toEqual(shopping); expect(submitV1Order).not.toHaveBeenCalled(); expect(commitV1LaunchPayment).not.toHaveBeenCalled();
  });
  it.each(["#/wishlist", "#/payments", "#/search", "#/account", "#/settings", `#/v1-orders/${fixtureId(20)}`, `#/orders/${fixtureId(20)}`])("restores %s without changing either cart or submitting an order", async hash => {
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [{ branchId: "saved", itemId: "meal", optionIds: [], quantity: 3 }] };
    saveCustomerCart("a", shopping); window.history.replaceState(null, "", hash);
    await act(async () => mount());
    if (hash === "#/wishlist") expect(host.textContent).toContain("Your Wishlist");
    if (hash === "#/payments") expect(host.querySelector('[aria-label="Operational account workspace"]')?.textContent).toContain("payments");
    if (hash === "#/search") expect(host.querySelector('input[type="search"]')).not.toBeNull();
    if (hash === "#/account" || hash === "#/settings") expect(host.querySelector('[aria-label="Operational account workspace"]')).not.toBeNull();
    if (hash.includes("v1-orders")) expect(host.querySelector('[data-order-id]')?.getAttribute("data-order-id")).toBe(fixtureId(20));
    if (hash.startsWith("#/orders/")) { expect(host.querySelector('[data-merchant-order-id]')?.getAttribute("data-merchant-order-id")).toBe(fixtureId(20)); expect(host.querySelector('[data-order-id]')).toBeNull(); }
    expect(window.location.hash).toBe(hash);
    expect(loadCustomerCart("a")).toEqual(shopping); expect(submitV1Order).not.toHaveBeenCalled(); expect(commitV1LaunchPayment).not.toHaveBeenCalled();
  });
  it("restores the older record on Back and clears its identity on Forward without touching carts", async () => {
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [] };
    saveCustomerCart("a", shopping); window.history.replaceState(null, "", `#/orders/${fixtureId(20)}`);
    await act(async () => mount()); await act(async () => click("Orders"));
    expect(window.location.hash).toBe("#/orders"); expect(host.querySelector('[data-merchant-order-id]')).toBeNull();
    for (const direction of ["back", "forward"] as const) {
      await act(async () => { await new Promise<void>(resolve => { window.addEventListener("popstate", () => resolve(), { once: true }); window.history[direction](); }); });
      expect(host.querySelector('[data-merchant-order-id]')?.getAttribute("data-merchant-order-id")).toBe(direction === "back" ? fixtureId(20) : undefined);
      expect(host.querySelector('[data-order-id]')).toBeNull(); expect(loadCustomerCart("a")).toEqual(shopping);
    }
    expect(submitV1Order).not.toHaveBeenCalled(); expect(commitV1LaunchPayment).not.toHaveBeenCalled();
  });
  it("restores Back/Forward across Wishlist, Payments and shopping while keeping current carts", async () => {
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food: [] }); await act(async () => mount());
    click("Open Wishlist"); expect(window.location.hash).toBe("#/wishlist");
    await act(async () => click("Orders")); click("Fixture Payments"); expect(window.location.hash).toBe("#/payments");
    click("Home");
    const traverse = async (direction: "back" | "forward") => {
      await act(async () => { await new Promise<void>(resolve => { window.addEventListener("popstate", () => resolve(), { once: true }); window.history[direction](); }); });
    };
    await traverse("back"); expect(host.querySelector('[aria-label="Operational account workspace"]')?.textContent).toContain("payments");
    await traverse("back"); expect(window.location.hash).toBe("#/orders");
    await traverse("back"); expect(host.textContent).toContain("Your Wishlist");
    await traverse("forward"); expect(window.location.hash).toBe("#/orders");
    expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 }); expect(submitV1Order).not.toHaveBeenCalled();
  });
  it("restores browse/detail history but does not roll back newer quantities", async () => {
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 1 }, food: [] }); await act(async () => mount());
    click("Rice"); click("View Test Plain Rice, 1 kg details"); click("Add one Test Plain Rice, 1 kg");
    await act(async () => { await new Promise<void>(resolve => { window.addEventListener("popstate", () => resolve(), { once: true }); window.history.back(); }); });
    expect(host.querySelector(".reimagined-product-detail")).toBeNull(); expect(host.textContent).toContain("Plain Rice");
    expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
  });
  it("reacts to an incoming hash link and removes history listeners on unmount", async () => {
    await act(async () => mount());
    await act(async () => { window.location.hash = "#/search?service=food&q=rice"; await new Promise<void>(resolve => window.addEventListener("hashchange", () => resolve(), { once: true })); });
    expect(host.textContent).toContain("Results for “rice”");
    expect(useReimaginedFood).toHaveBeenLastCalledWith(expect.anything(), true, true, undefined, "rice", undefined);
    const remove = vi.spyOn(window, "removeEventListener"); act(() => root.unmount());
    expect(remove).toHaveBeenCalledWith("popstate", expect.any(Function)); expect(remove).toHaveBeenCalledWith("hashchange", expect.any(Function)); remove.mockRestore();
  });
  it("rebuilds each part of a mixed order by choice and approval without submitting either order", async () => {
    const menu = foodMenuFixture(); const findRestaurant = vi.fn().mockResolvedValue(menu);
    vi.mocked(useReimaginedFood).mockReturnValue({ data: [], status: "ready", error: undefined, retry: vi.fn(), findRestaurant });
    const food = [{ branchId: fixtureId(30), itemId: fixtureId(33), optionIds: [fixtureId(35)], quantity: 1 }];
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 3 }, food }); mount(); await act(async () => click("Orders")); click("Fixture mixed order");
    expect(host.textContent).toContain("Rebuild this order as separate carts");
    await act(async () => click("Rebuild Grocery")); expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 3 });
    click("Replace cart and review"); expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 2 }, food });
    await act(async () => click("Orders")); click("Fixture mixed order"); await act(async () => click("Rebuild Food"));
    expect(findRestaurant).toHaveBeenCalledWith(menu.restaurant.branchId); expect(loadCustomerCart("a").food).toEqual(food);
    click("Replace cart and review"); expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 2 }, food: [{ ...food[0], quantity: 2 }] });
    expect(submitV1Order).not.toHaveBeenCalled(); expect(commitV1LaunchPayment).not.toHaveBeenCalled();
  });
  it("does not apply a late restaurant lookup after the user leaves Orders", async () => {
    let finish!: (menu: ReturnType<typeof foodMenuFixture>) => void;
    const findRestaurant = vi.fn().mockReturnValue(new Promise(resolve => { finish = resolve; }));
    vi.mocked(useReimaginedFood).mockReturnValue({ data: [], status: "ready", error: undefined, retry: vi.fn(), findRestaurant });
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 3 }, food: [] }); mount(); await act(async () => click("Orders")); click("Fixture mixed order");
    await act(async () => click("Rebuild Food")); click("Home"); await act(async () => finish(foodMenuFixture()));
    expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 3 }, food: [] }); expect(submitV1Order).not.toHaveBeenCalled();
  });
  it("opens a native Wishlist without leaving Reimagined", () => {
    mount(); click("Open Wishlist"); expect(host.textContent).toContain("Your Wishlist");
    click("Back to shopping"); expect(host.textContent).toContain("Quick picks");
  });
  it("requires approval before restoring an old order and retains the other cart", async () => {
    const food = [{ branchId: fixtureId(30), itemId: fixtureId(33), optionIds: [], quantity: 1 }];
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 3 }, food }); mount();
    await act(async () => click("Orders")); click("Fixture Order again");
    expect(host.textContent).toContain("Replace your current Bucket?"); expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 3 });
    click("Keep current cart"); expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 3 });
    click("Fixture Order again"); click("Replace cart and review");
    expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 2 }, food });
    expect(host.textContent).toContain("Review your Grocery items"); expect(submitV1Order).not.toHaveBeenCalled();
  });
  it("uses a successfully edited profile for the next billing review", async () => {
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 1 }, food: [] }); mount();
    await act(async () => click("Profile")); click("Fixture profile update"); click("Home"); click("Take to Cart"); click("2Delivery & billing");
    expect(host.querySelector('[aria-label="Delivery recipient"]')?.textContent).toContain("Updated recipient");
    expect(host.querySelector('[aria-label="Delivery recipient"]')?.textContent).toContain("+919876543210");
  });
  it("reviews delivery with the existing address resource without order requests or Bucket changes", () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    const select = vi.fn();
    const address = { addressId: "test-home", label: "Test Home", address: "Test Street", building: "1", details: "", displayAddress: "Test Home address", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" };
    vi.mocked(useReimaginedAddresses).mockReturnValue({ addresses: [address, { ...address, addressId: "test-office", label: "Test Office", isDefault: false }], selected: address, error: undefined, status: "ready", select, retry: vi.fn() });
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [] };
    saveCustomerCart("a", shopping); mount(); click("Take to Cart"); click("2Delivery & billing");
    expect(host.querySelector(".reimagined-selected-address")?.textContent).toContain("Test Home address");
    expect(host.querySelector('[aria-label="Billing estimate"]')?.textContent).toContain("₹200.00");
    expect(host.querySelector('[aria-label="Grocery checkout checks"]')?.textContent).toContain("name and phone number");
    act(() => host.querySelectorAll<HTMLInputElement>('input[type="radio"]')[1].click());
    expect(select).toHaveBeenCalledWith("test-office");
    expect([...host.querySelectorAll("button")].find(button => button.textContent === "Reserve Grocery order")?.disabled).toBe(true);
    click("1Items"); click("Continue Shopping");
    expect(loadCustomerCart("a")).toEqual(shopping); expect(fetcher).not.toHaveBeenCalled();
  });
  it("updates review quantities and estimates immediately, preserving both carts on return", () => {
    const food = [{ branchId: "branch", itemId: "meal", optionIds: [], quantity: 2 }];
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food }); mount(); click("Take to Cart");
    click("Increase Test Plain Rice, 1 kg in Bucket");
    expect(host.querySelector('[aria-label="Review Grocery Bucket"]')?.textContent).toContain("Estimated item subtotal: ₹300.00");
    click("Decrease Test Plain Rice, 1 kg in Bucket");
    expect(host.querySelector('[aria-label="Review Grocery Bucket"]')?.textContent).toContain("Estimated item subtotal: ₹200.00");
    click("Continue Shopping");
    expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 2 }, food });
  });
  it("blocks review increases offline but allows reductions and last-item removal", () => {
    vi.stubGlobal("navigator", { locks: checkoutLocksFixture(), onLine: false });
    const food = [{ branchId: "branch", itemId: "meal", optionIds: [], quantity: 2 }];
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food }); mount(); click("Take to Cart");
    const increase = host.querySelector<HTMLButtonElement>('button[aria-label="Increase Test Plain Rice, 1 kg in Bucket"]')!;
    expect(increase.disabled).toBe(true); act(() => increase.click());
    expect(loadCustomerCart("a").retail[fixtureId(6)]).toBe(2);
    click("Decrease Test Plain Rice, 1 kg in Bucket"); click("Decrease Test Plain Rice, 1 kg in Bucket");
    expect(loadCustomerCart("a")).toEqual({ retail: {}, food });
    expect(host.querySelector('[aria-label="Review Grocery Bucket"]')).toBeNull();
  });
  it("prevents increasing unresolved products or quantities beyond 99", () => {
    saveCustomerCart("a", { retail: { missing: 2, [fixtureId(6)]: 99 }, food: [] }); mount(); click("Take to Cart");
    expect(host.querySelector<HTMLButtonElement>('button[aria-label="Increase saved product in Bucket"]')?.disabled).toBe(true);
    expect(host.querySelector<HTMLButtonElement>('button[aria-label="Increase Test Plain Rice, 1 kg in Bucket"]')?.disabled).toBe(true);
    click("Decrease saved product in Bucket");
    expect(loadCustomerCart("a").retail).toEqual({ missing: 1, [fixtureId(6)]: 99 });
  });
  it("keeps every review edit disabled when this tab cannot own the cart", () => {
    vi.stubGlobal("navigator", { onLine: true });
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [] };
    saveCustomerCart("a", shopping); mount(); click("Take to Cart");
    const review = host.querySelector('[aria-label="Review Grocery Bucket"]')!;
    const controls = [...review.querySelectorAll<HTMLButtonElement>("button")];
    expect(controls).toHaveLength(3);
    expect(controls.every(button => button.disabled)).toBe(true);
    act(() => controls.forEach(button => button.click()));
    expect(loadCustomerCart("a")).toEqual(shopping);
  });
  it("shows checkout availability guidance rather than a reconnect warning for an online product", () => {
    mount(); click("Rice"); click("View Test Plain Rice, 1 kg details");
    const detail = host.querySelector(".reimagined-product-detail")!;
    expect(detail.textContent).toContain("Purchase availability will be confirmed at checkout.");
    expect(detail.textContent).not.toContain("Reconnect to add products");
    expect(detail.querySelector<HTMLButtonElement>('button[aria-label="Add Test Plain Rice, 1 kg"]')?.disabled).toBe(false);
  });
  it("shows the reconnect warning only while offline and removes it after reconnecting", () => {
    vi.stubGlobal("navigator", { locks: checkoutLocksFixture(), onLine: false });
    mount(); click("Rice"); click("View Test Plain Rice, 1 kg details");
    const detail = host.querySelector(".reimagined-product-detail")!;
    expect(detail.textContent).toContain("Reconnect to add products");
    expect(detail.querySelector<HTMLButtonElement>('button[aria-label="Add Test Plain Rice, 1 kg"]')?.disabled).toBe(true);
    vi.stubGlobal("navigator", { locks: navigator.locks, onLine: true });
    act(() => window.dispatchEvent(new Event("online")));
    expect(detail.textContent).not.toContain("Reconnect to add products");
    expect(detail.querySelector<HTMLButtonElement>('button[aria-label="Add Test Plain Rice, 1 kg"]')?.disabled).toBe(false);
    expect(loadCustomerCart("a")).toEqual({ retail: {}, food: [] });
  });
  it("prepares Food review and loads addresses without sending an order or changing carts", () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    const menu = foodMenuFixture(); const item = menu.categories[0].items[0];
    vi.mocked(useReimaginedFood).mockReturnValue({ data: [menu], error: undefined, status: "ready", retry: vi.fn() });
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [item.optionGroups[0].options[0].id], quantity: 2 }] };
    saveCustomerCart("a", shopping); mount(); click("Food"); click("Review Food cart");
    expect(useReimaginedAddresses).toHaveBeenLastCalledWith(expect.objectContaining({ accountId: "a" }), true);
    const review = host.querySelector('[aria-label="Food checkout preparation"]')!;
    expect(review.textContent).toContain("₹360.00"); expect(review.textContent).toContain("Choose a valid saved delivery address");
    expect([...review.querySelectorAll("button")].find(button => button.textContent === "Reserve Food order")?.disabled).toBe(true);
    click("Continue Shopping"); expect(loadCustomerCart("a")).toEqual(shopping);
    expect(useReimaginedAddresses).toHaveBeenLastCalledWith(expect.objectContaining({ accountId: "a" }), true);
    expect(fetcher).not.toHaveBeenCalled();
  });
  it("enables Food loading only on Food entry and preserves both carts through menus", () => {
    vi.mocked(useReimaginedFood).mockReturnValue({ data: [foodMenuFixture()], error: undefined, status: "ready", retry: vi.fn() });
    const shopping = { retail: { [fixtureId(6)]: 2 }, food: [{ branchId: "saved", itemId: "meal", optionIds: [], quantity: 3 }] };
    saveCustomerCart("a", shopping); mount();
    expect(useReimaginedFood).toHaveBeenLastCalledWith(expect.objectContaining({ accountId: "a" }), false, true, undefined, "", undefined);
    click("Food"); expect(useReimaginedFood).toHaveBeenLastCalledWith(expect.objectContaining({ accountId: "a" }), true, true, undefined, "", undefined);
    click("Open Test Café menu"); click("View Test Paneer Rice details"); click("Grocery");
    expect(loadCustomerCart("a")).toEqual(shopping);
  });
  it("keeps the server-driven order strip independent of shopping and navigation", async () => {
    vi.mocked(useReimaginedActiveOrder).mockReturnValue({ activeOrder: { id: fixtureId(20), service: "grocery" }, error: undefined, storageIssue: undefined, label: "Out for delivery", retry: vi.fn() });
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food: [] }); mount();
    click("Food"); await act(async () => click("Orders"));
    expect(host.querySelector(".reimagined-order-strip")?.textContent).toContain("Out for delivery");
    expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
  });
  it("loads addresses only for Location or Grocery review, and shows the same picker", () => {
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 1 }, food: [] }); mount();
    expect(useReimaginedAddresses).toHaveBeenLastCalledWith(expect.objectContaining({ accountId: "a" }), false);
    const location = host.querySelector('button[aria-expanded="false"]')!;
    act(() => (location as HTMLButtonElement).click());
    expect(useReimaginedAddresses).toHaveBeenLastCalledWith(expect.objectContaining({ accountId: "a" }), true);
    expect(host.querySelector('[aria-label="Delivery location"]')?.textContent).toContain("no saved delivery addresses");
    click("Close location"); click("Take to Cart");
    expect(host.querySelector('[aria-label="Choose a saved delivery address"]')).not.toBeNull();
  });
  it("passes existing session through, edits the existing cart and isolates Food review", () => {
    const food = [{ branchId: "branch", itemId: "meal", optionIds: [], quantity: 2 }];
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food }); mount();
    expect(useReimaginedCatalogue).toHaveBeenCalledWith(expect.objectContaining({ accountId: "a", accessToken: "session-token" }));
    click("Rice");
    click("Add one Test Plain Rice, 1 kg");
    click("Take to Cart");
    expect(host.textContent).toContain("Estimated item subtotal: ₹300.00");
    expect(host.querySelector('[aria-label="Review Grocery Bucket"]')?.textContent).not.toContain("meal");
    expect([...host.querySelectorAll("button")].find(button => button.textContent === "Reserve Grocery order")?.disabled).toBe(true);
    click("Continue Shopping"); click("Food"); click("Grocery");
    expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 3 }, food });
  });
  it("does not silently delete unresolved saved products or quote an incomplete subtotal", () => {
    saveCustomerCart("a", { retail: { missing: 1, [fixtureId(6)]: 2 }, food: [] }); mount(); click("Take to Cart");
    expect(host.textContent).toContain("This item has been retained, not silently removed.");
    expect(host.textContent).toContain("complete price is unavailable");
    expect(loadCustomerCart("a").retail.missing).toBe(1);
    click("Remove saved product from Bucket"); expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
  });
  it("preserves shopping on token refresh and switches accounts without leaking old lines", () => {
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food: [] });
    saveCustomerCart("b", { retail: { [fixtureId(8)]: 1 }, food: [] }); mount();
    act(() => root.render(<ReimaginedCustomerRoot {...props} accessToken="refreshed-token" />));
    expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
    act(() => root.render(<ReimaginedCustomerRoot {...props} accountId="b" />)); click("Take to Cart");
    const review = host.querySelector('[aria-label="Review Grocery Bucket"]')!;
    expect(review.textContent).toContain("Test Poha"); expect(review.textContent).not.toContain("Test Plain Rice");
    expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
  });
  it("uses the real host sign-out callback without deleting the saved cart", async () => {
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food: [] }); mount();
    await act(async () => click("Settings")); click("Sign out");
    expect(props.onSignOut).toHaveBeenCalledOnce(); expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
  });
  it("enables real Grocery checkout only on explicit clicks and clears only server-confirmed quantities", async () => {
    const address = { addressId: "home", label: "Home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" };
    vi.mocked(useReimaginedAddresses).mockReturnValue({ addresses: [address], selected: address, error: undefined, status: "ready", select: vi.fn(), retry: vi.fn() });
    const reserved = { id: fixtureId(20), displayOrderNumber: "TEST-20", version: 3, status: "AWAITING_PAYMENT", lines: [{ lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity: 2 }], price: { subtotalPaise: 20000, totalPaise: 22000 }, launchPayment: { state: "READY_TO_CONFIRM", reservationState: "ACTIVE", reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: true, noChargeNow: true, payAtDoorstep: true } } as V1Order;
    vi.mocked(submitV1Order).mockResolvedValue(reserved);
    vi.mocked(commitV1LaunchPayment).mockRejectedValueOnce(new Error("Lost confirmation response"));
    const foodLines = [{ branchId: fixtureId(30), itemId: fixtureId(31), optionIds: [], quantity: 1 }];
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 2 }, food: foodLines });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    await act(async () => root.render(<ReimaginedCustomerRoot {...props} phoneNumber="+919876543210" />));
    click("Take to Cart"); click("2Delivery & billing");
    expect(submitV1Order).not.toHaveBeenCalled(); expect(commitV1LaunchPayment).not.toHaveBeenCalled();
    await act(async () => click("Reserve Grocery order"));
    await act(async () => { await vi.waitFor(() => expect(submitV1Order).toHaveBeenCalledOnce()); });
    expect(submitV1Order).toHaveBeenCalledWith(expect.objectContaining({ accessToken: props.accessToken, order: expect.objectContaining({ lines: [{ lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity: 2 }] }) }));
    expect(commitV1LaunchPayment).not.toHaveBeenCalled();
    await act(async () => click("Confirm Grocery order"));
    expect(loadCustomerCart("a").retail).toEqual({ [fixtureId(6)]: 2 });
    vi.mocked(getV1Order).mockResolvedValue({ ...reserved, status: "PREPARING", version: 4, launchPayment: { ...reserved.launchPayment!, state: "PAYMENT_DUE_AT_DELIVERY", reservationState: "COMMITTED", canCommit: false } });
    await act(async () => click("Recover Grocery reservation"));
    expect(commitV1LaunchPayment).toHaveBeenCalledOnce();
    expect(loadCustomerCart("a")).toEqual({ retail: {}, food: foodLines });
  });
  it("enables Food checkout with exact options and leaves the Grocery Bucket untouched", async () => {
    const menu = foodMenuFixture(); const item = menu.categories[0].items[0]; const option = item.optionGroups[0].options[0];
    const address = { addressId: "home", label: "Home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" };
    vi.mocked(useReimaginedFood).mockReturnValue({ data: [menu], error: undefined, status: "ready", retry: vi.fn() });
    vi.mocked(useReimaginedAddresses).mockReturnValue({ addresses: [address], selected: address, error: undefined, status: "ready", select: vi.fn(), retry: vi.fn() });
    const food = [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [option.id], quantity: 2 }];
    const reserved: V1Order = {
      id: fixtureId(70), createdAt: "2026-10-07T00:00:00Z", updatedAt: "2026-10-07T00:00:00Z", displayOrderNumber: "TEST-70", orderType: "FOOD_ONLY", restaurant: menu.restaurant, version: 3, status: "AWAITING_PAYMENT",
      lines: [{ id: fixtureId(71), name: item.name, status: "SECURED", unitPricePaise: 18000, lineTotalPaise: 36000, lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, foodSelection: { options: [{ ...option, groupId: item.optionGroups[0].id, groupName: "Size" }] } }],
      price: { snapshotKind: "FINAL", subtotalPaise: 36000, deliveryFeePaise: 1000, platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 37000, currencyCode: "INR" },
      launchPayment: { optionLabel: "Pay via UPI/Cash on Delivery", reservationSecondsRemaining: 60, state: "READY_TO_CONFIRM", reservationState: "ACTIVE", reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: true, noChargeNow: true, payAtDoorstep: true },
    };
    vi.mocked(submitV1Order).mockResolvedValue(reserved);
    vi.mocked(commitV1LaunchPayment).mockResolvedValue({ ...reserved, version: 4, status: "PREPARING", launchPayment: { ...reserved.launchPayment!, state: "PAYMENT_DUE_AT_DELIVERY", reservationState: "COMMITTED", canCommit: false } });
    saveCustomerCart("a", { retail: { [fixtureId(6)]: 1 }, food });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    await act(async () => root.render(<ReimaginedCustomerRoot {...props} phoneNumber="+919876543210" />));
    click("Food"); click("Review Food cart");
    expect(submitV1Order).not.toHaveBeenCalled();
    await act(async () => click("Reserve Food order"));
    await act(async () => { await vi.waitFor(() => expect(submitV1Order).toHaveBeenCalledOnce()); });
    expect(submitV1Order).toHaveBeenCalledWith(expect.objectContaining({ accessToken: props.accessToken, order: expect.objectContaining({ restaurantBranchId: menu.restaurant.branchId, lines: [{ lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, optionIds: [option.id] }] }) }));
    expect(commitV1LaunchPayment).not.toHaveBeenCalled();
    await act(async () => click("Confirm Food order"));
    expect(loadCustomerCart("a")).toEqual({ retail: { [fixtureId(6)]: 1 }, food: [] });
  });
});
