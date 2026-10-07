// @vitest-environment jsdom
import { act, useReducer } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it } from "vitest";
import { ReimaginedBucketReview } from "./ReimaginedBucketReview";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
function Harness({ retail = { [fixtureId(6)]: 2, [fixtureId(7)]: 1 }, canEdit = true, canIncrease = true, maximumQuantity = 99 }: { retail?: Record<string, number>; canEdit?: boolean; canIncrease?: boolean; maximumQuantity?: number }) {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => ({ ...initialReimaginedState(), accountId: "test", bucketAcquired: true, shopping: { retail, food: [] } }));
  const data = { ...groceryFixture, catalogue: { ...groceryFixture.catalogue, skus: groceryFixture.catalogue.skus.map(sku => sku.id === fixtureId(6) ? { ...sku, imageKey: "local/test-rice.png", variant: "White" } : sku) } };
  return <ReimaginedBucketReview state={state} dispatch={dispatch} data={data} canEdit={canEdit} canIncrease={canIncrease} maximumQuantity={maximumQuantity} />;
}
function mount(props: Parameters<typeof Harness>[0] = {}) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness {...props} />)); }
function button(label: string) { return host.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`)!; }
function click(label: string) { act(() => button(label).click()); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Grocery mobile cart review", () => {
  it("shows exact identity, unit price, line total, item counts and a complete subtotal", () => {
    mount();
    expect(host.textContent).toContain("3 items · 2 products");
    expect(host.textContent).toContain("White · 1 kg");
    expect(host.textContent).toContain("₹100.00 each");
    expect(host.querySelector('[aria-label="Test Plain Rice, 1 kg line total"]')?.textContent).toBe("₹200.00");
    expect(host.querySelector(".reimagined-review-subtotal")?.textContent).toBe("Estimated item subtotal: ₹300.00");
    const image = host.querySelector("img")!;
    expect(image.getAttribute("alt")).toBe("Test Plain Rice, 1 kg");
    expect(image.getAttribute("src")).toContain("test-rice.png");
    expect(host.textContent).toContain("final payable amount comes from checkout");
  });
  it("updates quantity, line totals, subtotal and full removal immediately", () => {
    mount(); click("Increase Test Basmati Rice, 1 kg in Bucket");
    expect(host.querySelector(".reimagined-review-subtotal")?.textContent).toContain("₹400.00");
    click("Decrease Test Plain Rice, 1 kg in Bucket");
    expect(host.querySelector('[aria-label="Test Plain Rice, 1 kg line total"]')?.textContent).toBe("₹100.00");
    click("Remove Test Basmati Rice from Bucket");
    expect(host.textContent).toContain("1 item · 1 product");
    expect(host.querySelector(".reimagined-review-subtotal")?.textContent).toContain("₹100.00");
  });
  it("retains unresolved products and refuses a partial subtotal", () => {
    mount({ retail: { missing: 2, [fixtureId(6)]: 1 } });
    expect(host.textContent).toContain("This item has been retained, not silently removed.");
    expect(host.querySelector(".reimagined-review-subtotal")).toBeNull();
    expect(button("Increase saved product in Bucket").disabled).toBe(true);
    click("Remove saved product from Bucket");
    expect(host.querySelector(".reimagined-review-subtotal")?.textContent).toContain("₹100.00");
  });
  it("honours read-only, offline and quantity-cap constraints", () => {
    mount({ canEdit: false });
    expect([...host.querySelectorAll<HTMLButtonElement>("button")].every(item => item.disabled)).toBe(true);
    act(() => root.render(<Harness canIncrease={false} />));
    expect(button("Increase Test Plain Rice, 1 kg in Bucket").disabled).toBe(true);
    expect(button("Decrease Test Plain Rice, 1 kg in Bucket").disabled).toBe(false);
    act(() => root.render(<Harness maximumQuantity={2} />));
    expect(button("Increase Test Plain Rice, 1 kg in Bucket").disabled).toBe(true);
    expect(button("Increase Test Basmati Rice, 1 kg in Bucket").disabled).toBe(false);
  });
  it("shows a truthful empty state after removal of the last product", () => {
    mount({ retail: { [fixtureId(6)]: 1 } }); click("Decrease Test Plain Rice, 1 kg in Bucket");
    expect(host.textContent).toContain("Your Grocery Bucket is empty");
    expect(host.querySelectorAll(".reimagined-review-line")).toHaveLength(0);
    expect(host.querySelector(".reimagined-review-subtotal")?.textContent).toContain("₹0.00");
  });
});
