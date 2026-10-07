// @vitest-environment jsdom
import { act, useReducer } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it } from "vitest";
import { ReimaginedShell } from "./ReimaginedShell";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import type { V1CatalogueBrowseMap } from "./dastakV1";

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const map: V1CatalogueBrowseMap = { version: 1, nodes: [
  { key: "kitchen", parentKey: null, kind: "SECTION", label: "Grocery & Kitchen", sortOrder: 1, sources: [] },
  { key: "masalas", parentKey: "kitchen", kind: "DESTINATION", label: "Masalas", sortOrder: 2, sources: [] },
  { key: "atta", parentKey: "kitchen", kind: "DESTINATION", label: "Atta, Flour & Dal", sortOrder: 1, sources: [] },
] };
let root: Root;
let host: HTMLDivElement;
function Harness({ signedOut = false }: { signedOut?: boolean }) {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => signedOut ? initialReimaginedState() : reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "test" }));
  return <ReimaginedShell state={state} dispatch={dispatch} directory={reimaginedDirectory(map)} greeting="Hello" locationLabel="Choose location" locationContent={<p>Address picker</p>} onSignIn={() => dispatch({ type: "signedIn", accountId: "test" })} onOpenActiveOrder={() => dispatch({ type: "navigate", section: "orders" })} sectionContent={{ orders: "Order history", settings: "Settings content", profile: "Profile content" }} searchSuggestions={<button onClick={() => { dispatch({ type: "closeSearch" }); dispatch({ type: "openDetail", id: "missing" }); }}>Test missing suggestion</button>}>
    <button onClick={() => dispatch({ type: "signedOut" })}>Test sign out</button>
    <output data-testid="view">{JSON.stringify(state.exploration[state.service].view)}</output>
    <button onClick={() => dispatch({ type: "setGroceryQuantity", skuId: "sku", quantity: 2 })}>Test add</button>
    <button onClick={() => dispatch({ type: "openDetail", id: "scroll-test" })}>Test open details</button>
    {state.exploration[state.service].detailId === "scroll-test" ? <button className="reimagined-detail-close" onClick={() => dispatch({ type: "closeDetail" })}>Test close details</button> : null}
    <button onClick={() => dispatch({ type: "checkoutSucceeded", service: "food", orderId: "order", purchased: state.shopping })}>Test order</button>
  </ReimaginedShell>;
}
function mount(signedOut = false) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness signedOut={signedOut} />)); }
function button(label: string) { const found = Array.from(host.querySelectorAll("button")).find(item => (item.getAttribute("aria-label") ?? item.textContent?.trim()) === label); if (!found) throw new Error(`Missing button: ${label}`); return found; }
function click(label: string) { act(() => button(label).click()); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });

describe("Reimagined shell", () => {
  it("opens cart review at the top and restores shopping scroll and focus", () => {
    mount(); click("Take a Bucket"); click("Test add");
    const content = host.querySelector<HTMLElement>(".reimagined-panel-content")!;
    content.scrollTop = 163;
    click("Take to Cart");
    expect(content.scrollTop).toBe(0);
    expect(document.activeElement).toBe(button("Continue Shopping"));
    click("Continue Shopping");
    expect(content.scrollTop).toBe(163);
    expect(document.activeElement).toBe(button("Take to Cart"));
  });
  it("opens details at the top and restores panel scroll and focus on close", () => {
    mount();
    const content = host.querySelector<HTMLElement>(".reimagined-panel-content")!;
    content.scrollTop = 147;
    click("Test open details");
    expect(content.scrollTop).toBe(0);
    expect(document.activeElement).toBe(button("Test close details"));
    click("Test close details");
    expect(content.scrollTop).toBe(147);
    expect(document.activeElement).toBe(button("Test open details"));
  });
  it("mounts inert bundled Grocery and Café scenery for their own service states", () => {
    mount();
    const environment = host.querySelector(".reimagined-environment")!;
    expect(environment.getAttribute("aria-hidden")).toBe("true");
    expect(environment.querySelector('[data-environment-study="grocery-realtime-v1"]')).not.toBeNull();
    expect(environment.querySelectorAll("button, a, input, image, foreignObject")).toHaveLength(0);
    expect(environment.querySelector("canvas")).not.toBeNull();
    expect(environment.querySelector("img")).toBeNull();
    expect(environment.querySelector(".grocery-room-3d")?.getAttribute("data-status")).toContain("shopping remains available");
    click("Food");
    expect(environment.querySelector('[data-environment-study="grocery-realtime-v1"]')).toBeNull();
    expect(environment.querySelector('[data-environment-study="cafe-interior-v1"]')).not.toBeNull();
    expect(environment.querySelector("canvas")).not.toBeNull();
    click("Test sign out");
    expect(environment.querySelector(".grocery-room-3d")).toBeNull();
    expect(environment.querySelector(".room-storefront")).not.toBeNull();
  });
  it("focuses new main content for service/navigation/session changes", () => {
    mount(); click("Open search"); click("Food");
    expect(document.activeElement).toBe(host.querySelector("main"));
    click("Orders"); expect(document.activeElement).toBe(host.querySelector("main"));
    click("Home"); click("Test sign out");
    expect(document.activeElement).toBe(host.querySelector("main"));
    expect(host.querySelector(".reimagined-auth")).not.toBeNull();
  });
  it("falls back to main for a missing suggestion and never restores a removed search button", () => {
    mount(); click("Open search"); click("Test missing suggestion");
    expect(host.querySelector(".reimagined-search")).toBeNull();
    expect(document.activeElement).toBe(host.querySelector("main"));
    act(() => button("Test add").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })));
    expect(document.activeElement).toBe(host.querySelector("main"));
  });
  it("restores search and location focus after Escape from their close controls", () => {
    mount(); click("Open search");
    expect(document.activeElement).toBe(host.querySelector("input"));
    const closeSearch = button("Close search");
    act(() => { closeSearch.focus(); closeSearch.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })); });
    expect(host.querySelector("input")).toBeNull();
    expect(document.activeElement).toBe(button("Open search"));
    click("DELIVERING TOChoose location");
    expect(document.activeElement).toBe(button("Close location"));
    act(() => button("Close location").dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })));
    expect(document.activeElement).toBe(button("DELIVERING TOChoose location"));
    expect(host.querySelector(".reimagined-location-panel")).toBeNull();
  });
  it("preserves the 3D canvas across camera changes without delaying shopping or remounting content", () => {
    mount();
    const originalRoom = host.querySelector(".grocery-room-canvas");
    const content = host.querySelector("output");
    click("Take a Bucket"); click("Test add");
    expect(host.querySelector(".grocery-room-canvas")).toBe(originalRoom);
    click("Take to Cart");
    expect(host.querySelector(".grocery-room-canvas")).toBe(originalRoom);
    expect(host.querySelector("output")).toBe(content);
    expect(host.querySelector(".reimagined")?.getAttribute("data-scene")).toBe("groceryCounter");
    click("Continue Shopping");
    expect(host.querySelector(".reimagined-shopping-strip")?.textContent).toContain("2 items");
    click("Food");
    expect(host.querySelector("output")).toBe(content);
    expect(host.querySelector(".reimagined")?.getAttribute("data-scene")).toBe("foodEntrance");
  });
  it("uses ordered canonical keys and rejects ambiguous maps", () => {
    expect(reimaginedDirectory(map)[0].destinations.map(node => node.key)).toEqual(["atta", "masalas"]);
    expect(reimaginedDirectory({ version: 1, nodes: [...map.nodes, map.nodes[1]] })).toEqual([]);
    expect(reimaginedDirectory(null)).toEqual([]);
  });
  it("keeps department headings inert and the selected directory visible", () => {
    mount(); click("Masalas");
    expect(host.querySelector("output")?.textContent).toContain('"nodeKey":"masalas"');
    expect(button("Masalas").getAttribute("aria-pressed")).toBe("true");
    expect(host.querySelector(".reimagined-directory")).not.toBeNull();
    expect(host.querySelector("h3")?.textContent).toBe("Grocery & Kitchen");
    act(() => host.querySelector<HTMLElement>(".reimagined-environment")!.click());
    expect(button("Masalas").getAttribute("aria-pressed")).toBe("true");
    expect(button("Parcel, coming soon").disabled).toBe(true);
    expect(button("Print, coming soon").disabled).toBe(true);
  });
  it("does not replace main content while typing; explicit submit does", () => {
    mount(); click("Masalas"); click("Open search");
    const input = host.querySelector("input")!;
    act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "milk"); input.dispatchEvent(new Event("input", { bubbles: true })); });
    expect(host.querySelector("output")?.textContent).toContain('"nodeKey":"masalas"');
    act(() => host.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })));
    expect(host.querySelector("output")?.textContent).toContain('"query":"milk"');
    expect(host.querySelector("input")).toBeNull();
  });
  it("gates additions on the Bucket and separates shopping from active orders", () => {
    mount(); click("Test add"); expect(host.textContent).toContain("Take a bucket first");
    expect(host.querySelector(".reimagined-shopping-strip")).toBeNull();
    click("Take a Bucket"); click("Test add"); click("Test order");
    expect(host.querySelector(".reimagined-shopping-strip")?.textContent).toContain("2 items");
    expect(host.querySelector(".reimagined-order-strip")).not.toBeNull();
    click("Take to Cart"); expect(host.querySelector(".reimagined")?.getAttribute("data-scene")).toBe("groceryCounter");
    click("Continue Shopping"); expect(host.querySelector(".reimagined-shopping-strip")?.textContent).toContain("2 items");
    click("Food"); expect(host.querySelector(".reimagined-shopping-strip")).toBeNull();
    expect(host.querySelector(".reimagined-order-strip")).not.toBeNull();
    click("Grocery"); expect(host.querySelector(".reimagined-shopping-strip")?.textContent).toContain("2 items");
  });
  it("opens and explicitly closes location and forwards sign-in", () => {
    mount(true); expect(host.querySelector(".reimagined")?.getAttribute("data-scene")).toBe("outside");
    click("Continue with Apple"); expect(host.querySelector(".reimagined")?.getAttribute("data-scene")).toBe("groceryEntrance");
    click("DELIVERING TOChoose location"); expect(host.textContent).toContain("Address picker");
    act(() => host.querySelector<HTMLElement>(".reimagined-environment")!.click()); expect(host.textContent).toContain("Address picker");
    click("Close location"); expect(host.textContent).not.toContain("Address picker");
  });
});
