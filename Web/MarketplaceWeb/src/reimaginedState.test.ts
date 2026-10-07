import { describe, expect, it } from "vitest";
import { initialReimaginedState, reimaginedEnvironment, reimaginedReducer as reduce, type ReimaginedState } from "./reimaginedState";

const foodLine = { branchId: "branch-1", itemId: "menu-item-1", optionIds: ["option-1"], quantity: 2 };
const signedIn = () => reduce(initialReimaginedState(), { type: "signedIn", accountId: "account-1" });
function withShopping(): ReimaginedState {
  let state = reduce(signedIn(), { type: "takeBucket" });
  state = reduce(state, { type: "setGroceryQuantity", skuId: "sku-1", quantity: 3 });
  state = reduce(state, { type: "selectService", service: "food" });
  return reduce(state, { type: "setFoodQuantity", line: foodLine });
}

describe("Dastak Reimagined customer contract", () => {
  it("keeps branch-scoped Food category intent across service switches and clears it on Home", () => {
    let state = withShopping(); const shopping = state.shopping;
    const filter = { label: "Meals", members: [{ branchId: "branch-1", categoryId: "category-1" }] };
    state = reduce(state, { type: "selectFoodCategory", filter });
    expect(state.exploration.food.foodCategoryFilter).toEqual(filter);
    filter.members[0].categoryId = "changed";
    expect(state.exploration.food.foodCategoryFilter?.members[0].categoryId).toBe("category-1");
    state = reduce(state, { type: "selectService", service: "grocery" });
    expect(reduce(state, { type: "selectFoodCategory" })).toBe(state);
    state = reduce(state, { type: "selectService", service: "food" });
    expect(state.exploration.food.foodCategoryFilter?.label).toBe("Meals");
    state = reduce(state, { type: "navigate", section: "home" });
    expect(state.exploration.food.foodCategoryFilter).toBeUndefined();
    expect(state.shopping).toBe(shopping);
  });
  it("preserves canonical destination identity and explicit location state", () => {
    let state = reduce(signedIn(), { type: "openBrowseDestination", nodeKey: "masalas" });
    state = reduce(state, { type: "openLocation" });
    expect(state.locationOpen).toBe(true);
    state = reduce(state, { type: "outsideInteraction" });
    expect(state.locationOpen).toBe(true);
    state = reduce(state, { type: "closeLocation" });
    expect(state.locationOpen).toBe(false);
    state = reduce(state, { type: "selectService", service: "food" });
    state = reduce(state, { type: "selectService", service: "grocery" });
    expect(state.exploration.grocery.view).toEqual({ kind: "browse", nodeKey: "masalas" });
  });
  it("starts outside and enters Grocery after authentication", () => {
    expect(reimaginedEnvironment(initialReimaginedState())).toBe("outside");
    expect(reimaginedEnvironment(signedIn())).toBe("groceryEntrance");
  });
  it("requires an explicit Bucket before adding the exact SKU", () => {
    let state = reduce(signedIn(), { type: "setGroceryQuantity", skuId: "sku-1", quantity: 1 });
    expect(state.bucketPrompt).toBe(true);
    expect(state.shopping.retail).toEqual({});
    state = reduce(state, { type: "takeBucket" });
    state = reduce(state, { type: "setGroceryQuantity", skuId: "sku-1", quantity: 1 });
    expect(state.shopping.retail).toEqual({ "sku-1": 1 });
    expect(state.bucketPrompt).toBe(false);
  });
  it("preserves both shopping sessions and exploration during switching", () => {
    let state = reduce(withShopping(), { type: "openRestaurant", branchId: "branch-1" });
    state = reduce(state, { type: "selectService", service: "grocery" });
    state = reduce(state, { type: "openCategory", categoryId: "category-1" });
    const shopping = state.shopping;
    state = reduce(state, { type: "selectService", service: "food" });
    expect(state.exploration.food.view).toEqual({ kind: "restaurant", branchId: "branch-1" });
    state = reduce(state, { type: "selectService", service: "grocery" });
    expect(state.exploration.grocery.view).toEqual({ kind: "category", categoryId: "category-1" });
    expect(state.shopping).toBe(shopping);
  });
  it("resets exploration on Home or reselecting the active service", () => {
    let state = reduce(withShopping(), { type: "openRestaurant", branchId: "branch-1" });
    const shopping = state.shopping;
    state = reduce(state, { type: "navigate", section: "home" });
    expect(state.exploration.food.view.kind).toBe("home");
    state = reduce(state, { type: "selectService", service: "grocery" });
    state = reduce(state, { type: "openCategory", categoryId: "category-1" });
    state = reduce(state, { type: "selectService", service: "grocery" });
    expect(state.exploration.grocery.view.kind).toBe("home");
    expect(state.shopping).toBe(shopping);
    expect(state.bucketAcquired).toBe(true);
  });
  it("keeps the main view and detail fixed while typing until explicit submission", () => {
    let state = reduce(signedIn(), { type: "openCategory", categoryId: "category-1" });
    state = reduce(state, { type: "openDetail", id: "sku-1" });
    const view = state.exploration.grocery.view;
    state = reduce(state, { type: "openSearch" });
    state = reduce(state, { type: "typeSearch", query: "  milk  " });
    expect(state.exploration.grocery.view).toBe(view);
    expect(state.exploration.grocery.detailId).toBe("sku-1");
    state = reduce(state, { type: "submitSearch" });
    expect(state.exploration.grocery.view).toEqual({ kind: "search", query: "milk" });
    expect(state.exploration.grocery.detailId).toBeUndefined();
  });
  it("uses explicit cart review and preserves shopping after returning or failure", () => {
    let state = reduce(withShopping(), { type: "selectService", service: "grocery" });
    const shopping = state.shopping;
    state = reduce(state, { type: "reviewShopping" });
    expect(reimaginedEnvironment(state)).toBe("groceryCounter");
    expect(reduce(state, { type: "checkoutFailed" })).toBe(state);
    state = reduce(state, { type: "continueShopping" });
    expect(reimaginedEnvironment(state)).toBe("groceryEntrance");
    expect(state.shopping).toBe(shopping);
  });
  it("makes outside interaction and Soon services inert", () => {
    const state = withShopping();
    expect(reduce(state, { type: "outsideInteraction" })).toBe(state);
    expect(reduce(state, { type: "selectService", service: "parcel" })).toBe(state);
    expect(reduce(state, { type: "selectService", service: "print" })).toBe(state);
  });
  it("keeps active orders across navigation and clears only the purchased service", () => {
    const initial = withShopping();
    let state = reduce(initial, { type: "checkoutSucceeded", service: "food", orderId: "order-1", purchased: initial.shopping });
    expect(state.shopping.retail).toEqual({ "sku-1": 3 });
    expect(state.shopping.food).toEqual([]);
    expect(reimaginedEnvironment(state)).toBe("foodEntrance");
    state = reduce(state, { type: "selectService", service: "grocery" });
    state = reduce(state, { type: "navigate", section: "profile" });
    expect(state.activeOrder).toEqual({ id: "order-1", service: "food" });
  });
  it("returns outside on sign-out and isolates account-owned shopping", () => {
    const state = withShopping();
    expect(reduce(state, { type: "signedOut" })).toEqual(initialReimaginedState());
    const other = reduce(state, { type: "signedIn", accountId: "account-2" });
    expect(other.shopping).toEqual({ retail: {}, food: [] });
    expect(other.bucketAcquired).toBe(false);
  });
  it("preserves items added after the submitted checkout snapshot", () => {
    const initial = withShopping();
    let state = reduce(initial, { type: "setFoodQuantity", line: { ...foodLine, quantity: 4 } });
    state = reduce(state, { type: "checkoutSucceeded", service: "food", orderId: "order-1", purchased: initial.shopping });
    expect(state.shopping.food[0].quantity).toBe(2);
    expect(state.shopping.retail).toEqual(initial.shopping.retail);
  });
  it("tracks food options as distinct choices and returns to entrance when empty", () => {
    let state = withShopping();
    state = reduce(state, { type: "setFoodQuantity", line: { ...foodLine, optionIds: ["option-2"], quantity: 1 } });
    expect(state.shopping.food).toHaveLength(2);
    expect(reimaginedEnvironment(state)).toBe("foodApproachingCounter");
    for (const line of state.shopping.food) state = reduce(state, { type: "setFoodQuantity", line: { ...line, quantity: 0 } });
    expect(reimaginedEnvironment(state)).toBe("foodEntrance");
    expect(state.shopping.retail).toEqual({ "sku-1": 3 });
  });
  it("restores existing account shopping without aliasing storage snapshots", () => {
    const shopping = { retail: { "sku-1": 2 }, food: [foodLine] };
    const state = reduce(initialReimaginedState(), { type: "signedIn", accountId: "account-1", shopping });
    shopping.retail["sku-1"] = 99;
    expect(state.shopping.retail["sku-1"]).toBe(2);
    expect(state.bucketAcquired).toBe(true);
    expect(reduce(state, { type: "signedIn", accountId: "account-1" })).toBe(state);
  });
  it("rejects invalid quantities and keeps product type filters within a subcategory", () => {
    let state = reduce(signedIn(), { type: "takeBucket" });
    for (const quantity of [-1, 1.5, NaN, Infinity]) expect(reduce(state, { type: "setGroceryQuantity", skuId: "sku-1", quantity })).toBe(state);
    state = reduce(state, { type: "setProductType", subcategoryId: "milk", productTypeId: "full-cream" });
    expect(state.exploration.grocery.productTypeFilters).toEqual({ milk: "full-cream" });
    expect(state.exploration.grocery.view.kind).toBe("home");
  });
});
