import { useEffect, useRef, useState } from "react";
import { getV1ActiveOrders, getV1Order, type DastakV1Auth, type V1Order, type V1ActiveOrderHint } from "./dastakV1";
import type { ReimaginedState } from "./reimaginedState";

type Hint = NonNullable<ReimaginedState["activeOrder"]>;
type Session = DastakV1Auth & { accountId: string };
type Loader = typeof getV1Order;
const terminal = new Set(["DELIVERED", "UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT", "CANCELLED", "DASTAK_FULFILMENT_FAILURE"]);
const labels: Record<string, string> = {
  CREATED: "Order received", MATCHING: "Finding your items", FULLY_SECURED: "Items secured",
  AWAITING_PAYMENT: "Order awaiting confirmation", PAID: "Order confirmed", PREPARING: "Preparing your order",
  PICKUP_IN_PROGRESS: "Picking up your order", OUT_FOR_DELIVERY: "Out for delivery",
  payment_pending: "Order awaiting payment", paid: "Order paid", merchant_accepted: "Preparing your order", ready: "Ready for pickup",
  assigned: "Delivery partner assigned", en_route_to_pickup: "Partner heading to the store", at_store: "Partner at the store",
  picked_up: "Order picked up", in_transit: "Out for delivery", returning_to_merchant: "Order returning to the store",
};
export function activeOrderStorageKey(accountId: string, project: string) {
  return `dastak:reimagined-active-order:v1:${encodeURIComponent(project)}:${encodeURIComponent(accountId)}`;
}
function validHint(value: unknown): value is Hint {
  if (!value || typeof value !== "object") return false;
  const hint = value as Hint;
  return typeof hint.id === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(hint.id)
    && (hint.service === "grocery" || hint.service === "food") && (hint.kind === undefined || hint.kind === "merchant");
}
function readHint(key: string): Hint | undefined {
  try {
    const value = JSON.parse(localStorage.getItem(key) ?? "null") as { version?: number; order?: unknown } | null;
    return value?.version === 1 && validHint(value.order) ? { id: value.order.id, service: value.order.service, ...(value.order.kind ? { kind: value.order.kind } : {}) } : undefined;
  } catch { return undefined; }
}

// A saved ID is only a recovery hint, never evidence of a server status or payment.
export function useReimaginedActiveOrder(session: Session, incoming: ReimaginedState["activeOrder"], online: boolean, loader: Loader = getV1Order, discoveryLoader: typeof getV1ActiveOrders | null = getV1ActiveOrders) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const key = activeOrderStorageKey(accountId, supabaseUrl);
  const owner = JSON.stringify([key, accessToken, publishableKey]);
  const [hint, setHint] = useState<{ key: string; order?: Hint }>(() => ({ key, order: validHint(incoming) ? incoming : readHint(key) }));
  const [visible, setVisible] = useState(() => document.visibilityState !== "hidden");
  const [revision, setRevision] = useState(0);
  const [resource, setResource] = useState<{ context: string; order?: V1Order | V1ActiveOrderHint; hint?: Hint; count?: number; error?: unknown }>();
  const latest = useRef<{ owner: string; order: V1Order | V1ActiveOrderHint } | undefined>(undefined);
  const lastSaved = useRef<{ key: string; order: Hint } | undefined>(undefined);
  const [storageIssue, setStorageIssue] = useState<{ key: string; message: string }>();
  const incomingId = incoming?.id;
  const incomingService = incoming?.service;
  const incomingKind = incoming?.kind;
  useEffect(() => {
    const next = incomingId && incomingService ? { id: incomingId, service: incomingService, ...(incomingKind ? { kind: incomingKind } : {}) } : undefined;
    if (!validHint(next)) { setHint({ key, order: readHint(key) }); return; }
    setHint({ key, order: next });
    try { localStorage.setItem(key, JSON.stringify({ version: 1, order: next })); setStorageIssue(undefined); }
    catch { setStorageIssue({ key, message: "Order tracking could not be saved on this device. Use Orders after refreshing." }); }
  }, [key, incomingId, incomingService, incomingKind]);
  useEffect(() => {
    const visibility = () => setVisible(document.visibilityState !== "hidden");
    const storage = (event: StorageEvent) => { if (event.key === key || event.key === null) setHint({ key, order: readHint(key) }); };
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("storage", storage);
    return () => { document.removeEventListener("visibilitychange", visibility); window.removeEventListener("storage", storage); };
  }, [key]);
  const currentHint = hint.key === key ? hint.order : undefined;
  const id = currentHint?.id;
  const kind = currentHint?.kind;
  const service = currentHint?.service;
  const context = JSON.stringify([owner, id, kind, service]);
  useEffect(() => {
    if ((!id && !discoveryLoader) || !online || !visible) return;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const refresh = async () => {
      let finished = false;
      try {
        const discovered = discoveryLoader ? await discoveryLoader({ accessToken, supabaseUrl, publishableKey, signal: controller.signal }) : undefined;
        if (controller.signal.aborted) return;
        let order: V1Order | V1ActiveOrderHint | undefined = discovered
          ? discovered.orders.find(value => value.id === id && value.kind === (kind ?? "v1")) ?? discovered.orders[0]
          : await loader({ accessToken, supabaseUrl, publishableKey, orderId: id!, signal: controller.signal });
        if (controller.signal.aborted) return;
        if (!discovered && order?.id !== id) throw new Error("Order tracking returned a different order.");
        if (order && latest.current?.owner === owner && latest.current.order.id === order.id && latest.current.order.version > order.version) {
          order = latest.current.order;
        }
        if (order) latest.current = { owner, order };
        const nextHint: Hint | undefined = discovered && order && "kind" in order
          ? { id: order.id, service: order.service, ...(order.kind === "merchant" ? { kind: "merchant" as const } : {}) }
          : id && service ? { id, service, ...(kind ? { kind } : {}) } : undefined;
        const completed = discovered ? discovered.totalCount === 0 : Boolean(order && terminal.has(order.status));
        setResource({ context, order, hint: completed ? undefined : nextHint, count: discovered?.totalCount ?? (completed ? 0 : 1) });
        // Discovery must keep polling even when there is no order yet: another
        // device can place one later. Legacy per-ID mode stops on terminal state.
        finished = !discoveryLoader && completed;
        if (discovered && nextHint) {
          try {
            const stored = readHint(key);
            if ((!stored && !id) || (stored?.id === id && stored?.kind === kind)) {
              localStorage.setItem(key, JSON.stringify({ version: 1, order: nextHint }));
              lastSaved.current = { key, order: nextHint };
              setStorageIssue(undefined);
            }
          } catch { setStorageIssue({ key, message: "Order tracking could not be saved on this device. Use Orders after refreshing." }); }
        }
        if (completed) {
          // Do not erase a newer order saved by another tab while this read was in flight.
          try {
            const stored = readHint(key), saved = lastSaved.current;
            if (stored && ((stored.id === id && stored.kind === kind) || (saved?.key === key && stored.id === saved.order.id && stored.kind === saved.order.kind))) localStorage.removeItem(key);
          }
          catch { setStorageIssue({ key, message: "Completed order tracking could not be cleared on this device." }); }
        }
      } catch (error) { if (!controller.signal.aborted) setResource(previous => ({ ...(previous?.context === context ? previous : {}), context, error })); }
      if (!controller.signal.aborted && !finished) timer = setTimeout(() => { void refresh(); }, 60_000);
    };
    void refresh();
    return () => { controller.abort(); if (timer) clearTimeout(timer); };
  }, [id, kind, service, online, visible, accessToken, supabaseUrl, publishableKey, owner, key, context, revision, loader, discoveryLoader]);
  const current = resource?.context === context ? resource : undefined;
  const order = current?.order;
  return {
    activeOrder: current && current.count === 0 ? undefined : current?.hint ?? currentHint,
    activeCount: current?.count ?? (currentHint ? 1 : 0),
    label: !online ? "Order status unavailable — offline" : current?.error ? "Order status unavailable — open Orders"
      : (current?.count ?? 0) > 1 ? `${current!.count} active orders — view Orders` : order ? labels[order.status] ?? "View order status" : "Checking your order status…",
    error: current?.error,
    storageIssue: storageIssue?.key === key ? storageIssue.message : undefined,
    retry: () => setRevision(value => value + 1),
  };
}
