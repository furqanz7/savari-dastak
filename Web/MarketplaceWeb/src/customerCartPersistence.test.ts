import { describe, expect, it } from "vitest";
import {
  loadCustomerCart,
  persistedFoodCart,
  resolveFoodCart,
  saveCustomerCart,
  validateRetailCart,
} from "./customerCartPersistence";
import type { V1CatalogueSku, V1RestaurantMenu } from "./dastakV1";

describe("customer cart persistence", () => {
  it("migrates the retail-only v1 cart into the unified cart", () => {
    const storage = memoryStorage({
      "dastak:v1-cart:customer-1": JSON.stringify({
        version: 1,
        quantities: { "sku-1": 2, "sku-invalid": 0 },
      }),
    });

    expect(loadCustomerCart("customer-1", storage)).toEqual({
      retail: { "sku-1": 2 },
      food: [],
    });
  });

  it("persists retail and restaurant entries in one versioned customer cart", () => {
    const storage = memoryStorage();
    saveCustomerCart("customer-1", {
      retail: { "sku-1": 3 },
      food: [{ branchId: "branch-1", itemId: "item-1", optionIds: ["option-1"], quantity: 2 }],
    }, storage);

    expect(loadCustomerCart("customer-1", storage)).toEqual({
      retail: { "sku-1": 3 },
      food: [{ branchId: "branch-1", itemId: "item-1", optionIds: ["option-1"], quantity: 2 }],
    });
  });

  it("removes retail entries that are absent from the authoritative catalogue", () => {
    expect(validateRetailCart(
      { "sku-current": 2, "sku-removed": 4 },
      [catalogueSku("sku-current")],
    )).toEqual({ "sku-current": 2 });
  });

  it("does not discard an unresolved retail entry from a partial catalogue page", () => {
    expect(validateRetailCart(
      { "sku-current": 2, "sku-on-later-page": 4 },
      [catalogueSku("sku-current")],
      false,
    )).toEqual({ "sku-current": 2, "sku-on-later-page": 4 });
  });

  it("rehydrates restaurant entries from current menu truth and drops stale selections", () => {
    const menu = restaurantMenu();
    const resolved = resolveFoodCart([
      { branchId: "branch-1", itemId: "item-1", optionIds: ["option-1"], quantity: 2 },
      { branchId: "branch-1", itemId: "item-1", optionIds: ["option-removed"], quantity: 1 },
      { branchId: "branch-1", itemId: "item-removed", optionIds: [], quantity: 1 },
    ], [menu]);

    expect(resolved).toHaveLength(1);
    expect(resolved[0]).toMatchObject({
      branchId: "branch-1",
      restaurantName: "Current Restaurant Name",
      optionIds: ["option-1"],
      optionNames: ["Large"],
      unitPricePaise: 5500,
      quantity: 2,
    });
    expect(persistedFoodCart(resolved)).toEqual([
      { branchId: "branch-1", itemId: "item-1", optionIds: ["option-1"], quantity: 2 },
    ]);
  });
});

function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem(key: string) { return values.get(key) ?? null; },
    setItem(key: string, value: string) { values.set(key, value); },
  };
}

function catalogueSku(id: string): V1CatalogueSku {
  return {
    id,
    categoryId: "category-1",
    subcategoryId: "subcategory-1",
    name: "Rice",
    slug: "rice",
    packSize: "1 kg",
    listPricePaise: 10000,
    sellingPricePaise: 9500,
    currencyCode: "INR",
    logisticsAttributes: {},
    galleryImageKeys: [],
    attributes: {},
  };
}

function restaurantMenu(): V1RestaurantMenu {
  return {
    restaurant: {
      organizationId: "organization-1",
      branchId: "branch-1",
      name: "Current Restaurant Name",
      branchName: "Main Road",
      acceptingOrders: true,
      isOpen: true,
      branchStatus: "ACTIVE",
      merchantType: "RESTAURANT_CAFE",
      operationalVersion: 2,
      softActiveOrderThreshold: 5,
      activeOrderCount: 1,
    },
    categories: [{
      id: "category-1",
      name: "Drinks",
      sortOrder: 1,
      status: "ACTIVE",
      version: 1,
      items: [{
        id: "item-1",
        name: "Filter Coffee",
        basePricePaise: 5000,
        currencyCode: "INR",
        taxRateBps: 0,
        logisticsAttributes: {},
        status: "ACTIVE",
        version: 2,
        optionGroups: [{
          id: "group-1",
          name: "Size",
          selectionType: "SINGLE",
          minimumSelections: 1,
          maximumSelections: 1,
          sortOrder: 1,
          status: "ACTIVE",
          version: 1,
          options: [{
            id: "option-1",
            name: "Large",
            priceDeltaPaise: 500,
            sortOrder: 1,
            status: "ACTIVE",
            version: 1,
          }],
        }],
      }],
    }],
  };
}
