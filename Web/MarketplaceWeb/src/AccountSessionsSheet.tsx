import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent } from "react";
import { CheckCircle2, Laptop, LogOut, RefreshCw, ShieldCheck, Smartphone, X } from "lucide-react";
import {
  AccountSessionRequestError,
  getAccountSessions,
  revokeAccountSession,
  signOutOtherSessions,
  webSessionMetadata,
  type AccountSession,
} from "./accountSessions";
import { useModalDialog } from "./useModalDialog";

export function AccountSessionsSheet({ accessToken, supabaseUrl, publishableKey, appName, onDismiss, onSessionExpired }: {
  accessToken: string;
  supabaseUrl: string;
  publishableKey: string;
  appName: string;
  onDismiss: () => void;
  onSessionExpired: () => void;
}) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const metadata = useMemo(() => webSessionMetadata(appName), [appName]);
  const [sessions, setSessions] = useState<AccountSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [revokingSessionId, setRevokingSessionId] = useState<string>();
  const [error, setError] = useState<string>();
  const closeButton = useRef<HTMLButtonElement>(null);
  const operationBusy = busy || !!revokingSessionId;
  const dialog = useModalDialog<HTMLElement>({ busy: operationBusy, onDismiss, initialFocus: closeButton });

  const load = useCallback(async () => {
    setLoading(true); setError(undefined);
    try {
      setSessions((await getAccountSessions({ ...auth, ...metadata })).sessions);
    } catch (loadError) {
      if (loadError instanceof AccountSessionRequestError && loadError.status === 401) return onSessionExpired();
      setError(loadError instanceof Error ? loadError.message : "Devices could not be loaded.");
    } finally { setLoading(false); }
  }, [auth, metadata, onSessionExpired]);

  useEffect(() => { void load(); }, [load]);

  const signOutOthers = async () => {
    setBusy(true); setError(undefined);
    try {
      setSessions((await signOutOtherSessions({ ...auth, ...metadata })).sessions);
    } catch (signOutError) {
      if (signOutError instanceof AccountSessionRequestError && signOutError.status === 401) return onSessionExpired();
      setError(signOutError instanceof Error ? signOutError.message : "Other devices could not be signed out.");
    } finally { setBusy(false); }
  };

  const removeSession = async (sessionId: string) => {
    setRevokingSessionId(sessionId); setError(undefined);
    try {
      setSessions((await revokeAccountSession({ ...auth, sessionId })).sessions);
    } catch (removeError) {
      if (removeError instanceof AccountSessionRequestError && removeError.status === 401) return onSessionExpired();
      setError(removeError instanceof Error ? removeError.message : "That device could not be signed out.");
    } finally { setRevokingSessionId(undefined); }
  };

  const dismissFromBackdrop = (event: MouseEvent<HTMLDivElement>) => {
    if (event.target === event.currentTarget && !operationBusy) onDismiss();
  };
  const otherCount = sessions.filter((session) => !session.isCurrent).length;

  return <div className="customer-sheet-backdrop" role="presentation" onMouseDown={dismissFromBackdrop}>
    <section ref={dialog} className="customer-sheet account-sessions-sheet" role="dialog" aria-modal="true" aria-labelledby="sessions-title" tabIndex={-1}>
      <header className="account-sheet-heading"><span className="account-dialog-mark" aria-hidden="true"><ShieldCheck size={21} /></span><div><p className="eyebrow">Security</p><h2 id="sessions-title">Devices and sessions</h2><p>Review where your Dastak account is signed in.</p></div><button ref={closeButton} className="icon-button" type="button" onClick={onDismiss} disabled={operationBusy} aria-label="Close sessions" title="Close"><X size={19} /></button></header>
      {loading ? <div className="account-sessions-loading" role="status"><RefreshCw size={18} /> Checking devices…</div> : <div className="account-session-list">
        {sessions.map((session) => <SessionRow key={session.sessionId} session={session} busy={revokingSessionId === session.sessionId} disabled={operationBusy} onRemove={() => void removeSession(session.sessionId)} />)}
        {sessions.length === 0 && !error && <p className="account-sessions-empty">No active sessions were returned.</p>}
      </div>}
      {error && <div className="account-sessions-error" role="alert"><span>{error}</span><button type="button" onClick={() => void load()}>Try again</button></div>}
      <div className="account-sessions-note"><CheckCircle2 size={18} /><p><strong>This device stays signed in.</strong><span>Removed devices are blocked from Dastak requests and cannot refresh their sessions.</span></p></div>
      <button className="secondary-button account-sessions-action" type="button" onClick={() => void signOutOthers()} disabled={operationBusy || loading || otherCount === 0}><LogOut size={18} /> {busy ? "Signing out…" : otherCount === 0 ? "No other devices" : `Sign out ${otherCount} other ${otherCount === 1 ? "device" : "devices"}`}</button>
    </section>
  </div>;
}

function SessionRow({ session, busy, disabled, onRemove }: { session: AccountSession; busy: boolean; disabled: boolean; onRemove: () => void }) {
  const Icon = session.platform === "ios" ? Smartphone : Laptop;
  return <article className={session.isCurrent ? "current" : ""}>
    <span className="account-session-icon"><Icon size={19} /></span>
    <span><strong>{session.deviceName}</strong><small>{session.appName} · {relativeDate(session.lastSeenAt)}</small></span>
    {session.isCurrent
      ? <b>Current</b>
      : <button className="account-session-remove" type="button" disabled={disabled} onClick={onRemove}>{busy ? "Removing…" : "Remove"}</button>}
  </article>;
}

function relativeDate(value: string) {
  const elapsed = Date.now() - Date.parse(value);
  if (elapsed < 60_000) return "Active now";
  if (elapsed < 3_600_000) return `${Math.max(1, Math.floor(elapsed / 60_000))} min ago`;
  if (elapsed < 86_400_000) return `${Math.floor(elapsed / 3_600_000)} hr ago`;
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value));
}
