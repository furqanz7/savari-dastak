import { useReducer, useState } from "react";
import { createRoot } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CatalogueView } from "./CatalogueView";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { ReimaginedModalLayer } from "./ReimaginedModalLayer";
import { OrdersSection, PaymentsSection, MatchingSheet } from "./DastakV1CustomerExperience";
import { workspaceOrderFixture as order } from "./reimaginedWorkspace.testFixtures";
import { ReimaginedShell } from "./ReimaginedShell";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import "./styles.css";
import "./design/customer.css";
import "./design/v1-customer.css";
import "./design/customer-experience.css";

const noop = () => {};
const profile = { displayName: "Synthetic preview customer with a long name", phoneNumber: "+919876543210" };
const props = { ...profile, accountId: "synthetic", accessToken: "synthetic", client: {} as SupabaseClient, supabaseUrl: "https://example.invalid", publishableKey: "synthetic", email: "long.preview.customer@example.invalid", orderRefreshToken: 0, section: "account" as const, onNavigate: noop, onOpenOrder: noop, onCloseOrder: noop, onOpenParcel: noop, onSignOut: noop, deliveryPartnerUrl: "#delivery", merchantUrl: "#merchant", legalLinks: { privacy: "#privacy", terms: "#terms", support: "#support" } };
// Render-only snapshots: account effects, OAuth and destructive actions never run.
const profileHtml = renderToStaticMarkup(<CatalogueView {...props} accountPane="profile" onOpenSettings={noop} />);
const settingsHtml = renderToStaticMarkup(<CatalogueView {...props} accountPane="settings" onOpenProfile={noop} />);

export function WorkspaceCheck() {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "synthetic-workspaces" }));
  const [payments, setPayments] = useState(false), [record, setRecord] = useState(false), [edit, setEdit] = useState(false);
  const workspace = record ? <MatchingSheet order={order} busy={false} imageUrlForLine={() => null} onDismiss={() => setRecord(false)} onCancel={noop} onPay={noop} onReorder={noop} onRefresh={noop} onReportIssue={async () => false} presentation="panel" />
    : payments ? <PaymentsSection orders={[order]} loading={false} onOpen={() => setRecord(true)} onRefresh={noop} presentation="reimagined" />
    : <><button onClick={() => setPayments(true)}>Payments</button><OrdersSection orders={[order]} loading={false} loadingMore={false} canLoadMore={false} imageUrlForLine={() => null} onRefresh={noop} onLoadMore={noop} onOpen={() => setRecord(true)} onReorder={noop} onSessionExpired={noop} onShop={() => dispatch({ type: "navigate", section: "home" })} presentation="reimagined" /></>;
  return <><aside className="reimagined-local-notice">Synthetic local UI check · Profile/Settings read-only snapshots · no API/account/order writes</aside>
    <ReimaginedShell state={state} dispatch={action => { setRecord(false); setPayments(false); dispatch(action); }} directory={[]} greeting="Preview" locationLabel="Synthetic address" locationContent={null} onSignIn={noop} onOpenActiveOrder={noop} featureTitle={payments && state.section === "orders" ? "Payments" : undefined} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />}
      sectionContent={{ orders: <div className="variant-dastak-customer customer-workspace customer-experience" data-embedded="true"><div className="customer-view"><div className="v1-customer-shell" data-presentation="reimagined">{workspace}</div></div></div>, profile: <div className="customer-workspace customer-experience" data-embedded="true"><button onClick={() => setEdit(true)}>Preview profile editor</button>{edit ? <ReimaginedModalLayer><AccountProfileSheet presentation="customer" profile={profile} busy={false} onDismiss={() => setEdit(false)} onSave={async () => setEdit(false)} /></ReimaginedModalLayer> : null}<div dangerouslySetInnerHTML={{ __html: profileHtml }} /></div>, settings: <div className="customer-workspace customer-experience" data-embedded="true" dangerouslySetInnerHTML={{ __html: settingsHtml }} /> }}>
      <p>Choose Orders, Profile or Settings to inspect the real screen markup with synthetic data.</p>
    </ReimaginedShell>
  </>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  const root = createRoot(document.getElementById("root")!); root.render(<WorkspaceCheck />);
  import.meta.hot?.dispose(() => root.unmount());
}
