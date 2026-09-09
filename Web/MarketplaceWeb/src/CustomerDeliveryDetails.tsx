import { useState, type FormEvent } from "react";
import { ExternalLink, MapPin, Navigation } from "lucide-react";
import type { CustomerOrderSupportCase, CustomerOrderSupportCategory } from "./orders";

export type CustomerMapPoint = {
  label: string;
  address: string;
  latitude: number;
  longitude: number;
  kind: "pickup" | "dropoff" | "courier";
};

export function CustomerRouteMap({ points, routeOverlay = true }: { points: CustomerMapPoint[]; routeOverlay?: boolean }) {
  const available = points.filter((point) => Number.isFinite(point.latitude) && Number.isFinite(point.longitude));
  if (available.length === 0) return null;
  const focus = available.find((point) => point.kind === "courier") ?? available.find((point) => point.kind === "dropoff") ?? available[0];
  const latitudes = available.map((point) => point.latitude);
  const longitudes = available.map((point) => point.longitude);
  const padding = Math.max(.008, Math.max(Math.max(...latitudes) - Math.min(...latitudes), Math.max(...longitudes) - Math.min(...longitudes)) * .3);
  const minimumLongitude = Math.min(...longitudes) - padding;
  const minimumLatitude = Math.min(...latitudes) - padding;
  const maximumLongitude = Math.max(...longitudes) + padding;
  const maximumLatitude = Math.max(...latitudes) + padding;
  const bbox = [minimumLongitude, minimumLatitude, maximumLongitude, maximumLatitude].join(",");
  const projected = available.map((point) => ({
    ...point,
    left: ((point.longitude - minimumLongitude) / (maximumLongitude - minimumLongitude)) * 100,
    top: (1 - ((point.latitude - minimumLatitude) / (maximumLatitude - minimumLatitude))) * 100,
  }));
  const routePoints = [
    ...projected.filter((point) => point.kind === "pickup"),
    ...projected.filter((point) => point.kind === "courier"),
    ...projected.filter((point) => point.kind === "dropoff"),
  ];
  const routePath = routePoints.map((point) => `${point.left},${point.top}`).join(" ");
  const source = `https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent(bbox)}&layer=mapnik&marker=${focus.latitude}%2C${focus.longitude}`;
  const destination = available.find((point) => point.kind === "dropoff") ?? focus;
  const directions = `https://maps.apple.com/?daddr=${destination.latitude},${destination.longitude}`;

  return (
    <section className="customer-route-panel" aria-label="Delivery route">
      <div className="customer-map-frame"><iframe title="Delivery map" src={source} loading="lazy" referrerPolicy="no-referrer" />{routeOverlay ? <div className="customer-map-markers" aria-hidden="true">{routePoints.length > 1 ? <svg className="customer-map-route-line" viewBox="0 0 100 100" preserveAspectRatio="none"><polyline points={routePath} /></svg> : null}{projected.map((point) => <span key={`marker-${point.kind}-${point.latitude}-${point.longitude}`} className={`customer-map-marker ${point.kind}`} style={{ left: `${point.left}%`, top: `${point.top}%` }}><MapPin size={16} /></span>)}</div> : null}</div>
      <div className="customer-route-points">{available.map((point) => (
        <div key={`${point.kind}-${point.latitude}-${point.longitude}`}>
          <span className={`route-dot ${point.kind}`}><MapPin size={15} /></span>
          <span><strong>{point.label}</strong><small>{point.address}</small></span>
        </div>
      ))}</div>
      <a className="secondary-button customer-map-link" href={directions} target="_blank" rel="noreferrer"><Navigation size={17} /> Open in Maps <ExternalLink size={14} /></a>
    </section>
  );
}

export function CustomerTimeline({ items }: {
  items: Array<{ label: string; value?: string; statusText?: string }>;
}) {
  const visible = items.filter((item) => item.value || item.statusText);
  if (visible.length === 0) return null;
  return (
    <section className="customer-timeline" aria-label="Delivery timeline">
      <h2>Timeline</h2>
      <ol>{visible.map((item, index) => (
        <li key={item.label} className={index === visible.length - 1 ? "current" : ""}>
          <span /><div><strong>{item.label}</strong>{item.value
            ? <time dateTime={item.value}>{formatDate(item.value)}</time>
            : <small>{item.statusText}</small>}</div>
        </li>
      ))}</ol>
    </section>
  );
}

export function CancellationSheet({ title, busy, onDismiss, onConfirm }: {
  title: string;
  busy: boolean;
  onDismiss: () => void;
  onConfirm: (reason: string) => Promise<void>;
}) {
  const reasons = ["Plans changed", "Wrong address or items", "Taking too long"];
  return (
    <div className="customer-sheet-backdrop" role="presentation">
      <section className="customer-sheet cancellation-sheet" aria-modal="true" aria-labelledby="cancellation-title" role="dialog">
        <header><div><p className="eyebrow">Cancellation</p><h2 id="cancellation-title">{title}</h2></div><button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close" title="Close">×</button></header>
        <div className="cancellation-reasons">{reasons.map((reason) => <button type="button" key={reason} disabled={busy} onClick={() => void onConfirm(reason)}>{reason}</button>)}</div>
        <button className="secondary-button customer-sheet-action" type="button" onClick={onDismiss} disabled={busy}>Keep delivery</button>
      </section>
    </div>
  );
}

export function CustomerSupportSheet({ cases, busy, onDismiss, onSubmit }: {
  cases: CustomerOrderSupportCase[];
  busy: boolean;
  onDismiss: () => void;
  onSubmit: (category: CustomerOrderSupportCategory, message: string) => Promise<void>;
}) {
  const [category, setCategory] = useState<CustomerOrderSupportCategory>("delivery_status");
  const [message, setMessage] = useState("");
  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (message.trim().length < 10) return;
    void onSubmit(category, message.trim());
  };
  return (
    <div className="customer-sheet-backdrop" role="presentation">
      <section className="customer-sheet customer-support-sheet" aria-modal="true" aria-labelledby="support-title" role="dialog">
        <header><div><p className="eyebrow">Dastak support</p><h2 id="support-title">Help with this order</h2></div><button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close" title="Close">×</button></header>
        {cases.length > 0 && <div className="support-case-list">{cases.map((item) => <article key={item.caseId}><strong>{item.reference}</strong><span>{supportStatus(item.status)}</span><p>{item.message}</p>{item.resolution && <small>{item.resolution}</small>}</article>)}</div>}
        <form onSubmit={submit}>
          <label>What do you need help with?<select value={category} onChange={(event) => setCategory(event.target.value as CustomerOrderSupportCategory)}><option value="delivery_status">Delivery status</option><option value="merchant_or_items">Store or items</option><option value="payment">Payment</option><option value="refund">Refund</option><option value="cancellation">Cancellation</option><option value="safety">Safety</option><option value="other">Something else</option></select></label>
          <label>Tell us what happened<textarea value={message} onChange={(event) => setMessage(event.target.value)} maxLength={1000} placeholder="Include the details that will help us resolve this quickly." /></label>
          <button className="primary-button customer-sheet-action" type="submit" disabled={busy || message.trim().length < 10}>{busy ? "Sending..." : "Send to support"}</button>
        </form>
      </section>
    </div>
  );
}

function supportStatus(status: CustomerOrderSupportCase["status"]) {
  return ({ open: "Open", in_review: "In review", resolved: "Resolved", closed: "Closed" } as const)[status];
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
