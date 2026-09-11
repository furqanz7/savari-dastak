import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CircleAlert, PauseCircle, ShieldCheck } from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import {
  getV1AdminOperationalSafety,
  manageV1RiderEscalation,
  setV1OperationalPause,
  type DastakV1Auth,
  type V1OperationalPauseScope,
  type V1OperationalSafety,
} from "./dastakV1";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import { RefreshQueue } from "./orderRealtime";
import { adminFeedFailed, adminFeedStarted, adminFeedSucceeded, initialAdminFeedState } from "./adminRuntime";
import { userFacingError } from "./userFacingError";

type Props = { auth: DastakV1Auth };

export function AdminOperationalSafetyPanel({ auth }: Props) {
  const [snapshot, setSnapshot] = useState<V1OperationalSafety>();
  const [scope, setScope] = useState<V1OperationalPauseScope>("ZONE_RETAIL");
  const [targetId, setTargetId] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [reconciliationBlocked, setReconciliationBlocked] = useState(false);
  const [feedState, setFeedState] = useState(initialAdminFeedState);
  const queue = useRef(new RefreshQueue());
  const controller = useRef<AbortController | undefined>(undefined);
  const { reportRequestError } = useAdminRuntime();
  const [intent, setIntent] = useState<{
    dialog: AdminPrivilegedActionIntent;
    operationIdentity: string;
    mutate: (idempotencyKey: string, reason: string) => Promise<unknown>;
    success: string;
  }>();

  const refresh = useCallback(() => queue.current.request(false, async () => {
    controller.current?.abort();
    const nextController = new AbortController();
    controller.current = nextController;
    setFeedState((current) => adminFeedStarted(current));
    try {
      setSnapshot(await getV1AdminOperationalSafety({ ...auth, signal: nextController.signal }));
      setError(undefined);
      setFeedState((current) => adminFeedSucceeded(current));
    } catch (cause) {
      if (nextController.signal.aborted) return;
      reportRequestError(cause);
      setError(message(cause));
      setFeedState((current) => adminFeedFailed(current, cause));
      throw cause;
    }
  }), [auth, reportRequestError]);
  useEffect(() => { void refresh().catch(() => undefined); return () => controller.current?.abort(); }, [refresh]);
  useAdminWorkspaceRefresh("operationalSafety", refresh);

  const existing = useMemo(() => snapshot?.pauses.find((pause) =>
    pause.scope === scope && pause.targetId === targetId.trim()), [scope, snapshot, targetId]);

  const perform = async (operatorReason: string) => {
    if (!intent || busy) return;
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    setReconciliationBlocked(false);
    const result = await runAdminPrivilegedMutation({
      operationIdentity: intent.operationIdentity,
      mutate: (key) => intent.mutate(key, operatorReason),
      reconcile: refresh,
    });
    setBusy(false);
    if (result.kind === "completed") {
      setNotice(intent.success);
      setIntent(undefined);
    } else if (result.kind === "reconciled" || result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      if (result.kind === "reconciled") setIntent(undefined);
    } else if (result.kind === "uncertain_blocked") {
      setReconciliationBlocked(true);
      setError(result.message);
    } else { reportRequestError(result.error); setError(message(result.error)); }
  };

  const requestPause = () => {
    const normalizedTarget = targetId.trim();
    const normalizedReason = reason.trim();
    if (normalizedTarget.length !== 36 || normalizedReason.length < 3 || existing?.active) return;
    setIntent({
      operationIdentity: `operational-pause:${scope}:${normalizedTarget}:${existing?.version ?? 0}:active`,
      success: "New work is paused for the reviewed scope.",
      dialog: {
        title: "Pause new operational work?",
        entityLabel: scope.replaceAll("_", " "), entityValue: normalizedTarget,
        currentState: existing?.active ? "Paused" : "Accepting new commitments",
        resultingState: "New commitments paused",
        consequence: "New matching or assignments in this exact scope stop. Already-paid and already-committed work continues and must still be fulfilled.",
        confirmLabel: "Pause new work", tone: "danger", reason: normalizedReason,
      },
      mutate: (idempotencyKey) => setV1OperationalPause({
        ...auth, scope, targetId: normalizedTarget, active: true,
        reason: normalizedReason, expectedVersion: existing?.version ?? 0, idempotencyKey,
      }),
    });
  };

  const requestResume = (control: V1OperationalSafety["pauses"][number]) => {
    setIntent({
      operationIdentity: `operational-pause:${control.scope}:${control.targetId}:${control.version}:inactive`,
      success: "New work has resumed for the reviewed scope.",
      dialog: {
        title: "Resume new operational work?",
        entityLabel: control.scope.replaceAll("_", " "), entityValue: control.targetId,
        currentState: `Paused · ${control.reason}`, resultingState: "Accepting new commitments",
        consequence: "Eligible customer orders and rider assignments may begin entering this scope again immediately.",
        confirmLabel: "Resume new work",
        reasonOptions: ["Incident resolved", "Service restored", "Safety clearance", "Authorized override", "Other"],
      },
      mutate: (idempotencyKey, operatorReason) => setV1OperationalPause({
        ...auth, scope: control.scope, targetId: control.targetId, active: false,
        reason: operatorReason, expectedVersion: control.version, idempotencyKey,
      }),
    });
  };

  const requestManage = (escalation: V1OperationalSafety["riderEscalations"][number]) => {
    const action = escalation.custodyStarted ? "ENTER_DELIVERY_RECOVERY" as const : "RELEASE_REMATCH" as const;
    setIntent({
      operationIdentity: `rider-escalation:${escalation.missionId}:${escalation.version}:${action}`,
      success: escalation.custodyStarted ? "The mission entered Delivery Recovery." : "The rider was released and rematching can continue.",
      dialog: {
        title: escalation.custodyStarted ? "Enter Delivery Recovery?" : "Release rider and rematch?",
        entityLabel: "Order and mission", entityValue: `${escalation.displayOrderNumber} · ${escalation.missionId}`,
        currentState: `${escalation.escalationState.replaceAll("_", " ")} · ${escalation.custodyStarted ? "Package custody started" : "No package custody"}`,
        resultingState: escalation.custodyStarted ? "Delivery Recovery" : "Rider released for rematch",
        consequence: escalation.custodyStarted
          ? "The rider keeps recorded custody while Operations takes control of the recovery path. Normal completion remains blocked until recovery is resolved."
          : "This rider loses the assignment and the delivery returns to matching. No custody transfer has occurred.",
        confirmLabel: escalation.custodyStarted ? "Enter Delivery Recovery" : "Release and rematch",
        tone: escalation.custodyStarted ? "danger" : "primary",
        reasonOptions: ["Rider unreachable", "Safety intervention", "Operations reassignment", "Service disruption", "Other"],
      },
      mutate: (idempotencyKey, operatorReason) => manageV1RiderEscalation({
        ...auth, missionId: escalation.missionId, action, reason: operatorReason,
        expectedVersion: escalation.version, idempotencyKey,
      }),
    });
  };

  const reconcileIntent = async () => {
    setBusy(true);
    try {
      await refresh();
      setReconciliationBlocked(false);
      setNotice("Authoritative operational state was reloaded. Review it before acting again.");
      setIntent(undefined);
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="admin-approvals" role="tabpanel">
      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="admin-access-message success" role="status">{notice}</p>}
      {feedState.phase === "loading" && !snapshot ? <div className="catalogue-loading" role="status"><span /> Loading operational safety</div> : null}
      {snapshot ? <>
      <section className="admin-section">
        <header>
          <div><h2>Scoped emergency controls</h2><p>New commitments only; paid work continues.</p></div>
        </header>
        {!snapshot?.permissions.canManageOperationalPauses ? (
          <p className="admin-empty">This account has trace-only access.</p>
        ) : (
          <div className="exception-action">
            <select value={scope} onChange={(event) => setScope(event.target.value as V1OperationalPauseScope)} aria-label="Pause scope">
              <option value="ZONE_RETAIL">Zone · retail orders</option>
              <option value="ZONE_FOOD">Zone · food orders</option>
              <option value="ZONE_MIXED">Zone · mixed orders</option>
              <option value="MERCHANT_BRANCH">Merchant branch</option>
              <option value="RIDER_ASSIGNMENTS">Rider assignments</option>
            </select>
            <input value={targetId} onChange={(event) => setTargetId(event.target.value)} placeholder="Zone, branch or rider UUID" aria-label="Pause target ID" />
            <input value={reason} onChange={(event) => setReason(event.target.value)} maxLength={500} placeholder="Required reason" aria-label="Pause reason" />
            <button className="danger-button" type="button" disabled={busy || targetId.trim().length !== 36 || reason.trim().length < 3 || existing?.active} onClick={requestPause}><PauseCircle size={17} /> Pause new work</button>
          </div>
        )}
        <div className="exception-list">
          {snapshot?.pauses.filter((control) => control.active).map((control) => (
            <article className="exception-card high" key={control.id}>
              <header><ShieldCheck size={18} /><div><h3>{control.scope.replaceAll("_", " ")}</h3><p>{control.targetId}</p></div></header>
              <p>{control.reason}</p>
              {snapshot.permissions.canManageOperationalPauses && <button className="secondary-button" type="button" disabled={busy} onClick={() => requestResume(control)}>Resume new work</button>}
            </article>
          ))}
        </div>
      </section>

      <section className="admin-section">
        <header><div><h2>Rider escalations</h2><p>Release only before custody; otherwise enter Delivery Recovery.</p></div><span>{snapshot?.riderEscalations.length ?? 0}</span></header>
        {!snapshot?.riderEscalations.length ? <p className="admin-empty">No rider missions require action.</p> : (
          <div className="exception-list">
            {snapshot.riderEscalations.map((escalation) => (
              <article className="exception-card high" key={escalation.missionId}>
                <header><CircleAlert size={18} /><div><h3>{escalation.displayOrderNumber}</h3><p>{escalation.escalationState.replaceAll("_", " ")}</p></div></header>
                <p>{escalation.escalationReason ?? "Threshold escalation"}</p>
                <small>{escalation.custodyStarted ? "Package custody has started" : "No package custody"}</small>
                {snapshot.permissions.canManageRiderEscalations && ["STALLED", "UNRESPONSIVE"].includes(escalation.escalationState) && (
                  <button className={escalation.custodyStarted ? "danger-button" : "secondary-button"} type="button" disabled={busy} onClick={() => requestManage(escalation)}>
                    {escalation.custodyStarted ? "Enter Delivery Recovery" : "Release and rematch"}
                  </button>
                )}
              </article>
            ))}
          </div>
        )}
      </section>
      </> : null}
      {intent ? <AdminPrivilegedActionDialog intent={intent.dialog} busy={busy} error={error} notice={notice}
        reconciliationBlocked={reconciliationBlocked} onReconcile={reconcileIntent}
        onDismiss={() => { setIntent(undefined); setError(undefined); setNotice(undefined); }}
        onConfirm={perform} /> : null}
    </div>
  );
}

function message(error: unknown) {
  return userFacingError(error, "Operational safety is unavailable.");
}
