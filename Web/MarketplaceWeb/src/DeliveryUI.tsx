/* eslint-disable react-refresh/only-export-components -- pure, tested rider presentation helpers accompany their components. */
import { memo, useEffect, useState, type ReactNode } from "react";
import { ArrowRight, Check, CircleAlert, Crosshair, History, MapPin, Navigation, Radio, ShieldCheck, UserRound, WalletCards } from "lucide-react";
import type { V1DeliveryMission, V1ReturnMission, V1PickupStop } from "./delivery";
import { classifyPositionFix, type DeliveryGeolocationStatus, type PositionFix } from "./deliveryGeolocation";
import type { OrderRealtimeHealth } from "./orderRealtime";

export type DeliverySection = "deliveries" | "history" | "royalty" | "account";
const sections: Array<{ key: DeliverySection; label: string; icon: ReactNode }> = [
  { key: "deliveries", label: "Deliveries", icon: <Navigation size={21} /> },
  { key: "history", label: "History", icon: <History size={21} /> },
  { key: "royalty", label: "Earnings", icon: <WalletCards size={21} /> },
  { key: "account", label: "Account", icon: <UserRound size={21} /> },
];

export function DeliveryNavigation({ section, onChange }: { section: DeliverySection; onChange: (section: DeliverySection) => void }) {
  return <nav className="delivery-navigation" aria-label="Delivery Partner">
    {sections.map((item) => <button type="button" key={item.key} aria-current={section === item.key ? "page" : undefined} onClick={() => onChange(item.key)}>{item.icon}<span>{item.label}</span></button>)}
  </nav>;
}

export function MissionProgress({ step, returning = false }: { step: number; returning?: boolean }) {
  const labels = returning ? ["Collect", "Return", "Receipt"] : ["Pickup", "Route", "Handoff"];
  return <ol className="rider-progress" aria-label={returning ? "Return progress" : "Delivery progress"}>
    {labels.map((label, index) => <li key={label} className={index < step ? "complete" : ""} aria-current={index === step ? "step" : undefined}><span aria-hidden="true">{index < step ? <Check size={14} /> : index + 1}</span><strong>{label}</strong></li>)}
  </ol>;
}

export function missionNextStep(mission: V1DeliveryMission): { title: string; detail: string; step: number } {
  if (mission.status === "DELIVERY_RECOVERY") return { title: "Keep every package secure", detail: "Operations is arranging recovery. Custody stays with you until a verified handoff.", step: 2 };
  if (mission.status === "ASSIGNED") return { title: "Start your pickup route", detail: "Review the pickup stops below, then start pickups when you’re ready to leave.", step: 0 };
  if (mission.status === "EN_ROUTE_TO_PICKUPS" || mission.status === "PICKUP_IN_PROGRESS") {
    const stop = mission.pickupStops.find((item) => item.status !== "COMPLETED");
    return { title: stop?.status === "ARRIVED" ? stop.ready ? "Verify every package" : "Wait for packages to be ready" : `Head to ${stop?.branch.displayName ?? "your pickup"}`, detail: stop?.status === "ARRIVED" ? stop.ready ? "Account for every package and ask the merchant for the pickup code." : "The merchant is still preparing. Pickup verification opens when all packages are ready." : "Open the merchant route. Confirm arrival when your location is verified within 50 metres.", step: 0 };
  }
  if (mission.canStartFinalDelivery) return { title: "Start the customer route", detail: "All pickups are verified. Keep the packages together for the customer handoff.", step: 1 };
  if (mission.status === "OUT_FOR_DELIVERY") return { title: "Head to the customer", detail: "Open the route below. Confirm arrival within 50 metres of the destination.", step: 1 };
  if (mission.canCompleteDelivery) return { title: "Complete the delivery", detail: "Required checks are complete. Hand over every package and confirm delivery.", step: 2 };
  if (mission.finalVerification?.status === "BLOCKED") return { title: "Verification needs help", detail: "Keep all packages secure and contact Operations using the help actions below.", step: 2 };
  if (mission.canVerifyCustomerPIN) return { title: "You’ve arrived · verify the PIN", detail: "Ask the recipient for the six-digit delivery PIN before continuing.", step: 2 };
  if (mission.canCaptureDeliveryEvidence && !mission.finalVerification?.evidencePresent) return { title: "Take the package photo", detail: "The PIN is verified. Capture a clear photo of the complete delivery.", step: 2 };
  if (mission.launchCollection?.canRecord) return { title: "Collect payment at the door", detail: "Confirm the full amount has reached you by cash or UPI before recording it.", step: 2 };
  return { title: mission.status === "ARRIVED" ? "You’ve arrived" : "Continue your delivery", detail: "Follow the available action below. Each handoff check unlocks the next step.", step: mission.status === "ARRIVED" ? 2 : 1 };
}

export function MissionNextStep({ title, detail }: { title: string; detail: string }) {
  return <div className="rider-next-step" aria-label="Next required action"><span className="eyebrow">Up next</span><h3>{title}</h3><p>{detail}</p></div>;
}

export function HandoffProgress({ mission }: { mission: V1DeliveryMission }) {
  const arrived = mission.status === "ARRIVED" || Boolean(mission.arrivedCustomerAt);
  const pin = Boolean(mission.finalVerification?.pinVerified);
  const photo = Boolean(mission.finalVerification?.evidencePresent);
  const paid = !mission.launchCollection?.required || mission.launchCollection.state === "PAYMENT_COLLECTED";
  const steps = [
    { label: "Arrive", done: arrived }, { label: "PIN", done: pin },
    { label: "Photo", done: photo }, { label: "Payment", done: photo && paid }, { label: "Complete", done: false },
  ];
  const next = steps.findIndex((step) => !step.done);
  return <ol className="rider-handoff-progress" aria-label="Customer handoff sequence">{steps.map((step, index) => <li key={step.label} className={step.done ? "complete" : ""} aria-current={index === next ? "step" : undefined}><span aria-hidden="true">{step.done ? <Check size={13} /> : index + 1}</span>{step.label}<span className="customer-sr-only">{step.done ? ", completed" : index === next ? ", next" : ", locked"}</span></li>)}</ol>;
}

export type RiderDestination = { name: string; address: string; label: string; location: { latitude: number; longitude: number } | null };
export function missionDestination(mission: V1DeliveryMission | null, returning: V1ReturnMission | null): RiderDestination | undefined {
  if (returning) {
    if (returning.status !== "RETURNING_TO_MERCHANTS") return { name: returning.customerDestination.recipientName ?? "Return customer", address: returning.customerDestination.address, location: returning.customerDestination.location, label: "Return pickup" };
    const stop = returning.stops.find((item) => item.status !== "COMPLETED");
    return stop ? { name: stop.branch.displayName, address: stop.branch.address, location: stop.branch.location, label: `Return stop ${stop.sequence}` } : undefined;
  }
  if (!mission) return undefined;
  if (["ALL_PACKAGES_PICKED_UP", "OUT_FOR_DELIVERY", "ARRIVED", "DELIVERY_RECOVERY"].includes(mission.status) && mission.customerDestination) return { name: mission.customerDestination.recipientName ?? "Customer", address: mission.customerDestination.address, location: mission.customerDestination.location, label: "Customer destination" };
  const stop = mission.pickupStops.find((item) => item.status !== "COMPLETED");
  return stop ? { name: stop.branch.displayName, address: stop.branch.address, location: stop.branch.location, label: `Pickup ${stop.sequence} of ${mission.pickupCount}` } : undefined;
}

export function usePresentedGPS(gps: DeliveryGeolocationStatus, peekLocation: () => PositionFix | undefined) {
  const [now, setNow] = useState(Date.now);
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 5_000); return () => window.clearInterval(timer); }, []);
  const fix = peekLocation();
  return gps === "tracking" && fix ? classifyPositionFix(fix, now) : gps;
}

export function DeliveryHealthBadges({ gps, realtime, peekLocation }: { gps: DeliveryGeolocationStatus; realtime: OrderRealtimeHealth; peekLocation: () => PositionFix | undefined }) {
  const effectiveGPS = usePresentedGPS(gps, peekLocation);
  const offline = typeof navigator !== "undefined" && navigator.onLine === false;
  return <div className="rider-health-badges" aria-label="Connection and location status">
    <span className={!offline && realtime === "subscribed" ? "good" : "warning"}><Radio size={14} />{offline ? "Offline · updates paused" : realtime === "subscribed" ? "Updates connected" : realtime === "connecting" ? "Connecting updates" : "Updates reconnecting"}</span>
    <span className={effectiveGPS === "tracking" ? "good" : effectiveGPS === "idle" ? "" : "warning"}><Crosshair size={14} />{gpsLabel(effectiveGPS)}</span>
  </div>;
}

function gpsLabel(status: DeliveryGeolocationStatus) {
  switch (status) {
    case "tracking": return "GPS live · foreground";
    case "stale": return "GPS stale";
    case "inaccurate": return "GPS imprecise";
    case "background_limited": return "Tracking suspended";
    case "permission_denied": return "Location blocked";
    case "unavailable": return "Location unavailable";
    case "interrupted": return "GPS reconnecting";
    case "starting": return "Finding location";
    default: return "Tracking inactive";
  }
}

/** Presentation-only freshness clock reading the existing controller. No GPS or network ownership. */
export function DeliveryRouteContext({ destination, peekLocation, gps, children }: {
  destination?: RiderDestination; peekLocation: () => PositionFix | undefined; gps: DeliveryGeolocationStatus; children?: ReactNode;
}) {
  const [now, setNow] = useState(Date.now);
  const [showRider, setShowRider] = useState(false);
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 5_000); return () => window.clearInterval(timer); }, []);
  const fix = peekLocation();
  const fresh = fix && classifyPositionFix(fix, now) === "tracking" && gps === "tracking";
  // Snap map presentation to roughly 11 m. Raw fixes never reach the workspace.
  const location = showRider && fix ? { latitude: Number(fix.latitude.toFixed(4)), longitude: Number(fix.longitude.toFixed(4)) } : destination?.location;
  return <aside className="rider-route-context" aria-label="Route and tracking">
    {destination ? <section className="rider-route-card">
      <header><span className="eyebrow">{destination.label}</span><MapPin size={20} aria-hidden="true" /></header>
      <h2>{destination.name}</h2><p>{destination.address}</p>
      {location ? <RiderMap latitude={location.latitude} longitude={location.longitude} label={showRider ? "Your last GPS position" : destination.name} /> : <div className="rider-map-unavailable"><MapPin size={24} /><p>Map position unavailable. Follow the destination details above.</p></div>}
      {fix ? <div className="rider-map-controls" role="group" aria-label="Map focus"><button type="button" aria-pressed={!showRider} onClick={() => setShowRider(false)}>Destination</button><button type="button" aria-pressed={showRider} onClick={() => setShowRider(true)}><Crosshair size={15} />{fresh ? "My position" : "Last position"}</button></div> : null}
      {showRider ? <p className={`rider-map-freshness ${fresh ? "" : "warning"}`} role="status">{fresh ? "Live GPS · foreground tracking" : "Last-known GPS · not live"}{fix ? ` · ±${Math.ceil(fix.accuracyMeters)} m` : ""}</p> : null}
      {destination.location ? <a className="secondary-button rider-directions" href={directionsURL(destination.location)} target="_blank" rel="noreferrer"><Navigation size={18} /> Open directions <ArrowRight size={16} /></a> : null}
    </section> : <section className="rider-route-card rider-readiness"><ShieldCheck size={28} /><h2>Ready for the road</h2><p>Your destination and route appear here as soon as work is assigned.</p><ul><li>Allow precise location</li><li>Keep this tab visible during deliveries</li><li>Verify every package at handoff</li></ul></section>}
    {children}
  </aside>;
}

const RiderMap = memo(function RiderMap({ latitude, longitude, label }: { latitude: number; longitude: number; label: string }) {
  const bbox = [longitude - .006, latitude - .004, longitude + .006, latitude + .004].join(",");
  const source = `https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent(bbox)}&layer=mapnik&marker=${latitude}%2C${longitude}`;
  return <div className="rider-map"><iframe title={`Map: ${label}`} src={source} loading="lazy" referrerPolicy="no-referrer" /><small>Map context · open directions for navigation</small></div>;
});

export function directionsURL(location: { latitude: number; longitude: number }) {
  return `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(`${location.latitude},${location.longitude}`)}&travelmode=driving`;
}

export function PickupStatus({ stop }: { stop: V1PickupStop }) {
  const completed = stop.status === "COMPLETED";
  return <em className={completed || stop.ready ? "good" : stop.runningLate ? "warning" : ""}>{completed ? <Check size={14} /> : stop.runningLate ? <CircleAlert size={14} /> : null}{completed ? "Picked up" : stop.ready ? "Packages ready" : stop.runningLate ? "Preparing · delayed" : "Preparing"}</em>;
}
