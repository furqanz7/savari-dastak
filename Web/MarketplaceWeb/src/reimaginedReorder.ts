import type { V1Order, V1RestaurantMenu } from "./dastakV1";
import type { ReimaginedCatalogue } from "./reimaginedCatalogue";
import type { PersistedCustomerCart } from "./customerCartPersistence";
import { foodSelection } from "./reimaginedFoodSelection";

export function prepareReimaginedReorder(order: Pick<V1Order, "lines" | "restaurant">, catalogue?: ReimaginedCatalogue, menus?: V1RestaurantMenu[]): { service: "grocery" | "food"; shopping: PersistedCustomerCart } {
  if (!order.lines.length) throw new Error("This order has no items to reorder.");
  const shopping: PersistedCustomerCart = { retail: {}, food: [] };
  const retail = order.lines.every(line => line.lineType === "RETAIL_SKU");
  const food = order.lines.every(line => line.lineType === "FOOD_MENU_ITEM");
  if (!retail && !food) throw new Error("This older mixed order needs to be rebuilt as separate Grocery and Food carts. Your carts are unchanged.");
  for (const line of order.lines) {
    if (!Number.isSafeInteger(line.quantity) || line.quantity < 1 || line.quantity > 99) throw new Error("Review this order’s quantities before reordering.");
    if (retail) {
      const sku = catalogue?.catalogue.skus.find(value => value.id === line.skuId);
      if (!sku) throw new Error("Some exact products are unavailable in the current catalogue. Nothing was replaced.");
      const quantity = (shopping.retail[sku.id] ?? 0) + line.quantity;
      if (quantity > 99) throw new Error("The reordered quantity exceeds the Bucket limit.");
      shopping.retail[sku.id] = quantity;
    } else {
      const menu = menus?.find(value => value.restaurant.branchId === order.restaurant?.branchId);
      const item = menu?.categories.flatMap(category => category.items).find(value => value.id === line.menuItemId);
      const optionIds = line.foodSelection?.options.map(option => option.id).sort() ?? [];
      if (!menu || !item || !menu.restaurant.isOpen || !menu.restaurant.acceptingOrders || menu.restaurant.branchStatus !== "ACTIVE" || !foodSelection(item, optionIds).valid) throw new Error("The restaurant, dish or exact options are unavailable. Nothing was replaced.");
      const existing = shopping.food.find(value => value.itemId === item.id && JSON.stringify(value.optionIds) === JSON.stringify(optionIds));
      if (existing) {
        existing.quantity += line.quantity;
        if (existing.quantity > 99) throw new Error("The reordered quantity exceeds the Food cart limit.");
      } else shopping.food.push({ branchId: menu.restaurant.branchId, itemId: item.id, optionIds, quantity: line.quantity });
    }
  }
  return { service: retail ? "grocery" : "food", shopping };
}
