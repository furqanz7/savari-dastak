import { describe, expect, it } from "vitest";
import { readReimaginedHistory, reimaginedLink, reimaginedNavigationHash } from "./useReimaginedNavigation";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";

describe("Reimagined links and navigation-only history", () => {
  it("round-trips Food searches and handles blank/unknown links safely", () => {
    const search = reimaginedLink("#/search?service=food&q=tea+%26+coffee");
    expect(search.exploration.view).toEqual({ kind: "search", query: "tea & coffee" });
    expect(reimaginedLink(reimaginedNavigationHash(search))).toEqual(search);
    expect(reimaginedLink("#/search").exploration.searchOpen).toBe(true);
    expect(reimaginedLink("#/unknown").section).toBe("home");
    expect(reimaginedLink("#/orders/not-a-uuid").orderId).toBeUndefined();
  });
  it("rejects foreign-account, malformed and stale-hash history; strips non-navigation data", () => {
    const navigation = reimaginedLink("#/wishlist");
    const entry = { version: 1, owner: "a", hash: "#/wishlist", navigation: { ...navigation, shopping: { retail: { injected: 99 } }, accessToken: "not-a-real-token" } };
    expect(readReimaginedHistory({ dastakReimaginedNavigation: entry }, "a", "#/wishlist")).toEqual(navigation);
    expect(readReimaginedHistory({ dastakReimaginedNavigation: entry }, "b", "#/wishlist")).toBeUndefined();
    expect(readReimaginedHistory({ dastakReimaginedNavigation: entry }, "a", "#/search")).toBeUndefined();
    expect(readReimaginedHistory({ dastakReimaginedNavigation: { ...entry, navigation: { ...navigation, service: "parcel" } } }, "a", "#/wishlist")).toBeUndefined();
    expect(readReimaginedHistory({ dastakReimaginedNavigation: { ...entry, navigation: { ...navigation, exploration: { ...navigation.exploration, view: { kind: "search", query: {} } } } } }, "a", "#/wishlist")).toBeUndefined();
  });
  it("restores navigation without resurrecting an empty checkout or changing shopping/order state", () => {
    let state = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "a" });
    state = reimaginedReducer(state, { type: "openDetail", id: "old-detail" });
    state = reimaginedReducer(state, { type: "orderUpdated", order: { id: "current-order", service: "food" } });
    const navigation = reimaginedLink("#/home"); navigation.exploration.checkout = true;
    const restored = reimaginedReducer(state, { type: "restoreNavigation", navigation });
    expect(restored.shopping).toBe(state.shopping); expect(restored.activeOrder).toBe(state.activeOrder);
    expect(restored.exploration.grocery.checkout).toBe(false); expect(restored.exploration.grocery.detailId).toBeUndefined();
  });
});
