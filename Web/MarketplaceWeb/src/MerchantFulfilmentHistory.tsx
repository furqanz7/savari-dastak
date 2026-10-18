import { useCallback, useEffect, useRef, useState } from "react";
import { getV1MerchantFulfilmentHistory, type DastakV1Auth, type MerchantHistoryCursor, type V1MerchantFulfilment } from "./dastakV1";
import type { MerchantDetailTarget } from "./merchantOrderDetail";
import { merchantDataIssue } from "./merchantOperationsState";

export function MerchantFulfilmentHistory({ auth, branchId, onDetails, onSessionExpired }: {
  auth: DastakV1Auth; branchId: string; onDetails: (target: MerchantDetailTarget) => void; onSessionExpired: () => void;
}) {
  const [rows, setRows] = useState<V1MerchantFulfilment[]>([]);
  const [cursor, setCursor] = useState<MerchantHistoryCursor>();
  const [checked, setChecked] = useState<Date>();
  const [failure, setFailure] = useState<string>();
  const [loading, setLoading] = useState(false);
  const request = useRef<AbortController | undefined>(undefined);
  const { accessToken, publishableKey, supabaseUrl } = auth;
  const load = useCallback(async (before?: MerchantHistoryCursor) => {
    if (request.current) return;
    const controller = new AbortController(); request.current = controller; setLoading(true);
    try {
      const result = await getV1MerchantFulfilmentHistory({ accessToken, publishableKey, supabaseUrl,
        branchId, before, signal: controller.signal });
      if (controller.signal.aborted) return;
      setRows((current) => {
        const merged = new Map((before ? current : []).map((row) => [row.id, row]));
        result.fulfilments.forEach((row) => merged.set(row.id, row));
        return [...merged.values()];
      });
      setCursor(result.nextCursor); setChecked(new Date()); setFailure(undefined);
    } catch (error) {
      if (controller.signal.aborted) return;
      const issue = merchantDataIssue(error);
      if (issue.action === "sign_in" || issue.kind === "access") {
        setRows([]); setCursor(undefined); setChecked(undefined);
      }
      if (issue.action === "sign_in") onSessionExpired();
      setFailure("History could not be checked. Retained records are read-only; refresh history to try again.");
    } finally {
      if (request.current === controller) { request.current = undefined; setLoading(false); }
    }
  }, [accessToken, publishableKey, supabaseUrl, branchId, onSessionExpired]);
  useEffect(() => {
    setRows([]); setCursor(undefined); setChecked(undefined); setFailure(undefined);
    void load();
    return () => { request.current?.abort(); request.current = undefined; };
  }, [load]);
  return <section aria-label="Past fulfilments" className="v1-preparation-list">
    <h3 className="merchant-feed-heading">Past fulfilments <span>{rows.length} loaded</span></h3>
    <p>Newest commitments first for this location. Load older orders to continue; earlier legacy orders and return records are separate.</p>
    {failure ? <p role="alert">{failure}</p> : null}
    {loading ? <p role="status">Loading history…</p> : null}
    {rows.map((row) => <article key={row.id} className="v1-opportunity-card">
      <h4>{row.displayOrderNumber}</h4>
      <p>{row.orderStatus.replaceAll("_", " ").toLowerCase()} · Fulfilment {row.status.replaceAll("_", " ").toLowerCase()}</p>
      {row.lines.map((line) => <p key={line.orderLineId}>{line.quantity} × {line.name}</p>)}
      <button type="button" onClick={() => onDetails({ kind: "FULFILMENT", id: row.id, branchId: row.branch.id })}>View full order</button>
    </article>)}
    {checked && !rows.length && !failure ? <p>No past fulfilments for this location.</p> : null}
    {cursor ? <button type="button" disabled={loading || Boolean(failure)} onClick={() => void load(cursor)}>Load older orders</button>
      : rows.length > 0 && !failure ? <p>All currently available fulfilment history loaded.</p> : null}
    <button type="button" disabled={loading} onClick={() => void load()}>Refresh history</button>
    {checked ? <small>Checked {checked.toLocaleTimeString()} · Refresh to include newly finished orders.</small> : null}
  </section>;
}
