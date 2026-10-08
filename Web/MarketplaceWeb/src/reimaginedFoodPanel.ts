import type { V1RestaurantMenu } from "./dastakV1";
import type { ReimaginedState } from "./reimaginedState";
import { foodRestaurantName } from "./reimaginedFoodCatalogue";

export function foodPanelTitle(state: ReimaginedState, menus?: V1RestaurantMenu[]) {
  const exploration = state.exploration.food;
  if (exploration.checkout) return "Your Food cart";
  const branchId = exploration.view.kind === "restaurant" ? exploration.view.branchId : undefined;
  const menu = menus?.find(value => value.restaurant.branchId === branchId);
  const item = menu?.categories.flatMap(category => category.items).find(value => value.id === exploration.detailId);
  if (item) return item.name;
  if (menu) return foodRestaurantName(menu);
  if (exploration.view.kind === "search") return `Results for “${exploration.view.query}”`;
  return "Find your next favourite.";
}
