import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Check, Clock3, PackageCheck, RefreshCw, X } from "lucide-react";
import {
  getV1MerchantOpportunities,
  respondToV1MerchantOpportunity,
  type DastakV1Auth,
  type V1MerchantOpportunity,
} from "./dastakV1";

export function MerchantV1Opportunities({ auth }: { auth: DastakV1Auth }) {
  const [opportunities, setOpportunities] = useState<V1MerchantOpportunity[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyId, setBusyId] = useState<string>();
  const [error, setError] = useState<string>();
  const [confirmed, setConfirmed] = useState<Set<string>>(() => new Set());
  const [prepMinutes, setPrepMinutes] = useState<Record<string, number>>({});
  const [now, setNow] = useState(() => Date.now());
  const keys = useRef(new Map<string, string>());

  const refresh = useCallback(async (showProgress = false) => {
    if (showProgress) setRefreshing(true);
    try {
      const result = await getV1MerchantOpportunities({ ...auth, limit: 50 });
      setOpportunities(result);
      setPrepMinutes((current) => {
        const next = { ...current };
        result.forEach((opportunity) => {
          next[opportunity.id] ??= opportunity.promisedPrepMinutes ?? opportunity.prepTimeOptionsMinutes[0] ?? 10;
        });
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

  const respond = async (opportunity: V1MerchantOpportunity, action: "accept" | "unavailable") => {
    if (busyId || (action === "accept" && !confirmed.has(opportunity.id))) return;
    const identity = `${action}:${opportunity.id}:${opportunity.version}`;
    const idempotencyKey = keys.current.get(identity) ?? crypto.randomUUID();
    keys.current.set(identity, idempotencyKey);
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
        idempotencyKey,
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

  const visible = useMemo(
    () => opportunities.filter((opportunity) =>
      opportunity.status === "OFFERED" ||
      ["ITEMS_HELD_WHILE_ORDER_COMPLETES", "WAITING_FOR_CUSTOMER_PAYMENT", "PAYMENT_CONFIRMED", "RESERVATION_RELEASED"]
        .includes(opportunity.reservationState)
    ),
    [opportunities],
  );

  return <section className="v1-merchant-panel" aria-labelledby="v1-merchant-title">
    <header>
      <div><p className="eyebrow">DASTAK V1</p><h2 id="v1-merchant-title">Item requests</h2><span>Physically confirm only the exact items shown.</span></div>
      <button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={refreshing} aria-label="Refresh item requests"><RefreshCw size={18} /></button>
    </header>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {loading ? <div className="catalogue-loading" role="status"><span /> Loading item requests</div> : visible.length === 0 ? <p className="v1-merchant-empty">No V1 item requests right now.</p> : <div className="v1-opportunity-list">
      {visible.map((opportunity) => {
        const seconds = Math.max(0, Math.ceil((Date.parse(opportunity.expiresAt) - now) / 1_000));
        const offered = opportunity.status === "OFFERED" && seconds > 0;
        const busy = busyId === opportunity.id;
        return <article className="v1-opportunity-card" key={opportunity.id}>
          <header>
            <span className="v1-opportunity-icon"><PackageCheck size={20} /></span>
            <span><strong>{opportunity.displayOrderNumber}</strong><small>{opportunity.requestScope === "FULL_BASKET" ? "Complete basket request" : "Exact subset request"} · {opportunity.branch.displayName}</small></span>
            {offered ? <b><Clock3 size={14} /> {formatDuration(seconds)}</b> : <b>{reservationLabel(opportunity)}</b>}
          </header>
          <ul>{opportunity.lines.map((line) => <li key={line.orderLineId}><span><strong>{line.quantity}× {line.name}</strong><small>{[line.variant, line.packSize].filter(Boolean).join(" · ")}</small></span></li>)}</ul>
          {offered ? <>
            <label className="v1-physical-check"><input type="checkbox" checked={confirmed.has(opportunity.id)} onChange={(event) => setConfirmed((current) => {
              const next = new Set(current);
              if (event.target.checked) next.add(opportunity.id); else next.delete(opportunity.id);
              return next;
            })} /><span>I physically confirmed every exact SKU and quantity above.</span></label>
            <label className="v1-prep-choice"><span>Preparation promise</span><select value={prepMinutes[opportunity.id] ?? opportunity.prepTimeOptionsMinutes[0]} onChange={(event) => setPrepMinutes((current) => ({ ...current, [opportunity.id]: Number(event.target.value) }))}>{opportunity.prepTimeOptionsMinutes.map((minutes) => <option key={minutes} value={minutes}>{minutes} minutes</option>)}</select></label>
            <div className="v1-opportunity-actions"><button className="secondary-button" type="button" disabled={busy} onClick={() => void respond(opportunity, "unavailable")}><X size={17} /> Unavailable</button><button className="primary-button" type="button" disabled={busy || !confirmed.has(opportunity.id)} onClick={() => void respond(opportunity, "accept")}><Check size={17} /> {busy ? "Confirming…" : "Accept and hold items"}</button></div>
          </> : <p className={`v1-reservation-state ${opportunity.reservationState.toLowerCase()}`}>{reservationCopy(opportunity)}</p>}
        </article>;
      })}
    </div>}
  </section>;
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
    case "WAITING_FOR_CUSTOMER_PAYMENT": return "Selected for the final plan. Keep items reserved while the customer pays.";
    case "PAYMENT_CONFIRMED": return "Customer payment is confirmed. This request is final.";
    case "RESERVATION_RELEASED": return "Reservation released. Return these items to normal availability.";
    default: return "This request is no longer awaiting a response.";
  }
}

function formatDuration(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function message(error: unknown) {
  return error instanceof Error ? error.message : "V1 item requests are unavailable right now.";
}
