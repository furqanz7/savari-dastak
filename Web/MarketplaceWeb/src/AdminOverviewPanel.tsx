import {
  Activity,
  ArrowRight,
  Bike,
  Boxes,
  CircleAlert,
  PackageCheck,
  ShieldCheck,
  Store,
  UsersRound,
} from "lucide-react";
import type { ReactNode } from "react";
import type { V1AdminCommandCenter } from "./dastakV1";

type Destination = "approvals" | "orders" | "network" | "catalogue" | "safety" | "health";

export function AdminOverviewPanel({
  snapshot,
  loading,
  onNavigate,
}: {
  snapshot?: V1AdminCommandCenter;
  loading: boolean;
  onNavigate: (destination: Destination) => void;
}) {
  if (!snapshot && loading) {
    return <div className="admin-overview-skeleton" role="status" aria-label="Loading command center">
      <span /><span /><span /><span />
    </div>;
  }
  if (!snapshot) {
    return <section className="admin-empty-state">
      <Activity size={28} />
      <h2>Command center is temporarily unavailable</h2>
      <p>The specialist workspaces remain available from the navigation.</p>
    </section>;
  }

  const queue = snapshot.actionQueue;
  const actionCount = queue.merchantApplications + queue.deliveryApplications +
    queue.openIncidents + queue.riderEscalations + queue.activePauses;

  return <section className="admin-overview" aria-labelledby="admin-overview-title">
    <article className="admin-command-hero">
      <div>
        <p className="eyebrow">LIVE COMMAND CENTER</p>
        <h2 id="admin-overview-title">The whole marketplace, in one view.</h2>
        <p>Identity, fulfilment, delivery, safety, catalogue and system signals are connected to their authoritative Dastak records.</p>
      </div>
      <div className={actionCount > 0 ? "attention" : "clear"}>
        {actionCount > 0 ? <CircleAlert size={24} /> : <ShieldCheck size={24} />}
        <strong>{actionCount}</strong>
        <span>{actionCount === 1 ? "action waiting" : "actions waiting"}</span>
      </div>
    </article>

    <div className="admin-kpi-grid" aria-label="Live operating metrics">
      <Metric icon={<PackageCheck />} label="Active orders" value={snapshot.commerce.activeOrders} detail={`${snapshot.commerce.deliveredToday} delivered today`} onClick={() => onNavigate("orders")} />
      <Metric icon={<UsersRound />} label="Active accounts" value={snapshot.identities.activeAccounts} detail={`${snapshot.identities.customers} customers`} onClick={() => onNavigate("network")} />
      <Metric icon={<Store />} label="Merchant branches" value={snapshot.network.activeBranches} detail={`${snapshot.network.activeOrganizations} organizations`} onClick={() => onNavigate("network")} />
      <Metric icon={<Bike />} label="Riders online" value={snapshot.network.onlineRiders} detail={`${snapshot.network.assignedRiders} assigned`} onClick={() => onNavigate("safety")} />
      <Metric icon={<Boxes />} label="Active catalogue" value={snapshot.catalogue.active} detail={`${snapshot.catalogue.needsReview} need QA`} onClick={() => onNavigate("catalogue")} />
      <Metric icon={<Activity />} label="Open incidents" value={snapshot.actionQueue.openIncidents} detail="Invariant monitoring" onClick={() => onNavigate("health")} attention={snapshot.actionQueue.openIncidents > 0} />
    </div>

    <div className="admin-overview-columns">
      <section className="admin-action-queue">
        <header><div><p className="eyebrow">ACTION QUEUE</p><h3>Needs attention</h3></div><span>{actionCount}</span></header>
        <QueueRow icon={<Store />} title="Merchant applications" value={queue.merchantApplications} onClick={() => onNavigate("approvals")} />
        <QueueRow icon={<Bike />} title="Delivery applications" value={queue.deliveryApplications} onClick={() => onNavigate("approvals")} />
        <QueueRow icon={<CircleAlert />} title="Safety escalations" value={queue.riderEscalations + queue.activePauses} onClick={() => onNavigate("safety")} />
        <QueueRow icon={<Activity />} title="System incidents" value={queue.openIncidents} onClick={() => onNavigate("health")} />
      </section>

      <section className="admin-flow-card">
        <p className="eyebrow">FULFILMENT FLOW</p>
        <h3>Today’s live pipeline</h3>
        <div>
          <Flow label="Awaiting confirmation" value={snapshot.commerce.awaitingPayment} />
          <Flow label="Preparing" value={snapshot.commerce.preparingFulfilments} />
          <Flow label="Ready for pickup" value={snapshot.commerce.readyFulfilments} />
          <Flow label="Active delivery missions" value={snapshot.commerce.activeMissions} />
        </div>
        <button type="button" onClick={() => onNavigate("orders")}>Open live order control <ArrowRight size={16} /></button>
      </section>
    </div>

    <p className="admin-observed-at">Live snapshot observed {new Date(snapshot.observedAt).toLocaleString("en-IN")}</p>
  </section>;
}

function Metric({ icon, label, value, detail, onClick, attention = false }: {
  icon: ReactNode;
  label: string;
  value: number;
  detail: string;
  onClick: () => void;
  attention?: boolean;
}) {
  return <button type="button" className={`admin-kpi ${attention ? "attention" : ""}`} onClick={onClick}>
    <span>{icon}</span><div><small>{label}</small><strong>{value.toLocaleString("en-IN")}</strong><p>{detail}</p></div><ArrowRight size={15} />
  </button>;
}

function QueueRow({ icon, title, value, onClick }: { icon: ReactNode; title: string; value: number; onClick: () => void }) {
  return <button type="button" onClick={onClick}><span>{icon}</span><strong>{title}</strong><b className={value > 0 ? "attention" : "clear"}>{value}</b><ArrowRight size={16} /></button>;
}

function Flow({ label, value }: { label: string; value: number }) {
  return <div><span>{label}</span><strong>{value.toLocaleString("en-IN")}</strong></div>;
}
