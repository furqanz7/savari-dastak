import { useEffect, useRef, useState } from "react";
import { getV1Order, type DastakV1Auth, type V1Order } from "./dastakV1";
import type { ReimaginedState } from "./reimaginedState";

type Hint = NonNullable<ReimaginedState["activeOrder"]>;
type Session = DastakV1Auth & { accountId: string };
type Loader = typeof getV1Order;
const terminal = new Set(["DELIVERED", "UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT", "CANCELLED", "DASTAK_FULFILMENT_FAILURE"]);
const labels: Record<string, string> = {
  CREATED: "Order received", MATCHING: "Finding your items", FULLY_SECURED: "Items secured",
  AWAITING_PAYMENT: "Order awaiting confirmation", PAID: "Order confirmed", PREPARING: "Preparing your order",
  PICKUP_IN_PROGRESS: "Picking up your order", OUT_FOR_DELIVERY: "Out for delivery",
};
export function activeOrderStorageKey(accountId: string, project: string) {
  return `dastak:reimagined-active-order:v1:${encodeURIComponent(project)}:${encodeURIComponent(accountId)}`;
}
function validHint(value: unknown): value is Hint {
  if (!value || typeof value !== "object") return false;
  const hint = value as Hint;
  return typeof hint.id === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(hint.id)
    && (hint.service === "grocery" || hint.service === "food");
}
function readHint(key: string): Hint | undefined {
  try {
    const value = JSON.parse(localStorage.getItem(key) ?? "null") as { version?: number; order?: unknown } | null;
    return value?.version === 1 && validHint(value.order) ? { id: value.order.id, service: value.order.service } : undefined;
  } catch { return undefined; }
}

// A saved ID is only a recovery hint, never evidence of a server status or payment.
export function useReimaginedActiveOrder(session: Session, incoming: ReimaginedState["activeOrder"], online: boolean, loader: Loader = getV1Order) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const key = activeOrderStorageKey(accountId, supabaseUrl);
  const owner = JSON.stringify([key, accessToken, publishableKey]);
  const [hint, setHint] = useState<{ key: string; order?: Hint }>(() => ({ key, order: readHint(key) }));
  const [visible, setVisible] = useState(() => document.visibilityState !== "hidden");
  const [revision, setRevision] = useState(0);
  const [resource, setResource] = useState<{ owner: string; id: string; order?: V1Order; error?: unknown }>();
  const latest = useRef<{ owner: string; order: V1Order } | undefined>(undefined);
  const [storageIssue, setStorageIssue] = useState<{ key: string; message: string }>();
  const incomingId = incoming?.id;
  const incomingService = incoming?.service;
  useEffect(() => {
    const next = incomingId && incomingService ? { id: incomingId, service: incomingService } : undefined;
    if (!validHint(next)) { setHint({ key, order: readHint(key) }); return; }
    setHint({ key, order: next });
    try { localStorage.setItem(key, JSON.stringify({ version: 1, order: next })); setStorageIssue(undefined); }
    catch { setStorageIssue({ key, message: "Order tracking could not be saved on this device. Use Orders after refreshing." }); }
  }, [key, incomingId, incomingService]);
  useEffect(() => {
    const visibility = () => setVisible(document.visibilityState !== "hidden");
    const storage = (event: StorageEvent) => { if (event.key === key || event.key === null) setHint({ key, order: readHint(key) }); };
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("storage", storage);
    return () => { document.removeEventListener("visibilitychange", visibility); window.removeEventListener("storage", storage); };
  }, [key]);
  const currentHint = hint.key === key ? hint.order : undefined;
  const id = currentHint?.id;
  useEffect(() => {
    if (!id || !online || !visible) return;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const refresh = async () => {
      let finished = false;
      try {
        let order = await loader({ accessToken, supabaseUrl, publishableKey, orderId: id, signal: controller.signal });
        if (controller.signal.aborted) return;
        if (order.id !== id) throw new Error("Order tracking returned a different order.");
        if (latest.current?.owner === owner && latest.current.order.id === id && latest.current.order.version > order.version) {
          order = latest.current.order;
        }
        latest.current = { owner, order };
        setResource({ owner, id, order });
        finished = terminal.has(order.status);
        if (finished) {
          // Do not erase a newer order saved by another tab while this read was in flight.
          try { if (readHint(key)?.id === id) localStorage.removeItem(key); }
          catch { setStorageIssue({ key, message: "Completed order tracking could not be cleared on this device." }); }
        }
      } catch (error) { if (!controller.signal.aborted) setResource({ owner, id, error }); }
      if (!controller.signal.aborted && !finished) timer = setTimeout(() => { void refresh(); }, 60_000);
    };
    void refresh();
    return () => { controller.abort(); if (timer) clearTimeout(timer); };
  }, [id, online, visible, accessToken, supabaseUrl, publishableKey, owner, key, revision, loader]);
  const current = resource?.owner === owner && resource.id === id ? resource : undefined;
  const order = current?.order;
  return {
    activeOrder: order && terminal.has(order.status) ? undefined : currentHint,
    label: !online ? "Order status unavailable — offline" : current?.error ? "Order status unavailable — open Orders"
      : order ? labels[order.status] ?? "View order status" : "Checking your order status…",
    error: current?.error,
    storageIssue: storageIssue?.key === key ? storageIssue.message : undefined,
    retry: () => setRevision(value => value + 1),
  };
}
