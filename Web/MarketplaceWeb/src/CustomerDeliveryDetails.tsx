import { ExternalLink, MapPin, Navigation } from "lucide-react";

export type CustomerMapPoint = {
  label: string;
  address: string;
  latitude: number;
  longitude: number;
  kind: "pickup" | "dropoff" | "courier";
};

export function CustomerRouteMap({ points }: { points: CustomerMapPoint[] }) {
  const available = points.filter((point) => Number.isFinite(point.latitude) && Number.isFinite(point.longitude));
  if (available.length === 0) return null;
  const focus = available.find((point) => point.kind === "courier") ?? available.find((point) => point.kind === "dropoff") ?? available[0];
  const latitudes = available.map((point) => point.latitude);
  const longitudes = available.map((point) => point.longitude);
  const padding = Math.max(.008, Math.max(Math.max(...latitudes) - Math.min(...latitudes), Math.max(...longitudes) - Math.min(...longitudes)) * .3);
  const bbox = [Math.min(...longitudes) - padding, Math.min(...latitudes) - padding, Math.max(...longitudes) + padding, Math.max(...latitudes) + padding].join(",");
  const source = `https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent(bbox)}&layer=mapnik&marker=${focus.latitude}%2C${focus.longitude}`;
  const directions = `https://maps.apple.com/?daddr=${focus.latitude},${focus.longitude}`;

  return (
    <section className="customer-route-panel" aria-label="Delivery route">
      <div className="customer-map-frame"><iframe title="Delivery map" src={source} loading="lazy" referrerPolicy="no-referrer" /></div>
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

export function CustomerTimeline({ items }: { items: Array<{ label: string; value?: string }> }) {
  const visible = items.filter((item) => item.value);
  if (visible.length === 0) return null;
  return (
    <section className="customer-timeline" aria-label="Delivery timeline">
      <h2>Timeline</h2>
      <ol>{visible.map((item, index) => (
        <li key={item.label} className={index === visible.length - 1 ? "current" : ""}>
          <span /><div><strong>{item.label}</strong><time dateTime={item.value}>{formatDate(item.value!)}</time></div>
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

function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
