import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  BookOpen,
  Check,
  ClipboardList,
  LogOut,
  PackageCheck,
  ReceiptText,
  RefreshCw,
  Store,
  UserRound,
  X,
} from "lucide-react";
import { formatPrice } from "./catalogue";
import { MerchantCatalogueView } from "./MerchantCatalogueView";
import {
  acceptMerchantOrder,
  confirmMerchantCancellationReturn,
  formatDeliveryDistance,
  getMerchantOrders,
  markMerchantOrderReady,
  orderStatusLabel,
  rejectMerchantOrder,
  type MerchantOrderSnapshot,
} from "./orders";
import { processOrderRefund } from "./payments";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

type MerchantAction = "accept" | "ready" | "reject" | "confirmReturn" | "refund";
type MerchantSection = "orders" | "catalogue" | "store" | "account";

export function MerchantOrdersView({
  accessToken,
  accountId,
  client,
  displayName,
  email,
  phoneNumber,
  supabaseUrl,
  publishableKey,
  onSignOut,
}: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [orders, setOrders] = useState<MerchantOrderSnapshot[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busyOrderId, setBusyOrderId] = useState<string>();
  const [error, setError] = useState<string>();
  const [rejectingOrderId, setRejectingOrderId] = useState<string>();
  const [rejectionReason, setRejectionReason] = useState("");
  const [section, setSection] = useState<MerchantSection>("orders");
  const refreshInFlight = useRef(false);
  const mutationKeys = useRef(new Map<string, string>());

  const refreshOrders = useCallback(async (showProgress = false) => {
    if (refreshInFlight.current) return;
    refreshInFlight.current = true;
    if (showProgress) setRefreshing(true);
    try {
      const snapshot = await getMerchantOrders(auth);
      setOrders(snapshot.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt)));
      setError(undefined);
    } catch (refreshError) {
      setError(orderMessage(refreshError));
    } finally {
      refreshInFlight.current = false;
      setLoading(false);
      setRefreshing(false);
    }
  }, [auth]);

  useEffect(() => {
    void refreshOrders();
    const interval = window.setInterval(() => void refreshOrders(), 5_000);
    return () => window.clearInterval(interval);
  }, [refreshOrders]);

  const updateOrder = (updated: MerchantOrderSnapshot) => {
    setOrders((current) => current.map((order) => order.orderId === updated.orderId ? updated : order));
  };

  const runAction = async (order: MerchantOrderSnapshot, action: MerchantAction, reason?: string) => {
    const normalizedReason = reason?.trim();
    const requestIdentity = `${action}:${order.orderId}:${order.stateVersion}:${normalizedReason ?? ""}`;
    const idempotencyKey = mutationKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    mutationKeys.current.set(requestIdentity, idempotencyKey);
    setBusyOrderId(order.orderId);
    setError(undefined);
    try {
      if (action === "refund") {
        await processOrderRefund({ ...auth, orderId: order.orderId, idempotencyKey });
        mutationKeys.current.delete(requestIdentity);
        await refreshOrders();
        return;
      }
      const updated = action === "accept"
        ? await acceptMerchantOrder({ ...auth, orderId: order.orderId, idempotencyKey })
        : action === "ready"
          ? await markMerchantOrderReady({ ...auth, orderId: order.orderId, idempotencyKey })
          : action === "confirmReturn"
            ? await confirmMerchantCancellationReturn({
              ...auth,
              orderId: order.orderId,
              reason: normalizedReason ?? "Returned items received by merchant",
              idempotencyKey,
            })
            : await rejectMerchantOrder({
              ...auth,
              orderId: order.orderId,
              reason: normalizedReason ?? "",
              idempotencyKey,
            });
      mutationKeys.current.delete(requestIdentity);
      updateOrder(updated);
      if (action === "reject" || action === "confirmReturn") {
        setRejectingOrderId(undefined);
        setRejectionReason("");
        if (updated.paymentState === "refund_pending") {
          await processOrderRefund({
            ...auth,
            orderId: updated.orderId,
            idempotencyKey: crypto.randomUUID(),
          });
          await refreshOrders();
        }
      }
    } catch (actionError) {
      setError(orderMessage(actionError));
    } finally {
      setBusyOrderId(undefined);
    }
  };

  const activeOrders = orders.filter((order) => !isFinalOrder(order));
  const recentOrders = orders.filter(isFinalOrder).slice(0, 10);
  const awaitingDecision = activeOrders.filter((order) => order.status === "paid").length;
  const preparing = activeOrders.filter((order) => order.status === "merchant_accepted").length;
  const readyForPickup = activeOrders.filter((order) => order.status === "ready").length;

  return (
    <div className="merchant-workspace">
      <nav className="workspace-tabs merchant-tabs" aria-label="Merchant workspace" role="tablist">
        <MerchantTab selected={section === "orders"} onSelect={() => setSection("orders")} icon={<ClipboardList size={18} />} label="Orders" />
        <MerchantTab selected={section === "catalogue"} onSelect={() => setSection("catalogue")} icon={<BookOpen size={18} />} label="Catalogue" />
        <MerchantTab selected={section === "store"} onSelect={() => setSection("store")} icon={<Store size={18} />} label="Store" />
        <MerchantTab selected={section === "account"} onSelect={() => setSection("account")} icon={<UserRound size={18} />} label="Account" />
      </nav>
      {section === "catalogue" || section === "store" ? (
        <MerchantCatalogueView
          accessToken={accessToken}
          accountId={accountId}
          client={client}
          supabaseUrl={supabaseUrl}
          publishableKey={publishableKey}
          mode={section}
          onOpenStore={() => setSection("store")}
        />
      ) : section === "account" ? (
        <MerchantAccount
          displayName={displayName}
          email={email}
          phoneNumber={phoneNumber}
          onManageStore={() => setSection("store")}
          onSignOut={onSignOut}
        />
      ) : (
      <div className="merchant-orders-shell">
      <header className="merchant-orders-heading">
        <div>
          <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak merchant"}</p>
          <h1>Orders</h1>
          <p>Current fulfilment queue.</p>
        </div>
        <button className="icon-button" type="button" onClick={() => void refreshOrders(true)} disabled={refreshing} aria-label="Refresh orders" title="Refresh orders">
          <RefreshCw size={19} />
        </button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {loading ? (
        <div className="catalogue-loading" role="status"><span /> Loading orders</div>
      ) : (
        <>
          <div className="merchant-summary" aria-label="Order summary">
            <MerchantSummary label="Needs action" value={awaitingDecision} />
            <MerchantSummary label="Preparing" value={preparing} />
            <MerchantSummary label="Ready" value={readyForPickup} />
          </div>
          <MerchantOrderSection
            title="Active orders"
            orders={activeOrders}
            empty="No paid orders waiting."
            busyOrderId={busyOrderId}
            rejectingOrderId={rejectingOrderId}
            rejectionReason={rejectionReason}
            onRejectionReason={setRejectionReason}
            onStartReject={(orderId) => { setRejectingOrderId(orderId); setRejectionReason(""); }}
            onCancelReject={() => { setRejectingOrderId(undefined); setRejectionReason(""); }}
            onAction={runAction}
          />
          {recentOrders.length > 0 && (
            <MerchantOrderSection
              title="Recent orders"
              orders={recentOrders}
              empty=""
              busyOrderId={busyOrderId}
              rejectionReason=""
              onRejectionReason={() => undefined}
              onStartReject={() => undefined}
              onCancelReject={() => undefined}
              onAction={runAction}
            />
          )}
        </>
      )}
      </div>
      )}
    </div>
  );
}

function MerchantTab({
  selected,
  onSelect,
  icon,
  label,
}: {
  selected: boolean;
  onSelect: () => void;
  icon: ReactNode;
  label: string;
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={selected}
      className={selected ? "selected" : ""}
      onClick={onSelect}
    >
      {icon}
      <span>{label}</span>
    </button>
  );
}

function MerchantSummary({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <small>{label}</small>
      <strong>{value}</strong>
    </div>
  );
}

function MerchantAccount({
  displayName,
  email,
  phoneNumber,
  onManageStore,
  onSignOut,
}: {
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  onManageStore: () => void;
  onSignOut: () => void;
}) {
  return (
    <section className="merchant-account">
      <header className="merchant-orders-heading">
        <div>
          <p className="eyebrow">Dastak Merchant</p>
          <h1>Account</h1>
          <p>Your merchant identity and workspace access.</p>
        </div>
      </header>
      <div className="merchant-profile">
        <span><UserRound size={22} /></span>
        <div>
          <strong>{displayName || "Merchant account"}</strong>
          <small>Approved merchant</small>
        </div>
      </div>
      <dl className="merchant-account-list">
        {email && <div><dt>Email</dt><dd>{email}</dd></div>}
        {phoneNumber && <div><dt>Phone</dt><dd>{phoneNumber}</dd></div>}
        <div><dt>Access</dt><dd>Active</dd></div>
      </dl>
      <div className="merchant-account-actions">
        <button className="secondary-button" type="button" onClick={onManageStore}>
          <Store size={18} /> Manage store
        </button>
        <button className="danger-button" type="button" onClick={onSignOut}>
          <LogOut size={18} /> Sign out
        </button>
      </div>
    </section>
  );
}

function MerchantOrderSection({
  title,
  orders,
  empty,
  busyOrderId,
  rejectingOrderId,
  rejectionReason,
  onRejectionReason,
  onStartReject,
  onCancelReject,
  onAction,
}: {
  title: string;
  orders: MerchantOrderSnapshot[];
  empty: string;
  busyOrderId?: string;
  rejectingOrderId?: string;
  rejectionReason: string;
  onRejectionReason: (reason: string) => void;
  onStartReject: (orderId: string) => void;
  onCancelReject: () => void;
  onAction: (order: MerchantOrderSnapshot, action: MerchantAction, reason?: string) => Promise<void>;
}) {
  return (
    <section className="merchant-order-section" aria-label={title}>
      <header><h2>{title}</h2><span>{orders.length}</span></header>
      {orders.length === 0 ? <p className="merchant-orders-empty">{empty}</p> : (
        <div className="merchant-order-list" aria-live="polite">
          {orders.map((order) => (
            <MerchantOrderCard
              key={order.orderId}
              order={order}
              busy={busyOrderId === order.orderId}
              rejecting={rejectingOrderId === order.orderId}
              rejectionReason={rejectionReason}
              onRejectionReason={onRejectionReason}
              onStartReject={() => onStartReject(order.orderId)}
              onCancelReject={onCancelReject}
              onAction={onAction}
            />
          ))}
        </div>
      )}
    </section>
  );
}

function MerchantOrderCard({
  order,
  busy,
  rejecting,
  rejectionReason,
  onRejectionReason,
  onStartReject,
  onCancelReject,
  onAction,
}: {
  order: MerchantOrderSnapshot;
  busy: boolean;
  rejecting: boolean;
  rejectionReason: string;
  onRejectionReason: (reason: string) => void;
  onStartReject: () => void;
  onCancelReject: () => void;
  onAction: (order: MerchantOrderSnapshot, action: MerchantAction, reason?: string) => Promise<void>;
}) {
  const canReject = ["paid", "merchant_accepted", "ready"].includes(order.status);
  return (
    <article className="merchant-order-card">
      <header>
        <span className="order-icon"><ReceiptText size={20} /></span>
        <div>
          <strong>Order {order.orderId.slice(-6).toUpperCase()}</strong>
          <small>{formatOrderTime(order.createdAt)}</small>
        </div>
        <span className={`merchant-status status-${order.status}`}>{orderStatusLabel(order.status)}</span>
      </header>

      <ul className="merchant-order-lines">
        {order.lines.map((line) => (
          <li key={line.productId}>
            <span><b>{line.quantity}</b> {line.name}<small>{line.unitLabel}</small></span>
            <strong>{formatPrice(line.lineSubtotal.paise)}</strong>
          </li>
        ))}
      </ul>

      <dl className="merchant-order-totals">
        <div><dt>Items</dt><dd>{formatPrice(order.itemSubtotal.paise)}</dd></div>
        <div><dt>Delivery · {formatDeliveryDistance(order.deliveryDistanceMeters)}</dt><dd>{formatPrice(order.deliveryFee.paise)}</dd></div>
        <div><dt>Total paid</dt><dd>{formatPrice(order.total.paise)}</dd></div>
      </dl>

      {order.handoffCode?.purpose === "pickup" && (
        <div className="merchant-pickup-code"><PackageCheck size={19} /><span>Pickup code <b>{order.handoffCode.code}</b></span></div>
      )}

      {order.status === "returning_to_merchant" && (
        <p className="merchant-return-note">Customer cancellation approved. Confirm only after the delivery partner returns the items.</p>
      )}

      {!rejecting && (order.status === "paid" || order.status === "merchant_accepted" || canReject) && (
        <div className="merchant-order-actions">
          {order.status === "paid" && (
            <button className="primary-button" type="button" disabled={busy} onClick={() => void onAction(order, "accept")}>
              <Check size={18} /> Accept order
            </button>
          )}
          {order.status === "merchant_accepted" && (
            <button className="primary-button" type="button" disabled={busy} onClick={() => void onAction(order, "ready")}>
              <PackageCheck size={18} /> Mark ready
            </button>
          )}
          {canReject && (
            <button className="danger-button" type="button" disabled={busy} onClick={onStartReject}>
              <X size={17} /> Reject
            </button>
          )}
        </div>
      )}

      {order.status === "returning_to_merchant" && (
        <div className="merchant-order-actions">
          <button className="primary-button" type="button" disabled={busy} onClick={() => void onAction(order, "confirmReturn")}>
            <PackageCheck size={18} /> Confirm items returned
          </button>
        </div>
      )}

      {order.status === "cancelled" && order.paymentState === "refund_pending" && (
        <div className="merchant-order-actions">
          <button className="primary-button" type="button" disabled={busy} onClick={() => void onAction(order, "refund")}>
            <ReceiptText size={18} /> Process refund
          </button>
        </div>
      )}

      {rejecting && (
        <div className="merchant-reject-form">
          <label htmlFor={`reject-${order.orderId}`}>Reason for rejection</label>
          <input
            id={`reject-${order.orderId}`}
            value={rejectionReason}
            maxLength={300}
            autoFocus
            onChange={(event) => onRejectionReason(event.target.value)}
            placeholder="For example, item unavailable"
          />
          <div>
            <button className="secondary-button" type="button" disabled={busy} onClick={onCancelReject}>Keep order</button>
            <button className="danger-button" type="button" disabled={busy || !rejectionReason.trim()} onClick={() => void onAction(order, "reject", rejectionReason)}>Confirm rejection</button>
          </div>
        </div>
      )}
    </article>
  );
}

function isFinalOrder(order: MerchantOrderSnapshot) {
  return order.status === "cancelled" || order.status === "delivered";
}

function formatOrderTime(value: string) {
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function orderMessage(error: unknown) {
  return error instanceof Error ? error.message : "The merchant order service is unavailable right now.";
}
