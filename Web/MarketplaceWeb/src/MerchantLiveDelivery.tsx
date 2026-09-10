import { memo, useEffect, useMemo, useState } from "react";
import { Navigation, UserRound } from "lucide-react";
import type { V1MerchantFulfilment } from "./dastakV1";
import { CustomerRouteMap, type CustomerMapPoint } from "./CustomerDeliveryDetails";
import { deliveryTrackingFreshness } from "./customerDeliveryPresentation";
import { useCustomerOnline } from "./useCustomerOnline";

const TrackingMap = memo(CustomerRouteMap);

const phaseLabels: Record<string, string> = {
  ASSIGNED: "Rider assigned",
  EN_ROUTE_TO_PICKUPS: "Rider heading to pickup",
  PICKUP_IN_PROGRESS: "Pickup in progress",
  ALL_PACKAGES_PICKED_UP: "Every package collected",
  OUT_FOR_DELIVERY: "Rider heading to the customer",
  ARRIVED: "Rider at the customer destination",
  DELIVERY_RECOVERY: "Delivery needs assistance",
};

export function MerchantLiveDelivery({ fulfilment, delayed = false }: {
  fulfilment: V1MerchantFulfilment;
  delayed?: boolean;
}) {
  const online = useCustomerOnline();
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);
  const tracking = fulfilment.tracking;
  const presentation = deliveryTrackingFreshness(tracking, now, online && !delayed);
  const points = useMemo<CustomerMapPoint[]>(() => presentation.location ? [{
    label: tracking?.riderName ?? "Delivery partner",
    address: "Last reported rider position",
    ...presentation.location,
    kind: "courier" as const,
  }] : [], [presentation.location, tracking?.riderName]);
  if (!tracking) return null;
  const timestamp = presentation.recordedAt ? Date.parse(presentation.recordedAt) : NaN;
  const ageSeconds = Number.isFinite(timestamp) ? Math.max(0, Math.floor((now - timestamp) / 1_000)) : undefined;
  const age = ageSeconds === undefined ? undefined : ageSeconds < 60 ? "just now" : `${Math.floor(ageSeconds / 60)} min ago`;
  return <section className={`v1-merchant-tracking${presentation.live ? "" : " delayed"}`} aria-label="Rider tracking">
    <header>
      <span><UserRound size={20} /></span>
      <div><strong>{tracking.riderName}</strong><small>{phaseLabels[tracking.phase] ?? "Delivery in progress"}</small></div>
      <b><Navigation size={13} /> {presentation.live ? "Live" : "Delayed"}</b>
    </header>
    {points.length ? <TrackingMap points={points} routeOverlay={false} /> : null}
    <p><strong>{presentation.freshness}</strong>{age ? <small>Updated {age}</small> : null}</p>
  </section>;
}
