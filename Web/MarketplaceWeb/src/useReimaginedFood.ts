import { useEffect, useRef, useState } from "react";
import { getV1Restaurants, type DastakV1Auth, type V1RestaurantMenu } from "./dastakV1";
import { prepareFoodMenus } from "./reimaginedFoodCatalogue";

type Session = DastakV1Auth & { accountId: string };
type Resource = { owner: string; revision: number; data?: V1RestaurantMenu[]; error?: unknown };

// One bounded read on Food entry, cached in memory for this session. No per-keystroke calls.
export function useReimaginedFood(session: Session, enabled: boolean, online: boolean, loader = getV1Restaurants) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const owner = JSON.stringify([accountId, accessToken, supabaseUrl, publishableKey]);
  const [revision, setRevision] = useState(0);
  const [resource, setResource] = useState<Resource>();
  const cache = useRef<Resource | undefined>(undefined);
  useEffect(() => {
    if (!enabled || !online || (cache.current?.owner === owner && cache.current.revision === revision && cache.current.data)) return;
    const controller = new AbortController();
    loader({ accessToken, supabaseUrl, publishableKey, limit: 100, signal: controller.signal }).then(menus => {
      if (controller.signal.aborted) return;
      const next = { owner, revision, data: prepareFoodMenus(menus) };
      cache.current = next; setResource(next);
    }).catch((error: unknown) => { if (!controller.signal.aborted) setResource({ owner, revision, error }); });
    return () => controller.abort();
  }, [enabled, online, owner, revision, accessToken, supabaseUrl, publishableKey, loader]);
  const current = resource?.owner === owner && resource.revision === revision ? resource : undefined;
  return {
    data: current?.data, error: current?.error,
    status: current?.data ? "ready" as const : current?.error || !online ? "unavailable" as const : enabled ? "loading" as const : "idle" as const,
    retry: () => setRevision(value => value + 1),
  };
}
