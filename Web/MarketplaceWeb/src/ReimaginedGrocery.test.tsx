// @vitest-environment jsdom
import { act, useReducer } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it } from "vitest";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { fixtureId, groceryFixture as data } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
function Harness({ unavailable = false, home = false, preview = false, catalogue = data, related = [fixtureId(6), fixtureId(7)] }: { unavailable?: boolean; home?: boolean; preview?: boolean; catalogue?: typeof data; related?: string[] }) {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => {
    const initial = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "test" });
    return home ? initial : reimaginedReducer(initial, { type: "openBrowseDestination", nodeKey: "atta-flour-dal" });
  });
  return <><button onClick={() => dispatch({ type: "takeBucket" })}>Take Bucket</button><button onClick={() => dispatch({ type: "openSearch" })}>Search</button>
    <button onClick={() => dispatch({ type: "navigate", section: "home" })}>Home</button>
    <button onClick={() => dispatch({ type: "reviewShopping" })}>Review Bucket</button>
    <button onClick={() => dispatch({ type: "continueShopping" })}>Continue Shopping</button>
    <output data-testid="state">{JSON.stringify(state)}</output>
    <ReimaginedGrocery state={state} dispatch={dispatch} data={catalogue} status="ready" onRetry={() => undefined} supabaseUrl="https://example.supabase.co" trending={preview ? { city: "Preview city", skuIds: [fixtureId(7), "unknown", fixtureId(7), fixtureId(6)], preview: true } : undefined} eligibility={sku => ({ canAdd: !(unavailable && sku.id === fixtureId(7)), maximumQuantity: 2, reason: unavailable && sku.id === fixtureId(7) ? "Temporarily unavailable" : undefined })} relatedSkuIds={() => related} checkoutContent="Checkout slot" />
    {state.exploration.grocery.searchOpen ? <ReimaginedGrocerySuggestions data={data} query="basmati" dispatch={dispatch} /> : null}</>;
}
function mount(unavailable = false, home = false, preview = false) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness unavailable={unavailable} home={home} preview={preview} />)); }
function button(label: string) { const found = Array.from(host.querySelectorAll("button")).find(item => (item.getAttribute("aria-label") ?? item.textContent?.trim()) === label); if (!found) throw new Error(label); return found; }
function click(label: string) { act(() => button(label).click()); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Reimagined Grocery interactions", () => {
  it("retains shelf tracks and horizontal position through cart review", () => {
    mount(); click("Take Bucket"); click("Add Test Plain Rice, 1 kg");
    const track = host.querySelector<HTMLElement>(".reimagined-shelf-track")!;
    track.scrollLeft = 91;
    click("Review Bucket");
    expect(host.querySelector(".reimagined-grocery-browse")?.hasAttribute("inert")).toBe(true);
    expect(host.textContent).toContain("Checkout slot");
    click("Continue Shopping");
    expect(host.querySelector(".reimagined-shelf-track")).toBe(track);
    expect(track.scrollLeft).toBe(91);
    expect(host.querySelector<HTMLElement>(".reimagined-grocery-browse")?.hidden).toBe(false);
  });
  it("opens a quick pick's exact rail and keeps the cart when returning Home", () => {
    mount(false, true);
    expect(host.textContent).toContain("Trending in your city");
    expect(host.querySelectorAll(".reimagined-shelf-product")).toHaveLength(0);
    click("Basmati Rice");
    expect(host.querySelectorAll(".reimagined-shelf-track")).toHaveLength(1);
    expect(host.querySelector(".reimagined-product-name")?.textContent).toBe("Test Basmati Rice");
    click("Take Bucket"); click("Add Test Basmati Rice, 1 kg"); click("Home");
    expect(host.querySelector("output")?.textContent).toContain(`"${fixtureId(7)}":1`);
    expect(host.querySelector(".reimagined-quick-picks")).not.toBeNull();
    expect(host.textContent).toContain("city favourites are unavailable");
  });
  it("labels sample rankings, resolves exact SKUs, and keeps eligibility on trending products", () => {
    mount(true, true, true);
    expect(host.textContent).toContain("Preview ranking");
    expect(Array.from(host.querySelectorAll(".reimagined-product-name")).map(item => item.textContent)).toEqual(["Test Basmati Rice", "Test Plain Rice"]);
    expect(button("Add Test Basmati Rice, 1 kg").disabled).toBe(true);
    click("Search");
    expect(host.querySelector(".reimagined-grocery-home")).not.toBeNull();
    click("View Test Plain Rice, 1 kg details");
    expect(host.querySelector(".reimagined-product-detail h2")?.textContent).toBe("Test Plain Rice");
    click("Close product details");
    expect(host.querySelector(".reimagined-grocery-home")).not.toBeNull();
  });
  it("renders horizontal shelves with exact SKU add and capped quantity controls", () => {
    mount(); expect(host.querySelectorAll(".reimagined-shelf-track")).toHaveLength(3);
    click("Add Test Plain Rice, 1 kg"); expect(host.querySelector("output")?.textContent).toContain('"bucketPrompt":true');
    click("Take Bucket"); click("Add Test Plain Rice, 1 kg"); click("Add one Test Plain Rice, 1 kg");
    expect(button("Add one Test Plain Rice, 1 kg").disabled).toBe(true);
    expect(host.querySelector("output")?.textContent).toContain(`"${fixtureId(6)}":2`);
    click("Remove one Test Plain Rice, 1 kg"); expect(host.querySelector("output")?.textContent).toContain(`"${fixtureId(6)}":1`);
  });
  it("keeps unavailable products visible but disables their additions", () => {
    mount(true); expect(host.textContent).toContain("Test Basmati Rice"); expect(button("Add Test Basmati Rice, 1 kg").disabled).toBe(true);
    expect(host.textContent).toContain("Temporarily unavailable");
  });
  it("opens exact detail and switches canonical SKU without changing existing lines", () => {
    mount(); click("Take Bucket"); click("Add Test Plain Rice, 1 kg"); click("View Test Plain Rice, 1 kg details");
    expect(host.querySelector(".reimagined-product-detail h2")?.textContent).toBe("Test Plain Rice");
    click("Test Basmati Rice · 1 kg"); click("Add Test Basmati Rice, 1 kg");
    const serialized = host.querySelector("output")?.textContent;
    expect(serialized).toContain(`"${fixtureId(6)}":1`); expect(serialized).toContain(`"${fixtureId(7)}":1`);
    click("Close product details"); expect(host.querySelectorAll(".reimagined-shelf-track")).toHaveLength(3);
  });
  it("suggestion selection opens exact detail and explicitly closes search", () => {
    mount(); click("Search"); click("Test Basmati Rice1 kg");
    expect(host.querySelector(".reimagined-product-detail h2")?.textContent).toBe("Test Basmati Rice");
    expect(host.querySelector(".reimagined-grocery-suggestions")).toBeNull();
  });
  it("shows a truthful fallback if exact product imagery fails", () => {
    mount(); expect(host.querySelectorAll('.reimagined-sku-image-fallback[data-fallback="true"]')).toHaveLength(3);
  });
  it("uses exact SKU imagery and resets a failed image when its source changes", () => {
    mount();
    const catalogue = (imageKey: string) => ({ ...data, catalogue: { ...data.catalogue, skus: data.catalogue.skus.map(sku => sku.id === fixtureId(6) ? { ...sku, imageKey } : sku) } });
    act(() => root.render(<Harness catalogue={catalogue("sku-images/plain rice.jpg")} />));
    const image = host.querySelector<HTMLImageElement>(".reimagined-grocery-shelf img")!;
    expect(image.alt).toBe("Test Plain Rice, 1 kg");
    expect(image.src).toContain("/dastak-catalogue/sku-images/plain%20rice.jpg");
    act(() => image.dispatchEvent(new Event("error")));
    expect(image.hidden).toBe(true);
    expect(image.parentElement?.getAttribute("data-image-unavailable")).toBe("true");
    act(() => root.render(<Harness catalogue={catalogue("sku-images/replacement.jpg")} />));
    const replacement = host.querySelector<HTMLImageElement>(".reimagined-grocery-shelf img")!;
    expect(replacement.src).toContain("/dastak-catalogue/sku-images/replacement.jpg");
    expect(replacement.hidden).toBe(false);
    expect(replacement.parentElement?.hasAttribute("data-image-unavailable")).toBe(false);
  });
  it("retains full long product names in accessible shelf controls and details", () => {
    mount();
    const name = "Test extra long product name for clear shelf labels and exact pack identity";
    const catalogue = { ...data, catalogue: { ...data.catalogue, skus: data.catalogue.skus.map(sku => sku.id === fixtureId(6) ? { ...sku, name } : sku) } };
    act(() => root.render(<Harness catalogue={catalogue} />));
    expect(button(`View ${name}, 1 kg details`).title).toBe(name);
    click(`View ${name}, 1 kg details`);
    expect(host.querySelector(".reimagined-product-detail h2")?.textContent).toBe(name);
  });
  it("retains inert shelf DOM and swipe position while opening and closing details", () => {
    mount();
    const track = host.querySelector<HTMLElement>(".reimagined-shelf-track")!;
    track.scrollLeft = 85;
    click("View Test Plain Rice, 1 kg details");
    expect(host.querySelector(".reimagined-shelf-track")).toBe(track);
    expect(host.querySelector<HTMLElement>(".reimagined-grocery-browse")?.hidden).toBe(true);
    expect(host.querySelector(".reimagined-grocery-browse")?.hasAttribute("inert")).toBe(true);
    click("Close product details");
    expect(host.querySelector(".reimagined-shelf-track")).toBe(track);
    expect(track.scrollLeft).toBe(85);
    expect(host.querySelector<HTMLElement>(".reimagined-grocery-browse")?.hidden).toBe(false);
  });
  it("deduplicates explicit variant IDs, ignores unknown IDs, and omits single-SKU choices", () => {
    mount();
    act(() => root.render(<Harness related={[fixtureId(7), fixtureId(7), "unknown"]} />));
    click("View Test Plain Rice, 1 kg details");
    expect(host.querySelectorAll(".reimagined-variants button")).toHaveLength(2);
    expect(button("Test Plain Rice · 1 kg").getAttribute("aria-pressed")).toBe("true");
    act(() => root.render(<Harness related={[fixtureId(6), "unknown"]} />));
    expect(host.querySelector(".reimagined-variants")).toBeNull();
  });
});
