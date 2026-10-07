import { describe, expect, it } from "vitest";
import { browseChildren, browseSkuIds, validateBrowseMap, type BrowseTaxonomy } from "./catalogueBrowse";
import type { V1CatalogueBrowseMap } from "./dastakV1";

const source = (typeSlug: string, categorySlug: string | null, subcategorySlug: string | null, excludedSubcategorySlugs: string[] = []) =>
  ({ typeSlug, categorySlug, subcategorySlug, excludedCategorySlugs: [], excludedSubcategorySlugs });
const map: V1CatalogueBrowseMap = { version: 1, nodes: [
  { key: "grocery", parentKey: null, kind: "SECTION", label: "Grocery", sortOrder: 1, sources: [] },
  { key: "flour-dal", parentKey: "grocery", kind: "DESTINATION", label: "Atta, Flour & Dal", sortOrder: 1, sources: [source("staples", null, null)] },
  { key: "rice", parentKey: "flour-dal", kind: "RAIL", label: "Rice", sortOrder: 2, sources: [source("staples", "rice", null, ["basmati", "poha"])] },
  { key: "basmati", parentKey: "flour-dal", kind: "RAIL", label: "Basmati Rice", sortOrder: 1, sources: [source("staples", "rice", "basmati")] },
  { key: "ready-mix", parentKey: "flour-dal", kind: "RAIL", label: "Ready Mix", sortOrder: 3, sources: [source("frozen", "ready", "flour-mix")] },
] };
const taxonomy: BrowseTaxonomy = {
  types: [{ id: "staples-id", slug: "staples" }, { id: "frozen-id", slug: "frozen" }],
  categories: [{ id: "rice-id", typeId: "staples-id", slug: "rice" }, { id: "ready-id", typeId: "frozen-id", slug: "ready" }],
  subcategories: [
    { id: "plain-id", categoryId: "rice-id", slug: "plain" },
    { id: "basmati-id", categoryId: "rice-id", slug: "basmati" },
    { id: "poha-id", categoryId: "rice-id", slug: "poha" },
    { id: "mix-id", categoryId: "ready-id", slug: "flour-mix" },
  ],
};
const skus = [
  { id: "plain", categoryId: "rice-id", subcategoryId: "plain-id" },
  { id: "basmati", categoryId: "rice-id", subcategoryId: "basmati-id" },
  { id: "poha", categoryId: "rice-id", subcategoryId: "poha-id" },
  { id: "mix", categoryId: "ready-id", subcategoryId: "mix-id" },
];

describe("reference browse map", () => {
  it("sorts only direct children", () => {
    expect(browseChildren(map, "flour-dal").map((node) => node.key)).toEqual(["basmati", "rice", "ready-mix"]);
  });
  it("keeps Rice, Basmati and Poha separate", () => {
    expect([...browseSkuIds(map, "rice", taxonomy, skus)]).toEqual(["plain"]);
    expect([...browseSkuIds(map, "basmati", taxonomy, skus)]).toEqual(["basmati"]);
  });
  it("can place a SKU from another canonical department in the right reference rail", () => {
    expect([...browseSkuIds(map, "ready-mix", taxonomy, skus)]).toEqual(["mix"]);
  });
  it("rejects an invalid or ambiguous tree and does not guess", () => {
    const broken = { ...map, nodes: [...map.nodes, { ...map.nodes[2] }] };
    expect(validateBrowseMap(broken)).toContain("Duplicate browse key: rice");
    expect(browseSkuIds(broken, "rice", taxonomy, skus).size).toBe(0);
    expect(browseSkuIds(map, "missing", taxonomy, skus).size).toBe(0);
    expect(validateBrowseMap({ version: 1, nodes: [] })).toContain("Browse map has no nodes");
  });
});
