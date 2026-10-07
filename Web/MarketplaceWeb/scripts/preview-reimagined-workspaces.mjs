// Local, static renderer for actual workspace components. No browser account
// requests, scripts, handlers or production inventory; all data is synthetic.
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { createServer as createViteServer } from "vite";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const vite = await createViteServer({ root, server: { middlewareMode: true }, appType: "custom" });
const { CatalogueView } = await vite.ssrLoadModule("/src/CatalogueView.tsx");
const { MatchingSheet, OrdersSection, PaymentsSection } = await vite.ssrLoadModule("/src/DastakV1CustomerExperience.tsx");
const { ReimaginedShell } = await vite.ssrLoadModule("/src/ReimaginedShell.tsx");
const { initialReimaginedState, reimaginedReducer } = await vite.ssrLoadModule("/src/reimaginedState.ts");
const { workspaceOrderFixture: order } = await vite.ssrLoadModule("/src/reimaginedWorkspace.testFixtures.ts");
const noop = () => {};
const accountProps = { accountId: "synthetic", accessToken: "not-a-session", client: {}, supabaseUrl: "https://example.invalid", publishableKey: "not-a-key", displayName: "Preview customer", email: "preview@example.invalid", phoneNumber: "+919876543210", orderRefreshToken: 0, section: "account", onNavigate: noop, onOpenOrder: noop, onCloseOrder: noop, onOpenParcel: noop, onSignOut: noop, deliveryPartnerUrl: "#", merchantUrl: "#", legalLinks: { privacy: "#", terms: "#", support: "#" } };
const markup = new Map();
for (const view of ["profile", "settings", "orders", "record", "payments"]) {
  const pane = view === "profile" || view === "settings" ? React.createElement(CatalogueView, { ...accountProps, accountPane: view, onOpenProfile: noop, onOpenSettings: noop })
    : view === "orders" ? React.createElement(OrdersSection, { presentation: "reimagined", orders: [{ ...order, status: "PREPARING", deliveredAt: undefined }], loading: false, loadingMore: false, canLoadMore: false, imageUrlForLine: () => null, onRefresh: noop, onLoadMore: noop, onOpen: noop, onReorder: noop, onSessionExpired: noop })
      : view === "payments" ? React.createElement(PaymentsSection, { presentation: "reimagined", orders: [order], loading: false, onRefresh: noop, onOpen: noop })
        : React.createElement(MatchingSheet, { presentation: "panel", order, busy: false, imageUrlForLine: () => null, onDismiss: noop, onCancel: noop, onPay: noop, onReorder: noop, onRefresh: noop, onReportIssue: async () => true });
  let state = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "synthetic" });
  const section = view === "profile" || view === "settings" ? view : "orders";
  state = reimaginedReducer(state, { type: "navigate", section });
  const content = React.createElement("div", { className: "customer-experience" }, React.createElement("div", { "data-presentation": "reimagined" }, pane));
  const shell = renderToStaticMarkup(React.createElement(ReimaginedShell, { state, dispatch: noop, directory: [], greeting: "Preview", displayName: "Test customer", locationLabel: "Synthetic location", locationContent: null, onSignIn: noop, onOpenActiveOrder: noop, featureTitle: view === "payments" ? "Payments" : undefined, sectionContent: { [section]: content }, environment: React.createElement("div", { style: { minHeight: "100vh", background: "#d2dbcf" } }) }));
  const styles = ["styles.css", "design/customer.css", "design/v1-customer.css", "design/customer-experience.css", "design/reimagined.css"].map(path => `<link rel="stylesheet" href="http://127.0.0.1:5179/src/${path}">`).join("");
  markup.set(view, `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Reimagined ${view} — synthetic static preview</title>${styles}<style>body{margin:0}.preview-choices{position:fixed;bottom:2px;left:8px;right:8px;z-index:50;font:11px system-ui;display:flex;justify-content:center;gap:8px;background:#fffdf1}.preview-choices a{color:#28563b}</style></head><body class="variant-dastak-customer">${shell}<nav class="preview-choices" aria-label="Synthetic preview views">Static check · ${["profile", "settings", "orders", "record", "payments"].map(name => `<a href="/?view=${name}">${name}</a>`).join(" ")}</nav></body></html>`);
}
const server = createServer((request, response) => {
  if (request.method !== "GET") { response.writeHead(405); response.end(); return; }
  const view = new URL(request.url, "http://127.0.0.1:5181").searchParams.get("view") ?? "profile";
  response.writeHead(markup.has(view) ? 200 : 404, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
  response.end(markup.get(view) ?? "Unknown preview");
});
server.listen(5181, "127.0.0.1", () => console.log("Synthetic static workspace preview: http://127.0.0.1:5181/?view=profile"));
async function close() { server.close(); await vite.close(); }
process.on("SIGINT", () => void close()); process.on("SIGTERM", () => void close());
