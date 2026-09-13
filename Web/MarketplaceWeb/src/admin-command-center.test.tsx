import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AdminOverviewPanel } from "./AdminOverviewPanel";
import type { V1AdminCommandCenter } from "./dastakV1";

const snapshot: V1AdminCommandCenter = {
  observedAt: "2026-08-31T12:34:56Z",
  actionQueue: { merchantApplications: 2, deliveryApplications: 1, openIncidents: 0, riderEscalations: 1, activePauses: 0 },
  identities: { activeAccounts: 10, customers: 8, merchants: 3, deliveryPartners: 4, deletedPersonas: 1, recoveryEligiblePhones: 1 },
  commerce: { activeOrders: 7, awaitingPayment: 1, preparingFulfilments: 2, readyFulfilments: 1, activeMissions: 3, deliveredToday: 5 },
  network: { activeOrganizations: 3, activeBranches: 4, onlineRiders: 2, assignedRiders: 1 },
  catalogue: { total: 3637, active: 3000, draft: 637, needsReview: 20, missingPrimaryImage: 12 },
};

describe("finished Admin command center", () => {
  it("renders connected live actions and navigation destinations", () => {
    const destinations: string[] = [];
    const markup = renderToStaticMarkup(<AdminOverviewPanel
      snapshot={snapshot}
      loading={false}
      onNavigate={(destination) => destinations.push(destination)}
    />);

    expect(markup).toContain("Your attention, where it matters.");
    expect(markup).toContain("4</strong><span>actions waiting");
    expect(markup).toContain("Active orders");
    expect(markup).toContain("Active accounts");
    expect(markup).toContain("Active catalogue");
    expect(markup).toContain("Merchant applications");
    expect(markup).toContain("Delivery applications");
    expect(markup).toContain("Today’s live pipeline");
    expect(markup).not.toMatch(/Razorpay|service_role|evidence_object_path/i);
    expect(destinations).toEqual([]);
  });

  it("keeps partial backend failure truthful while specialist workspaces remain available", () => {
    const markup = renderToStaticMarkup(<AdminOverviewPanel
      snapshot={undefined}
      loading={false}
      onNavigate={() => undefined}
    />);
    expect(markup).toContain("Command center is temporarily unavailable");
    expect(markup).toContain("specialist workspaces remain available");
  });

  it("ships separate responsive desktop, mobile, and reduced-motion Admin layouts", () => {
    const dashboard = readFileSync(new URL("./AdminDashboard.tsx", import.meta.url), "utf8");
    const runtime = readFileSync(new URL("./adminRuntime.ts", import.meta.url), "utf8");
    const styles = readFileSync(new URL("./design/v1-admin.css", import.meta.url), "utf8");

    // The redesign replaces the two mobile strips with the same complete,
    // grouped navigation in an accessible drawer. Interaction tests cover it.
    const navigation = readFileSync(new URL("./AdminWorkspaceNavigation.tsx", import.meta.url), "utf8");
    expect(dashboard).toContain("<AdminWorkspaceNavigation");
    expect(navigation).toContain('className="admin-sidebar"');
    expect(navigation).toContain('className="admin-mobile-bar"');
    expect(navigation).toContain('className="admin-navigation-drawer"');
    expect(navigation).toContain('aria-current={selected === item.id ? "page"');
    expect(dashboard).toContain('label: "Daily operations"');
    expect(dashboard).toContain('label: "Marketplace"');
    expect(dashboard).toContain('label: "Oversight"');
    expect(dashboard).not.toContain("mainNavigation.slice(0, 5)");
    expect(dashboard).toContain("Promise.allSettled");
    expect(dashboard).toContain("AdminFeedStatus");
    expect(dashboard).toContain("feedStates");
    expect(dashboard).toContain("useAdminRealtime");
    expect(dashboard).toContain("adminFallbackCadence");
    expect(dashboard).toContain("actionError");
    expect(dashboard).not.toContain("Some live signals could not be refreshed");
    expect(dashboard).not.toContain("getAdminOrders({ ...auth, limit: 50 }).catch");
    expect(runtime).toContain("visibilitychange");
    expect(runtime).toContain("30_000");
    expect(runtime).toContain('.channel("admin-control", { config: { private: true } })');
    expect(runtime).toContain('{ event: "admin_changed" }');
    expect(dashboard).toContain("useAdminPullToRefresh");
    expect(dashboard).toContain("admin-pull-indicator");
    expect(dashboard).not.toMatch(/<button[^>]*>\s*(?:Refresh|Retry)/i);
    const catalogue = readFileSync(new URL("./AdminCataloguePanel.tsx", import.meta.url), "utf8");
    expect(catalogue).toContain("catalogueImageUrl");
    expect(catalogue).toContain("categoryTypeName");
    expect(catalogue).toContain("Full product record");
    expect(catalogue).not.toMatch(/<button[^>]*>\s*(?:Refresh|Retry)/i);
    expect(styles).toContain("grid-template-columns: 232px minmax(0, 1fr)");
    expect(styles).toContain("@media (max-width: 900px)");
    expect(styles).toContain("@media (max-width: 480px)");
    expect(styles).toContain("@media (prefers-reduced-motion: reduce)");
    expect(styles).toContain("env(safe-area-inset-bottom)");
    expect(styles).toContain(":focus-visible");
    expect(styles).toContain(".admin-person-mark");
    expect(styles).toContain("border-radius: 11px");
    expect(readFileSync(new URL("./styles.css", import.meta.url), "utf8")).toContain(".admin-feed-status");
  });
});
