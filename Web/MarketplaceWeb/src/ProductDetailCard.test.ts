import { describe, expect, it } from "vitest";
import { productUnitPrice, sameProductFamily, type DetailProduct } from "./productDetail";

const milk: DetailProduct = { id: "milk", name: "Toned Milk", brand: "Dairy", packSize: "500 ml", galleryImageKeys: [], price: 2400, listPrice: 2400, quantityValue: 500, quantityUnit: "ml", packCount: 1 };
describe("product detail contracts", () => {
  it("calculates unit prices from the exact pack and count", () => {
    expect(productUnitPrice(milk)).toBe("₹4.80/100 ml");
    expect(productUnitPrice({ ...milk, price: 4800, packCount: 2 })).toBe("₹4.80/100 ml");
    expect(productUnitPrice({ ...milk, price: 4800, quantityValue: 1, quantityUnit: "l" })).toBe("₹4.80/100 ml");
  });
  it("does not fabricate unit prices without valid structured data", () => {
    expect(productUnitPrice({ ...milk, quantityValue: undefined })).toBeUndefined();
    expect(productUnitPrice({ ...milk, quantityUnit: "unit" })).toBeUndefined();
    expect(productUnitPrice({ ...milk, quantityValue: 0 })).toBeUndefined();
  });
  it("only groups genuine matching product packs", () => {
    expect(sameProductFamily(milk, { ...milk, id: "large", packSize: "1 l" })).toBe(true);
    expect(sameProductFamily(milk, { ...milk, id: "another-brand", brand: "Other" })).toBe(false);
    expect(sameProductFamily(milk, { ...milk, id: "other-milk", name: "Full Cream Milk" })).toBe(false);
    expect(sameProductFamily(milk, { ...milk, id: "flavoured", variant: "Chocolate" })).toBe(false);
  });
});
