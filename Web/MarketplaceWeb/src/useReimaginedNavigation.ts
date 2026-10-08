import { useEffect, useRef, useState } from "react";
import { parseCustomerDestination } from "./customerNavigation";
import type { ReimaginedNavigationState, ReimaginedService, ReimaginedView } from "./reimaginedState";

export type ReimaginedNavigation = ReimaginedNavigationState & {
  savedOpen: boolean;
  payments: boolean;
  orderId?: string;
};
const historyKey = "dastakReimaginedNavigation";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const text = (value: unknown): value is string => typeof value === "string" && value.length > 0 && value.length <= 500;
const record = (value: unknown): Record<string, unknown> | undefined => value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;

function readView(value: unknown): ReimaginedView | undefined {
  const view = record(value);
  if (!view) return;
  switch (view.kind) {
    case "home": return { kind: "home" };
    case "category": return text(view.categoryId) ? { kind: "category", categoryId: view.categoryId } : undefined;
    case "browse": return text(view.nodeKey) && (view.railKey === undefined || text(view.railKey)) ? { kind: "browse", nodeKey: view.nodeKey, ...(view.railKey ? { railKey: view.railKey as string } : {}) } : undefined;
    case "restaurant": return text(view.branchId) ? { kind: "restaurant", branchId: view.branchId } : undefined;
    case "search": return text(view.query) ? { kind: "search", query: view.query } : undefined;
  }
}

// History is untrusted UI state. Copy only navigation fields, never a cart,
// recipient, credentials, payment journal or active-order status.
export function readReimaginedHistory(value: unknown, owner: string, hash: string): ReimaginedNavigation | undefined {
  const entry = record(record(value)?.[historyKey]);
  if (entry?.version !== 1 || entry.owner !== owner || entry.hash !== hash) return;
  const nav = record(entry.navigation), exploration = record(nav?.exploration), view = readView(exploration?.view);
  if (!nav || !exploration || !view || !["grocery", "food"].includes(String(nav.service)) || !["home", "orders", "profile", "settings"].includes(String(nav.section))) return;
  if (typeof nav.savedOpen !== "boolean" || typeof nav.payments !== "boolean" || typeof exploration.searchOpen !== "boolean" || typeof exploration.checkout !== "boolean") return;
  if (exploration.detailId !== undefined && !text(exploration.detailId)) return;
  if (nav.orderId !== undefined && (typeof nav.orderId !== "string" || !uuid.test(nav.orderId))) return;
  return { service: nav.service as ReimaginedNavigation["service"], section: nav.section as ReimaginedNavigation["section"], savedOpen: nav.savedOpen, payments: nav.payments,
    ...(nav.orderId ? { orderId: nav.orderId as string } : {}),
    exploration: { view, searchOpen: exploration.searchOpen, checkout: exploration.checkout, ...(exploration.detailId ? { detailId: exploration.detailId as string } : {}) } };
}

export function reimaginedLink(hash: string, defaultService: ReimaginedService = "grocery"): ReimaginedNavigation {
  const [path, query] = hash.split("?"), params = new URLSearchParams(query);
  const destination = parseCustomerDestination(path);
  const service = params.get("service") === "food" ? "food" : params.get("service") === "grocery" ? "grocery" : defaultService;
  const section = path === "#/settings" ? "settings" : path === "#/profile" || destination.section === "account" ? "profile" : destination.section === "orders" || destination.section === "payments" ? "orders" : "home";
  const search = destination.section === "search", term = params.get("q")?.trim().slice(0, 500);
  return { service, section, savedOpen: destination.section === "wishlist", payments: destination.section === "payments",
    ...(destination.entityType === "dastakV1Order" ? { orderId: destination.entityId } : {}),
    exploration: { view: search && term ? { kind: "search", query: term } : { kind: "home" }, searchOpen: search && !term, checkout: false } };
}

export function reimaginedNavigationHash(nav: ReimaginedNavigation): string {
  const path = nav.savedOpen ? "wishlist" : nav.payments ? "payments" : nav.section === "orders" ? nav.orderId ? `v1-orders/${nav.orderId}` : "orders" : nav.section === "profile" ? "account" : nav.section === "settings" ? "settings" : nav.exploration.searchOpen || nav.exploration.view.kind === "search" ? "search" : "home";
  const params = new URLSearchParams();
  if (nav.service === "food") params.set("service", "food");
  if (path === "search" && !nav.exploration.searchOpen && nav.exploration.view.kind === "search") params.set("q", nav.exploration.view.query);
  return `#/${path}${params.size ? `?${params}` : ""}`;
}

export function useReimaginedNavigation(owner: string, navigation: ReimaginedNavigation, onRestore: (navigation: ReimaginedNavigation) => void) {
  const live = useRef({ navigation, onRestore });
  const ownerRef = useRef<string | undefined>(undefined);
  const last = useRef<string | undefined>(undefined);
  const restoring = useRef<string | undefined>(undefined);
  const epoch = useRef(0);
  const [restoreEpoch, setRestoreEpoch] = useState(0);
  useEffect(() => { live.current = { navigation, onRestore }; });
  useEffect(() => {
    const restore = () => {
      // Skip links are page anchors, not requests to leave the current screen.
      if (window.location.hash === "#reimagined-main" || window.location.hash === "#customer-content") return;
      const next = readReimaginedHistory(window.history.state, owner, window.location.hash)
        ?? reimaginedLink(window.location.hash, live.current.navigation.service);
      const signature = JSON.stringify(next);
      if (signature === last.current || signature === restoring.current) return;
      restoring.current = signature;
      epoch.current += 1; setRestoreEpoch(epoch.current);
      live.current.onRestore(next);
    };
    ownerRef.current = owner; last.current = undefined; restoring.current = undefined;
    restore();
    window.addEventListener("popstate", restore); window.addEventListener("hashchange", restore);
    return () => { window.removeEventListener("popstate", restore); window.removeEventListener("hashchange", restore); ownerRef.current = undefined; };
  }, [owner]);
  const signature = JSON.stringify(navigation);
  useEffect(() => {
    if (ownerRef.current !== owner || restoreEpoch !== epoch.current) return;
    const restore = Boolean(restoring.current); restoring.current = undefined;
    if (last.current === signature) return;
    const hash = reimaginedNavigationHash(navigation);
    const previous = record(window.history.state) ?? {};
    const entry = { ...previous, [historyKey]: { version: 1, owner, hash, navigation } };
    try { window.history[restore || last.current === undefined ? "replaceState" : "pushState"](entry, "", hash); }
    catch { /* A restricted history API must not interrupt shopping or recovery. */ }
    last.current = signature;
  }, [owner, signature, navigation, restoreEpoch]);
}
