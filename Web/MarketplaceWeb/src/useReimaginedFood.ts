import { useEffect, useRef, useState } from "react";
import { getV1RestaurantPage, type DastakV1Auth, type V1RestaurantCursor, type V1RestaurantLocation, type V1RestaurantMenu } from "./dastakV1";
import { nearestFoodMenus, prepareFoodMenus } from "./reimaginedFoodCatalogue";

type Session = DastakV1Auth & { accountId: string };
type Page = { ids: string[]; cursor?: V1RestaurantCursor; seen: Set<string> };
type Cache = { owner: string; revision: number; menus: Map<string, V1RestaurantMenu>; pages: Map<string, Page> };
type Resource = { owner: string; revision: number; query: string; data?: V1RestaurantMenu[]; searchData?: V1RestaurantMenu[]; cursor?: V1RestaurantCursor; error?: unknown; loadingMore?: boolean };
export type ReimaginedFoodResource = {
  data?: V1RestaurantMenu[]; error?: unknown; status: "ready" | "unavailable" | "loading" | "idle"; retry: () => void;
  searchData?: V1RestaurantMenu[]; hasMore?: boolean; loadingMore?: boolean; loadMore?: () => Promise<void>;
  findRestaurant?: (branchId: string) => Promise<V1RestaurantMenu | undefined>;
  nearest?: boolean;
};

// Bounded pages on explicit entry/search/load-more, never per keystroke.
export function useReimaginedFood(session: Session, enabled: boolean, online: boolean, loader = getV1RestaurantPage, submittedQuery = "", location?: V1RestaurantLocation): ReimaginedFoodResource {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const owner = JSON.stringify([accountId, accessToken, supabaseUrl, publishableKey, location?.addressId, location?.updatedAt]);
  const query = submittedQuery.trim();
  const [revision, setRevision] = useState(0);
  const [resource, setResource] = useState<Resource>();
  const cache = useRef<Cache | undefined>(undefined);
  const epoch = useRef(0);
  const request = useRef<AbortController | undefined>(undefined);
  const lookups = useRef(new Set<AbortController>());
  function publish(store: Cache, page: Page, error?: unknown, loadingMore = false) {
    const menus = [...store.menus.values()];
    setResource({ owner, revision, query, data: location ? nearestFoodMenus(menus) : menus, searchData: page.ids.map(id => store.menus.get(id)!), cursor: page.cursor, error, loadingMore });
  }
  async function fetchPage(store: Cache, cursor?: V1RestaurantCursor) {
    const generation = epoch.current; const controller = new AbortController(); request.current = controller;
    const previous = store.pages.get(query);
    if (cursor && previous) publish(store, previous, undefined, true);
    try {
      if (query.length > 80) throw new Error("Use a Food search of 80 characters or fewer.");
      const result = await loader({ accessToken, supabaseUrl, publishableKey, limit: 100, query: query || undefined, cursor, location, signal: controller.signal });
      if (generation !== epoch.current || controller.signal.aborted) return;
      if (location && result.ordering !== "NEAREST") throw new Error("Nearest restaurants could not be verified. Refresh your location and Food menus.");
      const menus = prepareFoodMenus(result.restaurants);
      const nextKey = result.nextCursor ? JSON.stringify(result.nextCursor) : undefined;
      if (nextKey && (nextKey === JSON.stringify(cursor) || previous?.seen.has(nextKey))) throw new Error("Food pagination did not advance. Loaded menus are retained.");
      for (const menu of menus) store.menus.set(menu.restaurant.branchId, menu);
      const page: Page = { ids: [...new Set([...(cursor ? previous?.ids ?? [] : []), ...menus.map(menu => menu.restaurant.branchId)])], cursor: result.nextCursor, seen: new Set(cursor ? previous?.seen : []) };
      if (nextKey) page.seen.add(nextKey);
      store.pages.set(query, page); publish(store, page);
    } catch (error) {
      if (generation === epoch.current && !controller.signal.aborted) {
        if (previous) publish(store, previous, error);
        else {
          const menus = [...store.menus.values()];
          setResource({ owner, revision, query, data: menus.length ? location ? nearestFoodMenus(menus) : menus : undefined, error });
        }
      }
    } finally { if (request.current === controller) request.current = undefined; }
  }
  useEffect(() => {
    const generation = ++epoch.current; request.current?.abort();
    for (const controller of lookups.current) controller.abort();
    if (!enabled || !online) return;
    if (!cache.current || cache.current.owner !== owner || cache.current.revision !== revision) cache.current = { owner, revision, menus: new Map(), pages: new Map() };
    const store = cache.current; const saved = store.pages.get(query);
    if (saved) publish(store, saved); else void fetchPage(store);
    const pendingLookups = lookups.current;
    return () => { epoch.current = generation + 1; request.current?.abort(); for (const controller of pendingLookups) controller.abort(); };
    // Reads and explicit actions share this account/query cancellation boundary.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, online, owner, revision, query, loader]);
  const current = resource?.owner === owner && resource.revision === revision ? resource : undefined;
  const scoped = current?.query === query ? current : undefined;
  async function findRestaurant(branchId: string) {
    const store = cache.current;
    if (!enabled || !online || !store || store.owner !== owner || store.revision !== revision) return undefined;
    const cached = store.menus.get(branchId); if (cached) return cached;
    const generation = epoch.current;
    const controller = new AbortController(); lookups.current.add(controller);
    try {
      const result = await loader({ accessToken, supabaseUrl, publishableKey, branchId, limit: 1, signal: controller.signal });
      if (generation !== epoch.current || controller.signal.aborted) throw new DOMException("Food session changed", "AbortError");
      const menu = prepareFoodMenus(result.restaurants).find(value => value.restaurant.branchId === branchId);
      if (menu) { store.menus.set(branchId, menu); const page = store.pages.get(query); if (page) publish(store, page); }
      return menu;
    } finally { lookups.current.delete(controller); }
  }
  return {
    data: current?.data, searchData: scoped?.searchData, error: scoped?.error,
    status: scoped?.data ? "ready" : scoped?.error || !online ? "unavailable" : enabled ? "loading" : "idle",
    hasMore: Boolean(scoped?.cursor), loadingMore: scoped?.loadingMore,
    loadMore: async () => { if (online && enabled && scoped?.cursor && cache.current && !request.current) await fetchPage(cache.current, scoped.cursor); },
    findRestaurant, retry: () => setRevision(value => value + 1),
    nearest: Boolean(location && current?.data),
  };
}
