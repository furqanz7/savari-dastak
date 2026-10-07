import type {
  V1CatalogueSku,
  V1RestaurantMenu,
  V1RestaurantMenuItem,
} from "./dastakV1";

export type RetailCart = Record<string, number>;

export type PersistedFoodCartLine = {
  branchId: string;
  itemId: string;
  optionIds: string[];
  quantity: number;
};

export type ResolvedFoodCartLine = {
  key: string;
  branchId: string;
  restaurantName: string;
  item: V1RestaurantMenuItem;
  optionIds: string[];
  optionNames: string[];
  unitPricePaise: number;
  quantity: number;
};

export type PersistedCustomerCart = {
  retail: RetailCart;
  food: PersistedFoodCartLine[];
};

type CartStorage = Pick<Storage, "getItem" | "setItem">;

const cartVersion = 2;

export function loadCustomerCart(accountId: string, storage = browserStorage()): PersistedCustomerCart {
  if (!storage) return emptyCart();
  try {
    const value = JSON.parse(storage.getItem(cartKey(accountId)) ?? "null") as unknown;
    if (!isRecord(value)) return emptyCart();

    if (value.version === 1) {
      return { retail: parseRetail(value.quantities), food: [] };
    }
    if (value.version !== cartVersion) return emptyCart();
    return {
      retail: parseRetail(value.retail),
      food: parseFood(value.food),
    };
  } catch {
    return emptyCart();
  }
}

export function saveCustomerCart(
  accountId: string,
  cart: PersistedCustomerCart,
  storage = browserStorage(),
) {
  if (!storage) return;
  try {
    const previous = JSON.parse(storage.getItem(cartKey(accountId)) ?? "null") as unknown;
    const acknowledgements = checkoutAcknowledgements(previous);
    storage.setItem(cartKey(accountId), JSON.stringify({
      version: cartVersion,
      retail: parseRetail(cart.retail),
      food: parseFood(cart.food),
      ...(checkoutAcknowledgements(previous, "reimaginedFoodAcknowledgements").length ? { reimaginedFoodAcknowledgements: checkoutAcknowledgements(previous, "reimaginedFoodAcknowledgements") } : {}),
      ...(acknowledgements.length ? { reimaginedGroceryAcknowledgements: acknowledgements } : {}),
    }));
  } catch {
    // Private browsing or a full storage quota must not break the basket.
  }
}

function checkoutAcknowledgements(value: unknown, field = "reimaginedGroceryAcknowledgements"): string[] {
  if (!isRecord(value) || value[field] === undefined) return [];
  const ids = value[field];
  if (!Array.isArray(ids) || ids.some(id => typeof id !== "string" || !id.length || id.length > 200)) throw new Error("Checkout acknowledgement data is invalid.");
  return [...new Set(ids)] as string[];
}

// Strict opt-in editor helpers: invalid storage must not become an empty cart write.
export function loadCustomerCartStrict(accountId: string, storage = browserStorage()): PersistedCustomerCart {
  if (!storage) throw new Error("Cart storage is unavailable. Your saved cart was not changed.");
  const value = JSON.parse(storage.getItem(cartKey(accountId)) ?? "null") as unknown;
  if (value === null) return emptyCart();
  if (!isRecord(value) || (value.version !== 1 && value.version !== 2)) throw new Error("Saved cart data is invalid. It was not overwritten.");
  checkoutAcknowledgements(value);
  checkoutAcknowledgements(value, "reimaginedFoodAcknowledgements");
  const retail = value.version === 1 ? value.quantities : value.retail;
  if (!isRecord(retail) || Object.keys(parseRetail(retail)).length !== Object.keys(retail).length
    || (value.version === 2 && (!Array.isArray(value.food) || parseFood(value.food).length !== value.food.length))) throw new Error("Saved cart data is invalid. It was not overwritten.");
  return { retail: parseRetail(retail), food: value.version === 1 ? [] : parseFood(value.food) };
}

export function saveCustomerCartStrict(accountId: string, cart: PersistedCustomerCart, storage = browserStorage()) {
  if (!storage) throw new Error("Cart storage is unavailable. Your saved cart was not changed.");
  loadCustomerCartStrict(accountId, storage);
  const previous = JSON.parse(storage.getItem(cartKey(accountId)) ?? "null") as unknown;
  const ids = checkoutAcknowledgements(previous);
  storage.setItem(cartKey(accountId), JSON.stringify({ version: 2, retail: parseRetail(cart.retail), food: parseFood(cart.food),
    ...(checkoutAcknowledgements(previous, "reimaginedFoodAcknowledgements").length ? { reimaginedFoodAcknowledgements: checkoutAcknowledgements(previous, "reimaginedFoodAcknowledgements") } : {}),
    ...(ids.length ? { reimaginedGroceryAcknowledgements: ids } : {}) }));
}

export function groceryCheckoutAcknowledged(accountId: string, orderId: string, storage = browserStorage()) {
  if (!storage) throw new Error("Checkout recovery storage is unavailable.");
  return checkoutAcknowledgements(JSON.parse(storage.getItem(cartKey(accountId)) ?? "null")).includes(orderId);
}

// Basket and acknowledgement are one localStorage write: a crash cannot persist only one.
// Cross-tab read/write exclusion remains an activation prerequisite.
export function acknowledgeGroceryCheckout(accountId: string, orderId: string, purchased: RetailCart, storage = browserStorage()) {
  if (!storage) throw new Error("Checkout recovery storage is unavailable. Your Bucket is retained.");
  const raw = storage.getItem(cartKey(accountId));
  const value = JSON.parse(raw ?? "null") as unknown;
  if (value !== null && (!isRecord(value) || (value.version !== 1 && value.version !== 2))) throw new Error("Saved cart data is invalid. Your Bucket is retained.");
  const ids = checkoutAcknowledgements(value);
  if (ids.includes(orderId)) return false;
  if (isRecord(value)) {
    const retail = value.version === 1 ? value.quantities : value.retail;
    if (!isRecord(retail) || Object.keys(parseRetail(retail)).length !== Object.keys(retail).length
      || (value.version === 2 && (!Array.isArray(value.food) || parseFood(value.food).length !== value.food.length))) throw new Error("Saved cart data is invalid. Your Bucket is retained.");
  }
  const cart = !isRecord(value) ? emptyCart() : value.version === 1
    ? { retail: parseRetail(value.quantities), food: [] }
    : { retail: parseRetail(value.retail), food: parseFood(value.food) };
  const retail = Object.fromEntries(Object.entries(cart.retail).flatMap(([id, quantity]) => {
    const remaining = quantity - (purchased[id] ?? 0);
    return remaining > 0 ? [[id, remaining]] : [];
  }));
  storage.setItem(cartKey(accountId), JSON.stringify({ version: 2, retail, food: cart.food, reimaginedGroceryAcknowledgements: [...ids, orderId], reimaginedFoodAcknowledgements: checkoutAcknowledgements(value, "reimaginedFoodAcknowledgements") }));
  return true;
}

export function foodCheckoutAcknowledged(accountId: string, orderId: string, storage = browserStorage()) {
  if (!storage) throw new Error("Checkout recovery storage is unavailable.");
  return checkoutAcknowledgements(JSON.parse(storage.getItem(cartKey(accountId)) ?? "null"), "reimaginedFoodAcknowledgements").includes(orderId);
}

export function acknowledgeFoodCheckout(accountId: string, orderId: string, purchased: PersistedFoodCartLine[], storage = browserStorage()) {
  if (!storage) throw new Error("Checkout recovery storage is unavailable. Your Food cart is retained.");
  const cart = loadCustomerCartStrict(accountId, storage);
  const value = JSON.parse(storage.getItem(cartKey(accountId)) ?? "null") as unknown;
  const ids = checkoutAcknowledgements(value, "reimaginedFoodAcknowledgements");
  if (ids.includes(orderId)) return false;
  const identity = (line: PersistedFoodCartLine) => JSON.stringify([line.branchId, line.itemId, [...line.optionIds].sort()]);
  const quantities = new Map(purchased.map(line => [identity(line), line.quantity]));
  if (quantities.size !== purchased.length || purchased.some(line => !Number.isSafeInteger(line.quantity) || line.quantity < 1)) throw new Error("Purchased Food quantities are invalid.");
  const food = cart.food.flatMap(line => {
    const quantity = line.quantity - (quantities.get(identity(line)) ?? 0);
    return quantity > 0 ? [{ ...line, quantity }] : [];
  });
  storage.setItem(cartKey(accountId), JSON.stringify({ version: 2, retail: cart.retail, food, reimaginedGroceryAcknowledgements: checkoutAcknowledgements(value), reimaginedFoodAcknowledgements: [...ids, orderId] }));
  return true;
}

export function validateRetailCart(
  cart: RetailCart,
  skus: V1CatalogueSku[],
  catalogueIsComplete = true,
): RetailCart {
  if (!catalogueIsComplete) return parseRetail(cart);
  const availableSkuIds = new Set(skus.map((sku) => sku.id));
  return Object.fromEntries(
    Object.entries(parseRetail(cart)).filter(([skuId]) => availableSkuIds.has(skuId)),
  );
}

export function resolveFoodCart(
  entries: PersistedFoodCartLine[],
  restaurants: V1RestaurantMenu[],
): ResolvedFoodCartLine[] {
  const restaurantsByBranch = new Map(
    restaurants
      .filter((menu) => menu.restaurant.branchStatus === "ACTIVE")
      .map((menu) => [menu.restaurant.branchId, menu]),
  );
  const resolved = new Map<string, ResolvedFoodCartLine>();
  let basketBranchId: string | undefined;

  for (const entry of parseFood(entries)) {
    const restaurant = restaurantsByBranch.get(entry.branchId);
    if (!restaurant || (basketBranchId && basketBranchId !== entry.branchId)) continue;

    const activeCategories = restaurant.categories.filter((category) => category.status === "ACTIVE");
    const item = activeCategories.flatMap((category) => category.items)
      .find((candidate) => candidate.id === entry.itemId && candidate.status === "ACTIVE");
    if (!item) continue;

    const activeGroups = item.optionGroups.filter((group) => group.status === "ACTIVE");
    const selectedOptions = activeGroups.flatMap((group) => group.options)
      .filter((option) => option.status === "ACTIVE" && entry.optionIds.includes(option.id));
    if (selectedOptions.length !== entry.optionIds.length) continue;
    if (activeGroups.some((group) => {
      const selectedCount = group.options.filter((option) =>
        option.status === "ACTIVE" && entry.optionIds.includes(option.id)
      ).length;
      return selectedCount < group.minimumSelections || selectedCount > group.maximumSelections;
    })) continue;

    const optionIds = selectedOptions.map((option) => option.id).sort();
    const key = `${item.id}:${optionIds.join(",")}`;
    const existing = resolved.get(key);
    const quantity = Math.min((existing?.quantity ?? 0) + entry.quantity, 99);
    resolved.set(key, {
      key,
      branchId: restaurant.restaurant.branchId,
      restaurantName: restaurant.restaurant.name,
      item,
      optionIds,
      optionNames: selectedOptions.map((option) => option.name),
      unitPricePaise: item.basePricePaise + selectedOptions.reduce(
        (total, option) => total + option.priceDeltaPaise,
        0,
      ),
      quantity,
    });
    basketBranchId = entry.branchId;
  }

  return [...resolved.values()];
}

export function persistedFoodCart(lines: ResolvedFoodCartLine[]): PersistedFoodCartLine[] {
  return lines.map((line) => ({
    branchId: line.branchId,
    itemId: line.item.id,
    optionIds: line.optionIds,
    quantity: line.quantity,
  }));
}

export function foodCartKey(itemId: string, optionIds: string[]) {
  return `${itemId}:${[...optionIds].sort().join(",")}`;
}

function parseRetail(value: unknown): RetailCart {
  if (!isRecord(value)) return {};
  return Object.fromEntries(Object.entries(value).filter(([, quantity]) => validQuantity(quantity))) as RetailCart;
}

function parseFood(value: unknown): PersistedFoodCartLine[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((candidate) => {
    if (!isRecord(candidate) || typeof candidate.branchId !== "string" ||
      typeof candidate.itemId !== "string" || !validQuantity(candidate.quantity) ||
      !Array.isArray(candidate.optionIds) ||
      !candidate.optionIds.every((optionId) => typeof optionId === "string")) return [];
    return [{
      branchId: candidate.branchId,
      itemId: candidate.itemId,
      optionIds: [...new Set(candidate.optionIds)].sort(),
      quantity: candidate.quantity,
    }];
  });
}

function validQuantity(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0 && value <= 99;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function emptyCart(): PersistedCustomerCart {
  return { retail: {}, food: [] };
}

function cartKey(accountId: string) {
  return `dastak:v1-cart:${accountId}`;
}

function browserStorage(): CartStorage | undefined {
  return typeof localStorage === "undefined" ? undefined : localStorage;
}
