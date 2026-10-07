import { useEffect, useRef, useState, type Dispatch } from "react";
import { formatV1Price } from "./dastakV1";
import { customerDataIssue } from "./customerDataState";
import { canConfirmGroceryOrder } from "./reimaginedCheckout";
import { prepareFoodCheckout } from "./reimaginedFoodCheckoutPreparation";
import type { ReimaginedFoodRecovery } from "./reimaginedFoodRecovery";
import type { ReimaginedAction } from "./reimaginedState";

export function ReimaginedFoodCounter({ checkout, input, enabled = false, dispatch, onSessionExpired, ordersUrl }: {
  checkout: ReimaginedFoodRecovery; input: Parameters<typeof prepareFoodCheckout>[0]; enabled?: boolean;
  dispatch: Dispatch<ReimaginedAction>; onSessionExpired: () => void; ordersUrl: string;
}) {
  const [order, setOrder] = useState(checkout.order);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [now, setNow] = useState(Date.now);
  const session = useRef(0);
  useEffect(() => () => { session.current++; checkout.cancelRequests(); }, [checkout]);
  useEffect(() => {
    if (!enabled || !input.online || !input.canEdit) checkout.cancelRequests();
  }, [checkout, enabled, input.online, input.canEdit]);
  useEffect(() => {
    if (!enabled || !order?.launchPayment?.reservationExpiresAt) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [enabled, order?.launchPayment?.reservationExpiresAt]);
  const blocked = !enabled || !input.online || !input.canEdit || busy;
  async function run(operation: "reserve" | "refresh" | "confirm" | "restart") {
    if (blocked || checkout.busy) return;
    const epoch = session.current;
    const acknowledge = (action: ReimaginedAction) => {
      if (epoch !== session.current) throw new DOMException("Checkout session changed", "AbortError");
      dispatch(action);
    };
    setBusy(true); setError(undefined);
    try {
      if (operation === "reserve") await checkout.reserve(input);
      else if (operation === "refresh") await checkout.refresh();
      else if (operation === "restart") await checkout.restartAfterTerminalReservation();
      else await checkout.confirm(acknowledge);
      // A read can reconcile a lost commitment, but never initiates a new commitment.
      if (operation !== "confirm" && checkout.committed) await checkout.confirm(acknowledge);
    } catch (issue) {
      if (epoch !== session.current || (issue instanceof Error && issue.name === "AbortError")) return;
      if (customerDataIssue(issue).action === "sign_in") onSessionExpired();
      else setError(issue instanceof Error ? issue.message : "Food checkout could not complete. Your cart is retained.");
    } finally {
      if (epoch === session.current) { setOrder(checkout.order); setNow(Date.now()); setBusy(false); }
    }
  }
  return <section aria-label="Food checkout confirmation">
    {!enabled ? <><p>Food order submission remains disabled pending authenticated verification.</p><button type="button" disabled>Food checkout integration pending</button></>
      : checkout.recoveryIssue ? <p role="alert">{checkout.recoveryIssue}</p>
      : !order && checkout.recoverableOrderId ? <button type="button" disabled={blocked} onClick={() => void run("refresh")}>Recover Food reservation</button>
      : !order ? <><p>{checkout.hasPendingAttempt ? "Retry the exact original Food selections, recipient and address using the saved request key." : "Reserve Food to obtain the server-calculated total. Grocery items are not included."}</p><button type="button" disabled={blocked || !prepareFoodCheckout(input).submission} onClick={() => void run("reserve")}>Reserve Food order</button></>
      : <><h3>{order.displayOrderNumber}</h3><p>Server order total: {formatV1Price(order.price.totalPaise)}</p><p>{order.status}</p>
        <button type="button" disabled={blocked} onClick={() => void run("refresh")}>Refresh Food order status</button>
        <button type="button" disabled={blocked || (!checkout.committed && !canConfirmGroceryOrder(order, now))} onClick={() => void run("confirm")}>{checkout.committed ? "Recover confirmed Food cart" : "Confirm Food order"}</button>
        {["PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT"].includes(order.status) ? <button type="button" disabled={blocked} onClick={() => void run("restart")}>Recheck closed Food reservation</button> : null}</>}
    <a href={ordersUrl}>Review Food reservations in Orders</a>
    {error ? <p role="alert">{error}</p> : null}
  </section>;
}
