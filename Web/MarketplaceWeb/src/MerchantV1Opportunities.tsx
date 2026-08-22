import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  AlertTriangle, Camera, Check, Clock3, PackageCheck, RefreshCw, Timer, X,
} from "lucide-react";
import {
  addV1FulfilmentReadyEvidence,
  declareV1FulfilmentPackages,
  getV1MerchantFulfilments,
  getV1MerchantOpportunities,
  markV1FulfilmentReady,
  reportV1FulfilmentProblem,
  respondToV1MerchantOpportunity,
  uploadV1MerchantReadyEvidence,
  type DastakV1Auth,
  type V1MerchantFulfilment,
  type V1MerchantOpportunity,
} from "./dastakV1";

type Props = {
  auth: DastakV1Auth;
  client: SupabaseClient;
  accountId: string;
};

export function MerchantV1Opportunities({ auth, client, accountId }: Props) {
  const [opportunities, setOpportunities] = useState<V1MerchantOpportunity[]>([]);
  const [fulfilments, setFulfilments] = useState<V1MerchantFulfilment[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyId, setBusyId] = useState<string>();
  const [error, setError] = useState<string>();
  const [confirmed, setConfirmed] = useState<Set<string>>(() => new Set());
  const [readyConfirmed, setReadyConfirmed] = useState<Set<string>>(() => new Set());
  const [prepMinutes, setPrepMinutes] = useState<Record<string, number>>({});
  const [packageCounts, setPackageCounts] = useState<Record<string, number>>({});
  const [evidenceFiles, setEvidenceFiles] = useState<Record<string, File | undefined>>({});
  const [problemId, setProblemId] = useState<string>();
  const [problemReason, setProblemReason] = useState("");
  const [now, setNow] = useState(() => Date.now());
  const keys = useRef(new Map<string, string>());
  const uploadedEvidence = useRef(new Map<string, string>());

  const refresh = useCallback(async (showProgress = false) => {
    if (showProgress) setRefreshing(true);
    try {
      const [opportunityResult, fulfilmentResult] = await Promise.all([
        getV1MerchantOpportunities({ ...auth, limit: 50 }),
        getV1MerchantFulfilments({ ...auth, limit: 50 }),
      ]);
      setOpportunities(opportunityResult);
      setFulfilments(fulfilmentResult);
      setPrepMinutes((current) => {
        const next = { ...current };
        opportunityResult.forEach((opportunity) => {
          next[opportunity.id] ??= opportunity.promisedPrepMinutes ?? opportunity.prepTimeOptionsMinutes[0] ?? 10;
        });
        return next;
      });
      setPackageCounts((current) => {
        const next = { ...current };
        fulfilmentResult.forEach((fulfilment) => { next[fulfilment.id] ??= fulfilment.packageCount ?? 1; });
        return next;
      });
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      setLoading(false);
      if (showProgress) setRefreshing(false);
    }
  }, [auth]);

  useEffect(() => {
    void refresh();
    const poll = window.setInterval(() => void refresh(), 10_000);
    const clock = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => {
      window.clearInterval(poll);
      window.clearInterval(clock);
    };
  }, [refresh]);

  const keyFor = (identity: string) => {
    const key = keys.current.get(identity) ?? crypto.randomUUID();
    keys.current.set(identity, key);
    return key;
  };

  const respond = async (opportunity: V1MerchantOpportunity, action: "accept" | "unavailable") => {
    if (busyId || (action === "accept" && !confirmed.has(opportunity.id))) return;
    const identity = `${action}:${opportunity.id}:${opportunity.version}`;
    setBusyId(opportunity.id);
    setError(undefined);
    try {
      await respondToV1MerchantOpportunity({
        ...auth,
        opportunityId: opportunity.id,
        requestScope: opportunity.requestScope,
        expectedVersion: opportunity.version,
        action,
        promisedPrepMinutes: action === "accept" ? prepMinutes[opportunity.id] : undefined,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      await refresh();
    } catch (responseError) {
      setError(message(responseError));
      await refresh();
    } finally {
      setBusyId(undefined);
    }
  };

  const captureEvidence = async (fulfilment: V1MerchantFulfilment) => {
    const file = evidenceFiles[fulfilment.id];
    if (!file) throw new Error("Capture or choose a prepared-order photo first.");
    let objectPath = uploadedEvidence.current.get(fulfilment.id);
    if (!objectPath) {
      objectPath = await uploadV1MerchantReadyEvidence(client, accountId, file);
      uploadedEvidence.current.set(fulfilment.id, objectPath);
    }
    const identity = `evidence:${fulfilment.id}:${fulfilment.version}:${objectPath}`;
    const updated = await addV1FulfilmentReadyEvidence({
      ...auth,
      fulfilmentId: fulfilment.id,
      packageId: fulfilment.packages[0]?.id,
      objectPath,
      expectedVersion: fulfilment.version,
      idempotencyKey: keyFor(identity),
    });
    keys.current.delete(identity);
    uploadedEvidence.current.delete(fulfilment.id);
    setEvidenceFiles((current) => ({ ...current, [fulfilment.id]: undefined }));
    setFulfilments((current) => current.map((item) => item.id === updated.id ? updated : item));
    return updated;
  };

  const markReady = async (fulfilment: V1MerchantFulfilment) => {
    if (busyId || !readyConfirmed.has(fulfilment.id)) return;
    setBusyId(fulfilment.id);
    setError(undefined);
    try {
      let current = fulfilment;
      if (!current.packageCount) {
        const packageCount = packageCounts[current.id];
        if (!Number.isSafeInteger(packageCount) || packageCount < 1 || packageCount > 1000) {
          throw new Error("Enter a package count of at least 1.");
        }
        const identity = `packages:${current.id}:${current.version}:${packageCount}`;
        current = await declareV1FulfilmentPackages({
          ...auth,
          fulfilmentId: current.id,
          packageCount,
          expectedVersion: current.version,
          idempotencyKey: keyFor(identity),
        });
        keys.current.delete(identity);
        setFulfilments((values) => values.map((item) => item.id === current.id ? current : item));
      }
      if (current.evidence.length === 0) current = await captureEvidence(current);
      const identity = `ready:${current.id}:${current.version}`;
      const ready = await markV1FulfilmentReady({
        ...auth,
        fulfilmentId: current.id,
        expectedVersion: current.version,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      setFulfilments((values) => values.map((item) => item.id === ready.id ? ready : item));
      setReadyConfirmed((values) => without(values, ready.id));
    } catch (readyError) {
      setError(message(readyError));
      await refresh();
    } finally {
      setBusyId(undefined);
    }
  };

  const addPhoto = async (fulfilment: V1MerchantFulfilment) => {
    if (busyId || !fulfilment.packageCount) return;
    setBusyId(fulfilment.id);
    setError(undefined);
    try {
      await captureEvidence(fulfilment);
    } catch (evidenceError) {
      setError(message(evidenceError));
      await refresh();
    } finally {
      setBusyId(undefined);
    }
  };

  const reportProblem = async (fulfilment: V1MerchantFulfilment) => {
    const reason = problemReason.trim();
    if (busyId || reason.length < 3) return;
    const identity = `problem:${fulfilment.id}:${fulfilment.version}:${reason}`;
    setBusyId(fulfilment.id);
    setError(undefined);
    try {
      const updated = await reportV1FulfilmentProblem({
        ...auth,
        fulfilmentId: fulfilment.id,
        reason,
        expectedVersion: fulfilment.version,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      setFulfilments((values) => values.map((item) => item.id === updated.id ? updated : item));
      setProblemId(undefined);
      setProblemReason("");
    } catch (problemError) {
      setError(message(problemError));
      await refresh();
    } finally {
      setBusyId(undefined);
    }
  };

  const visibleOpportunities = useMemo(
    () => opportunities.filter((opportunity) =>
      opportunity.status === "OFFERED" ||
      ["ITEMS_HELD_WHILE_ORDER_COMPLETES", "WAITING_FOR_CUSTOMER_PAYMENT", "PAYMENT_CONFIRMED", "RESERVATION_RELEASED"]
        .includes(opportunity.reservationState)
    ),
    [opportunities],
  );
  const activeFulfilments = useMemo(
    () => fulfilments.filter((fulfilment) =>
      fulfilment.status === "PREPARING" || fulfilment.status === "READY" ||
      fulfilment.status === "PICKED_UP"),
    [fulfilments],
  );

  return <section className="v1-merchant-panel" aria-labelledby="v1-merchant-title">
    <header>
      <div><p className="eyebrow">DASTAK V1</p><h2 id="v1-merchant-title">Launch fulfilments</h2><span>Confirm exact items, then prepare every declared package after payment.</span></div>
      <button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={refreshing} aria-label="Refresh V1 fulfilments"><RefreshCw size={18} /></button>
    </header>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {loading ? <div className="catalogue-loading" role="status"><span /> Loading V1 fulfilments</div> : <>
      {activeFulfilments.length > 0 ? <div className="v1-preparation-list">
        {activeFulfilments.map((fulfilment) => <FulfilmentCard
          key={fulfilment.id}
          fulfilment={fulfilment}
          now={now}
          busy={busyId === fulfilment.id}
          packageCount={packageCounts[fulfilment.id] ?? 1}
          evidenceFile={evidenceFiles[fulfilment.id]}
          irreversibleConfirmed={readyConfirmed.has(fulfilment.id)}
          reportingProblem={problemId === fulfilment.id}
          problemReason={problemId === fulfilment.id ? problemReason : ""}
          onPackageCount={(value) => setPackageCounts((current) => ({ ...current, [fulfilment.id]: value }))}
          onEvidenceFile={(file) => {
            uploadedEvidence.current.delete(fulfilment.id);
            setEvidenceFiles((current) => ({ ...current, [fulfilment.id]: file }));
          }}
          onIrreversibleConfirm={(checked) => setReadyConfirmed((current) => checked ? withValue(current, fulfilment.id) : without(current, fulfilment.id))}
          onAddPhoto={() => void addPhoto(fulfilment)}
          onMarkReady={() => void markReady(fulfilment)}
          onStartProblem={() => { setProblemId(fulfilment.id); setProblemReason(""); }}
          onCancelProblem={() => { setProblemId(undefined); setProblemReason(""); }}
          onProblemReason={setProblemReason}
          onReportProblem={() => void reportProblem(fulfilment)}
        />)}
      </div> : null}
      {visibleOpportunities.length === 0 ? <p className="v1-merchant-empty">No item requests waiting right now.</p> : <div className="v1-opportunity-list">
        {visibleOpportunities.map((opportunity) => {
          const seconds = Math.max(0, Math.ceil((Date.parse(opportunity.expiresAt) - now) / 1_000));
          const offered = opportunity.status === "OFFERED" && seconds > 0;
          const busy = busyId === opportunity.id;
          return <article className="v1-opportunity-card" key={opportunity.id}>
            <header>
              <span className="v1-opportunity-icon"><PackageCheck size={20} /></span>
              <span><strong>{opportunity.displayOrderNumber}</strong><small>{opportunity.requestScope === "FULL_BASKET" ? "Complete basket request" : "Exact subset request"} · {opportunity.branch.displayName}</small></span>
              {offered ? <b><Clock3 size={14} /> {formatDuration(seconds)}</b> : <b>{reservationLabel(opportunity)}</b>}
            </header>
            <LineList lines={opportunity.lines} />
            {offered ? <>
              <label className="v1-physical-check"><input type="checkbox" checked={confirmed.has(opportunity.id)} onChange={(event) => setConfirmed((current) => event.target.checked ? withValue(current, opportunity.id) : without(current, opportunity.id))} /><span>I physically confirmed every exact SKU and quantity above.</span></label>
              <label className="v1-prep-choice"><span>Preparation promise</span><select value={prepMinutes[opportunity.id] ?? opportunity.prepTimeOptionsMinutes[0]} onChange={(event) => setPrepMinutes((current) => ({ ...current, [opportunity.id]: Number(event.target.value) }))}>{opportunity.prepTimeOptionsMinutes.map((minutes) => <option key={minutes} value={minutes}>{minutes} minutes</option>)}</select></label>
              <div className="v1-opportunity-actions"><button className="secondary-button" type="button" disabled={busy} onClick={() => void respond(opportunity, "unavailable")}><X size={17} /> Unavailable</button><button className="primary-button" type="button" disabled={busy || !confirmed.has(opportunity.id)} onClick={() => void respond(opportunity, "accept")}><Check size={17} /> {busy ? "Confirming…" : "Accept and hold items"}</button></div>
            </> : <p className={`v1-reservation-state ${opportunity.reservationState.toLowerCase()}`}>{reservationCopy(opportunity)}</p>}
          </article>;
        })}
      </div>}
    </>}
  </section>;
}

type FulfilmentCardProps = {
  fulfilment: V1MerchantFulfilment;
  now: number;
  busy: boolean;
  packageCount: number;
  evidenceFile?: File;
  irreversibleConfirmed: boolean;
  reportingProblem: boolean;
  problemReason: string;
  onPackageCount: (value: number) => void;
  onEvidenceFile: (file?: File) => void;
  onIrreversibleConfirm: (checked: boolean) => void;
  onAddPhoto: () => void;
  onMarkReady: () => void;
  onStartProblem: () => void;
  onCancelProblem: () => void;
  onProblemReason: (reason: string) => void;
  onReportProblem: () => void;
};

function FulfilmentCard(props: FulfilmentCardProps) {
  const { fulfilment } = props;
  const preparing = fulfilment.status === "PREPARING";
  const remaining = fulfilment.estimatedReadyAt
    ? Math.ceil((Date.parse(fulfilment.estimatedReadyAt) - props.now) / 1_000)
    : 0;
  const runningLate = preparing && remaining < 0;
  const hasRequiredEvidence = fulfilment.evidence.some((item) => item.type === "MERCHANT_READY_PHOTO");
  const readyActionEnabled = props.irreversibleConfirmed &&
    (fulfilment.packageCount !== undefined || props.packageCount >= 1) &&
    (hasRequiredEvidence || Boolean(props.evidenceFile));

  return <article className={`v1-preparation-card ${runningLate ? "running-late" : ""}`}>
    <header>
      <span className="v1-opportunity-icon">{runningLate ? <AlertTriangle size={20} /> : <Timer size={20} />}</span>
      <span><strong>{fulfilment.displayOrderNumber}</strong><small>{fulfilment.branch.displayName} · {fulfilment.promisedPrepMinutes}-minute promise</small></span>
      <b>{fulfilment.status === "PICKED_UP" ? "PICKED UP" : fulfilment.status === "READY" ? "READY FOR PICKUP" : runningLate ? `RUNNING LATE · +${formatDuration(Math.abs(remaining))}` : formatDuration(Math.max(0, remaining))}</b>
    </header>
    <LineList lines={fulfilment.lines} />
    <div className="v1-preparation-times">
      <span><small>Payment confirmed</small><strong>{formatOptionalTime(fulfilment.prepStartedAt)}</strong></span>
      <span><small>Promised Ready</small><strong>{formatOptionalTime(fulfilment.estimatedReadyAt)}</strong></span>
      <span><small>Actual Ready</small><strong>{formatOptionalTime(fulfilment.actualReadyAt)}</strong></span>
    </div>
    {fulfilment.delivery ? <div className="v1-merchant-pickup-state">
      <span><small>Delivery partner</small><strong>{fulfilment.delivery.riderAssigned ? fulfilment.delivery.rider?.displayName ?? "Assigned" : "Finding rider"}</strong></span>
      <span><small>Pickup status</small><strong>{merchantPickupLabel(fulfilment.delivery.stopStatus, fulfilment.delivery.riderArrivedAt)}</strong></span>
      <span><small>Waiting</small><strong>{fulfilment.delivery.riderArrivedAt ? formatDuration(fulfilment.delivery.waitingSeconds) : "—"}</strong></span>
      {fulfilment.delivery.pickupCode ? <div className="v1-merchant-pickup-code"><small>Give this in-app code to the assigned rider after every package is present</small><strong>{fulfilment.delivery.pickupCode}</strong></div> : null}
      {fulfilment.delivery.verificationStatus === "CONSUMED" ? <p><Check size={17} /> Pickup verified. Package custody transferred to the rider.</p> : null}
    </div> : null}
    {preparing ? <div className="v1-ready-workflow">
      <label><span>Physical package count</span><input type="number" inputMode="numeric" min={1} max={1000} value={fulfilment.packageCount ?? props.packageCount} disabled={fulfilment.packageCount !== undefined || props.busy} onChange={(event) => props.onPackageCount(Number(event.target.value))} />{fulfilment.packageCount ? <small>Declared and locked for pickup</small> : <small>All packages will transfer together in the next delivery step.</small>}</label>
      <label className="v1-photo-field"><span>Prepared items / package photo</span><input type="file" accept="image/jpeg,image/png,image/heic" capture="environment" disabled={props.busy} onChange={(event) => props.onEvidenceFile(event.target.files?.[0])} /><small>{props.evidenceFile?.name ?? (hasRequiredEvidence ? `${fulfilment.evidence.length} immutable photo(s) recorded` : "Required before Ready · JPG, PNG or HEIC up to 10 MB")}</small></label>
      {hasRequiredEvidence && props.evidenceFile ? <button className="secondary-button v1-add-photo" type="button" disabled={props.busy} onClick={props.onAddPhoto}><Camera size={17} /> {props.busy ? "Recording…" : "Add another photo"}</button> : null}
      <label className="v1-physical-check"><input type="checkbox" checked={props.irreversibleConfirmed} disabled={props.busy} onChange={(event) => props.onIrreversibleConfirm(event.target.checked)} /><span>I confirm every declared package is complete. Ready is irreversible.</span></label>
      <button className="primary-button v1-mark-ready" type="button" disabled={props.busy || !readyActionEnabled} onClick={props.onMarkReady}><PackageCheck size={18} /> {props.busy ? "Finalising Ready…" : "Mark Ready"}</button>
    </div> : <p className="v1-ready-complete"><PackageCheck size={18} /> {fulfilment.packageCount} package(s) {fulfilment.status === "PICKED_UP" ? "picked up together" : "Ready"}. Original evidence and Ready time are locked.</p>}
    {fulfilment.evidence.length > 0 ? <p className="v1-evidence-count"><Camera size={15} /> {fulfilment.evidence.length} immutable evidence photo(s)</p> : null}
    {fulfilment.status !== "PICKED_UP" ? (props.reportingProblem ? <div className="v1-problem-form"><label><span>Problem details</span><textarea value={props.problemReason} maxLength={500} rows={3} autoFocus onChange={(event) => props.onProblemReason(event.target.value)} /></label><div><button className="secondary-button" type="button" disabled={props.busy} onClick={props.onCancelProblem}>Back</button><button className="primary-button" type="button" disabled={props.busy || props.problemReason.trim().length < 3} onClick={props.onReportProblem}>{props.busy ? "Reporting…" : "Report problem"}</button></div></div> : <button className="v1-report-problem" type="button" disabled={props.busy} onClick={props.onStartProblem}><AlertTriangle size={16} /> Report problem</button>) : null}
    {fulfilment.problemReports.length > 0 ? <small className="v1-problem-history">{fulfilment.problemReports.length} problem report(s) preserved for operator review.</small> : null}
  </article>;
}

function merchantPickupLabel(status: "PENDING" | "ARRIVED" | "COMPLETED", arrivedAt?: string) {
  if (status === "COMPLETED") return "Picked Up";
  if (status === "ARRIVED" || arrivedAt) return "Rider arrived";
  return "Rider assigned";
}

function LineList({ lines }: { lines: V1MerchantOpportunity["lines"] }) {
  return <ul>{lines.map((line) => <li key={line.orderLineId}><span><strong>{line.quantity}× {line.name}</strong><small>{[line.variant, line.packSize].filter(Boolean).join(" · ")}</small></span></li>)}</ul>;
}

function reservationLabel(opportunity: V1MerchantOpportunity) {
  switch (opportunity.reservationState) {
    case "ITEMS_HELD_WHILE_ORDER_COMPLETES": return "Held provisionally";
    case "WAITING_FOR_CUSTOMER_PAYMENT": return "Waiting for payment";
    case "PAYMENT_CONFIRMED": return "Won · paid";
    case "RESERVATION_RELEASED": return "Released";
    default: return opportunity.status.replaceAll("_", " ").toLowerCase();
  }
}

function reservationCopy(opportunity: V1MerchantOpportunity) {
  switch (opportunity.reservationState) {
    case "ITEMS_HELD_WHILE_ORDER_COMPLETES": return "Items held while Dastak completes the order. No preparation capacity is consumed yet.";
    case "WAITING_FOR_CUSTOMER_PAYMENT": return "Selected for the final plan. Keep items reserved; preparation has not started.";
    case "PAYMENT_CONFIRMED": return "Payment is confirmed. Continue in the preparation card above.";
    case "RESERVATION_RELEASED": return "Reservation released. Return these items to normal availability.";
    default: return "This request is no longer awaiting a response.";
  }
}

function withValue(values: Set<string>, value: string) {
  const next = new Set(values);
  next.add(value);
  return next;
}
function without(values: Set<string>, value: string) {
  const next = new Set(values);
  next.delete(value);
  return next;
}
function formatDuration(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
function formatOptionalTime(value?: string) {
  return value ? new Intl.DateTimeFormat("en-IN", { hour: "numeric", minute: "2-digit" }).format(new Date(value)) : "—";
}
function message(error: unknown) {
  return error instanceof Error ? error.message : "V1 fulfilments are unavailable right now.";
}
