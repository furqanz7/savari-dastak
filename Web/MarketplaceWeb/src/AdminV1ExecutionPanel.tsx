import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { Clock3, RefreshCw, Route, ShieldCheck, WalletCards } from "lucide-react";
import {
  getV1AdminExecutionOrders,
  getV1AdminExecutionTrace,
  type DastakV1Auth,
  type V1AdminExecutionOrder,
  type V1AdminExecutionTrace,
} from "./dastakV1";

export function AdminV1ExecutionPanel({ auth }: { auth: DastakV1Auth }) {
  const [orders, setOrders] = useState<V1AdminExecutionOrder[]>([]);
  const [selectedId, setSelectedId] = useState<string>();
  const [trace, setTrace] = useState<V1AdminExecutionTrace>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const selectedIdRef = useRef<string | undefined>(undefined);

  const loadTrace = useCallback(async (orderId: string) => {
    try {
      const result = await getV1AdminExecutionTrace({ ...auth, orderId });
      setTrace(result);
      setError(undefined);
    } catch (traceError) {
      setError(message(traceError));
    }
  }, [auth]);

  const refresh = useCallback(async (showProgress = false) => {
    if (showProgress) setBusy(true);
    try {
      const result = await getV1AdminExecutionOrders({ ...auth, limit: 50 });
      setOrders(result);
      const currentId = selectedIdRef.current;
      const orderId = currentId && result.some((order) => order.id === currentId)
        ? currentId
        : result[0]?.id;
      selectedIdRef.current = orderId;
      setSelectedId(orderId);
      if (orderId) await loadTrace(orderId);
      else setTrace(undefined);
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      setLoading(false);
      if (showProgress) setBusy(false);
    }
  }, [auth, loadTrace]);

  useEffect(() => { void refresh(); }, [refresh]);

  const select = (orderId: string) => {
    selectedIdRef.current = orderId;
    setSelectedId(orderId);
    setTrace(undefined);
    void loadTrace(orderId);
  };

  return <section className="v1-execution-panel" role="tabpanel" aria-label="Dastak V1 execution trace">
    <header><div><p className="eyebrow">LAUNCH SPINE</p><h2>V1 execution trace</h2><span>Matching, holds, final plan, capacity and payment evidence.</span></div><button className="icon-button" type="button" disabled={busy} onClick={() => void refresh(true)} aria-label="Refresh V1 trace"><RefreshCw size={18} /></button></header>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {loading ? <div className="catalogue-loading" role="status"><span /> Loading V1 trace</div> : orders.length === 0 ? <p className="admin-empty">No V1 orders have been submitted.</p> : <div className="v1-execution-layout">
      <nav aria-label="V1 orders">{orders.map((order) => <button type="button" className={selectedId === order.id ? "selected" : ""} key={order.id} onClick={() => select(order.id)}><span><strong>{order.displayOrderNumber}</strong><small>{formatTime(order.updatedAt)}</small></span><b>{order.status.replaceAll("_", " ")}</b></button>)}</nav>
      <div className="v1-trace-detail">{trace ? <Trace trace={trace} /> : <div className="catalogue-loading" role="status"><span /> Loading order evidence</div>}</div>
    </div>}
  </section>;
}

function Trace({ trace }: { trace: V1AdminExecutionTrace }) {
  const paymentStatus = text(trace.payment, "status") ?? "NOT OPEN";
  const paymentAttempts = array(trace.payment, "attempts").length;
  const providerEvents = array(trace.payment, "providerEvents").length;
  return <>
    <header className="v1-trace-order"><span><strong>{trace.order.displayOrderNumber}</strong><small>Version {trace.order.version}</small></span><b>{trace.order.status.replaceAll("_", " ")}</b></header>
    <div className="v1-trace-summary">
      <TraceMetric icon={<Clock3 size={17} />} label="Attempts" value={String(trace.matchingAttempts.length)} />
      <TraceMetric icon={<Route size={17} />} label="Plans" value={String(trace.plans.length)} />
      <TraceMetric icon={<ShieldCheck size={17} />} label="Secured" value={trace.order.fullySecuredAt ? "YES" : "NO"} />
      <TraceMetric icon={<WalletCards size={17} />} label="Payment" value={paymentStatus} />
    </div>
    <TraceSection title="Wave 1 / Wave 2">
      {trace.matchingAttempts.length === 0 ? <p>Not started.</p> : trace.matchingAttempts.map((attempt, index) => <article key={text(attempt, "id") ?? index}><strong>{text(attempt, "wave") ?? "Attempt"} · {text(attempt, "status") ?? "UNKNOWN"}</strong><span>{array(attempt, "opportunities").length} opportunities · expires {formatOptional(text(attempt, "expiresAt"))}</span></article>)}
    </TraceSection>
    <TraceSection title="Provisional physical holds">
      <p>{countStatus(trace.provisionalHolds, "HELD")} held · {countStatus(trace.provisionalHolds, "SELECTED")} selected · {countStatus(trace.provisionalHolds, "RELEASED")} released</p>
    </TraceSection>
    <TraceSection title="Candidate / final plan">
      {trace.plans.length === 0 ? <p>No complete candidate plan yet.</p> : trace.plans.map((plan, index) => <article key={text(plan, "id") ?? index}><strong>{text(plan, "status") ?? "UNKNOWN"} · {number(plan, "merchantCount") ?? 0} merchant(s)</strong><span>{number(plan, "retailLineCount") ?? 0} lines · route {number(plan, "routeDistanceMeters") ?? 0}m{text(plan, "rejectionReason") ? ` · ${text(plan, "rejectionReason")}` : ""}</span></article>)}
    </TraceSection>
    <TraceSection title="Capacity at inspection">
      {trace.capacity.length === 0 ? <p>No candidate branches.</p> : trace.capacity.map((entry, index) => <article key={text(entry, "branchId") ?? index}><strong>{text(entry, "branchName") ?? "Branch"}</strong><span>{number(entry, "activeSlots") ?? 0} / {number(entry, "capacityLimit") ?? 0} active slots</span></article>)}
    </TraceSection>
    <TraceSection title="Payment reservation">
      <p>{paymentStatus} · {paymentAttempts} attempts · {providerEvents} provider events{trace.payment ? ` · expires ${formatOptional(text(trace.payment, "expiresAt"))}` : ""}</p>
    </TraceSection>
    <TraceSection title="Reconciliation">
      <p>{trace.reconciliationCases.length === 0 ? "No reconciliation cases." : `${trace.reconciliationCases.length} case(s) require operator review.`}</p>
    </TraceSection>
  </>;
}

function TraceMetric({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return <div><span>{icon}</span><small>{label}</small><strong>{value}</strong></div>;
}

function TraceSection({ title, children }: { title: string; children: ReactNode }) {
  return <section className="v1-trace-section"><h3>{title}</h3>{children}</section>;
}

function countStatus(values: Record<string, unknown>[], status: string) {
  return values.filter((value) => text(value, "status") === status).length;
}

function text(value: Record<string, unknown> | undefined, key: string) {
  const result = value?.[key];
  return typeof result === "string" ? result : undefined;
}
function number(value: Record<string, unknown> | undefined, key: string) {
  const result = value?.[key];
  return typeof result === "number" ? result : undefined;
}
function array(value: Record<string, unknown> | undefined, key: string) {
  const result = value?.[key];
  return Array.isArray(result) ? result : [];
}
function formatOptional(value?: string) {
  return value ? formatTime(value) : "—";
}
function formatTime(value: string) {
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}
function message(error: unknown) {
  return error instanceof Error ? error.message : "The V1 execution trace is unavailable.";
}
