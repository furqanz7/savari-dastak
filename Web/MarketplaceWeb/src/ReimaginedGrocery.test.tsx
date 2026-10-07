// @vitest-environment jsdom
import { act, useReducer } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it } from "vitest";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { fixtureId, groceryFixture as data } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
function Harness({ unavailable = false, home = false, preview = false, catalogue = data, related = [fixtureId(6), fixtureId(7)], searchQuery }: { unavailable?: boolean; home?: boolean; preview?: boolean; catalogue?: typeof data; related?: string[] | null; searchQuery?: string }) {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => {
    const initial = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "test" });
    if (searchQuery) return reimaginedReducer(reimaginedReducer(initial, { type: "typeSearch", query: searchQuery }), { type: "submitSearch" });
    return home ? initial : reimaginedReducer(initial, { type: "openBrowseDestination", nodeKey: "atta-flour-dal" });
  });
  return <><button onClick={() => dispatch({ type: "takeBucket" })}>Take Bucket</button><button onClick={() => dispatch({ type: "openSearch" })}>Search</button>
    <button onClick={() => dispatch({ type: "navigate", section: "home" })}>Home</button>
    <button onClick={() => dispatch({ type: "reviewShopping" })}>Review Bucket</button>
    <button onClick={() => dispatch({ type: "continueShopping" })}>Continue Shopping</button>
    <output data-testid="state">{JSON.stringify(state)}</output>
    <ReimaginedGrocery state={state} dispatch={dispatch} data={catalogue} status="ready" onRetry={() => undefined} supabaseUrl="https://example.supabase.co" trending={preview ? { city: "Preview city", skuIds: [fixtureId(7), "unknown", fixtureId(7), fixtureId(6)], preview: true } : undefined} eligibility={sku => ({ canAdd: !(unavailable && sku.id === fixtureId(7)), maximumQuantity: 2, reason: unavailable && sku.id === fixtureId(7) ? "Temporarily unavailable" : undefined })} relatedSkuIds={related ? () => related : undefined} checkoutContent="Checkout slot" />
    {state.exploration.grocery.searchOpen ? <ReimaginedGrocerySuggestions data={data} query="basmati" dispatch={dispatch} /> : null}</>;
}
function mount(unavailable = false, home = false, preview = false) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness unavailable={unavailable} home={home} preview={preview} />)); }
function button(label: string) { const found = Array.from(host.querySelectorAll("button")).find(item => (item.getAttribute("aria-label") ?? item.textContent?.trim()) === label); if (!found) throw new Error(label); return found; }
function click(label: string) { act(() => button(label).click()); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Reimagined Grocery interactions", () => {
  it("removes browser controls and shows the exact-product unavailable state if its SKU disappears", () => {
    mount(); click("View Test Plain Rice, 1 kg details");
    act(() => root.render(<Harness catalogue={{ ...data, catalogue: { ...data.catalogue, skus: [] } }} />));
    expect(host.textContent).toContain("This exact product is no longer in the loaded catalogue");
    expect(host.querySelector('.reimagined-product-browser')).toBeNull();
    click("Back to shelves"); expect(host.querySelector('.reimagined-grocery-browse')?.hasAttribute('hidden')).toBe(false);
  });
  it("limits detail paging to search products while retaining every size in the matching family", () => {
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const rice = { ...data.catalogue.skus[0], brand: { id: fixtureId(30), name: "Test", slug: "test" } };
    const large = { ...rice, id: fixtureId(31), packSize: "5 kg" };
    act(() => root.render(<Harness searchQuery="5 kg" related={null} catalogue={{ ...data, catalogue: { ...data.catalogue, skus: [rice, large, data.catalogue.skus[1]] } }} />));
    click("View Test Plain Rice, 5 kg details");
    expect(host.textContent).toContain("Product 1 of 1");
    expect(button("Next product").disabled).toBe(true);
    expect(host.querySelectorAll('.reimagined-detail-packs button')).toHaveLength(2);
    click("Test Plain Rice · 1 kg");
    expect(host.textContent).toContain("Product 1 of 1");
    expect(host.querySelector('.reimagined-product-orbit')).toBeNull();
  });
  it("browses products without adding or replacing exact pack lines and restores shelf position", () => {
    mount();
    const rice = { ...data.catalogue.skus[0], brand: { id: fixtureId(30), name: "Test", slug: "test" } };
    const large = { ...rice, id: fixtureId(31), packSize: "5 kg" };
    act(() => root.render(<Harness related={null} catalogue={{ ...data, catalogue: { ...data.catalogue, skus: [rice, large, data.catalogue.skus[1]] } }} />));
    click("Take Bucket"); click("Add Test Plain Rice, 1 kg");
    const track = host.querySelector<HTMLElement>('.reimagined-shelf-track')!; track.scrollLeft = 77;
    click("View Test Plain Rice, 1 kg details"); click("Test Plain Rice · 5 kg");
    click("Add Test Plain Rice, 5 kg"); click("Next product");
    expect(host.querySelector('.reimagined-product-detail h2')?.textContent).toBe("Test Basmati Rice");
    click("Previous product"); expect(button("Test Plain Rice · 5 kg").getAttribute("aria-pressed")).toBe("true");
    expect(host.querySelector('output[data-testid="state"]')?.textContent).toContain(`"${rice.id}":1`);
    expect(host.querySelector('output[data-testid="state"]')?.textContent).toContain(`"${large.id}":1`);
    click("Close product details"); expect(track.scrollLeft).toBe(77);
  });
  it("uses the same genuine pack family in shelves and details without crossing taxonomy boundaries", () => {
    mount();
    const rice = { ...data.catalogue.skus[0], brand: { id: fixtureId(30), name: "Test", slug: "test" } };
    const large = { ...rice, id: fixtureId(31), packSize: "5 kg" };
    const unrelated = { ...large, id: fixtureId(32), subcategoryId: fixtureId(4), packSize: "10 kg" };
    act(() => root.render(<Harness related={null} catalogue={{ ...data, catalogue: { ...data.catalogue, skus: [rice, large, unrelated] } }} />));
    click("View Test Plain Rice, 1 kg details");
    expect(host.querySelectorAll('.reimagined-detail-packs button')).toHaveLength(2);
    expect(host.querySelector('.reimagined-detail-packs')?.textContent).not.toContain("10 kg");
  });
  it("shows one card per product and switches price, image, add and quantity to the exact selected pack", () => {
    mount();
    const rice = { ...data.catalogue.skus[0], brand: { id: fixtureId(30), name: "Test brand", slug: "test-brand" }, imageKey: "sku-images/small.jpg" };
    const large = { ...rice, id: fixtureId(31), packSize: "5 kg", sellingPricePaise: 42000, listPricePaise: 50000, imageKey: "sku-images/large.jpg" };
    const catalogue = { ...data, catalogue: { ...data.catalogue, skus: [rice, large] } };
    act(() => root.render(<Harness catalogue={catalogue} related={[rice.id, large.id]} />));
    expect(host.querySelectorAll(".reimagined-shelf-product")).toHaveLength(1);
    expect(host.textContent).toContain("1 product");
    expect(host.textContent).toContain("2 pack sizes");
    click("Take Bucket"); click("Add Test Plain Rice, 1 kg");
    const picker = host.querySelector<HTMLSelectElement>(".reimagined-shelf-packs select")!;
    act(() => { picker.value = large.id; picker.dispatchEvent(new Event("change", { bubbles: true })); });
    expect(host.querySelector(".reimagined-shelf-product")?.getAttribute("data-sku-id")).toBe(large.id);
    expect(host.querySelector<HTMLImageElement>(".reimagined-grocery-shelf img")?.src).toContain("large.jpg");
    expect(host.querySelector(".reimagined-sku-price strong")?.textContent).toBe("₹420.00");
    expect(host.querySelector(".reimagined-product-saving")?.textContent).toBe("16% off");
    click("Add Test Plain Rice, 5 kg"); click("Add one Test Plain Rice, 5 kg");
    expect(button("Add one Test Plain Rice, 5 kg").disabled).toBe(true);
    expect(host.querySelector("output")?.textContent).toContain(`"${rice.id}":1`);
    expect(host.querySelector("output")?.textContent).toContain(`"${large.id}":2`);
    click("View Test Plain Rice, 5 kg details"); click("Close product details");
    expect(picker.value).toBe(large.id);
  });
  it("keeps unavailable packs selectable without enabling their addition or discarding other packs", () => {
    mount();
    const rice = { ...data.catalogue.skus[0], brand: { id: fixtureId(30), name: "Test", slug: "test" } };
    const large = { ...rice, id: fixtureId(7), packSize: "5 kg" };
    act(() => root.render(<Harness unavailable catalogue={{ ...data, catalogue: { ...data.catalogue, skus: [rice, large] } }} />));
    const picker = host.querySelector<HTMLSelectElement>("select")!;
    act(() => { picker.value = large.id; picker.dispatchEvent(new Event("change", { bubbles: true })); });
    expect(button("Add Test Plain Rice, 5 kg").disabled).toBe(true);
    expect(picker.options).toHaveLength(2);
  });
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
