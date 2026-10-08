import { useEffect, useRef, useState } from "react";
import { getV1Catalogue, type DastakV1Auth, type V1CatalogueSku } from "./dastakV1";
type Entry = { skus?: V1CatalogueSku[]; error?: unknown; loading?: boolean; receivedAt?: number };
type Cache = { owner: string; entries: Map<string, Entry>; facts: Map<string, V1CatalogueSku> };
type Resource = { owner: string; entries: Map<string, Entry>; facts: V1CatalogueSku[] };
// Canonical aliases/identifiers stay server-side. Typing affects only suggestions;
// results remain keyed to the explicit submission. Eight owned queries maximum.
export function useReimaginedGrocerySearch(session: DastakV1Auth & { accountId: string }, draft: string, submitted: string, searchOpen: boolean, enabled: boolean, online: boolean, loader = getV1Catalogue) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const owner = JSON.stringify([accountId, accessToken, supabaseUrl, publishableKey]);
  const draftQuery = draft.trim(), submittedQuery = submitted.trim();
  const query = searchOpen ? draftQuery : submittedQuery;
  const cache = useRef<Cache>({ owner, entries: new Map(), facts: new Map() });
  const [resource, setResource] = useState<Resource>();
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    if (cache.current.owner !== owner) cache.current = { owner, entries: new Map(), facts: new Map() };
    const previous = cache.current.entries.get(query);
    if (!enabled || !online || !query || (previous?.skus && Date.now() - (previous.receivedAt ?? 0) < 60000)) return;
    const controller = new AbortController(), store = cache.current;
    const publish = (entry: Entry) => {
      if (controller.signal.aborted) return;
      store.entries.set(query, entry);
      // Keep canonical facts for products already encountered, even if an old
      // query is evicted. Never orphan an added SKU by changing search terms.
      for (const sku of entry.skus ?? []) store.facts.set(sku.id, sku);
      while (store.entries.size > 8) {
        const victim = [...store.entries.keys()].find(key => key !== submittedQuery && key !== query);
        if (!victim) break; store.entries.delete(victim);
      }
      setResource({ owner, entries: new Map(store.entries), facts: [...store.facts.values()] });
    };
    const timer = window.setTimeout(() => {
      void (async () => {
        publish({ loading: true });
        try {
          if (query.length > 80) throw new Error("Use 80 characters or fewer for Grocery search.");
          const first = await loader({ accessToken, supabaseUrl, publishableKey, query, limit: 250, signal: controller.signal });
          const skus = new Map(first.skus.map(sku => [sku.id, sku]));
          const cursors = new Set<string>(); let cursor = first.nextCursor;
          while (cursor) {
            if (controller.signal.aborted) return;
            const key = JSON.stringify(cursor);
            if (cursors.has(key) || cursors.size >= 100) throw new Error("Search could not load completely. Try again.");
            cursors.add(key);
            const page = await loader({ accessToken, supabaseUrl, publishableKey, query, limit: 250, cursor, signal: controller.signal });
            if (page.catalogueVersion !== first.catalogueVersion) throw new Error("Catalogue changed during search. Try again.");
            for (const sku of page.skus) skus.set(sku.id, sku); cursor = page.nextCursor;
          }
          publish({ skus: [...skus.values()], receivedAt: Date.now() });
        } catch (error) { publish({ error }); }
      })();
    }, searchOpen && query !== submittedQuery ? 300 : 0);
    return () => { controller.abort(); window.clearTimeout(timer); };
  }, [owner, accessToken, supabaseUrl, publishableKey, query, submittedQuery, searchOpen, enabled, online, loader, revision]);
  const current = resource?.owner === owner ? resource.entries : undefined;
  return { suggestions: current?.get(draftQuery)?.skus, results: current?.get(submittedQuery)?.skus,
    facts: resource?.owner === owner ? resource.facts : undefined,
    error: current?.get(query)?.error,
    resultsError: current?.get(submittedQuery)?.error ?? (!online && submittedQuery && !current?.get(submittedQuery)?.skus ? "offline" : undefined),
    resultsLoading: Boolean(enabled && online && submittedQuery && !current?.get(submittedQuery)?.skus && !current?.get(submittedQuery)?.error),
    loading: Boolean(enabled && online && searchOpen && query && !current?.get(query)?.skus && !current?.get(query)?.error),
    retry: (selectedQuery = query) => { if (cache.current.owner === owner) cache.current.entries.delete(selectedQuery); setRevision(value => value + 1); } };
}
