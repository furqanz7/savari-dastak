import { useCallback, useEffect, useRef, useState } from "react";
import { KeyRound, Laptop, Search, ShieldAlert, Smartphone, UserRound } from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import {
  correctV1AdminCustomerPhone,
  getV1AdminCustomerRecoveryPage,
  revokeV1AdminCustomerSessions,
  type DastakV1Auth,
  type V1AdminCustomerRecoveryRow,
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

const sessionReasons = [
  "Customer-reported lost device",
  "Suspected account compromise",
  "Customer request",
  "Security incident",
  "Other",
] as const;

const phoneReasons = [
  "Customer request",
  "Contact correction",
  "Account recovery",
  "Security incident",
  "Other",
] as const;

const phonePattern = /^\+[1-9][0-9]{7,14}$/;

export function AdminCustomerRecoveryPanel({ auth }: { auth: DastakV1Auth }) {
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<V1AdminCustomerRecoveryRow[]>([]);
  const [cursor, setCursor] = useState<{ updatedAt: string; accountId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [feedState, setFeedState] = useState(initialAdminFeedState());
  const [replacementPhones, setReplacementPhones] = useState<Record<string, string>>({});
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
      const page = await getV1AdminCustomerRecoveryPage({
        ...auth,
        query: normalizedQuery,
        limit: 40,
        cursor: append ? cursor : undefined,
        signal,
      });
      if (signal?.aborted || generation !== requestGeneration.current) return;
      setRows((current) => append ? mergeRows(current, page.customers) : page.customers);
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
  }, [auth, cursor, normalizedQuery, reportRequestError]);

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
  }, [auth, normalizedQuery]);
  useAdminWorkspaceRefresh("customerRecovery", refresh);

  const reviewSessions = (row: V1AdminCustomerRecoveryRow, session?: V1AdminCustomerRecoveryRow["sessions"][number]) => {
    const scope = session ? "SINGLE" : "ALL";
    const count = session ? 1 : row.activeSessionCount;
    setIntent({
      operationIdentity: `customer-sessions:${row.account.accountId}:${scope}:${session?.sessionId ?? row.updatedAt}`,
      success: session ? "The reviewed Customer session was revoked." : "All authoritative active Customer sessions were revoked.",
      dialog: {
        eyebrow: "Customer session recovery",
        title: session ? "Revoke this Customer session?" : "Revoke all Customer sessions?",
        entityLabel: "Customer account",
        entityValue: `${row.account.displayName} · ${row.account.maskedPhoneNumber} · ${row.account.accountId}`,
        currentState: session
          ? `${session.deviceName} · ${session.appName} · session ${session.sessionId} · last seen ${formatWhen(session.lastSeenAt)}`
          : `${count} active session${count === 1 ? "" : "s"}`,
        resultingState: session ? "Selected session revoked" : "No currently active sessions",
        consequence: session
          ? "Only this reviewed session will lose refresh capability and Dastak API access. It must authenticate again; other Customer sessions remain active."
          : "Every session active for this account at authoritative execution time will lose refresh capability and Dastak API access. All affected devices must authenticate again.",
        confirmLabel: session ? "Revoke reviewed session" : "Revoke all sessions",
        tone: "danger",
        reasonOptions: sessionReasons,
        confirmationValue: session ? undefined : row.account.displayName,
      },
      mutate: (idempotencyKey, reason) => revokeV1AdminCustomerSessions({
        ...auth,
        accountId: row.account.accountId,
        scope,
        sessionId: session?.sessionId,
        reason,
        idempotencyKey,
      }),
    });
  };

  const reviewPhone = (row: V1AdminCustomerRecoveryRow) => {
    const replacement = (replacementPhones[row.account.accountId] ?? "").trim();
    if (row.phoneClaim.version < 1 || !phonePattern.test(replacement) || replacement === row.account.currentPhoneNumber) return;
    setIntent({
      operationIdentity: `customer-phone:${row.account.accountId}:${row.phoneClaim.version}:${replacement}`,
      success: "The Customer contact phone claim was corrected.",
      dialog: {
        eyebrow: "Customer contact recovery",
        title: "Correct Customer phone number?",
        entityLabel: "Customer account",
        entityValue: `${row.account.displayName} · ${row.account.accountId}`,
        currentState: `${row.account.maskedPhoneNumber} · claim version ${row.phoneClaim.version}`,
        resultingState: `${maskPhone(replacement)} · unverified contact claim`,
        consequence: "This atomically releases the reviewed phone claim and establishes the replacement claim. It changes Dastak contact data only—Apple or Google OAuth sign-in identity and email remain unchanged. It does not merge accounts.",
        confirmLabel: "Correct phone claim",
        tone: "primary",
        reasonOptions: phoneReasons,
        confirmationValue: replacement,
        confirmationLabel: `Type the full replacement number ${replacement} to confirm`,
      },
      mutate: (idempotencyKey, reason) => correctV1AdminCustomerPhone({
        ...auth,
        accountId: row.account.accountId,
        reviewedCurrentPhone: row.account.currentPhoneNumber,
        replacementPhone: replacement,
        expectedPhoneClaimVersion: row.phoneClaim.version,
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
      setNotice("Authoritative Customer recovery state was reloaded. Review it before acting again.");
      setIntent(undefined);
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  return <section className="admin-section admin-customer-recovery" role="tabpanel">
    <header className="admin-section-heading"><div><p className="eyebrow">CUSTOMER ACCOUNT RECOVERY</p><h2>Sessions and contact claims</h2><p>Review the exact account before revoking access or correcting Dastak contact data. OAuth identity is never changed here.</p></div></header>
    <label className="admin-search admin-governance-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search customer, phone, email or exact account ID" aria-label="Search Customer recovery" /></label>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {notice ? <p className="admin-access-message success" role="status">{notice}</p> : null}
    {feedState.phase === "loading" ? <div className="admin-directory-loading" role="status"><span /><p>Loading governed Customer accounts…</p></div> : null}
    {rows.length === 0 && adminFeedHasContent(feedState) ? <div className="admin-empty-state"><UserRound size={28} /><h3>No Customers match</h3><p>Try another identity, exact ID, phone or email.</p></div> : null}
    <div className="admin-governance-list">
      {rows.map((row) => <article className="admin-governance-card admin-customer-recovery-card" key={row.account.accountId}>
        <header>
          <span className="admin-person-mark" aria-hidden="true"><UserRound size={20} /></span>
          <div><p className="eyebrow">{row.identityProviders.map(title).join(" + ") || "CUSTOMER"}</p><h3>{row.account.displayName}</h3><p>{row.account.maskedPhoneNumber}{row.account.email ? ` · ${row.account.email}` : ""}</p><small>Account {row.account.accountId}</small></div>
          <div className="admin-governance-statuses"><span className={`admin-governance-status ${row.account.accountState.toLowerCase()}`}><small>Account</small><strong>{title(row.account.accountState)}</strong></span><span className="admin-governance-status"><small>Sessions</small><strong>{row.activeSessionCount}</strong></span></div>
        </header>

        <details className="admin-disclosure"><summary>Review sessions & contact recovery</summary>
        <section className="admin-customer-session-list" aria-label={`Active sessions for ${row.account.displayName}`}>
          <div className="admin-customer-recovery-heading"><div><KeyRound size={16} /><span><strong>Active sessions</strong><small>Refresh capability and Dastak API access are governed together.</small></span></div>{row.activeSessionCount > 0 ? <button className="danger-button" type="button" disabled={busy} onClick={() => reviewSessions(row)}>Revoke all</button> : null}</div>
          {row.sessions.length === 0 ? <p className="admin-governance-live">No active Customer sessions</p> : <ul>{row.sessions.map((session) => <li key={session.sessionId}>
            <span aria-hidden="true">{session.platform === "ios" ? <Smartphone size={18} /> : <Laptop size={18} />}</span>
            <div><strong>{session.deviceName}</strong><small>{session.appName} · {title(session.platform)} · last seen {formatWhen(session.lastSeenAt)}</small><code>{session.sessionId}</code></div>
            <button className="secondary-button" type="button" disabled={busy} onClick={() => reviewSessions(row, session)}>Revoke</button>
          </li>)}</ul>}
        </section>

        <section className="admin-customer-phone-correction">
          <div><ShieldAlert size={16} /><span><strong>Phone-claim correction</strong><small>Current {row.account.maskedPhoneNumber} · claim version {row.phoneClaim.version} · {title(row.phoneClaim.state)}</small></span></div>
          <label>Replacement phone (E.164)<input type="tel" inputMode="tel" autoComplete="off" placeholder="+919876543210" value={replacementPhones[row.account.accountId] ?? ""} onChange={(event) => setReplacementPhones((current) => ({ ...current, [row.account.accountId]: event.target.value }))} /></label>
          <button className="secondary-button" type="button" disabled={busy || row.phoneClaim.version < 1 || !phonePattern.test((replacementPhones[row.account.accountId] ?? "").trim()) || (replacementPhones[row.account.accountId] ?? "").trim() === row.account.currentPhoneNumber} onClick={() => reviewPhone(row)}>Review correction</button>
        </section>
        </details>
      </article>)}
    </div>
    {rows.length > 0 ? <button className="secondary-button admin-page-more" type="button" disabled={!hasMore || loadingMore} onClick={() => {
      controller.current?.abort();
      const next = new AbortController();
      controller.current = next;
      void load(true, next.signal).catch(() => undefined);
    }}>{loadingMore ? "Loading…" : hasMore ? "Load more Customers" : "All matching Customers loaded"}</button> : null}
    {intent ? <AdminPrivilegedActionDialog intent={intent.dialog} busy={busy} error={error} notice={notice} reconciliationBlocked={reconciliationBlocked} onReconcile={reconcileIntent} onDismiss={() => { setIntent(undefined); setError(undefined); setNotice(undefined); }} onConfirm={perform} /> : null}
  </section>;
}

function mergeRows(current: V1AdminCustomerRecoveryRow[], next: V1AdminCustomerRecoveryRow[]) {
  const rows = new Map(current.map((row) => [row.account.accountId, row]));
  next.forEach((row) => rows.set(row.account.accountId, row));
  return [...rows.values()];
}

function maskPhone(value: string) {
  return `${"•".repeat(Math.max(value.length - 4, 4))} ${value.slice(-4)}`;
}

function title(value: string) {
  return value.replaceAll("_", " ").toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatWhen(value: string) {
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function message(error: unknown) {
  return userFacingError(error, "Customer recovery is temporarily unavailable.");
}
