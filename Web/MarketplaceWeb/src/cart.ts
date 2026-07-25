import type { CatalogueProduct } from "./catalogue";

export const MAX_CART_PRODUCT_QUANTITY = 99;
export const CART_STORE_CONFLICT_MESSAGE =
  "Complete or clear the current cart before choosing another store.";
export const CART_QUANTITY_LIMIT_MESSAGE =
  `You can add up to ${MAX_CART_PRODUCT_QUANTITY} of one product.`;

export type CartEntry = {
  storeId: string;
  storeName: string;
  product: CatalogueProduct;
  quantity: number;
};

export type CartEntries = Record<string, CartEntry>;

export type CartState = {
  entries: CartEntries;
  error?: string;
};

export type CartAction =
  | {
    type: "changeQuantity";
    store: { storeId: string; name: string };
    product: CatalogueProduct;
    delta: -1 | 1;
  }
  | { type: "clear" };

export function createEmptyCart(): CartState {
  return { entries: {} };
}

export function cartReducer(state: CartState, action: CartAction): CartState {
  if (action.type === "clear") return createEmptyCart();

  const currentEntries = Object.values(state.entries);
  const currentStoreId = currentEntries[0]?.storeId;
  if (action.delta > 0 && currentStoreId && currentStoreId !== action.store.storeId) {
    return { ...state, error: CART_STORE_CONFLICT_MESSAGE };
  }

  const currentQuantity = state.entries[action.product.productId]?.quantity ?? 0;
  const nextQuantity = currentQuantity + action.delta;
  if (nextQuantity > MAX_CART_PRODUCT_QUANTITY) {
    return { ...state, error: CART_QUANTITY_LIMIT_MESSAGE };
  }

  const entries = { ...state.entries };
  if (nextQuantity <= 0) {
    delete entries[action.product.productId];
  } else {
    entries[action.product.productId] = {
      storeId: action.store.storeId,
      storeName: action.store.name,
      product: action.product,
      quantity: nextQuantity,
    };
  }

  return { entries };
}

export function summarizeCart(entries: CartEntries) {
  const items = Object.values(entries);
  return {
    items,
    storeId: items[0]?.storeId,
    storeName: items[0]?.storeName,
    itemCount: items.reduce((total, entry) => total + entry.quantity, 0),
    subtotalPaise: items.reduce(
      (total, entry) => total + entry.product.price.paise * entry.quantity,
      0,
    ),
  };
}
