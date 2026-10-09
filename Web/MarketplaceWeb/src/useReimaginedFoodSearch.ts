import { useEffect, useRef, useState } from "react";
import { getV1RestaurantPage, type DastakV1Auth, type V1RestaurantLocation, type V1RestaurantMenu } from "./dastakV1";
import { prepareFoodMenus } from "./reimaginedFoodCatalogue";

type Entry = { menus?: V1RestaurantMenu[]; more?: boolean; error?: unknown; checkedAt: number };
type Resource = { owner: string; entries: Map<string, Entry> };
const TTL = 60_000;

// One bounded regional page after a typing pause; never paginate on keystrokes.
// Full results keep using the explicit Submit / Load more discovery resource.
export function useReimaginedFoodSearch(session: DastakV1Auth & { accountId: string }, draft: string,
  enabled: boolean, online: boolean, location?: V1RestaurantLocation, loader = getV1RestaurantPage) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const owner = JSON.stringify([accountId, accessToken, supabaseUrl, publishableKey, location?.addressId, location?.updatedAt]);
  const query = draft.trim();
  const [resource, setResource] = useState<Resource>();
  const [revision, setRevision] = useState(0);
  const cache = useRef<Resource | undefined>(undefined);
  const current = resource?.owner === owner ? resource.entries.get(query) : undefined;
  const fresh = Boolean(current?.menus && Date.now() - current.checkedAt < TTL);
  useEffect(() => {
    if (cache.current?.owner !== owner) cache.current = { owner, entries: new Map() };
    if (!enabled || !online || !location || !query || fresh) return;
    const store = cache.current;
    const controller = new AbortController();
    function publish(entry: Entry) {
      if (controller.signal.aborted) return;
      store.entries.delete(query); store.entries.set(query, entry);
      while (store.entries.size > 8) store.entries.delete(store.entries.keys().next().value!);
      setResource({ owner, entries: new Map(store.entries) });
    }
    const timer = window.setTimeout(async () => {
      try {
        if (query.length > 80) throw new Error("Use a Food search of 80 characters or fewer.");
        const result = await loader({ accessToken, supabaseUrl, publishableKey, query, limit: 8, location, signal: controller.signal });
        if (controller.signal.aborted) return;
        if (result.ordering !== "NEAREST") throw new Error("Food search location could not be verified.");
        publish({ menus: prepareFoodMenus(result.restaurants), more: Boolean(result.nextCursor), checkedAt: Date.now() });
      } catch (error) { publish({ error, checkedAt: Date.now() }); }
    }, 300);
    return () => { controller.abort(); window.clearTimeout(timer); };
    // Location identity/version are included in owner, not object identity.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [owner, query, enabled, online, fresh, loader, revision]);
  const active = enabled && online && Boolean(location) && Boolean(query);
  return { menus: active && fresh ? current?.menus : undefined, more: active && fresh ? current?.more : false,
    error: active ? current?.error : undefined, loading: active && !fresh && !current?.error,
    retry: () => { cache.current?.entries.delete(query); setResource(undefined); setRevision(value => value + 1); } };
}
