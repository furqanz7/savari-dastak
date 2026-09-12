import { useCallback, useEffect, useRef, useState } from "react";
import { Bike, CheckCircle2, Clock3, Search, ShieldAlert } from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import {
  getV1AdminDeliveryPartnerGovernancePage,
  setV1AdminDeliveryPartnerStatus,
  type DastakV1Auth,
  type V1AdminDeliveryPartnerGovernanceRow,
} from "./dastakV1";
import { adminFeedFailed, adminFeedHasContent, adminFeedStarted, adminFeedSucceeded, initialAdminFeedState } from "./adminRuntime";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

type Intent = {
  dialog: AdminPrivilegedActionIntent;
  operationIdentity: string;
  mutate: (idempotencyKey: string, reason: string) => Promise<unknown>;
  success: string;
};

const reasonOptions = [
  "Safety review",
  "Identity/evidence concern",
  "Suspected account compromise",
  "Compliance",
  "Repeated custody failure",
  "Rider request",
  "Other",
] as const;

export function AdminDeliveryPartnerGovernancePanel({ auth }: { auth: DastakV1Auth }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"" | "ACTIVE" | "SUSPENDED">("");
  const [rows, setRows] = useState<V1AdminDeliveryPartnerGovernanceRow[]>([]);
  const [cursor, setCursor] = useState<{ updatedAt: string; riderId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [feedState, setFeedState] = useState(initialAdminFeedState());
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [reconciliationBlocked, setReconciliationBlocked] = useState(false);
  const [intent, setIntent] = useState<Intent>();
  const requestGeneration = useRef(0);
  const controller = useRef<AbortController | undefined>(undefined);
  const queue = useRef(new RefreshQueue());
  const { reportRequestError } = useAdminRuntime();
  const normalizedQuery = query.trim();

  const load = useCallback(async (append: boolean, signal?: AbortSignal) => {
    const generation = ++requestGeneration.current;
    if (append) setLoadingMore(true);
    else setFeedState((current) => adminFeedStarted(current));
    try {
      const page = await getV1AdminDeliveryPartnerGovernancePage({
        ...auth,
        query: normalizedQuery,
        status: status || undefined,
        limit: 40,
        cursor: append ? cursor : undefined,
        signal,
      });
      if (signal?.aborted || generation !== requestGeneration.current) return;
      setRows((current) => append ? mergeRows(current, page.deliveryPartners) : page.deliveryPartners);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore);
      setFeedState((current) => adminFeedSucceeded(current));
      setError(undefined);
    } catch (cause) {
      if (signal?.aborted || generation !== requestGeneration.current) return;
      reportRequestError(cause);
      setFeedState((current) => adminFeedFailed(current, cause));
      setError(message(cause));
      throw cause;
    } finally {
      if (generation === requestGeneration.current) setLoadingMore(false);
    }
  }, [auth, cursor, normalizedQuery, reportRequestError, status]);

  const refresh = useCallback(() => queue.current.request(false, async () => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    await load(false, next.signal);
  }), [load]);

  useEffect(() => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    const timer = window.setTimeout(() => void load(false, next.signal).catch(() => undefined), 250);
    return () => { window.clearTimeout(timer); next.abort(); };
    // Cursor belongs only to append loading.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, normalizedQuery, status]);
  useAdminWorkspaceRefresh("deliveryPartnerGovernance", refresh);

  const reviewStatus = (row: V1AdminDeliveryPartnerGovernanceRow) => {
    const suspending = row.governance.status === "ACTIVE";
    const target = suspending ? "SUSPENDED" : "ACTIVE";
    setIntent({
      operationIdentity: `delivery-partner-governance:${row.rider.accountId}:${row.governance.version}:${target}`,
      success: `Delivery Partner ${suspending ? "suspended" : "reactivated"}.`,
      dialog: {
        eyebrow: "Delivery Partner governance",
        title: `${suspending ? "Suspend" : "Reactivate"} Delivery Partner?`,
        entityLabel: "Delivery Partner",
        entityValue: `${row.rider.displayName} · ${row.rider.maskedPhoneNumber ?? row.rider.accountId}`,
        currentState: `${row.governance.status} · ${row.availability.status} · version ${row.governance.version}`,
        resultingState: suspending ? "SUSPENDED · OFFLINE" : "ACTIVE · OFFLINE",
        consequence: suspending
          ? "Suspension prevents availability and new work across V1 delivery, returns, legacy courier and parcel delivery. Any active work or physical custody blocks this action and must be handled through the existing recovery or release workflow first. Historical missions, evidence and earnings remain intact."
          : "Eligibility is restored, but the rider remains offline and must explicitly go online again through the normal availability flow. Historical work and evidence remain unchanged.",
        confirmLabel: suspending ? "Confirm suspension" : "Confirm reactivation",
        tone: suspending ? "danger" : "primary",
        reasonOptions,
        confirmationValue: suspending ? row.rider.displayName : undefined,
      },
      mutate: (idempotencyKey, reason) => setV1AdminDeliveryPartnerStatus({
        ...auth,
        riderId: row.rider.accountId,
        status: target,
        expectedGovernanceVersion: row.governance.version,
        reason,
        idempotencyKey,
      }),
    });
  };

  const perform = async (reason: string) => {
    if (!intent || busy) return;
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    setReconciliationBlocked(false);
    const result = await runAdminPrivilegedMutation({
      operationIdentity: intent.operationIdentity,
      mutate: (key) => intent.mutate(key, reason),
      reconcile: refresh,
    });
    setBusy(false);
    if (result.kind === "completed") {
      setNotice(intent.success);
      setIntent(undefined);
      await refresh().catch(() => undefined);
    } else if (result.kind === "reconciled" || result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      setIntent(undefined);
    } else if (result.kind === "uncertain_blocked") {
      setReconciliationBlocked(true);
      setError(result.message);
    } else {
      reportRequestError(result.error);
      setError(message(result.error));
    }
  };

  const reconcileIntent = async () => {
    setBusy(true);
    try {
      await refresh();
      setReconciliationBlocked(false);
      setNotice("Authoritative Delivery Partner state was reloaded. Review it before acting again.");
      setIntent(undefined);
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  return <section className="admin-section admin-delivery-partner-governance" role="tabpanel">
    <header className="admin-section-heading"><div><p className="eyebrow">DELIVERY PARTNER GOVERNANCE</p><h2>Rider eligibility</h2><p>Govern rider eligibility without weakening active-work custody, approval history or availability controls.</p></div></header>
    <div className="admin-governance-filters">
      <label className="admin-search admin-governance-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search rider, phone or exact account/application ID" aria-label="Search Delivery Partner governance" /></label>
      <label><span>Governance status</span><select value={status} onChange={(event) => setStatus(event.target.value as typeof status)}><option value="">All statuses</option><option value="ACTIVE">Active</option><option value="SUSPENDED">Suspended</option></select></label>
    </div>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {notice ? <p className="admin-access-message success" role="status">{notice}</p> : null}
    {feedState.phase === "loading" ? <div className="admin-directory-loading" role="status"><span /><p>Loading governed Delivery Partners…</p></div> : null}
    {rows.length === 0 && adminFeedHasContent(feedState) ? <div className="admin-empty-state"><Bike size={28} /><h3>No Delivery Partners match</h3><p>Try another identity, exact ID or governance status.</p></div> : null}
    <div className="admin-governance-list">
      {rows.map((row) => <article className="admin-governance-card" key={row.rider.accountId}>
        <header>
          <span className="admin-person-mark" aria-hidden="true"><Bike size={20} /></span>
          <div><p className="eyebrow">{label(row.transportMethod)}</p><h3>{row.rider.displayName}</h3><p>{row.rider.maskedPhoneNumber ?? row.rider.accountId}</p></div>
          <div className="admin-governance-statuses"><Status value={row.governance.status} label="Governance" /><Status value={row.availability.status} label="Availability" /></div>
        </header>
        <div className="admin-governance-branch">
          <div><strong>Approved rider profile</strong><span><CheckCircle2 size={14} /> {label(row.approval.status)} · evidence summary: identity {row.approval.hasIdentityEvidence ? "present" : "missing"}, vehicle {row.approval.hasVehicleEvidence ? "present" : "not applicable"}</span><small>Account {row.rider.accountId} · application {row.approval.applicationId}</small></div>
          <dl>
            <div><dt>Transport</dt><dd>{label(row.transportMethod)}</dd></div>
            <div><dt>Governance version</dt><dd>{row.governance.version}</dd></div>
            <div><dt>Service area</dt><dd>{row.availability.serviceZone?.name ?? "Not active"}</dd></div>
            <div><dt>Last seen</dt><dd>{formatWhen(row.availability.lastSeenAt)}</dd></div>
          </dl>
          {row.activeWork
            ? <p className="admin-governance-pause"><ShieldAlert size={15} /> Active {label(row.activeWork.domain)} work · {row.activeWork.id}</p>
            : <p className="admin-governance-live"><CheckCircle2 size={15} /> No active delivery or custody work</p>}
          {row.availability.availableUntil ? <p className="admin-governance-availability"><Clock3 size={14} /> Availability until {formatWhen(row.availability.availableUntil, true)}</p> : null}
        </div>
        <footer>
          <button className="secondary-button" type="button" disabled={busy || (row.governance.status === "ACTIVE" && Boolean(row.activeWork))} onClick={() => reviewStatus(row)}>
            {row.governance.status === "SUSPENDED" ? <CheckCircle2 size={16} /> : <ShieldAlert size={16} />} {row.governance.status === "SUSPENDED" ? "Reactivate rider" : "Suspend rider"}
          </button>
          {row.governance.status === "ACTIVE" && row.activeWork ? <small>Use the existing recovery or release workflow for {label(row.activeWork.domain)} work before suspension.</small> : null}
        </footer>
      </article>)}
    </div>
    {rows.length > 0 ? <button className="secondary-button admin-page-more" type="button" disabled={!hasMore || loadingMore} onClick={() => {
      controller.current?.abort();
      const next = new AbortController();
      controller.current = next;
      void load(true, next.signal).catch(() => undefined);
    }}>{loadingMore ? "Loading…" : hasMore ? "Load more Delivery Partners" : "All matching Delivery Partners loaded"}</button> : null}
    {intent ? <AdminPrivilegedActionDialog intent={intent.dialog} busy={busy} error={error} notice={notice} reconciliationBlocked={reconciliationBlocked} onReconcile={reconcileIntent} onDismiss={() => { setIntent(undefined); setError(undefined); setNotice(undefined); }} onConfirm={perform} /> : null}
  </section>;
}

function Status({ value, label: caption }: { value: string; label: string }) {
  return <span className={`admin-governance-status ${value.toLowerCase()}`}><small>{caption}</small><strong>{label(value)}</strong></span>;
}

function mergeRows(current: V1AdminDeliveryPartnerGovernanceRow[], next: V1AdminDeliveryPartnerGovernanceRow[]) {
  const rows = new Map(current.map((row) => [row.rider.accountId, row]));
  next.forEach((row) => rows.set(row.rider.accountId, row));
  return [...rows.values()];
}

function label(value: string) {
  return value.replaceAll("_", " ").toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatWhen(value?: string, exact = false) {
  if (!value) return "Not available";
  return new Intl.DateTimeFormat("en-IN", exact
    ? { dateStyle: "medium", timeStyle: "short" }
    : { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function message(error: unknown) {
  return userFacingError(error, "Delivery Partner governance is temporarily unavailable.");
}
