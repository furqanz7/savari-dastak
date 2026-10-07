import { describe, expect, it, vi } from "vitest";
import { groceryQuickPicks, groceryShelves, loadReimaginedCatalogue, searchGrocery } from "./reimaginedCatalogue";
import { fixtureId, groceryFixture as data } from "./reimaginedCatalogue.testFixtures";
import { parseReimaginedCatalogueImport } from "./reimaginedCatalogueImport";

const auth = { supabaseUrl: "https://example.supabase.co", publishableKey: "test-key", accessToken: "test-token" };
const clients = () => ({ getV1CatalogueBrowseMap: vi.fn().mockResolvedValue(data.map), getV1Catalogue: vi.fn().mockResolvedValue(data.catalogue) });
describe("Reimagined canonical Grocery projection", () => {
  it("builds populated canonical shortcuts and refuses rails from another destination", () => {
    expect(groceryQuickPicks(data).map(pick => pick.key)).toEqual(["rice", "basmati", "poha"]);
    expect(groceryQuickPicks({ ...data, catalogue: { ...data.catalogue, skus: [data.catalogue.skus[1]] } }).map(pick => pick.key)).toEqual(["basmati"]);
    expect(groceryShelves(data, { kind: "browse", nodeKey: "atta-flour-dal", railKey: "basmati" })[0].skus.map(sku => sku.id)).toEqual([fixtureId(7)]);
    expect(groceryShelves(data, { kind: "browse", nodeKey: "atta-flour-dal", railKey: "missing" })).toEqual([]);
    const otherRail = { ...data.map.nodes[2], key: "other-rice", parentKey: "other-destination" };
    const otherDestination = { ...data.map.nodes[1], key: "other-destination" };
    expect(groceryShelves({ ...data, map: { ...data.map, nodes: [...data.map.nodes, otherDestination, otherRail] } }, { kind: "browse", nodeKey: "atta-flour-dal", railKey: "other-rice" })).toEqual([]);
  });
  it("keeps Rice, Basmati and Poha separate without family grouping", () => {
    const shelves = groceryShelves(data, { kind: "browse", nodeKey: "atta-flour-dal" });
    expect(shelves.map(shelf => [shelf.label, shelf.skus.map(sku => sku.id)])).toEqual([["Rice", [fixtureId(6)]], ["Basmati Rice", [fixtureId(7)]], ["Poha & Puffed Rice", [fixtureId(8)]]]);
  });
  it("does not guess unknown destinations or malformed maps", () => {
    expect(groceryShelves(data, { kind: "browse", nodeKey: "salt" })).toEqual([]);
    expect(groceryShelves({ ...data, map: { ...data.map, nodes: [...data.map.nodes, data.map.nodes[0]] } }, { kind: "home" })).toEqual([]);
  });
  it("searches known SKUs regardless of purchase availability", () => {
    expect(searchGrocery(data, "Basmati 1 kg").map(sku => sku.id)).toEqual([fixtureId(7)]);
    expect(searchGrocery(data, "")).toEqual([]);
    expect(groceryShelves(data, { kind: "search", query: "poha" })[0].skus.map(sku => sku.id)).toEqual([fixtureId(8)]);
  });
  it("shows a genuinely empty canonical rail", () => {
    expect(groceryShelves({ ...data, catalogue: { ...data.catalogue, skus: [] } }, { kind: "browse", nodeKey: "atta-flour-dal" })).toHaveLength(3);
  });
  it("loads every page with exact-ID deduplication and the existing auth contract", async () => {
    const api = clients();
    const nextCursor = { name: "Test Plain Rice", skuId: fixtureId(6) };
    api.getV1Catalogue.mockResolvedValueOnce({ ...data.catalogue, skus: [data.catalogue.skus[0]], nextCursor }).mockResolvedValueOnce({ ...data.catalogue, skus: data.catalogue.skus });
    const result = await loadReimaginedCatalogue(auth, new AbortController().signal, api);
    expect(result.catalogue.skus).toHaveLength(3);
    expect(result.catalogue.nextCursor).toBeUndefined();
    expect(api.getV1Catalogue.mock.calls[1][0]).toMatchObject({ ...auth, cursor: nextCursor });
  });
  it("rejects cursor loops, unavailable maps and catalogue version drift", async () => {
    const api = clients();
    api.getV1Catalogue.mockResolvedValue({ ...data.catalogue, nextCursor: { name: "loop", skuId: fixtureId(6) } });
    await expect(loadReimaginedCatalogue(auth, new AbortController().signal, api)).rejects.toThrow("completely");
    api.getV1Catalogue.mockResolvedValueOnce({ ...data.catalogue, nextCursor: { name: "first", skuId: fixtureId(6) } }).mockResolvedValueOnce({ ...data.catalogue, catalogueVersion: "changed" });
    await expect(loadReimaginedCatalogue(auth, new AbortController().signal, api)).rejects.toThrow("changed");
    api.getV1CatalogueBrowseMap.mockResolvedValue(null);
    await expect(loadReimaginedCatalogue(auth, new AbortController().signal, api)).rejects.toThrow("directory");
  });
  it("rejects aborted responses", async () => {
    const controller = new AbortController(); controller.abort();
    await expect(loadReimaginedCatalogue(auth, controller.signal, clients())).rejects.toMatchObject({ name: "AbortError" });
  });
  it("imports only complete and unambiguous real response bundles", () => {
    expect(parseReimaginedCatalogueImport(data).catalogue.skus).toHaveLength(3);
    expect(() => parseReimaginedCatalogueImport({ ...data, catalogue: { ...data.catalogue, nextCursor: { name: "partial", skuId: fixtureId(6) } } })).toThrow("incomplete");
    expect(() => parseReimaginedCatalogueImport({ ...data, map: { ...data.map, nodes: [...data.map.nodes, data.map.nodes[0]] } })).toThrow("ambiguous");
  });
});
