import { describe, expect, it } from "vitest";
import { adjacentProductId, merchantStockAction, productPickerPose, productSwipeStep, productUnitPrice, sameProductFamily, type DetailProduct } from "./productDetail";

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

describe("product card navigation", () => {
  it("keeps the selected picker circle centered and curves neighbours symmetrically during a swipe", () => {
    expect(productPickerPose(0)).toEqual({ scale: 1, opacity: 1, rotation: 0, drop: 0 });
    const left = productPickerPose(-1.5); const right = productPickerPose(1.5);
    expect(left.scale).toBe(right.scale);
    expect(left.opacity).toBe(right.opacity);
    expect(left.drop).toBe(right.drop);
    expect(left.rotation).toBe(-right.rotation);
    expect(left.scale).toBeLessThan(1);
    expect(left.drop).toBeGreaterThan(0);
  });
  it("only accepts intentional horizontal swipes", () => {
    expect(productSwipeStep(-80, 10)).toBe(1);
    expect(productSwipeStep(80, 10)).toBe(-1);
    expect(productSwipeStep(-40, 0)).toBeUndefined();
    expect(productSwipeStep(-80, 65)).toBeUndefined();
    expect(productSwipeStep(0, 120)).toBeUndefined();
  });
  it("stops at the ends and keeps the same order as the product picker", () => {
    const products = [{ id: "a" }, { id: "b" }, { id: "c" }];
    expect(adjacentProductId(products, "b", 1)).toBe("c");
    expect(adjacentProductId(products, "b", -1)).toBe("a");
    expect(adjacentProductId(products, "a", -1)).toBeUndefined();
    expect(adjacentProductId(products, "c", 1)).toBeUndefined();
    expect(adjacentProductId(products, "missing", 1)).toBeUndefined();
  });
});

const stock = { text: "20", currentQuantity: 20, reserved: 3, selected: true, addingEmptySKU: false, stale: false, busy: false, active: true };
describe("merchant product stock actions", () => {
  it("offers Add and locks stock for unselected SKUs", () => {
    expect(merchantStockAction({ ...stock, selected: false, text: "" })).toMatchObject({ title: "Add", canSubmit: true, canEdit: false });
  });
  it("only enables Save Stock for a changed numeric count", () => {
    expect(merchantStockAction(stock)).toMatchObject({ title: "Save Stock", canEdit: true, canSubmit: false });
    expect(merchantStockAction({ ...stock, text: "21" }).canSubmit).toBe(true);
    expect(merchantStockAction({ ...stock, text: "020" }).canSubmit).toBe(false);
    expect(merchantStockAction({ ...stock, text: "0" }).canSubmit).toBe(true);
    expect(merchantStockAction({ ...stock, currentQuantity: 21, text: "21" }).canSubmit).toBe(false);
  });
  it("supports an initial count after Add without inventing stock", () => {
    expect(merchantStockAction({ ...stock, currentQuantity: undefined, text: "" }).canSubmit).toBe(false);
    expect(merchantStockAction({ ...stock, currentQuantity: undefined, text: "0" }).canSubmit).toBe(true);
  });
  it("requires a positive count when re-adding an empty SKU", () => {
    const empty = { ...stock, selected: false, currentQuantity: 0, text: "0", addingEmptySKU: true };
    expect(merchantStockAction(empty)).toMatchObject({ title: "Save Stock", canEdit: true, canSubmit: false });
    expect(merchantStockAction({ ...empty, text: "1" }).canSubmit).toBe(true);
  });
  it.each(["", " ", "-1", "1.5", "1e3", "NaN", "1000000", "9999999999999999999"])("rejects invalid or over-capacity stock %s", (text) => {
    expect(merchantStockAction({ ...stock, text }).canSubmit).toBe(false);
  });
  it("blocks stale, busy and inactive submissions including Add", () => {
    for (const blocked of [{ stale: true }, { busy: true }, { active: false }]) {
      expect(merchantStockAction({ ...stock, text: "21", ...blocked }).canSubmit).toBe(false);
      expect(merchantStockAction({ ...stock, selected: false, ...blocked }).canSubmit).toBe(false);
      expect(merchantStockAction({ ...stock, ...blocked }).canEdit).toBe(false);
    }
  });
});
