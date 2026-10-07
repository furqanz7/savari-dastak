// @vitest-environment jsdom
import { act, useReducer } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ReimaginedFood, ReimaginedFoodSuggestions } from "./ReimaginedFood";
import { ReimaginedShell } from "./ReimaginedShell";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { prepareFoodMenus } from "./reimaginedFoodCatalogue";
import type { useReimaginedFood } from "./useReimaginedFood";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const menus = prepareFoodMenus([foodMenuFixture()]);
const ready: ReturnType<typeof useReimaginedFood> = { data: menus, status: "ready", error: undefined, retry: vi.fn() };
let root: Root; let host: HTMLDivElement;
function Harness({ resource = ready, online = true, empty = false, canEdit = true }: { resource?: typeof ready; online?: boolean; empty?: boolean; canEdit?: boolean }) {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "a", shopping: { retail: { saved: 2 }, food: empty ? [] : [{ branchId: "saved", itemId: "saved", optionIds: [], quantity: 3 }] } }), { type: "selectService", service: "food" }));
  return <><ReimaginedShell state={state} dispatch={dispatch} directory={[]} greeting="Hi" locationLabel="Location" locationContent={null} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{}}
    searchSuggestions={<ReimaginedFoodSuggestions menus={resource.data} query={state.exploration.food.searchDraft} dispatch={dispatch} />}>
    <ReimaginedFood state={state} dispatch={dispatch} resource={resource} online={online} supabaseUrl="https://example.supabase.co" legacyUrl="/#home" canEdit={canEdit} />
  </ReimaginedShell><output aria-label="Saved shopping">{JSON.stringify(state.shopping)}</output></>;
}
function mount(resource = ready, online = true, empty = false) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness resource={resource} online={online} empty={empty} />)); }
function click(label: string) { const button = [...host.querySelectorAll("button")].find(value => (value.getAttribute("aria-label") ?? value.textContent) === label); if (!button) throw new Error(`Missing ${label}`); act(() => button.click()); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe("Food discovery and menus", () => {
  it("jumps to exact menu categories in the opened branch without changing either cart", () => {
    const menu = foodMenuFixture();
    menu.categories.push({ ...menu.categories[0], id: fixtureId(40), name: "Drinks", items: [] });
    const other = foodMenuFixture(fixtureId(41)); other.restaurant.branchName = "Other Café";
    const scroll = vi.fn();
    vi.stubGlobal("matchMedia", vi.fn().mockReturnValue({ matches: true }));
    Object.defineProperty(HTMLElement.prototype, "scrollIntoView", { configurable: true, value: scroll });
    mount({ ...ready, data: prepareFoodMenus([menu, other]) });
    const shopping = host.querySelector("output")!.textContent;
    click("Open Test Café menu"); click("Drinks");
    const target = host.querySelector('[aria-label="Drinks menu category"]')!;
    expect(document.activeElement).toBe(target);
    expect(scroll).toHaveBeenCalledWith({ block: "start", behavior: "instant" });
    expect(scroll.mock.instances[0]).toBe(target);
    const shortcut = [...host.querySelectorAll('.reimagined-menu-shortcuts button')].find(button => button.textContent === "Drinks")!;
    expect(shortcut.getAttribute("aria-controls")).toBe(target.id);
    const firstTarget = host.querySelector('[aria-label="Meals menu category"]')!.id;
    click("Back to restaurants"); click("Open Other Café menu"); click("Meals");
    expect(host.querySelector('[aria-label="Meals menu category"]')!.id).not.toBe(firstTarget);
    expect(host.querySelector('[aria-label="Drinks menu category"]')).toBeNull();
    expect(host.querySelector("output")!.textContent).toBe(shopping);
    delete (HTMLElement.prototype as { scrollIntoView?: unknown }).scrollIntoView;
  });
  it("filters restaurants by real menu categories and keeps both carts through service switching", () => {
    const drinks = foodMenuFixture(fixtureId(40)); drinks.restaurant.branchName = "Drinks Café"; drinks.categories[0].name = "Hot Drinks";
    mount({ ...ready, data: prepareFoodMenus([foodMenuFixture(), drinks]) });
    const shopping = host.querySelector("output")!.textContent;
    click("Browse Food category Hot Drinks");
    expect(host.querySelector('[aria-label="Browse Food category Hot Drinks"]')?.getAttribute("aria-pressed")).toBe("true");
    expect(host.querySelector('[aria-label="Open Drinks Café menu"]')).not.toBeNull();
    expect(host.querySelector('[aria-label="Open Test Café menu"]')).toBeNull();
    click("Grocery"); click("Food");
    expect(host.querySelector('[aria-label="Open Test Café menu"]')).toBeNull();
    click("All restaurants"); expect(host.querySelector('[aria-label="Open Test Café menu"]')).not.toBeNull();
    expect(host.querySelector("output")!.textContent).toBe(shopping);
  });
  it("keeps a category selection while typing, then shows complete explicit search results", () => {
    mount(); click("Browse Food category Meals"); click("Open search");
    const input = host.querySelector("input")!;
    act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "paneer"); input.dispatchEvent(new Event("input", { bubbles: true })); });
    expect(host.querySelector('[aria-label="Browse Food category Meals"]')?.getAttribute("aria-pressed")).toBe("true");
    expect(host.querySelector('[aria-label="Restaurant shelf"]')).not.toBeNull();
    act(() => host.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })));
    expect(host.querySelector('[aria-label="Food search results"]')).not.toBeNull();
    expect(host.querySelector('[aria-label="Food menu categories"]')).toBeNull();
    click("Home"); expect(host.querySelector('[aria-label="Food menu categories"] button')?.getAttribute("aria-pressed")).toBe("true");
  });
  it("shows an explicit empty filter after menu refresh rather than opening a replacement category", () => {
    mount(); click("Browse Food category Meals");
    const menu = foodMenuFixture(); menu.categories[0].id = fixtureId(45);
    act(() => root.render(<Harness resource={{ ...ready, data: prepareFoodMenus([menu]) }} />));
    expect(host.textContent).toContain("No restaurants in the loaded menus currently match this category");
    click("All restaurants"); expect(host.querySelector('[aria-label="Open Test Café menu"]')).not.toBeNull();
  });
  it("keeps differently customised dishes as separate lines", () => {
    const menu = foodMenuFixture(); const group = menu.categories[0].items[0].optionGroups[0];
    group.options.push({ ...group.options[0], id: "regular", name: "Regular", priceDeltaPaise: 0 });
    mount({ ...ready, data: prepareFoodMenus([menu]) }, true, true);
    click("Open Test Café menu"); click("View Test Paneer Rice details");
    act(() => (host.querySelectorAll('input[type="radio"]')[0] as HTMLInputElement).click()); click("Add to Food cart");
    act(() => (host.querySelectorAll('input[type="radio"]')[1] as HTMLInputElement).click()); click("Add to Food cart");
    const lines = JSON.parse(host.querySelector("output")!.textContent!).food;
    expect(lines).toHaveLength(2); expect(lines.map((line: { quantity: number }) => line.quantity)).toEqual([1, 1]);
    click("Remove one selected dish"); expect(JSON.parse(host.querySelector("output")!.textContent!).food).toHaveLength(1);
  });
  it("requires explicit options, accumulates exact selections and preserves Grocery", () => {
    mount(ready, true, true); click("Open Test Café menu"); click("View Test Paneer Rice details");
    expect(host.querySelector('input[type="radio"]')?.getAttribute("checked")).toBeNull();
    act(() => (host.querySelector('input[type="radio"]') as HTMLInputElement).click());
    click("Add to Food cart"); click("Add to Food cart");
    const shopping = JSON.parse(host.querySelector("output")!.textContent!);
    expect(shopping.retail).toEqual({ saved: 2 });
    expect(shopping.food).toEqual([{ branchId: menus[0].restaurant.branchId, itemId: menus[0].categories[0].items[0].id, optionIds: [menus[0].categories[0].items[0].optionGroups[0].options[0].id], quantity: 2 }]);
    click("Review Food cart"); expect(host.textContent).toContain("₹360.00 estimated"); expect(host.textContent).toContain("Large");
    click("Remove Test Paneer Rice"); expect(JSON.parse(host.querySelector("output")!.textContent!).food).toEqual([]);
  });
  it("blocks offline, paused, read-only and other-restaurant additions without dropping saved lines", () => {
    mount(); click("Open Test Café menu"); click("View Test Paneer Rice details");
    act(() => (host.querySelector('input[type="radio"]') as HTMLInputElement).click());
    expect(host.textContent).toContain("belongs to another restaurant");
    expect([...host.querySelectorAll("button")].find(button => button.textContent === "Add to Food cart")?.disabled).toBe(true);
    click("Review Food cart"); click("Remove saved dish"); click("View Test Paneer Rice details");
    act(() => (host.querySelector('input[type="radio"]') as HTMLInputElement).click());
    for (const props of [{ online: false }, { canEdit: false }, { resource: { ...ready, data: [{ ...menus[0], restaurant: { ...menus[0].restaurant, acceptingOrders: false } }] } }]) {
      act(() => root.render(<Harness {...props} />));
      expect([...host.querySelectorAll("button")].find(button => button.textContent === "Add to Food cart")?.disabled).toBe(true);
    }
    expect(JSON.parse(host.querySelector("output")!.textContent!).retail).toEqual({ saved: 2 });
  });
  it("opens canonical branch/menu/dish details without changing either cart", () => {
    mount(); const shopping = host.querySelector("output")!.textContent;
    click("Open Test Café menu"); expect(host.textContent).toContain("Meals"); click("View Test Paneer Rice details");
    expect(host.textContent).toContain("₹150.00"); expect(host.textContent).toContain("Large · +₹30.00");
    expect(host.querySelector('[aria-label="Test Paneer Rice dish details"]')).not.toBeNull();
    expect([...host.querySelectorAll("button")].find(button => button.textContent?.startsWith("Add to Food cart"))?.disabled).toBe(true);
    click("Back to menu"); click("Back to restaurants"); expect(host.querySelector("output")!.textContent).toBe(shopping);
  });
  it("typing shows suggestions without replacing content; Enter shows results", () => {
    mount(); click("Open search"); const input = host.querySelector("input")!;
    act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "paneer"); input.dispatchEvent(new Event("input", { bubbles: true })); });
    expect(host.querySelector('[aria-label="Restaurant shelf"]')).not.toBeNull(); expect(host.querySelector('[aria-label="Food suggestions"]')).not.toBeNull();
    act(() => host.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })));
    expect(host.querySelector('[aria-label="Food search results"]')).not.toBeNull(); expect(host.querySelector('[aria-label="Restaurant shelf"]')).toBeNull();
    click("Test Paneer Rice₹150.00 base"); expect(host.querySelector('[aria-label="Test Paneer Rice dish details"]')).not.toBeNull();
  });
  it("reviews and exits the retained Food cart with checkout disabled", () => {
    mount(); const shopping = host.querySelector("output")!.textContent; click("Review Food cart");
    expect(host.textContent).toContain("Quantity 3"); expect([...host.querySelectorAll("button")].find(button => button.textContent === "Food checkout integration pending")?.disabled).toBe(true);
    click("Continue Shopping"); expect(host.querySelector('[aria-label="Restaurant shelf"]')).not.toBeNull(); expect(host.querySelector("output")!.textContent).toBe(shopping);
  });
  it("shows failures, retry, empty catalogue and offline states honestly", () => {
    const retry = vi.fn(); mount({ status: "unavailable", error: new Error("network"), data: undefined, retry });
    click("Retry Food menus"); expect(retry).toHaveBeenCalledOnce();
    act(() => root.render(<Harness resource={{ ...ready, data: [] }} />)); expect(host.textContent).toContain("No restaurants returned");
    act(() => root.render(<Harness resource={{ ...ready, data: undefined }} online={false} />)); expect(host.textContent).toContain("Reconnect to load Food menus");
  });
  it("keeps missing menu/dish identities explicit instead of selecting a replacement", () => {
    mount(); click("Open Test Café menu"); click("View Test Paneer Rice details");
    act(() => root.render(<Harness resource={{ ...ready, data: [] }} />)); expect(host.textContent).toContain("dish is no longer");
    click("Back to menu"); expect(host.textContent).toContain("restaurant is not in the loaded");
  });
});
