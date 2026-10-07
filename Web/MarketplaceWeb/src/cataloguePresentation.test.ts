import { describe, expect, it } from "vitest";
import { CATALOGUE_NAVIGATION_VERSION, catalogueDepartmentName, catalogueHomeTiles, catalogueNavigationGroups, curatedCatalogueRails, resolveCatalogueRail, riceRailExcludedSubcategoryIds, validateCatalogueRails } from "./cataloguePresentation";

describe("catalogue presentation shared by customer, merchant and admin", () => {
  it("uses the requested storefront names without changing canonical slugs", () => {
    expect(catalogueDepartmentName("staples-pantry", "Staples & Pantry")).toBe("Atta, Flour & Dal");
    expect(catalogueDepartmentName("masala-cooking", "Masala & Cooking")).toBe("Masalas");
    expect(catalogueDepartmentName("fresh-produce", "Fresh Produce")).toBe("Fresh Produce");
  });

  it("keeps one deterministic navigation group order for all three apps", () => {
    const types = [
      { slug: "masala-cooking", name: "Masala & Cooking", sortOrder: 2, navigationSection: { key: "grocery", name: "Grocery & Kitchen", sortOrder: 10 } },
      { slug: "dairy-bread-eggs", name: "Dairy", sortOrder: 1, navigationSection: { key: "fresh", name: "Fresh Items", sortOrder: 0 } },
      { slug: "staples-pantry", name: "Staples", sortOrder: 1, navigationSection: { key: "grocery", name: "Grocery & Kitchen", sortOrder: 10 } },
    ];
    expect(catalogueNavigationGroups(types).map((group) => [group.key, group.types.map((type) => type.slug)])).toEqual([
      ["fresh", ["dairy-bread-eggs"]],
      ["grocery", ["staples-pantry", "masala-cooking"]],
    ]);
  });

  it("keeps dedicated Basmati and Poha buckets out of the broad Rice rail", () => {
    expect([...riceRailExcludedSubcategoryIds([
      { id: "a", slug: "basmati-rice" },
      { id: "b", slug: "poha-puffed-rice" },
      { id: "c", slug: "ponni-rice" },
    ])]).toEqual(["a", "b"]);
  });

  it("keeps every Masalas rail under one canonical department", () => {
    const rails = curatedCatalogueRails["masala-cooking"];
    expect(rails.map((rail) => rail.label)).toContain("Ready Masala");
    expect(rails.map((rail) => rail.label)).toContain("Herbs & Seasoning");
    expect(rails.every((rail) => rail.typeSlug === "masala-cooking")).toBe(true);
    expect(new Set(rails.map((rail) => rail.label)).size).toBe(rails.length);
  });

  it("resolves a rail only through its declared parent path", () => {
    const target = curatedCatalogueRails["masala-cooking"].find((item) => item.label === "Sugar and Jaggery")!;
    const types = [
      { id: "masalas", slug: "masala-cooking" },
      { id: "other", slug: "another-department" },
    ];
    const categories = [
      { id: "correct", categoryTypeId: "masalas", slug: "sugar-sweeteners" },
      { id: "wrong", categoryTypeId: "other", slug: "sugar-sweeteners" },
    ];
    expect(CATALOGUE_NAVIGATION_VERSION).toBe(1);
    expect(resolveCatalogueRail(target, types, categories, [])?.id).toBe("correct");
    expect(resolveCatalogueRail(target, types.slice(1), categories, [])).toBeUndefined();
    expect(resolveCatalogueRail(target, [...types, { id: "duplicate", slug: "masala-cooking" }], categories, [])).toBeUndefined();
    expect(validateCatalogueRails(types.slice(1), categories, []).some((issue) => issue.includes("Sugar and Jaggery"))).toBe(true);
  });

  it("places grocery shortcuts under the correct canonical type", () => {
    const types = [
      { id: "staples", slug: "staples-pantry", name: "Staples" },
      { id: "masalas", slug: "masala-cooking", name: "Masalas" },
      { id: "oils", slug: "oils-ghee", name: "Oils and Ghee" },
      { id: "breakfast", slug: "breakfast-spreads", name: "Breakfast" },
    ];
    const categories = [{ id: "oil", categoryTypeId: "oils", slug: "cooking-oils", name: "Cooking Oils" }];
    expect(catalogueHomeTiles("grocery-kitchen", types.slice(0, 3), types, categories).map(({ label, typeId, categoryId }) => [label, typeId, categoryId])).toEqual([
      ["Atta, Flour & Dal", "staples", undefined],
      ["Masalas", "masalas", undefined],
      ["Oils and Ghee", "oils", undefined],
      ["Cereals and Breakfast", "breakfast", undefined],
    ]);
    expect(catalogueHomeTiles("snacks-drinks", [types[3]], types, categories)).toEqual([]);
  });
});
