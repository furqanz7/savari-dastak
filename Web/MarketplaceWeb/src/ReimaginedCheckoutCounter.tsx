import { useEffect, useRef, useState } from "react";
import type { Dispatch } from "react";
import { formatV1Price, type V1Order } from "./dastakV1";
import { customerDataIssue } from "./customerDataState";
import { canConfirmGroceryOrder, type GroceryCheckoutDraft, type ReimaginedGroceryCheckout } from "./reimaginedCheckout";
import type { ReimaginedAction } from "./reimaginedState";

export function GroceryPaymentNotice() {
  return <div className="reimagined-checkout-payment"><strong>UPI / Cash on Delivery</strong><p>Pay via UPI/Cash on Delivery — pay your delivery partner at the doorstep. No charge now.</p></div>;
}

// Writes require explicit activation, an online session and exclusive cart ownership.
export function ReimaginedCheckoutCounter({ checkout, draft, enabled = false, canEdit = true, online, dispatch, onSessionExpired, ordersUrl, onOpenOrders }: {
  checkout: ReimaginedGroceryCheckout; draft?: GroceryCheckoutDraft; enabled?: boolean; canEdit?: boolean; online: boolean;
  dispatch: Dispatch<ReimaginedAction>; onSessionExpired: () => void; ordersUrl: string;
  onOpenOrders?: (id?: string) => void;
}) {
  const [order, setOrder] = useState<V1Order>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [now, setNow] = useState(() => Date.now());
  const session = useRef(0);
  const blocked = !enabled || !online || !canEdit || busy;
  useEffect(() => () => { session.current++; checkout.cancelRequests(); }, [checkout]);
  useEffect(() => {
    if (!enabled || !online || !canEdit) checkout.cancelRequests();
  }, [checkout, enabled, online, canEdit]);
  useEffect(() => {
    if (!order?.launchPayment?.reservationExpiresAt) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [order?.launchPayment?.reservationExpiresAt]);
  async function run(operation: "reserve" | "confirm" | "refresh" | "restart") {
    if (!enabled || !online || !canEdit || busy || checkout.busy) return;
    const epoch = session.current;
    const acknowledge = (action: ReimaginedAction) => {
      if (epoch !== session.current) throw new DOMException("Checkout session changed", "AbortError");
      dispatch(action);
    };
    setBusy(true); setError(undefined);
    try {
      if (operation === "reserve" && draft) setOrder(await checkout.reserve(draft));
      else if (operation === "refresh") setOrder(await checkout.refresh());
      else if (operation === "restart") { await checkout.restartAfterTerminalReservation(); setOrder(undefined); }
      else if (operation === "confirm") {
        await checkout.confirm(acknowledge);
        setOrder(checkout.order);
      }
      // Reconcile a lost confirmation response using the authoritative refreshed order.
      if (operation !== "confirm" && checkout.committed) {
        await checkout.confirm(acknowledge);
      }
    } catch (issue) {
      if (epoch !== session.current || (issue instanceof Error && issue.name === "AbortError")) return;
      if (customerDataIssue(issue).action === "sign_in") onSessionExpired();
      else setError(issue instanceof Error ? issue.message : "Checkout could not complete. Your Bucket is retained.");
    } finally {
      if (epoch === session.current) { setOrder(checkout.order); setNow(Date.now()); setBusy(false); }
    }
  }
  return <section className="reimagined-checkout-confirmation" aria-label="Grocery checkout confirmation">
    <h3>Payment & confirmation</h3>
    <GroceryPaymentNotice />
    {!enabled ? <><p>Order submission remains disabled until recovery and authenticated end-to-end verification are complete.</p><button type="button" disabled>Checkout integration pending</button></>
      : checkout.recoveryIssue ? <p role="alert">{checkout.recoveryIssue}</p>
      : !order && checkout.recoverableOrderId ? <><p>A saved Grocery reservation needs a server status check. No new order will be created.</p><button type="button" disabled={blocked} onClick={() => void run("refresh")}>Recover Grocery reservation</button></>
      : !order ? <><p>{checkout.hasPendingAttempt ? "An earlier attempt is unresolved. Retry the same Bucket, recipient and address using its saved request key." : "Reserve this Grocery Bucket to obtain the server-calculated total. Food items are not included."}</p><button type="button" disabled={!draft || blocked} onClick={() => void run("reserve")}>{busy ? "Reserving Grocery order…" : "Reserve Grocery order"}</button></>
      : <><h4>{order.displayOrderNumber}</h4><ServerOrderDelivery order={order} /><dl className="reimagined-server-bill" aria-label="Server-confirmed Grocery bill">
        {([
          ["Items", order.price.subtotalPaise], ["Delivery", order.price.deliveryFeePaise], ["Platform fee", order.price.platformFeePaise], ["Tax", order.price.taxPaise],
        ] as const).filter(([, value]) => Number.isSafeInteger(value) && value >= 0).map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{formatV1Price(value)}</dd></div>)}
        {Number.isSafeInteger(order.price.discountPaise) && order.price.discountPaise > 0 ? <div><dt>Discount</dt><dd>−{formatV1Price(order.price.discountPaise)}</dd></div> : null}
        <div className="reimagined-server-total"><dt>Server order total: </dt><dd>{formatV1Price(order.price.totalPaise)}</dd></div>
      </dl><p className="reimagined-checkout-status">Status: {order.status.replaceAll("_", " ").toLowerCase()}</p>
        <button type="button" disabled={blocked} onClick={() => void run("refresh")}>Refresh order status</button>
        <button type="button" disabled={blocked || !canConfirmGroceryOrder(order, now)} onClick={() => void run("confirm")}>Confirm Grocery order</button>
        {["PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT"].includes(order.status) ? <><p>This unpaid reservation is closed. Your Bucket is retained.</p><button type="button" disabled={blocked} onClick={() => void run("restart")}>Recheck closed reservation and return to Bucket</button></> : null}
        {onOpenOrders ? <button type="button" onClick={() => onOpenOrders(order.id)}>Open Orders to review or manage this reservation</button> : <a href={ordersUrl}>Open Orders to review or manage this reservation</a>}</>}
    {error ? <p role="alert">{error}</p> : null}
  </section>;
}

export function ServerOrderDelivery({ order }: { order: V1Order }) {
  return <section aria-label="Reserved order delivery details"><h4>This reservation</h4>
    {order.recipient ? <p>{order.recipient.name} · {order.recipient.phoneNumber}</p> : null}
    {order.deliveryAddress ? <p>{[order.deliveryAddress.label, order.deliveryAddress.line1, order.deliveryAddress.line2].filter(Boolean).join(" · ")}</p> : null}
    <p>The reservation keeps the recipient and address submitted with it. Later profile or address edits do not rewrite this order. Review it in Orders before confirming.</p>
  </section>;
}
