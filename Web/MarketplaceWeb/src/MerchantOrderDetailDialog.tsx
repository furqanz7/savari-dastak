import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { X, RefreshCw, PackageCheck, FileText } from "lucide-react";
import { DastakV1RequestError, getV1MerchantOrderDetail, type DastakV1Auth } from "./dastakV1";
import { parseMerchantOrderDetail, type MerchantDetailTarget, type MerchantOrderDetail } from "./merchantOrderDetail";
import "./merchantOrderDetail.css";

const label = (text: string) => text.replaceAll("_", " ").toLowerCase().replace(/^./, (s) => s.toUpperCase());
const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(paise / 100);
function Stamp({ title, value }: { title: string; value?: string }) {
  if (!value) return null;
  const date = new Date(value);
  return <p className="merchant-detail-stamp"><span>{title}</span><span>{Number.isNaN(date.valueOf()) ? "Time unavailable" : date.toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" })}</span></p>;
}

export function MerchantOrderDetailDialog({ auth, target, onClose }: { auth: DastakV1Auth; target: MerchantDetailTarget; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [detail, setDetail] = useState<MerchantOrderDetail>();
  const [failure, setFailure] = useState<string>();
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  const refresh = useCallback(() => setRevision((value) => value + 1), []);
  const { accessToken, publishableKey, supabaseUrl } = auth;
  const { branchId, id, kind } = target;
  useLayoutEffect(() => {
    const element = dialog.current, previous = document.activeElement as HTMLElement | null;
    const overflow = document.body.style.overflow;
    element?.showModal(); document.body.style.overflow = "hidden";
    return () => { element?.close(); document.body.style.overflow = overflow; previous?.focus({ preventScroll: true }); };
  }, []);
  useEffect(() => {
    const controller = new AbortController(); setLoading(true);
    void getV1MerchantOrderDetail({ accessToken, publishableKey, supabaseUrl, branchId, targetKind: kind, targetId: id, signal: controller.signal })
      .then((value) => { const parsed = parseMerchantOrderDetail(value, { kind, id, branchId }); if (!controller.signal.aborted) { setDetail(parsed); setFailure(undefined); } })
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        if (error instanceof DastakV1RequestError && [401,403,404].includes(error.status)) setDetail(undefined);
        setFailure("Order details could not be verified. Refresh or check your Merchant session. Retained details are from the last successful check.");
      }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [accessToken, publishableKey, supabaseUrl, branchId, id, kind, revision]);
  useEffect(() => {
    const timer = setInterval(() => { if (document.visibilityState === "visible") refresh(); }, 30_000);
    return () => clearInterval(timer);
  }, [refresh]);
  return <dialog className="merchant-order-detail" ref={dialog} aria-labelledby="merchant-detail-title" onCancel={(event) => { event.preventDefault(); onClose(); }}>
    <header><span><FileText size={20} /> Full order</span><button type="button" onClick={onClose} aria-label="Close full order"><X /></button></header>
    <div className="merchant-detail-body" aria-busy={loading}>
      {failure ? <p role="alert" className="merchant-detail-warning">{failure}</p> : null}
      {loading ? <p role="status">Checking order details…</p> : null}
      {detail ? <>
        <section className="merchant-detail-hero"><small>{detail.branch}</small><h2 id="merchant-detail-title">{detail.order.number}</h2><strong>{label(detail.order.status)}</strong><Stamp title="Order placed" value={detail.order.created} /></section>
        <p className="merchant-detail-note">Only this location’s items and operational records. Requested and fulfilled product values may overlap—do not add them together. Customer-wide charges and private delivery details are excluded.</p>
        {detail.records.map((record) => <section className="merchant-detail-record" key={`${record.kind}:${record.id}`}>
          <h3>{record.kind === "FULFILMENT" ? "Fulfilment" : record.kind === "RESTAURANT_REQUEST" ? "Kitchen request" : "Retail request"}<span>{label(record.status)}</span></h3>
          <ul className="merchant-detail-lines">{record.lines.map((line) => <li key={line.id}><b>{line.quantity}×</b><span><strong>{line.name}</strong><small>{[line.variant, line.packSize].filter(Boolean).join(" · ")}</small>{line.options.map((option, i) => <small key={i}>{option}</small>)}</span>{line.subtotal !== undefined ? <strong>{money(line.subtotal)}</strong> : null}</li>)}</ul>
          {record.productValue !== undefined ? <p className="merchant-detail-value"><span>Product value</span><strong>{money(record.productValue)}</strong></p> : null}
          {record.prep !== undefined ? <p>Preparation promise · {record.prep} min</p> : null}
          {record.packages !== undefined ? <p><PackageCheck size={16} /> {record.packages} sealed package(s)</p> : null}
          <Stamp title="Offered" value={record.offered} /><Stamp title="Responded" value={record.responded} />
          <Stamp title="Preparation started" value={record.prepStarted} /><Stamp title="Expected ready" value={record.expectedReady} /><Stamp title="Ready" value={record.ready} />
          {record.responseReason ? <p>{record.responseReason}</p> : null}
          {record.kind === "FULFILMENT" ? <><p>{record.evidence.length} Ready photo(s) recorded</p>{record.evidence.map((photo) => <Stamp key={photo.id} title="Photo recorded" value={photo.at} />)}
            {record.delivery.assigned ? <p>{record.delivery.rider ?? "Delivery partner assigned"}{record.delivery.stop ? ` · Pickup ${label(record.delivery.stop)}` : ""}</p> : null}<Stamp title="Collected" value={record.delivery.collected} /></> : null}
          {record.problems.map((problem) => <div key={problem.id}><p>{problem.reason}</p><Stamp title="Reported" value={problem.at} /></div>)}
          {record.recovery.map((recovery) => <div key={recovery.id}><p>{label(recovery.status)} · {recovery.reason}</p><Stamp title="Recovery opened" value={recovery.opened} /><Stamp title="Resolved" value={recovery.resolved} /></div>)}
        </section>)}
        {detail.records.length === 0 ? <p>No preparation record is available for this recovery or return yet.</p> : null}
        {detail.recoveryOffers.length > 0 ? <section className="merchant-detail-record"><h3>Exact-item recovery</h3>{detail.recoveryOffers.map((offer) => <div key={offer.id}><p><strong>{offer.quantity}× {offer.name} · {offer.pack}</strong></p><p>{label(offer.status)}</p><Stamp title="Recovery offered" value={offer.offered} /></div>)}</section> : null}
        {detail.returns.length > 0 ? <section className="merchant-detail-record"><h3>Returns</h3>{detail.returns.map((receipt) => <div key={receipt.id}><p>{receipt.packages} package(s) · {label(receipt.status)}</p><Stamp title="Arrived" value={receipt.arrived} /><Stamp title="Received" value={receipt.completed} /></div>)}</section> : null}
        {detail.settlements.length > 0 ? <section className="merchant-detail-record"><h3>Fulfilment settlement records</h3><small>Not a balance or bank payout confirmation.</small>{detail.settlements.map((entry) => <p key={entry.id}>{label(entry.type)} · {label(entry.status)} · {entry.calculation === "CALCULATED" && entry.amount !== undefined && entry.currency === "INR" ? money(entry.amount) : "Amount not calculated"}</p>)}</section> : null}
        <p className="merchant-detail-note">Pickup and return codes remain on their guarded operational cards.</p>
      </> : !loading ? <h2 id="merchant-detail-title">Order details unavailable</h2> : <h2 id="merchant-detail-title">Full order</h2>}
      <button type="button" className="merchant-detail-refresh" onClick={refresh} disabled={loading}><RefreshCw size={16} /> Refresh details</button>
    </div>
  </dialog>;
}
