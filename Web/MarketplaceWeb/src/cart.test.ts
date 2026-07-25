import { describe, expect, it } from "vitest";
import type { CatalogueProduct } from "./catalogue";
import {
  CART_QUANTITY_LIMIT_MESSAGE,
  CART_STORE_CONFLICT_MESSAGE,
  cartReducer,
  createEmptyCart,
  MAX_CART_PRODUCT_QUANTITY,
  summarizeCart,
  type CartState,
} from "./cart";

const firstStore = { storeId: "11111111-1111-4111-8111-111111111111", name: "First Store" };
const secondStore = { storeId: "22222222-2222-4222-8222-222222222222", name: "Second Store" };
const bread = product("33333333-3333-4333-8333-333333333333", firstStore.storeId, 4500);
const milk = product("44444444-4444-4444-8444-444444444444", firstStore.storeId, 3000);
const water = product("55555555-5555-4555-8555-555555555555", secondStore.storeId, 2000);

describe("customer cart", () => {
  it("adds products and calculates quantity and subtotal", () => {
    let state = createEmptyCart();
    state = change(state, firstStore, bread, 1);
    state = change(state, firstStore, bread, 1);
    state = change(state, firstStore, milk, 1);

    expect(summarizeCart(state.entries)).toMatchObject({
      storeId: firstStore.storeId,
      storeName: firstStore.name,
      itemCount: 3,
      subtotalPaise: 12000,
    });
  });

  it("removes a product when its quantity reaches zero", () => {
    let state = change(createEmptyCart(), firstStore, bread, 1);
    state = change(state, firstStore, bread, -1);

    expect(summarizeCart(state.entries)).toMatchObject({ itemCount: 0, subtotalPaise: 0 });
    expect(state.entries).toEqual({});
  });

  it("prevents products from different stores sharing one cart", () => {
    let state = change(createEmptyCart(), firstStore, bread, 1);
    state = change(state, secondStore, water, 1);

    expect(state.error).toBe(CART_STORE_CONFLICT_MESSAGE);
    expect(Object.keys(state.entries)).toEqual([bread.productId]);
  });

  it("caps each product at the server quantity limit", () => {
    const state: CartState = {
      entries: {
        [bread.productId]: {
          storeId: firstStore.storeId,
          storeName: firstStore.name,
          product: bread,
          quantity: MAX_CART_PRODUCT_QUANTITY,
        },
      },
    };

    const result = change(state, firstStore, bread, 1);

    expect(result.entries[bread.productId].quantity).toBe(MAX_CART_PRODUCT_QUANTITY);
    expect(result.error).toBe(CART_QUANTITY_LIMIT_MESSAGE);
  });

  it("clears every product and cart error", () => {
    const populated = change(createEmptyCart(), firstStore, bread, 1);
    expect(cartReducer(populated, { type: "clear" })).toEqual(createEmptyCart());
  });
});

function change(
  state: CartState,
  store: { storeId: string; name: string },
  catalogueProduct: CatalogueProduct,
  delta: -1 | 1,
) {
  return cartReducer(state, {
    type: "changeQuantity",
    store,
    product: catalogueProduct,
    delta,
  });
}

function product(productId: string, storeId: string, pricePaise: number): CatalogueProduct {
  return {
    productId,
    storeId,
    categoryId: "66666666-6666-4666-8666-666666666666",
    name: `Product ${productId.slice(0, 4)}`,
    description: null,
    unitLabel: "1 unit",
    price: { paise: pricePaise },
    imageObjectPath: null,
    availability: "in_stock",
    catalogueKind: "general",
    restrictedApprovalState: "not_applicable",
    isActive: true,
  };
}
