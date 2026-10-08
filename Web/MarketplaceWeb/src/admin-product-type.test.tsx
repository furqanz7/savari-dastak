// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SkuEditor } from "./AdminCataloguePanel";
import type { V1AdminCataloguePageSku } from "./dastakV1";
import { groceryFixture } from "./reimaginedCatalogue.testFixtures";
vi.mock("./AdminCatalogueAssets", () => ({ AdminCatalogueAssets: () => null }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const sku: V1AdminCataloguePageSku = { ...groceryFixture.catalogue.skus[0],
  attributes: { productType: "White", ingredients: ["Rice"], verifiedSource: "fixture" },
  taxRateBps: 0, status: "ACTIVE", selectionCount: 0, version: 7, updatedAt: "2026-10-08T00:00:00Z",
  categoryName: "Grains", subcategoryName: "Rice", dietType: "VEG", qaStatus: "VERIFIED", activationReady: true,
  activationBlockers: [], imageCount: 1, aliasCount: 0, identifierCount: 0,
};
async function mount(disabled = false) {
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  const save = vi.fn().mockResolvedValue(undefined);
  await act(async () => root.render(<SkuEditor sku={sku} auth={{ accessToken: "test", supabaseUrl: "https://example.invalid", publishableKey: "public" }} supabaseUrl="https://example.invalid" disabled={disabled} onSave={save} onDelete={vi.fn()} onCatalogueChanged={vi.fn()} />));
  const input = [...host.querySelectorAll("label")].find(label => label.querySelector("span")?.textContent === "Product Type")!.querySelector("input")!;
  return { save, input };
}
async function enter(input: HTMLInputElement, value: string) {
  await act(async () => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value); input.dispatchEvent(new Event("input", { bubbles: true })); });
}
async function submit() { await act(async () => host.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Admin authoritative Product Type editor", () => {
  it("saves through the original versioned SKU review with unrelated attributes preserved", async () => {
    const { input, save } = await mount();
    expect(input.value).toBe("White"); expect(input.maxLength).toBe(100);
    expect(input.getAttribute("aria-describedby")).toBeTruthy();
    await enter(input, " Brown "); await submit();
    expect(save).toHaveBeenCalledWith(sku, expect.objectContaining({ attributes: { ...sku.attributes, productType: "Brown" }, name: sku.name, variant: null, status: "ACTIVE" }));
    expect(sku.version).toBe(7); expect(sku.attributes.productType).toBe("White");
  });
  it("clears only classification and does not send unchanged attributes on other edits", async () => {
    const { input, save } = await mount(); await enter(input, ""); await submit();
    expect(save.mock.calls[0][1].attributes).toEqual({ ingredients: ["Rice"], verifiedSource: "fixture" });
    await enter(input, "White");
    const name = [...host.querySelectorAll("label")].find(label => label.querySelector("span")?.textContent === "Product name")!.querySelector("input")!;
    await enter(name, "Reviewed Rice"); await submit();
    expect(save.mock.calls[1][1]).not.toHaveProperty("attributes");
  });
  it("rejects invalid classification and disables editing during a pending mutation", async () => {
    const { input, save } = await mount(true); expect(input.disabled).toBe(true);
    await enter(input, "a".repeat(101)); await submit(); expect(save).not.toHaveBeenCalled();
  });
});
