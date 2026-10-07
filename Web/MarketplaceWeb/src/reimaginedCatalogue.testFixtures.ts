import type { V1CatalogueSku } from "./dastakV1";
import type { ReimaginedCatalogue } from "./reimaginedCatalogue";

// Test-only identities and content. Never imported by production; local studies
// and browser fixtures must identify these as synthetic, not live inventory.
export const fixtureId = (number: number) => `00000000-0000-4000-8000-${String(number).padStart(12, "0")}`;
export function cartStorageFixture() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value); },
    clear: () => values.clear(),
    get length() { return values.size; },
  };
}
export function checkoutLocksFixture() {
  const held = new Set<string>();
  const waiting = new Map<string, Array<() => void>>();
  return {
    async request<T>(name: string, options: { ifAvailable?: boolean }, callback: (lock: object | null) => Promise<T>) {
      if (held.has(name) && options.ifAvailable) return callback(null);
      while (held.has(name)) await new Promise<void>(resolve => { waiting.set(name, [...(waiting.get(name) ?? []), resolve]); });
      held.add(name);
      try { return await callback({ name }); } finally { held.delete(name); waiting.get(name)?.shift()?.(); }
    },
  };
}
const category = { id: fixtureId(2), categoryTypeId: fixtureId(1), name: "Rice", slug: "rice", previewImageKeys: [], sortOrder: 1 };
const sku = (number: number, name: string, subcategory: number): V1CatalogueSku => ({ id: fixtureId(number), categoryId: category.id, subcategoryId: fixtureId(subcategory), name, slug: `test-${number}`, packSize: "1 kg", galleryImageKeys: [], attributes: {}, listPricePaise: 12000, sellingPricePaise: 10000, currencyCode: "INR", logisticsAttributes: {} });
const source = (subcategory: string | null, excluded: string[] = []) => ({ typeSlug: "staples", categorySlug: "rice", subcategorySlug: subcategory, excludedCategorySlugs: [], excludedSubcategorySlugs: excluded });
export const groceryFixture: ReimaginedCatalogue = {
  map: { version: 1, nodes: [
    { key: "kitchen", parentKey: null, kind: "SECTION", label: "Grocery & Kitchen", sortOrder: 1, sources: [] },
    { key: "atta-flour-dal", parentKey: "kitchen", kind: "DESTINATION", label: "Atta, Flour & Dal", sortOrder: 1, sources: [source(null)] },
    { key: "rice", parentKey: "atta-flour-dal", kind: "RAIL", label: "Rice", sortOrder: 1, sources: [source(null, ["basmati", "poha"])] },
    { key: "basmati", parentKey: "atta-flour-dal", kind: "RAIL", label: "Basmati Rice", sortOrder: 2, sources: [source("basmati")] },
    { key: "poha", parentKey: "atta-flour-dal", kind: "RAIL", label: "Poha & Puffed Rice", sortOrder: 3, sources: [source("poha")] },
  ] },
  catalogue: {
    catalogueVersion: "2026-09-30T00:00:00.000Z",
    categoryTypes: [{ id: fixtureId(1), name: "Staples", slug: "staples", previewImageKeys: [], sortOrder: 1 }],
    categories: [category],
    subcategories: ["plain", "basmati", "poha"].map((slug, index) => ({ id: fixtureId(index + 3), categoryId: category.id, name: slug, slug, previewImageKeys: [], sortOrder: index })),
    skus: [sku(6, "Test Plain Rice", 3), sku(7, "Test Basmati Rice", 4), sku(8, "Test Poha", 5)],
  },
};
