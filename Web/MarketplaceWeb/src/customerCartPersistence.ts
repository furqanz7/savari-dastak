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
    storage.setItem(cartKey(accountId), JSON.stringify({
      version: cartVersion,
      retail: parseRetail(cart.retail),
      food: parseFood(cart.food),
    }));
  } catch {
    // Private browsing or a full storage quota must not break the basket.
  }
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
