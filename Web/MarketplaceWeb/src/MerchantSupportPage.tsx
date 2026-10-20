import { useEffect, useRef, useState, type FormEvent } from "react";
import { ArrowLeft, ArrowRight, CheckCircle2, LifeBuoy, LockKeyhole, RefreshCw } from "lucide-react";
import { callMerchantSupport, createSupportCapability, MerchantSupportError, parseSupportRecoveryCode, parseSupportTicket, readMerchantSupportConnection, supportCategories, supportRecoveryCode, supportStatuses,
  type SupportCapability, type SupportConnection, type SupportInput, type SupportTicket } from "./merchantSupport";
import "./design/merchant-support.css";

export function MerchantSupportEntry() {
  try {
    const connection = readMerchantSupportConnection(import.meta.env, { development: import.meta.env.DEV, pageUrl: window.location.href });
    return <MerchantSupportPage connection={connection} />;
  } catch { return <main className="merchant-support"><h1>Merchant support</h1><p role="alert">Support is not configured on this site. No request has been sent.</p><a href="/">Back to Dastak</a></main>; }
}

export function MerchantSupportPage({ connection }: { connection: SupportConnection }) {
  const [mode, setMode] = useState<"create" | "track">("create");
  const [subject, setSubject] = useState(""); const [message, setMessage] = useState("");
  const [category, setCategory] = useState("ACCESS"); const [website, setWebsite] = useState("");
  const [consent, setConsent] = useState(false); const [code, setCode] = useState("");
  const [capability, setCapability] = useState<SupportCapability>(); const [ticket, setTicket] = useState<SupportTicket>();
  const [pending, setPending] = useState<SupportInput>(); const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>(); const [notice, setNotice] = useState<string>();
  const inFlight = useRef(false); const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true; document.title = "Merchant support — Dastak";
    // Capabilities are deliberately absent from URLs, cookies and persistent storage.
    const meta = document.createElement("meta"); meta.name = "referrer"; meta.content = "no-referrer"; document.head.append(meta);
    return () => { mounted.current = false; meta.remove(); };
  }, []);
  async function send(input: SupportInput) {
    if (inFlight.current) return;
    inFlight.current = true; setBusy(true); setError(undefined); setNotice(undefined);
    const mutation = ["create", "reply"].includes(input.operation);
    if (mutation) setPending(input);
    try {
      const result = parseSupportTicket(await callMerchantSupport(connection, input));
      if (result.id !== input.ticketId) throw new MerchantSupportError("support_unavailable");
      if (!mounted.current) return;
      setTicket(result); setMode("track");
      if (mutation) { setPending(undefined); setMessage(""); setNotice(input.operation === "create" ? "Request received. Save your private recovery code below." : "Your reply was received."); }
      else if (pending && result.messages.some(m => m.id === pending.requestId && m.body === pending.message)) {
        setPending(undefined); setMessage(""); setNotice("Your saved request is confirmed in this conversation.");
      }
    } catch (e) {
      if (!mounted.current) return;
      setError(e instanceof Error ? e.message : "Support is unavailable.");
      // Definitive rejections are not ambiguous writes; allow editing/reloading.
      if (e instanceof MerchantSupportError && ["support_invalid", "support_stale", "support_thread_full", "support_conflict"].includes(e.code)) setPending(undefined);
    } finally { inFlight.current = false; if (mounted.current) setBusy(false); }
  }
  function submit(event: FormEvent) {
    event.preventDefault(); if (pending || busy || !consent) return;
    const next = createSupportCapability(); setCapability(next); setCode(supportRecoveryCode(next));
    void send({ operation: "create", ...next, requestId: crypto.randomUUID(), subject, message, category, consent, website });
  }
  function open(event: FormEvent) {
    event.preventDefault(); const next = parseSupportRecoveryCode(code);
    if (!next) { setError("Paste the entire private recovery code."); return; }
    setCapability(next); setTicket(undefined); void send({ operation: "read", ...next });
  }
  function startNew() {
    setCapability(undefined); setTicket(undefined); setCode(""); setMessage(""); setSubject(""); setConsent(false); setPending(undefined); setError(undefined); setNotice(undefined); setMode("create");
  }
  return <div className="merchant-support-page">
    <header className="merchant-support-top"><a href="/" className="merchant-support-brand">Dastak <span lang="ur">دستک</span></a><a href="/privacy">Privacy</a></header>
    <main className="merchant-support">
      <section className="merchant-support-hero"><span className="merchant-support-mark"><LifeBuoy aria-hidden="true" /></span><p className="eyebrow">FOR THE PEOPLE BEHIND THE STORE</p><h1>A little help.<br /><em>A clear next step.</em></h1><p>Merchant help for sign-in, your store, orders and earnings. You can reach us here even if you can’t sign in.</p></section>
      <aside className="merchant-support-safety"><LockKeyhole aria-hidden="true" /><div><strong>Keep the sensitive things private.</strong><p>Never send passwords, UPI PINs, bank-account numbers, identity documents or active handoff codes. A support request cannot approve an account, release a payment or change an order.</p></div></aside>
      {!ticket && !pending ? <nav aria-label="Support options" className="merchant-support-tabs"><button aria-pressed={mode === "create"} onClick={() => { setMode("create"); setError(undefined); }}>New request</button><button aria-pressed={mode === "track"} onClick={() => { setMode("track"); setError(undefined); }}>Read a reply</button></nav> : null}
      {error ? <p className="merchant-support-alert" role="alert">{error}</p> : null}
      {notice ? <p className="merchant-support-notice" role="status"><CheckCircle2 aria-hidden="true" />{notice}</p> : null}
      {capability ? <section className="merchant-support-card"><h2>Your private recovery code</h2><p>Save this somewhere private before leaving. Anyone with it can read and reply to this conversation. We do not email replies, and cannot recover a lost code.</p><label>Recovery code<input aria-label="Your private recovery code" readOnly value={supportRecoveryCode(capability)} onFocus={e => e.currentTarget.select()} autoComplete="off" spellCheck={false} /></label><small>Select the field to copy. Return to this page and choose “Read a reply”. Do not send this code to support.</small></section> : null}
      {pending ? <section className="merchant-support-card"><h2>Keep your original request</h2><p>Until a response confirms it, retry sends exactly the same details and will not intentionally create a second request.</p><button className="merchant-support-primary" disabled={busy} onClick={() => void send(pending)}><RefreshCw size={18} />{busy ? "Checking…" : "Retry same request"}</button><button disabled={busy} onClick={() => capability && void send({ operation: "read", ...capability })}>Check saved result</button></section> : null}
      {ticket ? <section className="merchant-support-card" aria-label="Support conversation"><div className="merchant-support-ticket-head"><span>{supportCategories[ticket.category]}</span><span className={`merchant-support-status ${ticket.status.toLowerCase()}`}>{supportStatuses[ticket.status]}</span></div><h2>{ticket.subject}</h2><small>Reference: {ticket.id}</small><SupportConversation ticket={ticket} />
        <button disabled={busy} onClick={() => capability && void send({ operation: "read", ...capability })}><RefreshCw size={16} />Refresh replies</button>
        {!pending ? <form onSubmit={e => { e.preventDefault(); if (capability) void send({ operation: "reply", ...capability, requestId: crypto.randomUUID(), version: ticket.version, message }); }}><label>Your reply<textarea required minLength={5} maxLength={2000} value={message} disabled={busy} onChange={e => setMessage(e.target.value)} /></label><small>A reply reopens a resolved request. Please allow 30 seconds between messages.</small><button className="merchant-support-primary" disabled={busy || message.trim().length < 5}>Send reply<ArrowRight size={18} /></button></form> : null}
        <button disabled={busy || !!pending} onClick={startNew}>Close this conversation</button>
      </section> : !pending && mode === "create" ? <form className="merchant-support-card" onSubmit={submit}><h2>Tell us what needs attention.</h2><p>No sign-in or email address needed. Support replies appear on this private page when you return with your recovery code.</p><fieldset disabled={busy}><label>What is this about?<select value={category} onChange={e => setCategory(e.target.value)}>{Object.entries(supportCategories).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label><label>A short summary<input required minLength={5} maxLength={100} value={subject} onChange={e => setSubject(e.target.value)} /></label><label>How can we help?<textarea required minLength={5} maxLength={2000} value={message} onChange={e => setMessage(e.target.value)} placeholder="What happened, and what did you expect? You may include an order reference, but never a live handoff code." /></label><small>{message.length}/2000 characters · No attachments</small><div className="merchant-support-trap" aria-hidden="true"><label>Website<input tabIndex={-1} autoComplete="off" value={website} onChange={e => setWebsite(e.target.value)} /></label></div><label className="merchant-support-consent"><input type="checkbox" checked={consent} onChange={e => setConsent(e.target.checked)} required /><span>I understand this text is stored for Dastak support and visible to authorized Admin staff. I will save the private recovery code to read replies.</span></label><button className="merchant-support-primary" disabled={!consent || subject.trim().length < 5 || message.trim().length < 5}>Send request<ArrowRight size={18} /></button></fieldset></form>
        : !pending ? <form className="merchant-support-card" onSubmit={open}><h2>Pick up the conversation.</h2><p>Paste your private recovery code. It is not an order number, password or OTP.</p><label>Private recovery code<input required autoComplete="off" spellCheck={false} value={code} onChange={e => setCode(e.target.value)} disabled={busy} /></label><button className="merchant-support-primary" disabled={busy}>Open request<ArrowRight size={18} /></button></form> : null}
      <footer><p>This is not an emergency service. There is no guaranteed reply time. Keep your recovery code and return to check for updates.</p><a href="/"><ArrowLeft size={16} />Back to Dastak</a></footer>
    </main>
  </div>;
}

export function SupportConversation({ ticket }: { ticket: SupportTicket }) {
  return <ol className="merchant-support-conversation">{ticket.messages.map(m => <li key={m.id} className={m.side.toLowerCase()}><div><strong>{m.side === "SUPPORT" ? "Dastak support" : "Merchant"}</strong><time dateTime={m.createdAt}>{new Date(m.createdAt).toLocaleString()}</time></div><p>{m.body}</p></li>)}</ol>;
}
