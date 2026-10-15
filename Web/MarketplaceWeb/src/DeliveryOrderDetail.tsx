import { useEffect, useState } from "react";
import { formatPrice } from "./catalogue";
import { CustomerNotice } from "./CustomerUI";
import { getDeliveryOrderDetail, type DeliveryOrderDetail, type DeliveryWorkHistoryItem } from "./delivery";

type Auth = { accessToken: string; supabaseUrl: string; publishableKey: string };
export function DeliveryOrderDetailPanel({ auth, kind, workId }: { auth: Auth; kind: DeliveryWorkHistoryItem["kind"]; workId: string }) {
  const [open, setOpen] = useState(false);
  const [detail, setDetail] = useState<DeliveryOrderDetail>();
  const [error, setError] = useState(false);
  const [revision, setRevision] = useState(0);
  const { accessToken, supabaseUrl, publishableKey } = auth;
  useEffect(() => {
    if (!open) return;
    const update = () => { if (!document.hidden) setRevision((value) => value + 1); };
    const timer = window.setInterval(update, 30_000);
    document.addEventListener("visibilitychange", update);
    return () => { window.clearInterval(timer); document.removeEventListener("visibilitychange", update); };
  }, [open]);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setDetail(undefined); setError(false);
    void getDeliveryOrderDetail({ accessToken, supabaseUrl, publishableKey, kind, workId, signal: controller.signal })
      .then((value) => { if (!controller.signal.aborted) setDetail(value); })
      .catch(() => { if (!controller.signal.aborted) setError(true); });
    return () => controller.abort();
  }, [open, accessToken, supabaseUrl, publishableKey, kind, workId, revision]);
  return <section className="delivery-full-order">
    <button type="button" className="rider-quiet-action" aria-expanded={open} onClick={() => setOpen((value) => !value)}>{open ? "Close full order" : "View full order"}</button>
    {open ? <div className="delivery-full-order-content" aria-label="Full order details" aria-live="polite">
      {error ? <CustomerNotice title="Full order unavailable" onRetry={() => setRevision((value) => value + 1)}>Refresh the order or contact support if this work is no longer available to your account.</CustomerNotice> : !detail ? <p role="status">Loading full order…</p> : <>
        <header><p className="eyebrow">{detail.order.displayOrderNumber}</p><h3>{label(detail.missionStatus)}</h3><p>{label(detail.order.orderType)}</p></header>
        {detail.terminal ? <p>Completed work · customer contact is private.</p> : null}
        <h4>Items</h4>
        {detail.order.lines.map((line) => <div className="delivery-detail-line" key={line.id}>
          <strong>{line.quantity} × {line.name}</strong><span>{formatPrice(line.lineTotalPaise)}</span>
          <small>{[line.variant, line.packSize, ...(line.foodSelection?.options.map((option) => option.name) ?? [])].filter(Boolean).join(" · ")}</small>
        </div>)}
        <h4>{detail.kind === "RETURN" ? "Return stops" : "Pickup stops"}</h4>
        {detail.pickupStops.map((stop) => <div className="delivery-detail-stop" key={stop.id}><strong>{stop.sequence}. {stop.name ?? stop.branch?.displayName ?? "Pickup"}</strong><p>{address(stop.address ?? stop.branch?.address)}</p><small>{label(stop.status ?? "")}{stop.packageCount != null ? ` · ${stop.packageCount} packages` : ""}</small></div>)}
        {!detail.terminal && detail.order.deliveryAddress ? <><h4>Deliver to</h4><p>{address(detail.order.deliveryAddress)}</p>{detail.order.deliveryAddress.instructions ? <p>{detail.order.deliveryAddress.instructions}</p> : null}<p>{detail.order.recipient?.name}</p>{/^\+[1-9]\d{7,14}$/.test(detail.order.recipient?.phoneNumber ?? "") ? <a href={`tel:${detail.order.recipient!.phoneNumber}`}>Call customer</a> : null}</> : null}
        <h4>{detail.kind === "RETURN" ? "Original order bill" : "Order bill"}</h4>
        {detail.kind === "RETURN" ? <p>For reference only. Do not collect this amount again for a return.</p> : null}
        <dl>{[["Items", detail.order.price.subtotalPaise], ["Delivery", detail.order.price.deliveryFeePaise], ["Platform fee", detail.order.price.platformFeePaise], ["Discount", -detail.order.price.discountPaise], ["Total", detail.order.price.totalPaise]].map(([name, value]) => <div className="delivery-detail-line" key={name}><dt>{name}</dt><dd>{formatPrice(Number(value))}</dd></div>)}</dl>
        <p>Tax is included</p>
        {detail.collection ? <p>{label(detail.collection.state)}{detail.collection.lastMethod ? ` · ${detail.collection.lastMethod}` : ""}</p> : null}
        <small>The order bill is not your earnings balance.</small>
        <h4>Order record</h4><p>Created: {date(detail.order.createdAt)}</p><p>Updated: {date(detail.order.updatedAt)}</p>{detail.order.deliveredAt ? <p>Delivered: {date(detail.order.deliveredAt)}</p> : null}
      </>}
    </div> : null}
  </section>;
}
function label(value: string) { return value.replaceAll("_", " ").toLowerCase().replace(/^./, (letter) => letter.toUpperCase()); }
function date(value: string) { const parsed = new Date(value); return Number.isNaN(parsed.getTime()) ? "Not available" : parsed.toLocaleString("en-IN"); }
function address(value: string | Record<string, unknown> | undefined) {
  if (typeof value === "string") return value;
  return [value?.line2, value?.line1, value?.landmark, value?.city, value?.state, value?.postalCode].filter((part): part is string => typeof part === "string" && part.length > 0).join(", ") || "Address unavailable";
}
