import { describe, expect, it } from "vitest";
import { catalogueProductType, validProductType, withCatalogueProductType } from "./catalogueProductType";
describe("shared Product Type metadata", () => {
  it("reads only a valid dedicated value, never variant or name guesses", () => {
    expect(catalogueProductType({ productType: " Full Cream " })).toBe("Full Cream");
    for (const attributes of [{}, { variant: "Toned" }, { product_type: "Toned" }, { productType: 3 }, { productType: {} }, { productType: " " }, { productType: "a".repeat(101) }, { productType: "Toned\nMilk" }]) expect(catalogueProductType(attributes)).toBeUndefined();
  });
  it("preserves unrelated metadata, trims and clears only Product Type", () => {
    const original = { productType: "Toned", ingredients: ["Milk"], evidence: { reviewed: true } };
    expect(withCatalogueProductType(original, " Full Cream ")).toEqual({ ...original, productType: "Full Cream" });
    expect(withCatalogueProductType(original, " ")).toEqual({ ingredients: ["Milk"], evidence: { reviewed: true } });
    expect(original.productType).toBe("Toned");
    expect(validProductType("a".repeat(100))).toBe(true);
    expect(() => withCatalogueProductType(original, "a".repeat(101))).toThrow("100");
    expect(() => withCatalogueProductType(original, "Toned\tMilk")).toThrow("control");
  });
});
