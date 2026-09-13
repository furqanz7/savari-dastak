import { useCallback, useEffect, useRef, useState } from "react";
import { WalletCards } from "lucide-react";
import { formatPrice } from "./catalogue";
import { getAdminRoyaltyPayouts, type AdminRoyaltyPayout, type AdminRoyaltyPayoutPage } from "./earnings";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import { adminFeedFailed, adminFeedHasContent, adminFeedStarted, adminFeedSucceeded, initialAdminFeedState } from "./adminRuntime";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

type Auth = { accessToken: string; supabaseUrl: string; publishableKey: string };

export function AdminRoyaltyPayoutPanel({ auth }: { auth: Auth }) {
  const [payouts, setPayouts] = useState<AdminRoyaltyPayout[]>([]);
  const [feedState, setFeedState] = useState(initialAdminFeedState);
  const queue = useRef(new RefreshQueue());
  const controller = useRef<AbortController | undefined>(undefined);
  const cursor = useRef<AdminRoyaltyPayoutPage["nextCursor"]>(undefined);
  const [hasMore, setHasMore] = useState(false);
  const { reportRequestError } = useAdminRuntime();
  const refresh = useCallback(() => queue.current.request(false, async () => {
    controller.current?.abort();
    const nextController = new AbortController();
    controller.current = nextController;
    setFeedState((current) => adminFeedStarted(current));
    try {
      const page = await getAdminRoyaltyPayouts({ ...auth, limit: 50, signal: nextController.signal });
      setPayouts(page.withdrawals);
      setHasMore(page.hasMore);
      cursor.current = page.nextCursor;
      setFeedState((current) => adminFeedSucceeded(current));
    } catch (loadError) {
      if (nextController.signal.aborted) return;
      reportRequestError(loadError);
      setFeedState((current) => adminFeedFailed(current, loadError));
      throw loadError;
    }
  }), [auth, reportRequestError]);

  useEffect(() => { void refresh().catch(() => undefined); return () => controller.current?.abort(); }, [refresh]);
  useAdminWorkspaceRefresh("royaltyPayouts", refresh);

  const loadMore = useCallback(() => queue.current.request(false, async () => {
    const nextCursor = cursor.current;
    if (!hasMore || !nextCursor) return;
    try {
      const page = await getAdminRoyaltyPayouts({ ...auth, limit: 50, cursor: nextCursor });
      setPayouts((current) => mergePayouts(current, page.withdrawals));
      setHasMore(page.hasMore);
      cursor.current = page.nextCursor;
    } catch (loadError) {
      reportRequestError(loadError);
      setFeedState((current) => adminFeedFailed(current, loadError));
    }
  }), [auth, hasMore, reportRequestError]);

  return (
    <section className="admin-royalty-payouts" role="tabpanel" aria-labelledby="admin-payouts-title">
      <header>
        <div>
          <p className="eyebrow">Financial operations</p>
          <h2 id="admin-payouts-title">Payout records</h2>
          <p>Provider state, immutable destination snapshots, attempts, and reconciliation.</p>
        </div>
      </header>
      {feedState.phase === "failed-with-content" || feedState.phase === "failed-without-content" ? <p className="order-error" role="alert">{message(feedState.error)}</p> : null}
      {feedState.phase === "loading" && payouts.length === 0
        ? <div className="catalogue-loading" role="status"><span /> Loading payouts</div>
        : payouts.length === 0 && adminFeedHasContent(feedState)
        ? <p className="admin-empty">No payout withdrawals yet.</p>
        : payouts.length > 0 ? <><div className="admin-payout-list">{payouts.map((payout) => <PayoutCard key={payout.id} payout={payout} />)}</div><button className="secondary-button admin-page-more" type="button" disabled={!hasMore} onClick={() => void loadMore()}>{hasMore ? "Load older payouts" : "All payouts loaded"}</button></> : null}
    </section>
  );
}

function PayoutCard({ payout }: { payout: AdminRoyaltyPayout }) {
  return (
    <article className="admin-payout-card">
      <header>
        <span><WalletCards size={18} /></span>
        <div>
          <strong>{formatPrice(payout.amountPaise)} · {payout.effectiveStatus.replaceAll("_", " ")}</strong>
          <small>{payout.subjectType.replaceAll("_", " ")} · {shortId(payout.subjectId)} · {new Date(payout.requestedAt).toLocaleString()}</small>
        </div>
      </header>
      <dl>
        <div><dt>Destination snapshot</dt><dd>{payout.destinationSnapshot.displayLabel} · {payout.destinationSnapshot.type.replaceAll("_", " ")}</dd></div>
        <div><dt>Provider reference</dt><dd>{payout.providerPayoutReference ?? "Not established"}</dd></div>
        <div><dt>Provider status</dt><dd>{payout.providerStatus ?? "Not submitted"}</dd></div>
        <div><dt>Reconciliation</dt><dd>{payout.reconciliationState ?? "PENDING"}</dd></div>
        <div><dt>UTR</dt><dd>{payout.utr ?? "Not available"}</dd></div>
      </dl>
      <div className="admin-payout-history">
        <History label="Domain attempts" entries={payout.attempts} />
        <History label="Provider requests" entries={payout.providerRequests} />
        <History label="Webhook / reconciliation events" entries={payout.webhookHistory} />
      </div>
    </article>
  );
}

function History({ label, entries }: { label: string; entries: Array<Record<string, unknown>> }) {
  return (
    <details>
      <summary>{label} · {entries.length}</summary>
      {entries.length === 0
        ? <p>No records.</p>
        : <ol>{entries.map((entry, index) => <li key={string(entry.id) ?? string(entry.eventId) ?? index}>{historyLine(entry)}</li>)}</ol>}
    </details>
  );
}

function historyLine(entry: Record<string, unknown>) {
  const status = string(entry.status) ?? string(entry.outcome) ?? string(entry.providerStatus) ?? "RECORDED";
  const kind = string(entry.operation) ?? string(entry.eventType) ?? `Attempt ${number(entry.attemptNumber) ?? ""}`;
  const result = string(entry.applicationResult);
  const occurredAt = string(entry.occurredAt) ?? string(entry.startedAt) ?? string(entry.processedAt);
  return `${kind} · ${status}${result ? ` · ${result}` : ""}${occurredAt ? ` · ${new Date(occurredAt).toLocaleString()}` : ""}`;
}

function string(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function shortId(value: string) {
  return value.slice(0, 8).toUpperCase();
}

function mergePayouts(current: AdminRoyaltyPayout[], incoming: AdminRoyaltyPayout[]) {
  const merged = new Map(current.map((payout) => [payout.id, payout]));
  incoming.forEach((payout) => merged.set(payout.id, payout));
  return Array.from(merged.values());
}

function message(error: unknown) {
  return userFacingError(error, "Royalty payouts are unavailable.");
}
