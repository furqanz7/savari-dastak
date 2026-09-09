import { memo, useEffect, useMemo, useState } from "react";
import { UserRound } from "lucide-react";
import type { V1Order } from "./dastakV1";
import { CustomerRouteMap, type CustomerMapPoint } from "./CustomerDeliveryDetails";
import { customerTrackingPresentation } from "./customerDeliveryPresentation";
import { useCustomerOnline } from "./useCustomerOnline";

const TrackingMap = memo(CustomerRouteMap);

/** Local freshness clock; no request, subscription, or order-screen refresh ownership. */
export function CustomerLiveDelivery({ order, delayed = false }: { order: V1Order; delayed?: boolean }) {
  const online = useCustomerOnline();
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);
  const tracking = customerTrackingPresentation(order, now, online && !delayed);
  const location = tracking?.location;
  const destination = order.deliveryAddress;
  const points = useMemo<CustomerMapPoint[]>(() => [
    ...(destination ? [{ label: destination.label ?? "Delivery destination", address: destination.line1, latitude: destination.latitude, longitude: destination.longitude, kind: "dropoff" as const }] : []),
    ...(location ? [{ label: "Your delivery partner", address: "Last reported position", ...location, kind: "courier" as const }] : []),
  ], [destination, location]);
  if (!tracking) return null;
  const timestamp = tracking.recordedAt ? Date.parse(tracking.recordedAt) : NaN;
  const ageSeconds = Math.max(0, Math.floor((now - timestamp) / 1_000));
  const age = ageSeconds < 60 ? "just now" : `${Math.floor(ageSeconds / 60)} min ago`;
  return <section className={`v1-live-delivery${tracking.live ? "" : " delayed"}`} aria-label="Delivery tracking">
    <header><span className="customer-rider-avatar"><UserRound size={24} /></span><div><h3>{tracking.riderName}</h3><span>{tracking.phase}</span></div><p className="customer-tracking-badge"><i />{tracking.live ? "Live" : "Delayed"}</p></header>
    {points.length ? <TrackingMap points={points} routeOverlay={false} /> : null}
    <div className="customer-tracking-freshness"><strong>{!online ? "You’re offline · last-known information" : tracking.freshness}</strong>{!tracking.live ? <p>{!online ? "Updates will resume when you reconnect." : "We’ll update the map when a fresh, precise location arrives."}</p> : null}{Number.isFinite(timestamp) ? <small>Location updated {age}</small> : null}</div>
  </section>;
}
