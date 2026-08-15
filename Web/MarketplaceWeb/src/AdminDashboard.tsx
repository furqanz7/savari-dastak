import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  Bike,
  Check,
  ExternalLink,
  FileText,
  PackageSearch,
  RefreshCw,
  Store,
  UserRound,
  X,
} from "lucide-react";
import { RoleAccountView } from "./RoleAccountView";
import {
  getAdminOrders,
  getEvidenceUrl,
  getMerchantApplications,
  getPartnerApplications,
  reviewOrderRefund,
  reviewMerchantApplication,
  reviewPartnerApplication,
  type AdminOrder,
  type MerchantAdminApplication,
  type PartnerAdminApplication,
  type ReviewDecision,
} from "./admin";
import { formatPrice } from "./catalogue";
import { orderStatusLabel } from "./orders";
import { processOrderRefund } from "./payments";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

export function AdminDashboard({ accessToken, displayName, email, phoneNumber, supabaseUrl, publishableKey, onSignOut }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [merchants, setMerchants] = useState<MerchantAdminApplication[]>([]);
  const [partners, setPartners] = useState<PartnerAdminApplication[]>([]);
  const [orders, setOrders] = useState<AdminOrder[]>([]);
  const [tab, setTab] = useState<"approvals" | "orders" | "account">("approvals");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const reviewKeys = useRef(new Map<string, string>());

  const refresh = useCallback(async (showProgress = false) => {
    if (showProgress) setBusy("refresh");
    try {
      const [merchantApplications, partnerApplications, recentOrders] = await Promise.all([
        getMerchantApplications(auth),
        getPartnerApplications(auth),
        getAdminOrders({ ...auth, limit: 50 }),
      ]);
      setMerchants(merchantApplications.filter((application) => application.status === "pending"));
      setPartners(partnerApplications.filter((application) => application.status === "pending"));
      setOrders(recentOrders);
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      setLoading(false);
      if (showProgress) setBusy(undefined);
    }
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);

  const review = async (kind: "merchant" | "partner", applicationId: string, decision: ReviewDecision, reason?: string) => {
    const identity = `${kind}:${applicationId}:${decision}:${reason ?? ""}`;
    const idempotencyKey = reviewKeys.current.get(identity) ?? crypto.randomUUID();
    reviewKeys.current.set(identity, idempotencyKey);
    setBusy(identity);
    setError(undefined);
    try {
      const input = { ...auth, applicationId, decision, reason, idempotencyKey };
      if (kind === "merchant") await reviewMerchantApplication(input);
      else await reviewPartnerApplication(input);
      reviewKeys.current.delete(identity);
      await refresh();
    } catch (reviewError) {
      setError(message(reviewError));
      throw reviewError;
    } finally {
      setBusy(undefined);
    }
  };

  const openEvidence = async (objectPath: string) => {
    setBusy(`evidence:${objectPath}`);
    setError(undefined);
    try {
      const signedUrl = await getEvidenceUrl({ ...auth, objectPath });
      window.location.assign(signedUrl);
    } catch (evidenceError) {
      setError(message(evidenceError));
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
    setError(undefined);
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
      setError(message(reviewError));
    } finally {
      setBusy(undefined);
    }
  };

  const retryRefund = async (order: AdminOrder) => {
    setBusy(`process-refund:${order.orderId}`);
    setError(undefined);
    try {
      await processOrderRefund({ ...auth, orderId: order.orderId, idempotencyKey: crypto.randomUUID() });
      await refresh();
    } catch (refundError) {
      setError(message(refundError));
    } finally {
      setBusy(undefined);
    }
  };

  const activeOrders = orders.filter((order) => !["delivered", "cancelled"].includes(order.status)).length;

  return (
    <div className="admin-shell">
      <header className="admin-heading">
        <div>
          <p className="eyebrow">{displayName ? `Owner: ${displayName}` : "Owner workspace"}</p>
          <h1>Dastak operations</h1>
          <p>Approvals and recent marketplace activity.</p>
        </div>
        <button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={Boolean(busy)} aria-label="Refresh admin data" title="Refresh admin data">
          <RefreshCw size={19} />
        </button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}

      <section className="admin-summary" aria-label="Operations summary">
        <Summary label="Merchant reviews" value={merchants.length} icon={<Store size={19} />} />
        <Summary label="Partner reviews" value={partners.length} icon={<Bike size={19} />} />
        <Summary label="Active orders" value={activeOrders} icon={<PackageSearch size={19} />} />
      </section>

      <div className="admin-tabs" role="tablist" aria-label="Admin views">
        <button type="button" role="tab" aria-selected={tab === "approvals"} className={tab === "approvals" ? "selected" : ""} onClick={() => setTab("approvals")}>Approvals</button>
        <button type="button" role="tab" aria-selected={tab === "orders"} className={tab === "orders" ? "selected" : ""} onClick={() => setTab("orders")}>Orders</button>
        <button type="button" role="tab" aria-selected={tab === "account"} className={tab === "account" ? "selected" : ""} onClick={() => setTab("account")}><UserRound size={17} /> Account</button>
      </div>

      {tab === "account" ? <RoleAccountView
        accessToken={accessToken}
        displayName={displayName}
        email={email}
        phoneNumber={phoneNumber}
        roleName="Owner"
        accessLabel="Full access"
        supabaseUrl={supabaseUrl}
        publishableKey={publishableKey}
        allowsAccountDeletion={false}
        onSignOut={onSignOut}
      /> : loading ? <div className="catalogue-loading" role="status"><span /> Loading operations</div> : tab === "approvals" ? (
        <div className="admin-approvals" role="tabpanel">
          <ApprovalSection title="Merchant applications" count={merchants.length} empty="No merchant applications waiting.">
            {merchants.map((application) => (
              <ReviewCard
                key={application.applicationId}
                icon={<Store size={20} />}
                title={application.businessName}
                subtitle={application.businessAddress}
                facts={[`Account ${shortId(application.accountId)}`]}
                evidence={[{ label: "View business evidence", path: application.evidenceObjectPath }]}
                busy={Boolean(busy)}
                onEvidence={openEvidence}
                onReview={(decision, reason) => review("merchant", application.applicationId, decision, reason)}
              />
            ))}
          </ApprovalSection>

          <ApprovalSection title="Delivery-partner applications" count={partners.length} empty="No delivery-partner applications waiting.">
            {partners.map((application) => (
              <ReviewCard
                key={application.applicationId}
                icon={<Bike size={20} />}
                title={application.displayName}
                subtitle={application.phoneNumber}
                facts={[
                  methodLabel(application.deliveryMethod),
                  ...(application.vehicleRegistrationNumber
                    ? [`${application.vehicleRegistrationNumber} · ${application.vehicleMakeModel}`]
                    : []),
                  `Submitted ${formatDate(application.submittedAt)}`,
                ]}
                evidence={[
                  { label: "View identity proof", path: application.identityEvidenceObjectPath },
                  ...(application.vehicleEvidenceObjectPath
                    ? [{ label: "View vehicle RC", path: application.vehicleEvidenceObjectPath }]
                    : []),
                ]}
                busy={Boolean(busy)}
                onEvidence={openEvidence}
                onReview={(decision, reason) => review("partner", application.applicationId, decision, reason)}
              />
            ))}
          </ApprovalSection>
        </div>
      ) : (
        <OrdersPanel
          orders={orders}
          busy={Boolean(busy)}
          onReview={reviewRefund}
          onRefund={retryRefund}
        />
      )}
    </div>
  );
}

function Summary({ label, value, icon }: { label: string; value: number; icon: ReactNode }) {
  return <div><span>{icon}</span><p><small>{label}</small><strong>{value}</strong></p></div>;
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

function OrdersPanel({ orders, busy, onReview, onRefund }: {
  orders: AdminOrder[];
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
      {orders.length === 0 ? <p className="admin-empty">No orders yet.</p> : (
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
      <div><strong>{shortId(order.orderId)}</strong><small>{formatDate(order.createdAt)} · {order.itemCount} items</small></div>
      <strong>{order.store.name}</strong>
      <span className={`admin-status status-${order.status}`}>{orderStatusLabel(order.status)}</span>
      <span>{paymentLabel(order.paymentState)}</span>
      <strong>{formatPrice(order.total.paise)}</strong>

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
function methodLabel(value: string) { return value.charAt(0).toUpperCase() + value.slice(1); }
function paymentLabel(value: AdminOrder["paymentState"]) {
  return value.split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}
function message(error: unknown) { return error instanceof Error ? error.message : "Dastak Admin is unavailable."; }
