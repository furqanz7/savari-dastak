import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  Bike,
  Check,
  CircleAlert,
  Activity,
  Database,
  ExternalLink,
  FileText,
  LayoutDashboard,
  PackageSearch,
  RefreshCw,
  RotateCcw,
  ShieldCheck,
  Store,
  UserRound,
  UsersRound,
  WalletCards,
  X,
} from "lucide-react";
import { RoleAccountView } from "./RoleAccountView";
import { AdminAccessPanel } from "./AdminAccessPanel";
import { AdminCataloguePanel } from "./AdminCataloguePanel";
import {
  getAdminOrders,
  getEvidenceUrl,
  getMerchantApplications,
  getOwnerOperations,
  getPartnerApplications,
  reconcileOwnerOrders,
  resetOwnerHandoff,
  resolveOwnerSupportCase,
  reviewOrderRefund,
  reviewMerchantApplication,
  reviewPartnerApplication,
  type AdminOrder,
  type MerchantAdminApplication,
  type OwnerOperationsSnapshot,
  type OwnerOrderException,
  type PartnerAdminApplication,
  type ReviewDecision,
} from "./admin";
import { formatPrice } from "./catalogue";
import { orderStatusLabel } from "./orders";
import { processOrderRefund } from "./payments";
import { AdminV1ExecutionPanel } from "./AdminV1ExecutionPanel";
import { AdminSystemHealthPanel } from "./AdminSystemHealthPanel";
import { AdminOperationalSafetyPanel } from "./AdminOperationalSafetyPanel";
import { AdminRoyaltyPayoutPanel } from "./AdminRoyaltyPayoutPanel";
import { AdminOverviewPanel } from "./AdminOverviewPanel";
import { AdminNetworkPanel } from "./AdminNetworkPanel";
import {
  getV1AdminAccess,
  getV1AdminCommandCenter,
  type V1AdminAccess,
  type V1AdminCommandCenter,
} from "./dastakV1";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

type AdminTab =
  | "overview" | "approvals" | "exceptions" | "orders" | "network"
  | "catalogue" | "safety" | "finance" | "health" | "access"
  | "legacy" | "account";

type AdminBootstrapFeed =
  | "merchantApprovals"
  | "deliveryApprovals"
  | "legacyHistory"
  | "operations"
  | "adminAccess"
  | "commandCenter";

type AdminFeedIssue = {
  feed: AdminBootstrapFeed;
  label: string;
  message: string;
  failedAt: string;
};

const adminFeedLabels: Record<AdminBootstrapFeed, string> = {
  merchantApprovals: "Merchant approvals",
  deliveryApprovals: "Delivery approvals",
  legacyHistory: "Legacy history",
  operations: "Exception desk",
  adminAccess: "Admin access",
  commandCenter: "Command center",
};

const adminBootstrapFeeds: AdminBootstrapFeed[] = [
  "merchantApprovals",
  "deliveryApprovals",
  "legacyHistory",
  "operations",
  "adminAccess",
  "commandCenter",
];

export function AdminDashboard({ accessToken, displayName, email, phoneNumber, supabaseUrl, publishableKey, onSignOut }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [merchants, setMerchants] = useState<MerchantAdminApplication[]>([]);
  const [partners, setPartners] = useState<PartnerAdminApplication[]>([]);
  const [orders, setOrders] = useState<AdminOrder[]>([]);
  const [operations, setOperations] = useState<OwnerOperationsSnapshot>();
  const [adminAccess, setAdminAccess] = useState<V1AdminAccess>();
  const [commandCenter, setCommandCenter] = useState<V1AdminCommandCenter>();
  const [tab, setTab] = useState<AdminTab>("overview");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [feedIssues, setFeedIssues] = useState<Partial<Record<AdminBootstrapFeed, AdminFeedIssue>>>({});
  const [feedUpdatedAt, setFeedUpdatedAt] = useState<Partial<Record<AdminBootstrapFeed, string>>>({});
  const [notice, setNotice] = useState<string>();
  const reviewKeys = useRef(new Map<string, string>());
  const refreshInFlight = useRef(false);

  const refresh = useCallback(async (showProgress = false) => {
    if (refreshInFlight.current) return;
    refreshInFlight.current = true;
    if (showProgress) setBusy("refresh");
    try {
      const results = await Promise.allSettled([
        getMerchantApplications(auth),
        getPartnerApplications(auth),
        // Legacy history is diagnostic only and its failure remains isolated.
        getAdminOrders({ ...auth, limit: 50 }),
        getOwnerOperations({ ...auth, limit: 50 }),
        getV1AdminAccess(auth),
        getV1AdminCommandCenter(auth),
      ]);
      const [merchantResult, partnerResult, legacyResult, operationsResult, accessResult, commandResult] = results;
      if (merchantResult.status === "fulfilled") setMerchants(merchantResult.value.filter((application) => application.status === "pending"));
      if (partnerResult.status === "fulfilled") setPartners(partnerResult.value.filter((application) => application.status === "pending"));
      if (legacyResult.status === "fulfilled") setOrders(legacyResult.value);
      if (operationsResult.status === "fulfilled") setOperations(operationsResult.value);
      if (accessResult.status === "fulfilled") setAdminAccess(accessResult.value);
      if (commandResult.status === "fulfilled") setCommandCenter(commandResult.value);
      const observedAt = new Date().toISOString();
      setFeedIssues((current) => {
        const next = { ...current };
        results.forEach((result, index) => {
          const feed = adminBootstrapFeeds[index];
          if (result.status === "fulfilled") delete next[feed];
          else next[feed] = {
            feed,
            label: adminFeedLabels[feed],
            message: feedFailureMessage(feed, result.reason),
            failedAt: observedAt,
          };
        });
        return next;
      });
      setFeedUpdatedAt((current) => {
        const next = { ...current };
        results.forEach((result, index) => {
          if (result.status === "fulfilled") next[adminBootstrapFeeds[index]] = observedAt;
        });
        return next;
      });
      setLoading(false);
    } finally {
      refreshInFlight.current = false;
      if (showProgress) setBusy(undefined);
    }
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    const refreshWhenVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    const interval = window.setInterval(refreshWhenVisible, 30_000);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [refresh]);

  const review = async (kind: "merchant" | "partner", applicationId: string, decision: ReviewDecision, reason?: string) => {
    const identity = `${kind}:${applicationId}:${decision}:${reason ?? ""}`;
    const idempotencyKey = reviewKeys.current.get(identity) ?? crypto.randomUUID();
    reviewKeys.current.set(identity, idempotencyKey);
    setBusy(identity);
    setActionError(undefined);
    try {
      const input = { ...auth, applicationId, decision, reason, idempotencyKey };
      if (kind === "merchant") await reviewMerchantApplication(input);
      else await reviewPartnerApplication(input);
      reviewKeys.current.delete(identity);
      await refresh();
    } catch (reviewError) {
      setActionError(message(reviewError));
      throw reviewError;
    } finally {
      setBusy(undefined);
    }
  };

  const openEvidence = async (objectPath: string) => {
    setBusy(`evidence:${objectPath}`);
    setActionError(undefined);
    try {
      const signedUrl = await getEvidenceUrl({ ...auth, objectPath });
      window.location.assign(signedUrl);
    } catch (evidenceError) {
      setActionError(message(evidenceError));
    } finally {
      setBusy(undefined);
    }
  };

  const reviewRefund = async (
    order: AdminOrder,
    outcome: "approve_full" | "approve_items_only" | "deny",
    faultSource: "merchant" | "dastak" | null,
    reason: string,
  ) => {
    const identity = `refund:${order.orderId}:${outcome}:${faultSource ?? "none"}:${reason}`;
    const idempotencyKey = reviewKeys.current.get(identity) ?? crypto.randomUUID();
    reviewKeys.current.set(identity, idempotencyKey);
    setBusy(identity);
    setActionError(undefined);
    try {
      const updated = await reviewOrderRefund({
        ...auth, orderId: order.orderId, outcome, faultSource, reason, idempotencyKey,
      });
      reviewKeys.current.delete(identity);
      await refresh();
      if (outcome !== "deny" && updated.paymentState === "refund_pending" &&
        updated.status !== "returning_to_merchant") {
        await processOrderRefund({ ...auth, orderId: order.orderId, idempotencyKey: crypto.randomUUID() });
        await refresh();
      }
    } catch (reviewError) {
      setActionError(message(reviewError));
    } finally {
      setBusy(undefined);
    }
  };

  const retryRefund = async (order: AdminOrder) => {
    setBusy(`process-refund:${order.orderId}`);
    setActionError(undefined);
    try {
      await processOrderRefund({ ...auth, orderId: order.orderId, idempotencyKey: crypto.randomUUID() });
      await refresh();
    } catch (refundError) {
      setActionError(message(refundError));
    } finally {
      setBusy(undefined);
    }
  };

  const resolveSupport = async (exception: OwnerOrderException, resolution: string) => {
    const identity = `support:${exception.entityId}:${resolution}`;
    const idempotencyKey = reviewKeys.current.get(identity) ?? crypto.randomUUID();
    reviewKeys.current.set(identity, idempotencyKey);
    setBusy(identity);
    setActionError(undefined);
    try {
      await resolveOwnerSupportCase({ ...auth, caseId: exception.entityId, resolution, idempotencyKey });
      reviewKeys.current.delete(identity);
      setNotice("Support case resolved and recorded.");
      await refresh();
    } catch (supportError) {
      setActionError(message(supportError));
      throw supportError;
    } finally {
      setBusy(undefined);
    }
  };

  const resetHandoff = async (exception: OwnerOrderException, reason: string) => {
    if (!exception.purpose) return;
    const identity = `handoff:${exception.entityKind}:${exception.entityId}:${exception.purpose}:${reason}`;
    const idempotencyKey = reviewKeys.current.get(identity) ?? crypto.randomUUID();
    reviewKeys.current.set(identity, idempotencyKey);
    setBusy(identity);
    setActionError(undefined);
    try {
      await resetOwnerHandoff({
        ...auth,
        entityKind: exception.entityKind,
        entityId: exception.entityId,
        purpose: exception.purpose,
        reason,
        idempotencyKey,
      });
      reviewKeys.current.delete(identity);
      setNotice("Handoff code unlocked and securely regenerated.");
      await refresh();
    } catch (handoffError) {
      setActionError(message(handoffError));
      throw handoffError;
    } finally {
      setBusy(undefined);
    }
  };

  const reconcile = async () => {
    setBusy("reconcile");
    setActionError(undefined);
    try {
      const result = await reconcileOwnerOrders(auth);
      const recovered = result.merchantOrdersRecovered + result.parcelsRecovered;
      const offers = result.merchantOffersCreated + result.parcelOffersCreated;
      setNotice(`Recovery complete: ${recovered} records repaired, ${offers} offers created.`);
      await refresh();
    } catch (reconcileError) {
      setActionError(message(reconcileError));
    } finally {
      setBusy(undefined);
    }
  };

  const mainNavigation: Array<{ id: AdminTab; label: string; icon: ReactNode; badge?: number }> = [
    { id: "overview", label: "Overview", icon: <LayoutDashboard size={18} /> },
    { id: "approvals", label: "Approvals", icon: <ShieldCheck size={18} />, badge: merchants.length + partners.length },
    { id: "orders", label: "Live orders", icon: <PackageSearch size={18} /> },
    { id: "network", label: "Network", icon: <UsersRound size={18} /> },
    { id: "catalogue", label: "Catalogue", icon: <Database size={18} /> },
    { id: "exceptions", label: "Exceptions", icon: <CircleAlert size={18} />, badge: operations?.summary.totalExceptions },
  ];
  const controlNavigation: Array<{ id: AdminTab; label: string; icon: ReactNode }> = [
    { id: "safety", label: "Safety controls", icon: <CircleAlert size={18} /> },
    { id: "finance", label: "Finance & Royalty", icon: <WalletCards size={18} /> },
    { id: "health", label: "System health", icon: <Activity size={18} /> },
    { id: "legacy", label: "Legacy history", icon: <FileText size={18} /> },
    { id: "access", label: "Admin access", icon: <ShieldCheck size={18} /> },
    { id: "account", label: "My account", icon: <UserRound size={18} /> },
  ];
  const mobilePrimaryNavigation = mainNavigation.filter((item) => item.id !== "catalogue");
  const mobileWorkspaceNavigation = [
    ...mainNavigation.filter((item) => item.id === "catalogue"),
    ...controlNavigation,
  ];

  return <div className="admin-console">
    <aside className="admin-sidebar" aria-label="Admin navigation">
      <header><span>D</span><div><strong>Dastak</strong><small>Admin control</small></div></header>
      <p>OPERATIONS</p>
      <AdminNavigation items={mainNavigation} selected={tab} onSelect={setTab} />
      <p>CONTROL & GOVERNANCE</p>
      <AdminNavigation items={controlNavigation} selected={tab} onSelect={setTab} />
      <footer><span>{initials(displayName ?? "Admin")}</span><div><strong>{displayName ?? "Dastak Admin"}</strong><small>{adminRoleLabel(adminAccess?.role)}</small></div></footer>
    </aside>

    <main className="admin-shell">
      <header className="admin-heading"><div><p className="eyebrow">{adminRoleLabel(adminAccess?.role).toUpperCase()} WORKSPACE</p><h1>{tabTitle(tab)}</h1><p>{tabDescription(tab)}</p></div><button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={busy === "refresh"} aria-label="Refresh Admin workspace"><RefreshCw size={19} /></button></header>
      <nav className="admin-secondary-mobile" aria-label="More Admin workspaces"><AdminNavigation items={mobileWorkspaceNavigation} selected={tab} onSelect={setTab} /></nav>
      <AdminFeedStatus issues={feedIssues} updatedAt={feedUpdatedAt} busy={busy === "refresh"} onRetry={() => void refresh(true)} />
      {actionError ? <p className="order-error" role="alert">{actionError}</p> : null}
      {notice ? <div className="admin-notice" role="status"><Check size={18} /><span>{notice}</span><button type="button" onClick={() => setNotice(undefined)} aria-label="Dismiss confirmation"><X size={16} /></button></div> : null}

      {tab === "overview" ? <AdminOverviewPanel snapshot={commandCenter} loading={loading} onNavigate={setTab} />
        : tab === "network" ? <AdminNetworkPanel auth={auth} />
        : tab === "catalogue" ? <AdminCataloguePanel auth={auth} />
        : tab === "orders" ? <AdminV1ExecutionPanel auth={auth} />
        : tab === "finance" ? <AdminRoyaltyPayoutPanel auth={auth} />
        : tab === "safety" ? <AdminOperationalSafetyPanel auth={auth} />
        : tab === "health" ? <AdminSystemHealthPanel auth={auth} />
        : tab === "access" ? adminAccess?.canManageAdmins
          ? <AdminAccessPanel auth={auth} access={adminAccess} onChange={setAdminAccess} />
          : <section className="admin-section" role="tabpanel"><h2>Admin access</h2><p className="admin-empty">{adminAccess ? "Only the permanent Superadmin can assign Executive Admin seats." : "Admin access settings are not available yet. Use the workspace retry above."}</p></section>
        : tab === "account" ? <RoleAccountView accessToken={accessToken} displayName={displayName} email={email} phoneNumber={phoneNumber} roleName={adminRoleLabel(adminAccess?.role)} accessLabel="Full operations access" supabaseUrl={supabaseUrl} publishableKey={publishableKey} allowsAccountDeletion={false} onSignOut={onSignOut} />
        : loading ? <div className="catalogue-loading" role="status"><span /> Loading operations</div>
        : tab === "approvals" ? <div className="admin-approvals" role="tabpanel">
          <ApprovalSection title="Merchant applications" count={merchants.length} empty={feedIssues.merchantApprovals && !feedUpdatedAt.merchantApprovals ? "Merchant application count is not available yet." : "No merchant applications waiting."}>{merchants.map((application) => <ReviewCard key={application.applicationId} icon={<Store size={20} />} title={application.businessName} subtitle={application.businessAddress} facts={[`Account ${shortId(application.accountId)}`]} evidence={[{ label: "View business evidence", path: application.evidenceObjectPath }]} busy={Boolean(busy)} onEvidence={openEvidence} onReview={(decision, reason) => review("merchant", application.applicationId, decision, reason)} />)}</ApprovalSection>
          <ApprovalSection title="Delivery Partner applications" count={partners.length} empty={feedIssues.deliveryApprovals && !feedUpdatedAt.deliveryApprovals ? "Delivery application count is not available yet." : "No Delivery Partner applications waiting."}>{partners.map((application) => <ReviewCard key={application.applicationId} icon={<Bike size={20} />} title={application.displayName} subtitle={application.phoneNumber} facts={[methodLabel(application.deliveryMethod), ...(application.vehicleRegistrationNumber ? [`${application.vehicleRegistrationNumber} · ${application.vehicleMakeModel}`] : []), `Submitted ${formatDate(application.submittedAt)}`]} evidence={[{ label: "View identity proof", path: application.identityEvidenceObjectPath }, ...(application.vehicleEvidenceObjectPath ? [{ label: "View vehicle RC", path: application.vehicleEvidenceObjectPath }] : [])]} busy={Boolean(busy)} onEvidence={openEvidence} onReview={(decision, reason) => review("partner", application.applicationId, decision, reason)} />)}</ApprovalSection>
        </div>
        : tab === "legacy" ? <OrdersPanel orders={orders} available={!feedIssues.legacyHistory || Boolean(feedUpdatedAt.legacyHistory)} busy={Boolean(busy)} onReview={reviewRefund} onRefund={retryRefund} />
        : <ExceptionsPanel operations={operations} available={!feedIssues.operations || Boolean(feedUpdatedAt.operations)} busy={Boolean(busy)} onResolve={resolveSupport} onReset={resetHandoff} onReconcile={reconcile} onReviewRefund={() => setTab("legacy")} />}
    </main>

    <nav className="admin-mobile-navigation" aria-label="Primary Admin navigation"><AdminNavigation items={mobilePrimaryNavigation} selected={tab} onSelect={setTab} /></nav>
  </div>;
}

function AdminNavigation({ items, selected, onSelect }: {
  items: Array<{ id: AdminTab; label: string; icon: ReactNode; badge?: number }>;
  selected: AdminTab;
  onSelect: (tab: AdminTab) => void;
}) {
  return <>{items.map((item) => <button type="button" key={item.id} className={selected === item.id ? "selected" : ""} aria-current={selected === item.id ? "page" : undefined} onClick={() => onSelect(item.id)}>{item.icon}<span>{item.label}</span>{item.badge ? <b>{item.badge}</b> : null}</button>)}</>;
}

function AdminFeedStatus({ issues, updatedAt, busy, onRetry }: {
  issues: Partial<Record<AdminBootstrapFeed, AdminFeedIssue>>;
  updatedAt: Partial<Record<AdminBootstrapFeed, string>>;
  busy: boolean;
  onRetry: () => void;
}) {
  const activeIssues = adminBootstrapFeeds
    .map((feed) => issues[feed])
    .filter((issue): issue is AdminFeedIssue => Boolean(issue));
  if (activeIssues.length === 0) return null;
  return <section className="admin-feed-status" aria-label="Workspace refresh status">
    <header><span><RefreshCw size={18} /></span><div><strong>Some workspaces need a refresh</strong><p>Current successful data remains visible. Each unavailable feed is identified below.</p></div></header>
    <ul>{activeIssues.map((issue) => <li key={issue.feed}><div><strong>{issue.label}</strong><span>{issue.message}</span></div><small>{formatFeedUpdatedAt(updatedAt[issue.feed])}</small></li>)}</ul>
    <button className="secondary-button" type="button" disabled={busy} onClick={onRetry}><RefreshCw size={16} /> Retry unavailable workspaces</button>
  </section>;
}

function tabTitle(tab: AdminTab) {
  return ({
    overview: "Command center", approvals: "Application approvals", exceptions: "Exception desk",
    orders: "Live order control", network: "Marketplace network", catalogue: "Master catalogue",
    safety: "Safety controls", finance: "Finance & Royalty", health: "System health",
    access: "Admin access", legacy: "Historical orders", account: "My account",
  } satisfies Record<AdminTab, string>)[tab];
}

function tabDescription(tab: AdminTab) {
  return ({
    overview: "A connected, real-time view of the Dastak marketplace.",
    approvals: "Review Merchant and Delivery Partner evidence with a complete audit trail.",
    exceptions: "Resolve customer support, refunds, secure handoffs and stalled lifecycles.",
    orders: "Inspect matching, preparation, custody, collection, delivery and financial truth.",
    network: "Understand every identity and its independently onboarded personas.",
    catalogue: "Control exact SKUs, evidence, QA readiness, pricing and visibility.",
    safety: "Manage scoped pauses and rider recovery without weakening custody.",
    finance: "Review earned Royalty and controlled payout readiness.",
    health: "Monitor invariants, outbox delivery and reconciliation queues.",
    access: "Protect one permanent Superadmin and two replaceable Executive Admin seats.",
    legacy: "Read-only oversight for the pre-V1 order lifecycle.",
    account: "Profile, security, sessions and sign-out controls.",
  } satisfies Record<AdminTab, string>)[tab];
}

function initials(value: string) {
  return value.split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
}

function adminRoleLabel(role?: V1AdminAccess["role"]) {
  return role === "SUPERADMIN" ? "Superadmin" : role === "EXECUTIVE_ADMIN" ? "Executive Admin" : "Admin";
}

function ExceptionsPanel({ operations, available, busy, onResolve, onReset, onReconcile, onReviewRefund }: {
  operations?: OwnerOperationsSnapshot;
  available: boolean;
  busy: boolean;
  onResolve: (exception: OwnerOrderException, resolution: string) => Promise<void>;
  onReset: (exception: OwnerOrderException, reason: string) => Promise<void>;
  onReconcile: () => Promise<void>;
  onReviewRefund: () => void;
}) {
  const exceptions = operations?.exceptions ?? [];
  return (
    <section className="admin-section admin-exceptions" role="tabpanel">
      <header>
        <div><h2>Exceptions</h2><p>Support, locked handoffs, refunds and stalled deliveries.</p></div>
        <button className="secondary-button" type="button" disabled={busy} onClick={() => void onReconcile()}><RotateCcw size={17} /> Run recovery</button>
      </header>
      {exceptions.length === 0 ? <p className="admin-empty">{available ? "No marketplace exceptions need attention." : "Exception data is not available yet."}</p> : (
        <div className="exception-list">
          {exceptions.map((exception) => (
            <ExceptionCard
              key={exception.exceptionId}
              exception={exception}
              busy={busy}
              onResolve={onResolve}
              onReset={onReset}
              onReviewRefund={onReviewRefund}
              onReconcile={onReconcile}
            />
          ))}
        </div>
      )}
    </section>
  );
}

function ExceptionCard({ exception, busy, onResolve, onReset, onReviewRefund, onReconcile }: {
  exception: OwnerOrderException;
  busy: boolean;
  onResolve: (exception: OwnerOrderException, resolution: string) => Promise<void>;
  onReset: (exception: OwnerOrderException, reason: string) => Promise<void>;
  onReviewRefund: () => void;
  onReconcile: () => Promise<void>;
}) {
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const requiresNote = exception.kind === "support" || exception.kind === "handoff_locked";

  const submit = async () => {
    if (note.trim().length < 5) return;
    setSubmitting(true);
    try {
      if (exception.kind === "support") await onResolve(exception, note.trim());
      if (exception.kind === "handoff_locked") await onReset(exception, note.trim());
    } catch {
      // The dashboard keeps the note in place and displays the action error.
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <article className={`exception-card ${exception.severity}`}>
      <header><span><CircleAlert size={19} /></span><div><p className="eyebrow">{exception.kind.replaceAll("_", " ")}</p><h3>{exception.title}</h3></div><time>{formatDate(exception.occurredAt)}</time></header>
      <p>{exception.detail}</p>
      <small>{exception.entityKind.replaceAll("_", " ")} · {shortId(exception.entityId)} · {exception.status.replaceAll("_", " ")}</small>
      {requiresNote && <div className="exception-action"><input value={note} maxLength={exception.kind === "support" ? 500 : 300} onChange={(event) => setNote(event.target.value)} placeholder={exception.kind === "support" ? "Resolution shared with the customer" : "Reason for secure code reset"} /><button className="primary-button" type="button" disabled={busy || submitting || note.trim().length < 5} onClick={() => void submit()}>{exception.kind === "support" ? "Resolve case" : "Reset code"}</button></div>}
      {exception.kind === "refund_review" && <button className="primary-button" type="button" disabled={busy} onClick={onReviewRefund}>Review refund</button>}
      {exception.kind === "stalled_order" && <button className="secondary-button" type="button" disabled={busy} onClick={() => void onReconcile()}><RotateCcw size={17} /> Recover lifecycle</button>}
    </article>
  );
}

function ApprovalSection({ title, count, empty, children }: { title: string; count: number; empty: string; children: ReactNode }) {
  return (
    <section className="admin-section">
      <header><h2>{title}</h2><span>{count}</span></header>
      {count === 0 ? <p className="admin-empty">{empty}</p> : <div className="review-list">{children}</div>}
    </section>
  );
}

function ReviewCard({ icon, title, subtitle, facts, evidence, busy, onEvidence, onReview }: {
  icon: ReactNode;
  title: string;
  subtitle: string;
  facts: string[];
  evidence: Array<{ label: string; path: string }>;
  busy: boolean;
  onEvidence: (path: string) => Promise<void>;
  onReview: (decision: ReviewDecision, reason?: string) => Promise<void>;
}) {
  const [mode, setMode] = useState<ReviewDecision>();
  const [reason, setReason] = useState("");

  const confirm = async () => {
    if (!mode || (mode === "reject" && !reason.trim())) return;
    try {
      await onReview(mode, mode === "reject" ? reason : undefined);
      setMode(undefined);
      setReason("");
    } catch {
      // The dashboard displays the server error and preserves the review form.
    }
  };

  return (
    <article className="review-card">
      <header><span className="review-icon">{icon}</span><div><h3>{title}</h3><p>{subtitle}</p></div></header>
      <div className="review-facts">{facts.map((fact) => <span key={fact}>{fact}</span>)}</div>
      {evidence.map((document) => (
        <button key={document.path} className="evidence-button" type="button" disabled={busy} onClick={() => void onEvidence(document.path)}>
          <FileText size={17} /> {document.label} <ExternalLink size={14} />
        </button>
      ))}
      {!mode ? (
        <div className="review-actions">
          <button className="danger-button" type="button" disabled={busy} onClick={() => setMode("reject")}><X size={17} /> Reject</button>
          <button className="primary-button" type="button" disabled={busy} onClick={() => setMode("approve")}><Check size={17} /> Approve</button>
        </div>
      ) : (
        <div className="review-confirmation">
          <strong>{mode === "approve" ? "Approve this application?" : "Reason for rejection"}</strong>
          {mode === "reject" && <input value={reason} maxLength={500} onChange={(event) => setReason(event.target.value)} placeholder="Required reason" />}
          <div>
            <button className="secondary-button" type="button" disabled={busy} onClick={() => setMode(undefined)}>Cancel</button>
            <button className={mode === "approve" ? "primary-button" : "danger-button"} type="button" disabled={busy || (mode === "reject" && !reason.trim())} onClick={() => void confirm()}>
              {mode === "approve" ? <Check size={17} /> : <X size={17} />} Confirm
            </button>
          </div>
        </div>
      )}
    </article>
  );
}

function OrdersPanel({ orders, available, busy, onReview, onRefund }: {
  orders: AdminOrder[];
  available: boolean;
  busy: boolean;
  onReview: (
    order: AdminOrder,
    outcome: "approve_full" | "approve_items_only" | "deny",
    faultSource: "merchant" | "dastak" | null,
    reason: string,
  ) => Promise<void>;
  onRefund: (order: AdminOrder) => Promise<void>;
}) {
  return (
    <section className="admin-section admin-orders" role="tabpanel">
      <header><h2>Recent orders</h2><span>{orders.length}</span></header>
      {orders.length === 0 ? <p className="admin-empty">{available ? "No historical orders yet." : "Historical order data is not available yet."}</p> : (
        <div className="admin-order-table" role="table" aria-label="Recent orders">
          <div className="admin-order-header" role="row"><span>Order</span><span>Store</span><span>Status</span><span>Payment</span><span>Total</span></div>
          {orders.map((order) => (
            <AdminOrderRow key={order.orderId} order={order} busy={busy} onReview={onReview} onRefund={onRefund} />
          ))}
        </div>
      )}
    </section>
  );
}

function AdminOrderRow({ order, busy, onReview, onRefund }: {
  order: AdminOrder;
  busy: boolean;
  onReview: (
    order: AdminOrder,
    outcome: "approve_full" | "approve_items_only" | "deny",
    faultSource: "merchant" | "dastak" | null,
    reason: string,
  ) => Promise<void>;
  onRefund: (order: AdminOrder) => Promise<void>;
}) {
  const postPickup = order.refundDecision?.eligibility === "delivery_fee_retained_unless_fault" ||
    ["picked_up", "in_transit", "returning_to_merchant"].includes(order.status);
  const [outcome, setOutcome] = useState<"approve_full" | "approve_items_only" | "deny">(
    postPickup ? "approve_items_only" : "approve_full",
  );
  const [faultSource, setFaultSource] = useState<"merchant" | "dastak" | "">("");
  const [reason, setReason] = useState("");
  const needsFault = postPickup && outcome === "approve_full";

  return (
    <article className="admin-order-row" role="row">
      <div data-label="Order"><strong>{shortId(order.orderId)}</strong><small>{formatDate(order.createdAt)} · {order.itemCount} items</small></div>
      <strong data-label="Store">{order.store.name}</strong>
      <span data-label="Status" className={`admin-status status-${order.status}`}>{orderStatusLabel(order.status)}</span>
      <span data-label="Payment">{paymentLabel(order.paymentState)}</span>
      <strong data-label="Total">{formatPrice(order.total.paise)}</strong>

      {order.refundDecision?.decisionStatus === "review_required" && (
        <div className="admin-refund-review">
          <strong>Refund review</strong>
          <small>{order.refundDecision.reason}</small>
          <select value={outcome} onChange={(event) => setOutcome(event.target.value as typeof outcome)} aria-label="Refund decision">
            {postPickup && <option value="approve_items_only">Refund items only</option>}
            <option value="approve_full">Full refund</option>
            <option value="deny">Deny refund</option>
          </select>
          {needsFault && (
            <select value={faultSource} onChange={(event) => setFaultSource(event.target.value as typeof faultSource)} aria-label="Responsible party">
              <option value="">Select responsible party</option>
              <option value="merchant">Merchant fault</option>
              <option value="dastak">Dastak fault</option>
            </select>
          )}
          <input value={reason} maxLength={300} onChange={(event) => setReason(event.target.value)} placeholder="Decision reason" />
          <button
            className="primary-button"
            type="button"
            disabled={busy || !reason.trim() || (needsFault && !faultSource)}
            onClick={() => void onReview(order, outcome, faultSource || null, reason.trim())}
          >
            Submit decision
          </button>
        </div>
      )}

      {order.paymentState === "refund_pending" && order.status !== "returning_to_merchant" && (
        <div className="admin-refund-review">
          <strong>Refund pending</strong>
          <small>Retry safely if the provider call did not finish.</small>
          <button className="primary-button" type="button" disabled={busy} onClick={() => void onRefund(order)}>Process refund</button>
        </div>
      )}
    </article>
  );
}

function shortId(value: string) { return `#${value.slice(0, 8).toUpperCase()}`; }
function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
function formatFeedUpdatedAt(value?: string) {
  return value ? `Last updated ${formatDate(value)}` : "No successful response yet";
}
function methodLabel(value: string) { return value.charAt(0).toUpperCase() + value.slice(1); }
function paymentLabel(value: AdminOrder["paymentState"]) {
  return value.split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}
function feedFailureMessage(feed: AdminBootstrapFeed, error: unknown) {
  const raw = message(error);
  if (/\b(401|unauthorized|authentication|session|jwt)\b/i.test(raw)) {
    return "Your Admin session needs to be refreshed. Reopen the app or sign in again.";
  }
  return ({
    merchantApprovals: "Merchant applications could not be refreshed.",
    deliveryApprovals: "Delivery Partner applications could not be refreshed.",
    legacyHistory: "Read-only historical orders could not be refreshed.",
    operations: "Support, refunds and recovery signals could not be refreshed.",
    adminAccess: "Protected Admin access settings could not be refreshed.",
    commandCenter: "Command center metrics could not be refreshed.",
  } satisfies Record<AdminBootstrapFeed, string>)[feed];
}
function message(error: unknown) { return error instanceof Error ? error.message : "Dastak Admin is unavailable."; }
