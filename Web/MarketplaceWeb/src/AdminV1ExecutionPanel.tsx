import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { Camera, Clock3, PackageCheck, RefreshCw, Route, ShieldCheck, WalletCards } from "lucide-react";
import { getEvidenceUrl } from "./admin";
import {
  authorizeV1ExceptionalDeliveryHandoff,
  assignV1ReturnRider,
  createV1ExactSkuRecoveryOffer,
  decideV1CustomerIssue,
  failV1ExactSkuRecovery,
  finalizeV1SettlementCalculation,
  formatV1Price,
  getV1AdminExecutionOrders,
  getV1AdminExecutionTrace,
  manageV1DeliveryRecovery,
  type DastakV1Auth,
  type V1AdminExecutionOrder,
  type V1AdminExecutionTrace,
} from "./dastakV1";
import { processV1Refund } from "./payments";

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

  return <section className="v1-execution-panel" role="tabpanel" aria-label="Current Dastak orders">
    <header><div><p className="eyebrow">LIVE ORDER CONTROL</p><h2>Orders</h2><span>Inspect matching, payment, fulfilment, custody and recovery in one trace.</span></div><button className="icon-button" type="button" disabled={busy} onClick={() => void refresh(true)} aria-label="Refresh orders"><RefreshCw size={18} /></button></header>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {loading ? <div className="catalogue-loading" role="status"><span /> Loading orders</div> : orders.length === 0 ? <p className="admin-empty">No current-generation orders have been submitted.</p> : <div className="v1-execution-layout">
      <nav aria-label="Current orders">{orders.map((order) => <button type="button" className={selectedId === order.id ? "selected" : ""} key={order.id} onClick={() => select(order.id)}><span><strong>{order.displayOrderNumber}</strong><small>{formatTime(order.updatedAt)}</small></span><b>{order.status.replaceAll("_", " ")}</b></button>)}</nav>
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
    {trace.restaurant ? <TraceSection title="Restaurant / Cafe commitment">
      {!trace.restaurant.request ? <p>No Restaurant/Cafe request.</p> : <>
        <article><strong>{text(trace.restaurant.request, "restaurantName") ?? text(trace.restaurant.request, "branchName") ?? "Selected restaurant"} · {text(trace.restaurant.request, "status") ?? "UNKNOWN"}</strong><span>Exact request {formatOptional(text(trace.restaurant.request, "offeredAt"))} · response {formatOptional(text(trace.restaurant.request, "respondedAt"))} · prep promise {number(trace.restaurant.request, "promisedPrepMinutes") ?? "—"} min</span></article>
        <p>{trace.restaurant.foodLines.length} exact food line(s) · no silent rerouting · prepared food physically returnable: no</p>
        {trace.restaurant.foodLines.map((line, index) => <article key={text(line, "id") ?? index}><strong>{number(line, "quantity") ?? 0}× {text(line, "name") ?? "Food item"}</strong><span>{formatV1Price(number(line, "unitPricePaise") ?? 0)} each · immutable selection snapshot</span></article>)}
        {trace.restaurant.commitment ? <article><strong>Operational commitment · {text(trace.restaurant.commitment, "status") ?? "UNKNOWN"}</strong><span>Active orders at confirmation {number(trace.restaurant.commitment, "activeOrderCountAtAcceptance") ?? 0} · soft threshold {number(trace.restaurant.commitment, "softThreshold") ?? 5} · released {formatOptional(text(trace.restaurant.commitment, "releasedAt"))}</span></article> : null}
      </>}
    </TraceSection> : null}
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
    <FailureAndFinanceTrace trace={trace} auth={auth} onChanged={onChanged} />
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

function FailureAndFinanceTrace({ trace, auth, onChanged }: {
  trace: V1AdminExecutionTrace;
  auth: DastakV1Auth;
  onChanged: () => void;
}) {
  const state = trace.failureAndFinance;
  if (!state) return <TraceSection title="Failure, returns and finance"><p>No Step 5 trace.</p></TraceSection>;
  const permissions = state.permissions;
  return <TraceSection title="Failure, returns and finance">
    <p>{state.recoveryCases.length} recovery case(s) · {state.customerIssues.length} customer issue(s) · {state.returns.length} return(s) · {state.refunds.length} refund(s) · {state.royaltyLedger.length} Royalty entry/entries</p>
    {state.recoveryCases.map((recovery, index) => <article key={text(recovery, "id") ?? index}>
      <strong>{text(recovery, "type")?.replaceAll("_", " ")} recovery · {text(recovery, "status")?.replaceAll("_", " ")}</strong>
      <span>{text(recovery, "reason") ?? "—"} · {array(recovery, "opportunities").length} exact-item offer(s){text(recovery, "problemCode") === "CUSTOMER_UNREACHABLE" ? ` · customer contact due ${formatOptional(text(recovery, "nextActionAt"))}` : ""}</span>
      {boolean(permissions, "canManageRecovery") ? <RecoveryAction recovery={recovery} auth={auth} onChanged={onChanged} preparedFoodPresent={trace.order.orderType !== "RETAIL_ONLY"} /> : null}
    </article>)}
    {state.customerIssues.map((issue, index) => <article key={text(issue, "id") ?? index}>
      <strong>{text(issue, "category")?.replaceAll("_", " ")} · {text(issue, "status")?.replaceAll("_", " ")}</strong>
      <span>{text(issue, "description") ?? "—"} · {formatOptional(text(issue, "reportedAt"))}{array(issue, "evidence").map((entry, evidenceIndex) => {
        const evidence = asRecord(entry);
        return <EvidenceButton key={text(evidence, "id") ?? evidenceIndex} auth={auth} objectPath={text(evidence, "objectPath")} />;
      })}</span>
      {boolean(permissions, "canApproveReturns") || boolean(permissions, "canApproveRefunds") ? <IssueAction issue={issue} auth={auth} onChanged={onChanged} /> : null}
    </article>)}
    {state.returns.map((customerReturn, index) => {
      const mission = object(customerReturn, "mission");
      return <article key={text(customerReturn, "id") ?? index}>
        <strong>Return · {text(customerReturn, "status")?.replaceAll("_", " ")}</strong>
        <span>{array(customerReturn, "packages").length} package(s) · mission {text(mission, "status")?.replaceAll("_", " ") ?? "not started"} · custody {array(customerReturn, "packages").map((item) => text(asRecord(item), "custodyOwnerType") ?? "—").join(", ") || "—"}</span>
        {boolean(permissions, "canApproveReturns") && text(mission, "status") === "RIDER_SEARCH" ? <ReturnRiderAction mission={mission!} auth={auth} onChanged={onChanged} /> : null}
      </article>;
    })}
    {state.refunds.map((refund, index) => <article key={text(refund, "id") ?? index}>
      <strong>Refund · {text(refund, "status")?.replaceAll("_", " ")}</strong>
      <span>{formatV1Price(number(refund, "amountPaise") ?? 0)} · original payment method · {text(refund, "faultSource") ?? "UNKNOWN"}</span>
      {boolean(permissions, "canProcessRefunds") && ["APPROVED", "FAILED"].includes(text(refund, "status") ?? "") ? <RefundAction orderId={trace.order.id} refund={refund} auth={auth} onChanged={onChanged} /> : null}
    </article>)}
    {state.platformFees.map((fee, index) => <article key={text(fee, "id") ?? index}>
      <strong>Platform fee · {text(fee, "type")?.replaceAll("_", " ")}</strong>
      <span>{formatV1Price(number(fee, "amountPaise") ?? 0)} · immutable paid-total allocation · {formatOptional(text(fee, "createdAt"))}</span>
    </article>)}
    {state.royaltyBalances.map((balance, index) => <article key={`${text(balance, "subjectType")}:${text(balance, "subjectId")}:${index}`}>
      <strong>Royalty · {text(balance, "subjectType")?.replaceAll("_", " ")} · {shortId(text(balance, "subjectId"))}</strong>
      <span>Available {formatV1Price(number(balance, "availablePaise") ?? 0)} · negative {formatV1Price(number(balance, "negativeBalancePaise") ?? 0)} · derived balance {formatV1Price(number(balance, "balancePaise") ?? 0)}</span>
    </article>)}
    {state.royaltyLedger.map((entry, index) => <article key={text(entry, "id") ?? index}>
      <strong>{text(entry, "type")?.replaceAll("_", " ")} · {text(entry, "subjectType")?.replaceAll("_", " ")}</strong>
      <span>{formatV1Price(number(entry, "amountPaise") ?? 0)} · {text(entry, "reason") ?? "Audited financial event"} · {formatOptional(text(entry, "createdAt"))}</span>
    </article>)}
    {state.withdrawals.map((withdrawal, index) => <article key={text(withdrawal, "id") ?? index}>
      <strong>Withdrawal · {text(withdrawal, "status")?.replaceAll("_", " ")}</strong>
      <span>{formatV1Price(number(withdrawal, "amountPaise") ?? 0)} · {text(object(withdrawal, "destination"), "displayLabel") ?? "snapshotted payout destination"} · provider reference {text(withdrawal, "providerPayoutReference") ?? "not confirmed"}</span>
    </article>)}
    {state.settlements.map((settlement, index) => <article key={text(settlement, "id") ?? index}>
      <strong>{text(settlement, "subjectType")?.replaceAll("_", " ")} · {text(settlement, "status")}</strong>
      <span>{text(settlement, "entryType")?.replaceAll("_", " ")} · {formatV1Price(number(settlement, "amountPaise") ?? 0)} · calculation {text(settlement, "calculationStatus")?.replaceAll("_", " ")}{text(object(settlement, "payoutCadenceSnapshot"), "mode") ? ` · payout ${text(object(settlement, "payoutCadenceSnapshot"), "mode")}` : ""}</span>
      {boolean(permissions, "canManageSettlements") && text(settlement, "status") === "PENDING" ? <SettlementAction settlement={settlement} auth={auth} onChanged={onChanged} /> : null}
    </article>)}
  </TraceSection>;
}

function RecoveryAction({ recovery, auth, onChanged, preparedFoodPresent }: {
  recovery: Record<string, unknown>; auth: DastakV1Auth; onChanged: () => void;
  preparedFoodPresent: boolean;
}) {
  const [branchId, setBranchId] = useState("");
  const [reason, setReason] = useState("");
  const [faultSource, setFaultSource] = useState("RIDER");
  const [refundAmount, setRefundAmount] = useState("");
  const [addressLine, setAddressLine] = useState("");
  const [latitude, setLatitude] = useState("");
  const [longitude, setLongitude] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const id = text(recovery, "id");
  const version = number(recovery, "version");
  const type = text(recovery, "type");
  const status = text(recovery, "status");
  const correctedAddressValid = !addressLine.trim() && !latitude.trim() && !longitude.trim() ||
    Boolean(addressLine.trim()) && Boolean(latitude.trim()) && Boolean(longitude.trim()) &&
    Number.isFinite(Number(latitude)) && Number.isFinite(Number(longitude)) &&
    Number(latitude) >= -90 && Number(latitude) <= 90 && Number(longitude) >= -180 && Number(longitude) <= 180;
  const refundValid = !refundAmount.trim() ||
    faultSource !== "CUSTOMER" && Number.isInteger(Number(refundAmount)) && Number(refundAmount) > 0;
  const run = async (action: "offer" | "fail" | "resume" | "return") => {
    if (!id || !version || busy) return;
    setBusy(true); setError(undefined);
    try {
      if (action === "offer") await createV1ExactSkuRecoveryOffer({
        ...auth, recoveryCaseId: id, branchId, expectedVersion: version,
        idempotencyKey: crypto.randomUUID(),
      });
      else if (action === "fail") await failV1ExactSkuRecovery({
        ...auth, recoveryCaseId: id, reason, expectedVersion: version,
        idempotencyKey: crypto.randomUUID(),
      });
      else await manageV1DeliveryRecovery({
        ...auth, recoveryCaseId: id,
        action: action === "resume" ? "RESUME_DELIVERY" : "RETURN_TO_ORIGIN",
        faultSource,
        refundAmountPaise: action === "return" && refundAmount.trim()
          ? Number(refundAmount)
          : undefined,
        correctedAddress: action === "resume" && addressLine.trim()
          ? { line1: addressLine.trim(), latitude: Number(latitude), longitude: Number(longitude) }
          : undefined,
        reason, expectedVersion: version, idempotencyKey: crypto.randomUUID(),
      });
      onChanged();
    } catch (actionError) { setError(message(actionError)); }
    finally { setBusy(false); }
  };
  if (!["OPEN", "SEARCHING_EXACT_SKU", "ACTION_REQUIRED"].includes(status ?? "")) return null;
  return <div className="v1-exceptional-handoff">
    {type === "EXACT_SKU" ? <><label>Candidate branch UUID<input value={branchId} onChange={(event) => setBranchId(event.target.value)} placeholder="Branch UUID" /></label><button className="secondary-button" type="button" disabled={busy || !uuid(branchId)} onClick={() => void run("offer")}>Offer exact SKU to branch</button></> : null}
    {type === "DELIVERY" ? <>
      <label>Fault source<select value={faultSource} onChange={(event) => setFaultSource(event.target.value)}><option>RIDER</option><option>MERCHANT</option><option>DASTAK</option><option>CUSTOMER</option></select></label>
      <label>Corrected address line (optional, resume only)<input value={addressLine} maxLength={300} onChange={(event) => setAddressLine(event.target.value)} /></label>
      <label>Corrected latitude<input inputMode="decimal" value={latitude} onChange={(event) => setLatitude(event.target.value)} /></label>
      <label>Corrected longitude<input inputMode="decimal" value={longitude} onChange={(event) => setLongitude(event.target.value)} /></label>
      <label>Return refund in paise (optional)<input type="number" min={1} value={refundAmount} onChange={(event) => setRefundAmount(event.target.value)} /></label>
    </> : null}
    <label>Operations reason<textarea value={reason} minLength={3} maxLength={500} onChange={(event) => setReason(event.target.value)} /></label>
    {type === "EXACT_SKU" ? <button className="danger-button" type="button" disabled={busy || reason.trim().length < 3} onClick={() => void run("fail")}>Close recovery as failed</button> : <>
      <button className="primary-button" type="button" disabled={busy || reason.trim().length < 10 || !correctedAddressValid} onClick={() => void run("resume")}>Resume assigned delivery</button>
      {preparedFoodPresent
        ? <small>Prepared food cannot enter return-to-origin custody. Resume delivery or use the investigation/refund resolution path.</small>
        : <button className="danger-button" type="button" disabled={busy || reason.trim().length < 10 || !refundValid} onClick={() => void run("return")}>Start return to origin</button>}
    </>}
    {error ? <p className="order-error" role="alert">{error}</p> : null}
  </div>;
}

function IssueAction({ issue, auth, onChanged }: {
  issue: Record<string, unknown>; auth: DastakV1Auth; onChanged: () => void;
}) {
  const [decision, setDecision] = useState<"REJECT" | "RESOLVE_NO_REFUND" | "REFUND_WITHOUT_RETURN" | "PHYSICAL_RETURN">("RESOLVE_NO_REFUND");
  const [faultSource, setFaultSource] = useState("UNKNOWN");
  const [amount, setAmount] = useState("");
  const [packages, setPackages] = useState("1");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  if (!["OPEN", "UNDER_REVIEW"].includes(text(issue, "status") ?? "")) return null;
  const physicalReturnAllowed = boolean(issue, "physicalReturnAllowed") === true;
  const preparedFood = boolean(issue, "preparedFood") === true;
  const requiresRefund = decision === "REFUND_WITHOUT_RETURN" || decision === "PHYSICAL_RETURN";
  const submit = async () => {
    const id = text(issue, "id"); const version = number(issue, "version");
    if (!id || !version || busy) return;
    setBusy(true); setError(undefined);
    try {
      await decideV1CustomerIssue({
        ...auth, issueId: id, decision,
        refundAmountPaise: requiresRefund ? Number(amount) : undefined,
        faultSource: requiresRefund ? faultSource : undefined,
        returnPackageCount: decision === "PHYSICAL_RETURN" ? Number(packages) : undefined,
        reason, expectedVersion: version, idempotencyKey: crypto.randomUUID(),
      });
      onChanged();
    } catch (actionError) { setError(message(actionError)); }
    finally { setBusy(false); }
  };
  return <div className="v1-exceptional-handoff">
    <label>Decision<select value={decision} onChange={(event) => setDecision(event.target.value as typeof decision)}><option value="RESOLVE_NO_REFUND">Resolve without refund</option><option value="REFUND_WITHOUT_RETURN">Refund without physical return</option>{physicalReturnAllowed ? <option value="PHYSICAL_RETURN">Require physical return</option> : null}<option value="REJECT">Reject</option></select></label>
    {preparedFood ? <small>Prepared-food issues use investigation/refund resolution; physical return is forbidden.</small> : null}
    {requiresRefund ? <><label>Refund amount (paise)<input type="number" min={1} value={amount} onChange={(event) => setAmount(event.target.value)} /></label><label>Fault source<select value={faultSource} onChange={(event) => setFaultSource(event.target.value)}><option>UNKNOWN</option><option>MERCHANT</option><option>RIDER</option><option>DASTAK</option><option>CUSTOMER</option><option>NONE</option></select></label></> : null}
    {decision === "PHYSICAL_RETURN" ? <label>Return package count<input type="number" min={1} value={packages} onChange={(event) => setPackages(event.target.value)} /></label> : null}
    <label>Recorded reason<textarea minLength={3} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
    <button className="primary-button" type="button" disabled={busy || reason.trim().length < 3 || (requiresRefund && Number(amount) < 1) || (decision === "PHYSICAL_RETURN" && Number(packages) < 1)} onClick={() => void submit()}>{busy ? "Recording…" : "Record decision"}</button>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
  </div>;
}

function ReturnRiderAction({ mission, auth, onChanged }: {
  mission: Record<string, unknown>; auth: DastakV1Auth; onChanged: () => void;
}) {
  const [riderId, setRiderId] = useState(""); const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const assign = async () => {
    const missionId = text(mission, "id"); const version = number(mission, "version");
    if (!missionId || !version || !uuid(riderId)) return;
    setBusy(true); setError(undefined);
    try { await assignV1ReturnRider({ ...auth, returnMissionId: missionId, riderId, expectedVersion: version, idempotencyKey: crypto.randomUUID() }); onChanged(); }
    catch (actionError) { setError(message(actionError)); } finally { setBusy(false); }
  };
  return <div className="v1-exceptional-handoff"><label>Eligible rider UUID<input value={riderId} onChange={(event) => setRiderId(event.target.value)} /></label><button className="primary-button" type="button" disabled={busy || !uuid(riderId)} onClick={() => void assign()}>Assign return rider</button>{error ? <p className="order-error" role="alert">{error}</p> : null}</div>;
}

function RefundAction({ orderId, refund, auth, onChanged }: {
  orderId: string; refund: Record<string, unknown>; auth: DastakV1Auth; onChanged: () => void;
}) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState<string>();
  const process = async () => {
    const refundId = text(refund, "id"); if (!refundId) return;
    setBusy(true); setError(undefined);
    try { await processV1Refund({ ...auth, orderId, refundId, idempotencyKey: crypto.randomUUID() }); onChanged(); }
    catch (actionError) { setError(message(actionError)); } finally { setBusy(false); }
  };
  return <div className="v1-exceptional-handoff"><button className="primary-button" type="button" disabled={busy} onClick={() => void process()}>{busy ? "Submitting…" : "Process original-method refund"}</button>{error ? <p className="order-error" role="alert">{error}</p> : null}</div>;
}

function SettlementAction({ settlement, auth, onChanged }: {
  settlement: Record<string, unknown>; auth: DastakV1Auth; onChanged: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const id = text(settlement, "id");
  const version = number(settlement, "version");
  const run = async () => {
    if (!id || !version) return; setBusy(true); setError(undefined);
    try {
      await finalizeV1SettlementCalculation({ ...auth, settlementEntryId: id, expectedVersion: version, idempotencyKey: crypto.randomUUID() });
      onChanged();
    } catch (actionError) { setError(message(actionError)); } finally { setBusy(false); }
  };
  return <div className="v1-exceptional-handoff"><button className="primary-button" type="button" disabled={busy} onClick={() => void run()}>Finalize calculation</button>{error ? <p className="order-error" role="alert">{error}</p> : null}</div>;
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
function asRecord(value: unknown) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
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
function shortId(value?: string) {
  return value ? value.slice(0, 8).toUpperCase() : "—";
}
function message(error: unknown) {
  return error instanceof Error ? error.message : "The V1 execution trace is unavailable.";
}
function uuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
