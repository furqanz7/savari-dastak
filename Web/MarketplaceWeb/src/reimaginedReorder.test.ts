import { describe, expect, it } from "vitest";
import { prepareReimaginedReorder } from "./reimaginedReorder";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import type { V1Order } from "./dastakV1";

describe("Reimagined reordering", () => {
  it("restores exact SKUs into Grocery review without touching Food", () => {
    const order = { lines: [{ lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity: 2 }] } as V1Order;
    const prepared = prepareReimaginedReorder(order, groceryFixture);
    const original = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "a", shopping: { retail: {}, food: [{ branchId: "b", itemId: "i", optionIds: [], quantity: 1 }] } });
    const next = reimaginedReducer(original, { type: "replaceServiceShopping", ...prepared });
    expect(next.shopping.retail).toEqual({ [fixtureId(6)]: 2 }); expect(next.shopping.food).toEqual(original.shopping.food);
    expect(next.bucketAcquired).toBe(true); expect(next.exploration.grocery.checkout).toBe(true);
  });
  it("retains exact Food options and the other Bucket", () => {
    const menu = foodMenuFixture(); const item = menu.categories[0].items[0]; const option = item.optionGroups[0].options[0];
    const order = { restaurant: menu.restaurant, lines: [{ id: "line", name: item.name, status: "SECURED", unitPricePaise: 18000, lineTotalPaise: 36000, lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, foodSelection: { options: [{ ...option, groupId: "size", groupName: "Size" }] } }] };
    const prepared = prepareReimaginedReorder(order, undefined, [menu]);
    expect(prepared.shopping.food).toEqual([{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [option.id], quantity: 2 }]);
    const original = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "a", shopping: { retail: { [fixtureId(6)]: 3 }, food: [] } });
    expect(reimaginedReducer(original, { type: "replaceServiceShopping", ...prepared }).shopping.retail).toEqual(original.shopping.retail);
    expect(() => prepareReimaginedReorder(order, undefined, [{ ...menu, restaurant: { ...menu.restaurant, isOpen: false } }])).toThrow("unavailable");
  });
  it("never substitutes unavailable items, invalid quantities or older mixed orders", () => {
    expect(() => prepareReimaginedReorder({ lines: [{ lineType: "RETAIL_SKU", skuId: fixtureId(999), quantity: 1 }] } as V1Order, groceryFixture)).toThrow("Nothing was replaced");
    expect(() => prepareReimaginedReorder({ lines: [{ lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity: 100 }] } as V1Order, groceryFixture)).toThrow("quantities");
    expect(() => prepareReimaginedReorder({ lines: [{ lineType: "RETAIL_SKU" }, { lineType: "FOOD_MENU_ITEM" }] } as V1Order, groceryFixture)).toThrow("mixed order");
  });
  it("splits an old mixed order by explicit service while preserving exact quantities and options", () => {
    const menu = foodMenuFixture(); const item = menu.categories[0].items[0]; const option = item.optionGroups[0].options[0];
    const order = { restaurant: menu.restaurant, lines: [
      { id: "retail", name: "Rice", status: "DELIVERED", unitPricePaise: 10000, lineTotalPaise: 20000, lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity: 2 },
      { id: "food", name: item.name, status: "DELIVERED", unitPricePaise: 18000, lineTotalPaise: 36000, lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, foodSelection: { options: [{ ...option, groupId: "size", groupName: "Size" }] } },
    ] };
    expect(prepareReimaginedReorder(order, groceryFixture, [menu], "grocery").shopping).toEqual({ retail: { [fixtureId(6)]: 2 }, food: [] });
    expect(prepareReimaginedReorder(order, groceryFixture, [menu], "food").shopping).toEqual({ retail: {}, food: [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [option.id], quantity: 2 }] });
    expect(() => prepareReimaginedReorder(order, groceryFixture, [], "food")).toThrow("unavailable");
    expect(prepareReimaginedReorder(order, groceryFixture, [], "grocery").shopping.retail).toEqual({ [fixtureId(6)]: 2 });
  });
});
