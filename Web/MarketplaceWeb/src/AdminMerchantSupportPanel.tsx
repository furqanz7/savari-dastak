import { useCallback, useEffect, useRef, useState } from "react";
import { ArrowLeft, Inbox, RefreshCw, Send } from "lucide-react";
import { callMerchantSupport, MerchantSupportError, parseSupportPage, parseSupportTicket, supportCategories, supportStatuses,
  type SupportConnection, type SupportInput, type SupportStatus, type SupportTicket, type SupportTicketRow } from "./merchantSupport";
import { SupportConversation } from "./MerchantSupportPage";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import "./design/merchant-support.css";

export function AdminMerchantSupportPanel({ auth }: { auth: SupportConnection }) {
  const [rows, setRows] = useState<SupportTicketRow[]>([]); const [more, setMore] = useState(false);
  const [filter, setFilter] = useState<SupportStatus>("OPEN"); const [ticket, setTicket] = useState<SupportTicket>();
  const [message, setMessage] = useState(""); const [status, setStatus] = useState<SupportStatus>("WAITING_ON_MERCHANT");
  const [pending, setPending] = useState<SupportInput>(); const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>(); const [notice, setNotice] = useState<string>();
  const generation = useRef(0); const lock = useRef(false); const mutation = useRef(false);
  const controller = useRef<AbortController | undefined>(undefined);
  const load = useCallback(async (append = false, after?: SupportTicketRow) => {
    if (lock.current || mutation.current) return;
    const gen = ++generation.current; controller.current?.abort(); controller.current = new AbortController();
    lock.current = true; setBusy(true); setError(undefined);
    try {
      const page = parseSupportPage(await callMerchantSupport(auth, { operation: "adminList", status: filter,
        ...(after ? { cursorAt: after.updatedAt, cursorId: after.id } : {}) }, controller.current.signal));
      if (gen !== generation.current) return;
      setRows(current => append ? [...current, ...page.tickets.filter(t => !current.some(c => c.id === t.id))] : page.tickets); setMore(page.more);
    } catch (e) { if (gen === generation.current) setError(e instanceof Error ? e.message : "Inbox unavailable."); }
    finally { if (gen === generation.current) { lock.current = false; setBusy(false); } }
  }, [auth, filter]);
  useEffect(() => {
    void load();
    // Capture the ref objects, not a stale numeric generation. Cleanup must
    // invalidate whichever request is active when auth/filter/unmount changes.
    const lifecycle = generation; const abort = controller; const requestLock = lock;
    return () => { lifecycle.current++; abort.current?.abort(); requestLock.current = false; };
  }, [load]);
  async function read(id: string) {
    if (lock.current) return;
    const gen = ++generation.current; lock.current = true; setBusy(true); setError(undefined);
    try { const result = parseSupportTicket(await callMerchantSupport(auth, { operation: "adminRead", ticketId: id }));
      if (gen === generation.current) {
        setTicket(result); setNotice(undefined);
        if (pending && result.messages.some(m => m.id === pending.requestId && m.body === pending.message && m.side === "SUPPORT")) {
          setPending(undefined); mutation.current = false; setMessage(""); setNotice("The saved reply is confirmed in this conversation.");
        }
      } }
    catch (e) { if (gen === generation.current) setError(e instanceof Error ? e.message : "Conversation unavailable."); }
    finally { if (gen === generation.current) { lock.current = false; setBusy(false); } }
  }
  useAdminWorkspaceRefresh("merchantSupport", async () => { if (ticket) await read(ticket.id); else await load(); });
  async function send(input: SupportInput) {
    if (lock.current) return;
    const gen = ++generation.current; lock.current = true; mutation.current = true; setBusy(true); setPending(input); setError(undefined); setNotice(undefined);
    try {
      const result = parseSupportTicket(await callMerchantSupport(auth, input));
      if (gen === generation.current) { setTicket(result); setMessage(""); setPending(undefined); mutation.current = false;
        setNotice("Reply saved. The merchant can read it using their private recovery code. No email or push was sent."); }
    } catch (e) {
      if (gen !== generation.current) return;
      setError(e instanceof Error ? e.message : "Reply was not confirmed.");
      if (e instanceof MerchantSupportError && ["support_invalid", "support_stale", "support_thread_full", "support_conflict", "authentication_required", "support_forbidden"].includes(e.code)) { setPending(undefined); mutation.current = false; }
    } finally { if (gen === generation.current) { lock.current = false; setBusy(false); } }
  }
  return <section className="admin-section merchant-support-admin" aria-label="Merchant support inbox">
    <header><div><p className="eyebrow">MERCHANT CARE</p><h2><Inbox aria-hidden="true" />A clear path to a reply.</h2><p>Unverified reports from the public help form. A ticket or claimed order number is not proof of identity. Verify ownership through existing procedures before any separate account or financial action.</p></div></header>
    {error ? <p role="alert" className="merchant-support-alert">{error}</p> : null}
    {notice ? <p role="status" className="merchant-support-notice">{notice}</p> : null}
    <p className="merchant-support-safety">Never request passwords, bank details, identity documents or active handoff codes in this conversation. Reply text is visible to anyone holding the private recovery code.</p>
    {ticket ? <>
      <button disabled={busy || !!pending} onClick={() => { setTicket(undefined); setMessage(""); setNotice(undefined); void load(); }}><ArrowLeft size={16} />Back to inbox</button>
      <div className="merchant-support-ticket-head"><span>{supportCategories[ticket.category]}</span><span className={`merchant-support-status ${ticket.status.toLowerCase()}`}>{supportStatuses[ticket.status]}</span></div><h3>{ticket.subject}</h3><small>Reference: {ticket.id}</small>
      <SupportConversation ticket={ticket} />
      <button disabled={busy} onClick={() => void read(ticket.id)}><RefreshCw size={16} />Refresh conversation</button>
      {pending ? <div><p>The reply has not been confirmed. Retry uses the original text and request ID.</p><button disabled={busy} onClick={() => void send(pending)}>Retry same reply</button></div> : <form onSubmit={e => { e.preventDefault(); void send({ operation: "adminReply", ticketId: ticket.id, requestId: crypto.randomUUID(), message, status, version: ticket.version }); }}>
        <label>Reply to merchant<textarea required minLength={5} maxLength={2000} disabled={busy} value={message} onChange={e => setMessage(e.target.value)} /></label>
        <label>After this reply<select value={status} disabled={busy} onChange={e => setStatus(e.target.value as SupportStatus)}>{Object.entries(supportStatuses).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>
        <button className="merchant-support-primary" disabled={busy || message.trim().length < 5}><Send size={16} />Save reply & status</button>
      </form>}
    </> : <>
      <div className="merchant-support-inbox-tools"><label>Show requests<select disabled={busy} value={filter} onChange={e => setFilter(e.target.value as SupportStatus)}>{Object.entries(supportStatuses).map(([key, label]) => <option value={key} key={key}>{label}</option>)}</select></label><button disabled={busy} onClick={() => void load()}><RefreshCw size={16} />{busy ? "Refreshing…" : "Refresh inbox"}</button></div>
      <p>No email alert is configured. Check this inbox regularly; changing a filter or refreshing loads the server’s current records.</p>
      <ul className="merchant-support-inbox">{rows.map(row => <li key={row.id}><button disabled={busy} onClick={() => void read(row.id)}><span><small>{supportCategories[row.category]} · {supportStatuses[row.status]}</small><strong>{row.subject}</strong><small>{new Date(row.updatedAt).toLocaleString()}</small></span><span aria-hidden="true">→</span></button></li>)}</ul>
      {!rows.length && !busy && !error ? <p>No requests in this view.</p> : null}
      {more ? <button disabled={busy} onClick={() => void load(true, rows.at(-1))}>Load more requests</button> : null}
    </>}
  </section>;
}
