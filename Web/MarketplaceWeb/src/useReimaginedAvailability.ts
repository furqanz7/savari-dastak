import { useEffect, useState } from "react";
import { getV1AreaAvailability, type DastakV1Auth, type V1AreaAvailability, type V1RestaurantLocation } from "./dastakV1";

// One sparse inventory snapshot per selected location, never one request per product.
// Expired, failed, offline, changed-address and changed-session snapshots fail closed.
export function useReimaginedAvailability(session: DastakV1Auth & { accountId: string }, location: V1RestaurantLocation | undefined, online: boolean, loader = getV1AreaAvailability) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const addressId = location?.addressId, updatedAt = location?.updatedAt;
  const key = JSON.stringify([accountId, accessToken, supabaseUrl, publishableKey, addressId, updatedAt]);
  const [resource, setResource] = useState<{ key: string; data?: V1AreaAvailability; error?: unknown }>();
  const [revision, setRevision] = useState(0);
  const [now, setNow] = useState(Date.now);
  const [received, setReceived] = useState(0);
  useEffect(() => {
    if (!addressId || !updatedAt || !online) return;
    const controller = new AbortController();
    loader({ accessToken, supabaseUrl, publishableKey, location: { addressId, updatedAt }, signal: controller.signal }).then(data => {
      if (!controller.signal.aborted) { setResource({ key, data }); setReceived(Date.now()); setNow(Date.now()); }
    }).catch((error: unknown) => { if (!controller.signal.aborted) setResource({ key, error }); });
    return () => { controller.abort(); };
  }, [key, addressId, updatedAt, accessToken, supabaseUrl, publishableKey, online, revision, loader]);
  useEffect(() => () => { setResource(current => current?.key === key ? undefined : current); }, [key, online]);
  useEffect(() => {
    if (!online || !addressId) return;
    const refresh = () => { setNow(Date.now()); if (!document.hidden) setRevision(value => value + 1); };
    const timer = window.setInterval(refresh, 30000);
    document.addEventListener("visibilitychange", refresh);
    return () => { window.clearInterval(timer); document.removeEventListener("visibilitychange", refresh); };
  }, [online, addressId]);
  const current = online && resource?.key === key ? resource : undefined;
  const data = current?.data && now - received < 45000 ? current.data : undefined;
  return { data, error: current?.error, status: !location ? "location_required" as const : data ? "ready" as const : current?.error || !online ? "unavailable" as const : "loading" as const,
    retry: () => { setResource(undefined); setRevision(value => value + 1); } };
}
