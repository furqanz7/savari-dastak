import { foodCartKey, type PersistedCustomerCart, type PersistedFoodCartLine } from "./customerCartPersistence";

export type ReimaginedService = "grocery" | "food";
export type ReimaginedSection = "home" | "orders" | "profile" | "settings";
export type FoodCategoryFilter = { label: string; members: { branchId: string; categoryId: string }[] };
export type ReimaginedView =
  | { kind: "home" }
  | { kind: "category"; categoryId: string }
  | { kind: "browse"; nodeKey: string; railKey?: string }
  | { kind: "restaurant"; branchId: string }
  | { kind: "search"; query: string };
export type ReimaginedExploration = {
  view: ReimaginedView;
  searchOpen: boolean;
  searchDraft: string;
  detailId?: string;
  productTypeFilters: Record<string, string>;
  foodCategoryFilter?: FoodCategoryFilter;
  checkout: boolean;
};
export type ReimaginedState = {
  accountId?: string;
  service: ReimaginedService;
  section: ReimaginedSection;
  exploration: Record<ReimaginedService, ReimaginedExploration>;
  shopping: PersistedCustomerCart;
  bucketAcquired: boolean;
  bucketPrompt: boolean;
  locationOpen: boolean;
  activeOrder?: { id: string; service: ReimaginedService; kind?: "merchant" };
};
export type ReimaginedNavigationState = Pick<ReimaginedState, "service" | "section"> & {
  exploration: Pick<ReimaginedExploration, "view" | "searchOpen" | "detailId" | "checkout">;
};
export type ReimaginedAction =
  | { type: "signedIn"; accountId: string; shopping?: PersistedCustomerCart }
  | { type: "signedOut" }
  | { type: "selectService"; service: ReimaginedService | "parcel" | "print" }
  | { type: "navigate"; section: ReimaginedSection }
  | { type: "restoreNavigation"; navigation: ReimaginedNavigationState }
  | { type: "openCategory"; categoryId: string }
  | { type: "openBrowseDestination"; nodeKey: string; railKey?: string }
  | { type: "openLocation" }
  | { type: "closeLocation" }
  | { type: "openRestaurant"; branchId: string }
  | { type: "selectFoodCategory"; filter?: FoodCategoryFilter }
  | { type: "openDetail"; id: string }
  | { type: "closeDetail" }
  | { type: "setProductType"; subcategoryId: string; productTypeId?: string }
  | { type: "openSearch" }
  | { type: "typeSearch"; query: string }
  | { type: "submitSearch" }
  | { type: "closeSearch" }
  | { type: "takeBucket" }
  | { type: "setGroceryQuantity"; skuId: string; quantity: number }
  | { type: "setFoodQuantity"; line: PersistedFoodCartLine }
  | { type: "reviewShopping" }
  | { type: "continueShopping" }
  | { type: "checkoutFailed" }
  | { type: "replaceServiceShopping"; service: ReimaginedService; shopping: PersistedCustomerCart }
  | { type: "checkoutSucceeded"; service: ReimaginedService; orderId: string; purchased: PersistedCustomerCart }
  | { type: "orderUpdated"; order?: ReimaginedState["activeOrder"] }
  | { type: "outsideInteraction" };

const home = (): ReimaginedExploration => ({
  view: { kind: "home" }, searchOpen: false, searchDraft: "", productTypeFilters: {}, checkout: false,
});

export function initialReimaginedState(): ReimaginedState {
  return {
    service: "grocery", section: "home", exploration: { grocery: home(), food: home() },
    shopping: { retail: {}, food: [] }, bucketAcquired: false, bucketPrompt: false, locationOpen: false,
  };
}

function explore(state: ReimaginedState, patch: Partial<ReimaginedExploration>): ReimaginedState {
  return { ...state, exploration: { ...state.exploration, [state.service]: { ...state.exploration[state.service], ...patch } } };
}

export function reimaginedReducer(state: ReimaginedState, action: ReimaginedAction): ReimaginedState {
  if (action.type === "signedOut") return initialReimaginedState();
  if (action.type === "signedIn") {
    if (!action.accountId.trim() || action.accountId === state.accountId) return state;
    const shopping = action.shopping ?? { retail: {}, food: [] };
    return {
      ...initialReimaginedState(), accountId: action.accountId,
      shopping: { retail: { ...shopping.retail }, food: shopping.food.map(line => ({ ...line, optionIds: [...line.optionIds] })) },
      bucketAcquired: Object.values(shopping.retail).some(quantity => quantity > 0),
    };
  }
  if (!state.accountId) return state;
  switch (action.type) {
    case "restoreNavigation": {
      const { service, section, exploration } = action.navigation;
      const hasItems = service === "grocery" ? Object.keys(state.shopping.retail).length > 0 : state.shopping.food.length > 0;
      return explore({ ...state, service, section, locationOpen: false, bucketPrompt: false }, {
        ...exploration, detailId: exploration.detailId, checkout: exploration.checkout && hasItems,
        ...(exploration.view.kind === "search" ? { searchDraft: exploration.view.query } : {}),
      });
    }
    case "replaceServiceShopping": {
      const next = resetHome({ ...state, service: action.service, shopping: {
        retail: action.service === "grocery" ? { ...action.shopping.retail } : state.shopping.retail,
        food: action.service === "food" ? action.shopping.food.map(line => ({ ...line, optionIds: [...line.optionIds] })) : state.shopping.food,
      }, bucketAcquired: action.service === "grocery" || state.bucketAcquired });
      return explore(next, { checkout: true });
    }
    case "selectService":
      if (action.service === "parcel" || action.service === "print") return state;
      if (action.service === state.service) return resetHome(state);
      return { ...state, service: action.service, section: "home", bucketPrompt: false };
    case "navigate":
      return action.section === "home" ? resetHome(state) : { ...state, section: action.section };
    case "openCategory":
      return state.service === "grocery" ? explore({ ...state, section: "home" }, { view: { kind: "category", categoryId: action.categoryId }, detailId: undefined, checkout: false }) : state;
    case "openBrowseDestination":
      return state.service === "grocery" ? explore({ ...state, section: "home" }, { view: { kind: "browse", nodeKey: action.nodeKey, ...(action.railKey ? { railKey: action.railKey } : {}) }, detailId: undefined, checkout: false }) : state;
    case "openLocation": return { ...state, locationOpen: true };
    case "closeLocation": return { ...state, locationOpen: false };
    case "openRestaurant":
      return state.service === "food" ? explore({ ...state, section: "home" }, { view: { kind: "restaurant", branchId: action.branchId }, detailId: undefined, checkout: false }) : state;
    case "selectFoodCategory":
      return state.service === "food" ? explore({ ...state, section: "home" }, {
        view: { kind: "home" }, detailId: undefined, checkout: false, searchOpen: false,
        foodCategoryFilter: action.filter ? { label: action.filter.label, members: action.filter.members.map(member => ({ ...member })) } : undefined,
      }) : state;
    case "openDetail": return explore(state, { detailId: action.id });
    case "closeDetail": return explore(state, { detailId: undefined });
    case "setProductType": {
      if (state.service !== "grocery") return state;
      const filters = { ...state.exploration.grocery.productTypeFilters };
      if (action.productTypeId) filters[action.subcategoryId] = action.productTypeId;
      else delete filters[action.subcategoryId];
      return explore(state, { productTypeFilters: filters });
    }
    case "openSearch": return explore(state, { searchOpen: true });
    case "typeSearch": return explore(state, { searchDraft: action.query });
    case "submitSearch": {
      const query = state.exploration[state.service].searchDraft.trim();
      return query ? explore({ ...state, section: "home" }, { view: { kind: "search", query }, searchOpen: false, detailId: undefined, checkout: false }) : state;
    }
    case "closeSearch": return explore(state, { searchOpen: false });
    case "takeBucket": return state.service === "grocery" ? { ...state, bucketAcquired: true, bucketPrompt: false } : state;
    case "setGroceryQuantity": {
      if (state.service !== "grocery" || !validQuantity(action.quantity)) return state;
      if (action.quantity > 0 && !state.bucketAcquired) return { ...state, bucketPrompt: true };
      const retail = { ...state.shopping.retail };
      if (action.quantity === 0) delete retail[action.skuId];
      else retail[action.skuId] = action.quantity;
      const next = { ...state, shopping: { ...state.shopping, retail }, bucketPrompt: false };
      return Object.keys(retail).length === 0 ? explore(next, { checkout: false }) : next;
    }
    case "setFoodQuantity": {
      if (state.service !== "food" || !validQuantity(action.line.quantity)) return state;
      const key = foodLineKey(action.line);
      const food = state.shopping.food.filter(line => foodLineKey(line) !== key);
      if (action.line.quantity > 0) food.push({ ...action.line, optionIds: [...action.line.optionIds] });
      const next = { ...state, shopping: { ...state.shopping, food } };
      return food.length === 0 ? explore(next, { checkout: false }) : next;
    }
    case "reviewShopping": {
      const hasItems = state.service === "grocery" ? Object.keys(state.shopping.retail).length > 0 : state.shopping.food.length > 0;
      return hasItems ? explore({ ...state, section: "home" }, { checkout: true, searchOpen: false, detailId: undefined }) : state;
    }
    case "continueShopping": return explore(state, { checkout: false });
    case "checkoutSucceeded": {
      const service = action.service;
      const retail = Object.fromEntries(Object.entries(state.shopping.retail).flatMap(([id, quantity]) => {
        const remaining = quantity - (action.purchased.retail[id] ?? 0);
        return remaining > 0 ? [[id, remaining]] : [];
      }));
      const purchasedFood = new Map(action.purchased.food.map(line => [foodLineKey(line), line.quantity]));
      const food = state.shopping.food.flatMap(line => {
        const quantity = line.quantity - (purchasedFood.get(foodLineKey(line)) ?? 0);
        return quantity > 0 ? [{ ...line, quantity }] : [];
      });
      return {
        ...state, shopping: service === "grocery" ? { ...state.shopping, retail } : { ...state.shopping, food },
        exploration: { ...state.exploration, [service]: home() },
        activeOrder: { id: action.orderId, service }, bucketPrompt: false,
      };
    }
    case "orderUpdated": return { ...state, activeOrder: action.order };
    case "checkoutFailed":
    case "outsideInteraction": return state;
  }
}

function resetHome(state: ReimaginedState): ReimaginedState {
  return { ...state, section: "home", exploration: { ...state.exploration, [state.service]: home() }, bucketPrompt: false };
}

function validQuantity(quantity: number) {
  return Number.isSafeInteger(quantity) && quantity >= 0;
}

function foodLineKey(line: PersistedFoodCartLine) {
  return `${line.branchId}:${foodCartKey(line.itemId, line.optionIds)}`;
}

export function reimaginedEnvironment(state: ReimaginedState): "outside" | "groceryEntrance" | "groceryCounter" | "foodEntrance" | "foodApproachingCounter" | "foodCounter" {
  if (!state.accountId) return "outside";
  if (state.service === "grocery") return state.exploration.grocery.checkout ? "groceryCounter" : "groceryEntrance";
  if (state.exploration.food.checkout) return "foodCounter";
  return state.shopping.food.length ? "foodApproachingCounter" : "foodEntrance";
}
