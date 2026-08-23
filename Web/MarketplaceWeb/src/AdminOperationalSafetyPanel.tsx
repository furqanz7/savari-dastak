import { useCallback, useEffect, useMemo, useState } from "react";
import { CircleAlert, PauseCircle, RefreshCw, ShieldCheck } from "lucide-react";
import {
  getV1AdminOperationalSafety,
  manageV1RiderEscalation,
  setV1OperationalPause,
  type DastakV1Auth,
  type V1OperationalPauseScope,
  type V1OperationalSafety,
} from "./dastakV1";

type Props = { auth: DastakV1Auth };

export function AdminOperationalSafetyPanel({ auth }: Props) {
  const [snapshot, setSnapshot] = useState<V1OperationalSafety>();
  const [scope, setScope] = useState<V1OperationalPauseScope>("ZONE_RETAIL");
  const [targetId, setTargetId] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const refresh = useCallback(async () => {
    try {
      setSnapshot(await getV1AdminOperationalSafety(auth));
      setError(undefined);
    } catch (cause) {
      setError(message(cause));
    }
  }, [auth]);
  useEffect(() => { void refresh(); }, [refresh]);

  const existing = useMemo(() => snapshot?.pauses.find((pause) =>
    pause.scope === scope && pause.targetId === targetId.trim()), [scope, snapshot, targetId]);

  const pause = async () => {
    setBusy(true);
    try {
      await setV1OperationalPause({
        ...auth, scope, targetId: targetId.trim(), active: true,
        reason: reason.trim(), expectedVersion: existing?.version ?? 0,
        idempotencyKey: crypto.randomUUID(),
      });
      setReason("");
      await refresh();
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  const resume = async (control: V1OperationalSafety["pauses"][number]) => {
    setBusy(true);
    try {
      await setV1OperationalPause({
        ...auth, scope: control.scope, targetId: control.targetId, active: false,
        reason: "Authorized Operations resume", expectedVersion: control.version,
        idempotencyKey: crypto.randomUUID(),
      });
      await refresh();
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  const manage = async (
    escalation: V1OperationalSafety["riderEscalations"][number],
  ) => {
    const action = escalation.custodyStarted
      ? "ENTER_DELIVERY_RECOVERY" as const
      : "RELEASE_REMATCH" as const;
    setBusy(true);
    try {
      await manageV1RiderEscalation({
        ...auth, missionId: escalation.missionId, action,
        reason: escalation.custodyStarted
          ? "Operations escalated unresponsive rider after custody"
          : "Operations released unresponsive rider before custody",
        expectedVersion: escalation.version, idempotencyKey: crypto.randomUUID(),
      });
      await refresh();
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="admin-approvals" role="tabpanel">
      {error && <p className="order-error" role="alert">{error}</p>}
      <section className="admin-section">
        <header>
          <div><h2>Scoped emergency controls</h2><p>New commitments only; paid work continues.</p></div>
          <button className="icon-button" type="button" disabled={busy} onClick={() => void refresh()} aria-label="Refresh operational safety"><RefreshCw size={18} /></button>
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
            <button className="danger-button" type="button" disabled={busy || targetId.trim().length !== 36 || reason.trim().length < 3 || existing?.active} onClick={() => void pause()}><PauseCircle size={17} /> Pause new work</button>
          </div>
        )}
        <div className="exception-list">
          {snapshot?.pauses.filter((control) => control.active).map((control) => (
            <article className="exception-card high" key={control.id}>
              <header><ShieldCheck size={18} /><div><h3>{control.scope.replaceAll("_", " ")}</h3><p>{control.targetId}</p></div></header>
              <p>{control.reason}</p>
              {snapshot.permissions.canManageOperationalPauses && <button className="secondary-button" type="button" disabled={busy} onClick={() => void resume(control)}>Resume new work</button>}
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
                  <button className={escalation.custodyStarted ? "danger-button" : "secondary-button"} type="button" disabled={busy} onClick={() => void manage(escalation)}>
                    {escalation.custodyStarted ? "Enter Delivery Recovery" : "Release and rematch"}
                  </button>
                )}
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function message(error: unknown) {
  return error instanceof Error ? error.message : "Operational safety is unavailable.";
}
