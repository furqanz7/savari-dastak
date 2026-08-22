import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { Camera, Clock3, PackageCheck, RefreshCw, Route, ShieldCheck, WalletCards } from "lucide-react";
import { getEvidenceUrl } from "./admin";
import {
  authorizeV1ExceptionalDeliveryHandoff,
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
    <header><div><p className="eyebrow">LAUNCH SPINE</p><h2>V1 execution trace</h2><span>Matching through verified final delivery and package custody.</span></div><button className="icon-button" type="button" disabled={busy} onClick={() => void refresh(true)} aria-label="Refresh V1 trace"><RefreshCw size={18} /></button></header>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {loading ? <div className="catalogue-loading" role="status"><span /> Loading V1 trace</div> : orders.length === 0 ? <p className="admin-empty">No V1 orders have been submitted.</p> : <div className="v1-execution-layout">
      <nav aria-label="V1 orders">{orders.map((order) => <button type="button" className={selectedId === order.id ? "selected" : ""} key={order.id} onClick={() => select(order.id)}><span><strong>{order.displayOrderNumber}</strong><small>{formatTime(order.updatedAt)}</small></span><b>{order.status.replaceAll("_", " ")}</b></button>)}</nav>
      <div className="v1-trace-detail">{trace ? <Trace trace={trace} auth={auth} onChanged={() => void loadTrace(trace.order.id)} /> : <div className="catalogue-loading" role="status"><span /> Loading order evidence</div>}</div>
    </div>}
  </section>;
}

function Trace({ trace, auth, onChanged }: {
  trace: V1AdminExecutionTrace;
  auth: DastakV1Auth;
  onChanged: () => void;
}) {
  const paymentStatus = text(trace.payment, "status") ?? "NOT OPEN";
  const paymentAttempts = array(trace.payment, "attempts").length;
  const providerEvents = array(trace.payment, "providerEvents").length;
  const preparation = trace.preparation;
  const delivery = trace.delivery;
  const readyCount = preparation?.fulfilments.filter((item) =>
    text(item, "status") === "READY" || text(item, "status") === "PICKED_UP").length ?? 0;
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
    <TraceSection title="Preparation clocks">
      {!preparation || preparation.fulfilments.length === 0 ? <p>Payment-confirmed preparation has not started.</p> : preparation.fulfilments.map((fulfilment, index) => {
        const capacity = object(fulfilment, "capacity");
        const runningLate = boolean(fulfilment, "runningLate") === true;
        return <article key={text(fulfilment, "id") ?? index} className={runningLate ? "running-late" : ""}>
          <strong>{text(fulfilment, "branchName") ?? "Branch"} · {text(fulfilment, "status") ?? "UNKNOWN"}</strong>
          <span>{number(fulfilment, "promisedPrepMinutes") ?? 0} min · start {formatOptional(text(fulfilment, "prepStartedAt"))} · ETA {formatOptional(text(fulfilment, "estimatedReadyAt"))} · actual {formatOptional(text(fulfilment, "actualReadyAt"))}{runningLate ? ` · late ${formatDuration(number(fulfilment, "lateSeconds") ?? 0)}` : ""}<br />Capacity {text(capacity, "status") ?? "—"}{text(capacity, "releasedAt") ? ` · released ${formatOptional(text(capacity, "releasedAt"))}` : ""}</span>
        </article>;
      })}
    </TraceSection>
    <TraceSection title="Packages and Ready evidence">
      {!preparation ? <p>No package declarations.</p> : <>
        <p>{preparation.packages.length} package(s) · {preparation.evidence.length} immutable evidence record(s) · {readyCount}/{preparation.fulfilments.length} fulfilments Ready</p>
        {preparation.packages.map((item, index) => <article key={text(item, "id") ?? index}><strong>Package {number(item, "packageNumber") ?? "—"} · {text(item, "status") ?? "UNKNOWN"}</strong><span>Custody {text(item, "custodyOwnerType") ?? "—"} · Ready {formatOptional(text(item, "readyAt"))}</span></article>)}
        {preparation.evidence.map((item, index) => <article key={text(item, "id") ?? index}><strong><Camera size={14} /> Merchant Ready photo</strong><span>{formatOptional(text(item, "capturedAt"))} <EvidenceButton auth={auth} objectPath={text(item, "objectPath")} /></span></article>)}
      </>}
    </TraceSection>
    <TraceSection title="Preparation exceptions and history">
      {!preparation ? <p>No preparation history.</p> : <>
        <p>{preparation.problems.length === 0 ? "No preparation problems reported." : `${preparation.problems.length} problem report(s).`}</p>
        {preparation.problems.map((item, index) => <article key={text(item, "id") ?? index}><strong>{text(item, "statusAtReport") ?? "UNKNOWN"}</strong><span>{text(item, "reason") ?? "—"} · {formatOptional(text(item, "reportedAt"))}</span></article>)}
        {preparation.history.map((item, index) => <article key={`${text(item, "eventType") ?? "event"}-${index}`}><strong><PackageCheck size={14} /> {text(item, "eventType")?.replaceAll("_", " ") ?? "EVENT"}</strong><span>{formatOptional(text(item, "occurredAt"))}</span></article>)}
      </>}
    </TraceSection>
    <TraceSection title="Rider-match threshold foundation">
      <p>{boolean(preparation?.riderMatchEligibility, "eligible") ? "Eligible" : "Not eligible"} · {number(preparation?.riderMatchEligibility, "satisfiedFulfilmentCount") ?? 0}/{number(preparation?.riderMatchEligibility, "requiredFulfilmentCount") ?? 0} fulfilments satisfy Ready or ≤5 minutes.</p>
    </TraceSection>
    <TraceSection title="Rider mission and offer pool">
      {!delivery?.mission ? <p>No rider mission yet.</p> : <>
        <article><strong>{text(delivery.mission, "status")?.replaceAll("_", " ") ?? "MISSION"} · {text(delivery.mission, "riderName") ?? "No rider assigned"}</strong><span>{text(delivery.mission, "transportType") ?? "Transport pending"} · {number(delivery.mission, "pickupCount") ?? 0} pickup(s) · pool round {number(delivery.mission, "poolRound") ?? 0}<br />Out for delivery {formatOptional(text(delivery.mission, "outForDeliveryAt"))} · rider arrived {formatOptional(text(delivery.mission, "arrivedCustomerAt"))} · delivered {formatOptional(text(delivery.mission, "deliveredAt"))}</span></article>
        <p>{delivery.offers.length} rider offer(s) · {countStatus(delivery.offers, "ACCEPTED")} accepted · {countStatus(delivery.offers, "CLOSED")} competing closed</p>
        {delivery.offers.map((offer, index) => <article key={text(offer, "id") ?? index}><strong>{text(offer, "riderName") ?? "Rider"} · {text(offer, "status") ?? "UNKNOWN"}</strong><span>{text(offer, "transportType") ?? "—"} · {number(offer, "distanceMeters") ?? 0}m · round {number(offer, "poolRound") ?? 0}</span></article>)}
      </>}
    </TraceSection>
    <TraceSection title="Pickup stops and waiting">
      {!delivery || delivery.pickupStops.length === 0 ? <p>No pickup stops.</p> : delivery.pickupStops.map((stop, index) => <article key={text(stop, "id") ?? index}><strong>Stop {number(stop, "sequence") ?? "—"} · {text(stop, "branchName") ?? "Branch"} · {text(stop, "status") ?? "UNKNOWN"}</strong><span>{number(stop, "packageCount") ?? 0} package(s) · arrival {formatOptional(text(stop, "arrivedAt"))} · waiting {formatDuration(number(stop, "waitingSeconds") ?? 0)}</span></article>)}
    </TraceSection>
    <TraceSection title="Verification and package custody">
      {!delivery ? <p>No pickup verification.</p> : <>
        <p>{delivery.verification.length} verification record(s) · {countStatus(delivery.verification, "CONSUMED")} consumed · {delivery.custody.length} package custody transfer(s)</p>
        {delivery.verification.map((verification, index) => <article key={text(verification, "id") ?? index}><strong>{text(verification, "type")?.replaceAll("_", " ") ?? "HANDOFF"} · {text(verification, "status") ?? "UNKNOWN"}</strong><span>{number(verification, "failedAttempts") ?? 0} failed attempt(s) · blocked {formatOptional(text(verification, "blockedAt"))} · consumed {formatOptional(text(verification, "consumedAt"))}{text(verification, "overrideReason") ? ` · override: ${text(verification, "overrideReason")}` : ""}</span></article>)}
        {delivery.custody.map((custody, index) => <article key={text(custody, "id") ?? index}><strong>Package custody · {text(custody, "fromOwnerType") ?? "—"} → {text(custody, "toOwnerType") ?? "—"}</strong><span>{formatOptional(text(custody, "transferredAt"))}</span></article>)}
        {delivery.problems.map((problem, index) => <article className="running-late" key={text(problem, "id") ?? index}><strong>Delivery problem · {text(problem, "missionStatusAtReport") ?? "UNKNOWN"}</strong><span>{text(problem, "reason") ?? "—"} · custody started {boolean(problem, "custodyStarted") ? "yes" : "no"}</span></article>)}
      </>}
    </TraceSection>
    <TraceSection title="Final-delivery evidence and completion">
      {!delivery ? <p>Final delivery has not started.</p> : <>
        <p>{delivery.deliveryEvidence.length} immutable rider photo(s) · Delivered {formatOptional(trace.order.deliveredAt)}</p>
        {delivery.deliveryEvidence.map((evidence, index) => <article key={text(evidence, "id") ?? index}><strong><Camera size={14} /> Rider package photo · {array(evidence, "packageIds").length} package(s)</strong><span>{formatOptional(text(evidence, "capturedAt"))}<EvidenceButton auth={auth} objectPath={text(evidence, "objectPath")} /></span></article>)}
        {delivery.exceptionalHandoffs.map((handoff, index) => <article className="running-late" key={text(handoff, "id") ?? index}><strong>Exceptional handoff · OVERRIDDEN</strong><span>{text(handoff, "authorizerName") ?? "Operations"} · {text(handoff, "reason") ?? "—"} · {formatOptional(text(handoff, "authorizedAt"))}<br />Normal code verification: no</span></article>)}
        <ExceptionalHandoffAction trace={trace} auth={auth} onChanged={onChanged} />
      </>}
    </TraceSection>
    <TraceSection title="Reconciliation">
      <p>{trace.reconciliationCases.length === 0 ? "No reconciliation cases." : `${trace.reconciliationCases.length} case(s) require operator review.`}</p>
    </TraceSection>
  </>;
}

function ExceptionalHandoffAction({ trace, auth, onChanged }: {
  trace: V1AdminExecutionTrace;
  auth: DastakV1Auth;
  onChanged: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const delivery = trace.delivery;
  const missionId = text(delivery?.mission, "id");
  const missionVersion = number(delivery?.mission, "version");
  const evidenceId = text(delivery?.deliveryEvidence[0], "id");
  const available = delivery?.canAuthorizeExceptionalHandoff === true &&
    Boolean(missionId && missionVersion && evidenceId) &&
    ["ARRIVED", "DELIVERY_RECOVERY"].includes(text(delivery?.mission, "status") ?? "") &&
    delivery.exceptionalHandoffs.length === 0;
  if (!available) return null;

  const authorize = async () => {
    if (busy || reason.trim().replace(/\s+/g, " ").length < 10 || !missionId ||
      !missionVersion || !evidenceId) return;
    if (!window.confirm(
      "Authorize an exceptional handoff? This will deliver every package as OVERRIDDEN without normal code verification.",
    )) return;
    setBusy(true);
    setError(undefined);
    try {
      await authorizeV1ExceptionalDeliveryHandoff({
        ...auth,
        missionId,
        deliveryEvidenceId: evidenceId,
        reason,
        expectedMissionVersion: missionVersion,
        idempotencyKey: crypto.randomUUID(),
      });
      onChanged();
    } catch (actionError) {
      setError(message(actionError));
    } finally {
      setBusy(false);
    }
  };

  return <div className="v1-exceptional-handoff">
    <label>
      Operations exception reason
      <textarea value={reason} maxLength={500} onChange={(event) => setReason(event.target.value)} placeholder="Record why normal in-app verification cannot be completed." />
    </label>
    <button className="danger-button" type="button" disabled={busy || reason.trim().length < 10} onClick={() => void authorize()}>
      {busy ? "Authorizing…" : "Authorize exceptional handoff"}
    </button>
    <small>This records OVERRIDDEN, never normal verification success.</small>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
  </div>;
}

function EvidenceButton({ auth, objectPath }: { auth: DastakV1Auth; objectPath?: string }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  if (!objectPath) return null;
  const open = async () => {
    if (busy) return;
    setBusy(true);
    setError(undefined);
    try {
      window.location.assign(await getEvidenceUrl({ ...auth, objectPath }));
    } catch (openError) {
      setError(message(openError));
    } finally {
      setBusy(false);
    }
  };
  return <>{" · "}<button className="v1-evidence-link" type="button" disabled={busy} onClick={() => void open()}>{busy ? "Opening…" : "View"}</button>{error ? <small role="alert">{error}</small> : null}</>;
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
function object(value: Record<string, unknown> | undefined, key: string) {
  const result = value?.[key];
  return result !== null && typeof result === "object" && !Array.isArray(result)
    ? result as Record<string, unknown>
    : undefined;
}
function boolean(value: Record<string, unknown> | undefined, key: string) {
  const result = value?.[key];
  return typeof result === "boolean" ? result : undefined;
}
function formatOptional(value?: string) {
  return value ? formatTime(value) : "—";
}
function formatTime(value: string) {
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}
function formatDuration(seconds: number) {
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}
function message(error: unknown) {
  return error instanceof Error ? error.message : "The V1 execution trace is unavailable.";
}
