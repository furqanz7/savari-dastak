import type { ReactNode } from "react";
import { ArrowRight, CircleAlert, Package, WifiOff, X } from "lucide-react";
import type { OrderRealtimeHealth } from "./orderRealtime";
import { useCustomerOnline } from "./useCustomerOnline";

/** Customer presentation primitives. Network ownership stays with the calling screen. */
export function CustomerPageHeading({ eyebrow, title, description, children }: {
  eyebrow: string; title: string; description?: string; children?: ReactNode;
}) {
  return <header className="customer-page-title"><div><p className="customer-eyebrow">{eyebrow}</p><h1>{title}</h1>{description ? <p>{description}</p> : null}</div>{children}</header>;
}

export function CustomerNotice({ title, children, onRetry, onDismiss, actionLabel = "Try again", tone = "warning" }: {
  title: string; children?: ReactNode; onRetry?: () => void; onDismiss?: () => void;
  actionLabel?: string; tone?: "warning" | "offline" | "info";
}) {
  return <div className={`customer-notice ${tone}`} role={tone === "warning" ? "alert" : "status"}>
    {tone === "offline" ? <WifiOff size={20} /> : <CircleAlert size={20} />}
    <div><strong>{title}</strong>{children ? <p>{children}</p> : null}</div>
    {onRetry ? <button type="button" onClick={onRetry}>{actionLabel}<ArrowRight size={16} /></button> : null}
    {onDismiss ? <button className="customer-notice-dismiss" type="button" aria-label="Dismiss message" onClick={onDismiss}><X size={18} /></button> : null}
  </div>;
}

export function CustomerEmptyState({ title, copy, icon = <Package size={30} />, action, onAction }: {
  title: string; copy: string; icon?: ReactNode; action?: string; onAction?: () => void;
}) {
  return <div className="customer-empty-state"><span className="customer-empty-art" aria-hidden="true">{icon}</span><h2>{title}</h2><p>{copy}</p>{onAction && action ? <button className="customer-button" type="button" onClick={onAction}>{action}<ArrowRight size={18} /></button> : null}</div>;
}

export function CustomerSkeleton({ label, kind = "products" }: { label: string; kind?: "products" | "orders" }) {
  return <div className={`customer-skeleton ${kind}`} role="status" aria-label={label}><span className="customer-sr-only">{label}</span><div aria-hidden="true">{Array.from({ length: kind === "orders" ? 3 : 6 }, (_, index) => <div className="customer-skeleton-card" key={index}><i /><span /><span /><b /></div>)}</div></div>;
}

export function CustomerSyncStatus({ health, refreshing = false, failed = false }: {
  health?: OrderRealtimeHealth; refreshing?: boolean; failed?: boolean;
}) {
  const online = useCustomerOnline();
  const label = !online ? "You’re offline" : failed ? "Updates delayed" : refreshing ? "Updating orders" : health === "degraded" ? "Reconnecting" : health === "connecting" ? "Connecting" : "Updates automatically";
  return <span className={`customer-sync-status${!online || failed || health === "degraded" ? " delayed" : ""}`} role="status"><i aria-hidden="true" />{label}</span>;
}
