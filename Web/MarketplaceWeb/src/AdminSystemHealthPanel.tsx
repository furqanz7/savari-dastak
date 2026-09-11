import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { AlertTriangle, BellRing, Clock3, ServerCog, ShieldCheck } from "lucide-react";
import {
  getV1AdminSystemHealth,
  type DastakV1Auth,
  type V1SystemHealth,
} from "./dastakV1";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import { adminFeedFailed, adminFeedHasContent, adminFeedStarted, adminFeedSucceeded, initialAdminFeedState } from "./adminRuntime";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

export function AdminSystemHealthPanel({ auth }: { auth: DastakV1Auth }) {
  const [health, setHealth] = useState<V1SystemHealth>();
  const [feedState, setFeedState] = useState(initialAdminFeedState);
  const queue = useRef(new RefreshQueue());
  const controller = useRef<AbortController | undefined>(undefined);
  const { reportRequestError } = useAdminRuntime();

  const refresh = useCallback(() => queue.current.request(false, async () => {
    controller.current?.abort();
    const nextController = new AbortController();
    controller.current = nextController;
    setFeedState((current) => adminFeedStarted(current));
    try {
      setHealth(await getV1AdminSystemHealth({ ...auth, signal: nextController.signal }));
      setFeedState((current) => adminFeedSucceeded(current));
    } catch (healthError) {
      if (nextController.signal.aborted) return;
      reportRequestError(healthError);
      setFeedState((current) => adminFeedFailed(current, healthError));
      throw healthError;
    }
  }), [auth, reportRequestError]);

  useEffect(() => { void refresh().catch(() => undefined); return () => controller.current?.abort(); }, [refresh]);
  useAdminWorkspaceRefresh("systemHealth", refresh);

  return <section className="v1-health-panel" role="tabpanel" aria-label="Dastak V1 system health">
    <header>
      <div>
        <p className="eyebrow">LAUNCH HEALTH</p>
        <h2>System health</h2>
        <span>Transactional delivery, critical invariants and payment reconciliation.</span>
      </div>
    </header>
    {feedState.phase === "failed-with-content" || feedState.phase === "failed-without-content" ? <p className="order-error" role="alert">{message(feedState.error)}</p> : null}
    {feedState.phase === "loading" ? <div className="catalogue-loading" role="status"><span /> Loading system health</div> : health && adminFeedHasContent(feedState) ? <>
      <div className={`v1-health-state ${health.healthy ? "healthy" : "degraded"}`} role="status">
        {health.healthy ? <ShieldCheck size={22} /> : <AlertTriangle size={22} />}
        <div><strong>{health.healthy ? "Healthy" : "Needs attention"}</strong><span>Observed {formatTime(health.observedAt)}</span></div>
      </div>
      <div className="v1-health-grid">
        <Metric icon={<ServerCog size={18} />} label="Worker" value={health.workerConfigured ? "Scheduled" : "Not scheduled"} attention={!health.workerConfigured} />
        <Metric icon={<ShieldCheck size={18} />} label="Critical incidents" value={String(health.openCriticalIncidentCount)} attention={health.openCriticalIncidentCount > 0} />
        <Metric icon={<Clock3 size={18} />} label="Outbox pending" value={String(health.outbox.pending)} detail={`Oldest ${duration(health.outbox.oldestPendingSeconds)}`} attention={health.outbox.oldestPendingSeconds > health.outbox.staleThresholdSeconds} />
        <Metric icon={<AlertTriangle size={18} />} label="Outbox dead letter" value={String(health.outbox.deadLetter)} attention={health.outbox.deadLetter > 0} />
        <Metric icon={<BellRing size={18} />} label="Notifications" value={`${health.notifications.pending} pending`} detail={`${health.notifications.inFlight} in flight · ${health.notifications.deadLetter} dead`} attention={health.notifications.deadLetter > 0} />
        <Metric icon={<Clock3 size={18} />} label="Payment reconciliation" value={String(health.paymentReconciliationOpen)} attention={health.paymentReconciliationOpen > 0} />
        <Metric icon={<AlertTriangle size={18} />} label="Rider escalations" value={String(health.operationalAlerts.counts.riderEscalationOpenCount)} detail={`Alert above ${health.operationalAlerts.thresholds.riderEscalationOpenCount}`} attention={health.operationalAlerts.counts.riderEscalationOpenCount > health.operationalAlerts.thresholds.riderEscalationOpenCount} />
        <Metric icon={<AlertTriangle size={18} />} label="Unreachable merchants" value={String(health.operationalAlerts.counts.merchantUnreachableBranchCount)} detail={`Alert above ${health.operationalAlerts.thresholds.merchantUnreachableBranchCount}`} attention={health.operationalAlerts.counts.merchantUnreachableBranchCount > health.operationalAlerts.thresholds.merchantUnreachableBranchCount} />
        <Metric icon={<Clock3 size={18} />} label="Customer contact due" value={String(health.operationalAlerts.counts.customerUnreachableDueCount)} detail={`Alert above ${health.operationalAlerts.thresholds.customerUnreachableDueCount}`} attention={health.operationalAlerts.counts.customerUnreachableDueCount > health.operationalAlerts.thresholds.customerUnreachableDueCount} />
      </div>
      <section className="v1-health-monitor">
        <h3>Invariant monitor</h3>
        <p>{health.lastMonitorRun
          ? `Last completed ${formatTime(health.lastMonitorRun.completedAt)} with ${health.lastMonitorRun.findingCount} finding(s).`
          : "No monitor run has been recorded yet."}</p>
      </section>
      <section className="v1-health-incidents">
        <header><h3>Open critical incidents</h3><span>{health.incidents.length}</span></header>
        {health.incidents.length === 0 ? <p className="admin-empty">No impossible-state violations detected.</p> : health.incidents.map((incident) => <article key={incident.id}>
          <div><strong>{label(incident.invariantKey)}</strong><span>{incident.entityType} · #{incident.entityId.slice(0, 8).toUpperCase()}</span></div>
          <span>Last seen {formatTime(incident.lastDetectedAt)} · {incident.occurrenceCount} occurrence(s)</span>
        </article>)}
      </section>
    </> : null}
  </section>;
}

function Metric({ icon, label: metricLabel, value, detail, attention = false }: {
  icon: ReactNode;
  label: string;
  value: string;
  detail?: string;
  attention?: boolean;
}) {
  return <article className={attention ? "attention" : ""}>{icon}<div><span>{metricLabel}</span><strong>{value}</strong>{detail ? <small>{detail}</small> : null}</div></article>;
}

function label(value: string) {
  return value.toLowerCase().split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}

function duration(seconds: number) {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  return `${Math.floor(seconds / 3600)}h`;
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function message(error: unknown) {
  return userFacingError(error, "System health is unavailable.");
}
