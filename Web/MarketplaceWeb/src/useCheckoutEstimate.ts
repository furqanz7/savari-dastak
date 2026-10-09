import { useEffect, useState } from "react";
import { getV1CheckoutQuote, type DastakV1Auth, type V1CheckoutQuote, type V1OrderSubmission, type V1RestaurantLocation } from "./dastakV1";

export function useCheckoutEstimate(auth: DastakV1Auth | undefined, location: V1RestaurantLocation | undefined,
  lines: V1OrderSubmission["lines"], restaurantBranchId: string | undefined, online: boolean, enabled: boolean,
  loader = getV1CheckoutQuote) {
  const accessToken = auth?.accessToken, supabaseUrl = auth?.supabaseUrl, publishableKey = auth?.publishableKey;
  const addressId = location?.addressId, updatedAt = location?.updatedAt;
  const basket = JSON.stringify(lines);
  const key = JSON.stringify([accessToken, supabaseUrl, publishableKey, addressId, updatedAt, basket, restaurantBranchId]);
  const [result, setResult] = useState<{ key: string; data?: V1CheckoutQuote; expiresAt?: number; error?: boolean }>();
  const [revision, setRevision] = useState(0);
  const [now, setNow] = useState(Date.now);
  const ready = Boolean(enabled && online && accessToken && supabaseUrl && publishableKey && addressId && updatedAt && lines.length);
  useEffect(() => {
    if (!ready || !accessToken || !supabaseUrl || !publishableKey || !addressId || !updatedAt) return;
    setResult(undefined);
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      loader({ accessToken, supabaseUrl, publishableKey, location: { addressId, updatedAt },
        lines: JSON.parse(basket) as V1OrderSubmission["lines"], restaurantBranchId, signal: controller.signal })
        .then(data => { if (!controller.signal.aborted) { setNow(Date.now()); setResult({ key, data, expiresAt: Math.min(Date.now() + 45000, Date.parse(data.validUntil)) }); } })
        .catch(() => { if (!controller.signal.aborted) setResult({ key, error: true }); });
    }, 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [ready, key, basket, restaurantBranchId, accessToken, supabaseUrl, publishableKey, addressId, updatedAt, revision, loader]);
  useEffect(() => {
    if (!ready) return;
    const tick = () => setNow(Date.now());
    const timer = window.setInterval(tick, 1000);
    document.addEventListener("visibilitychange", tick);
    return () => { window.clearInterval(timer); document.removeEventListener("visibilitychange", tick); };
  }, [ready]);
  const current = ready && result?.key === key ? result : undefined;
  const expired = current?.data && Math.max(now, Date.now()) >= (current.expiresAt ?? 0);
  return { data: expired ? undefined : current?.data,
    status: !ready ? "incomplete" : current?.error || expired ? "unavailable" : current?.data ? "ready" : "loading",
    retry: () => { setResult(undefined); setRevision(value => value + 1); } };
}
