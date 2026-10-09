import type { V1RestaurantMenu } from "./dastakV1";
import type { FoodCategoryFilter } from "./reimaginedState";

// Discovery groups are a projection of exact menu labels, not a new taxonomy.
// Selection always retains branch/category identities; no dish-name inference.
export function foodCategoryControls(menus: V1RestaurantMenu[]): FoodCategoryFilter[] {
  const groups = new Map<string, FoodCategoryFilter>();
  for (const menu of menus) for (const category of menu.categories) {
    const label = category.name.trim();
    if (!label || category.status !== "ACTIVE" || !category.items.some(item => item.status === "ACTIVE")) continue;
    let group = groups.get(label);
    if (!group) { group = { label, members: [] }; groups.set(label, group); }
    group.members.push({ branchId: menu.restaurant.branchId, categoryId: category.id });
  }
  return [...groups.values()];
}

export function foodCategoryRestaurants(menus: V1RestaurantMenu[], filter?: FoodCategoryFilter): V1RestaurantMenu[] {
  if (!filter) return menus;
  const members = new Set(filter.members.map(member => JSON.stringify([member.branchId, member.categoryId])));
  return menus.filter(menu => menu.categories.some(category =>
    members.has(JSON.stringify([menu.restaurant.branchId, category.id])) && category.name.trim() === filter.label &&
    category.status === "ACTIVE" && category.items.some(item => item.status === "ACTIVE")));
}

export function foodRestaurantName(menu: V1RestaurantMenu) {
  return menu.restaurant.branchName.trim() || menu.restaurant.name;
}

// Preserve the server's stable tie order; unknown locations never appear as 0m.
export function nearestFoodMenus(menus: V1RestaurantMenu[]): V1RestaurantMenu[] {
  return [...menus].sort((a, b) => (a.restaurant.distanceMeters ?? Infinity) - (b.restaurant.distanceMeters ?? Infinity));
}

export function foodDistance(menu: V1RestaurantMenu): string {
  const metres = menu.restaurant.distanceMeters;
  if (metres === undefined) return "Distance unavailable";
  return metres < 1000 ? `${metres} m away` : `${(metres / 1000).toFixed(1)} km away`;
}

export function foodAcceptingOrders(menu: V1RestaurantMenu) {
  return menu.restaurant.branchStatus === "ACTIVE" && menu.restaurant.isOpen && menu.restaurant.acceptingOrders;
}
export function foodAvailability(menu: V1RestaurantMenu) {
  return foodAcceptingOrders(menu) ? "Open — availability checked at checkout" : "Store closed";
}

// Keep identity branch-scoped; duplicate IDs must never select an arbitrary restaurant/dish.
export function prepareFoodMenus(menus: V1RestaurantMenu[]): V1RestaurantMenu[] {
  const branches = new Set<string>();
  return menus.map(menu => {
    const branch = menu.restaurant.branchId;
    if (branches.has(branch)) throw new Error("Food catalogue contains a duplicate restaurant identity.");
    branches.add(branch);
    const categories = new Set<string>(); const items = new Set<string>();
    return { ...menu, categories: menu.categories.filter(category => category.status === "ACTIVE").map(category => {
      if (categories.has(category.id)) throw new Error("Food catalogue contains a duplicate menu category.");
      categories.add(category.id);
      return { ...category, items: category.items.filter(item => item.status === "ACTIVE").map(item => {
        if (items.has(item.id)) throw new Error("Food catalogue contains a duplicate dish identity.");
        items.add(item.id);
        const groupIds = new Set<string>(); const optionIds = new Set<string>();
        for (const group of item.optionGroups.filter(value => value.status === "ACTIVE")) {
          if (groupIds.has(group.id) || !Number.isSafeInteger(group.minimumSelections) || !Number.isSafeInteger(group.maximumSelections) || group.minimumSelections < 0 || group.maximumSelections < group.minimumSelections || (group.selectionType === "SINGLE" && group.maximumSelections > 1)) throw new Error("Food catalogue contains ambiguous option groups.");
          groupIds.add(group.id);
          for (const option of group.options.filter(value => value.status === "ACTIVE")) {
            if (optionIds.has(option.id)) throw new Error("Food catalogue contains duplicate option identities.");
            optionIds.add(option.id);
          }
        }
        return { ...item, optionGroups: item.optionGroups.filter(group => group.status === "ACTIVE")
          .map(group => ({ ...group, options: group.options.filter(option => option.status === "ACTIVE").sort((a, b) => a.sortOrder - b.sortOrder) }))
          .sort((a, b) => a.sortOrder - b.sortOrder) };
      }) };
    }).sort((a, b) => a.sortOrder - b.sortOrder) };
  });
}

export function searchFood(menus: V1RestaurantMenu[], query: string, canonical = false) {
  const terms = query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) return [];
  return menus.flatMap(menu => {
    const name = `${foodRestaurantName(menu)} ${menu.restaurant.name}`;
    const dishes = menu.categories.flatMap(category => category.items.map(item => ({ item, category: category.name })))
      .filter(({ item, category }) => terms.every(term => `${name} ${category} ${item.name}`.toLocaleLowerCase().includes(term)));
    const restaurantMatches = terms.every(term => name.toLocaleLowerCase().includes(term));
    // Regional server matches can include organisation aliases not displayed
    // as the branch name. Never discard an authoritative returned restaurant.
    return canonical || restaurantMatches || dishes.length ? [{ menu, dishes }] : [];
  });
}
