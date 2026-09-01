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

    expect(markup).toContain("The whole marketplace, in one view.");
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
    const styles = readFileSync(new URL("./design/v1-admin.css", import.meta.url), "utf8");

    expect(dashboard).toContain('className="admin-sidebar"');
    expect(dashboard).toContain('className="admin-mobile-navigation"');
    expect(dashboard).toContain('className="admin-secondary-mobile"');
    expect(dashboard).toContain('item.id !== "catalogue"');
    expect(dashboard).toContain('item.id === "catalogue"');
    expect(dashboard).not.toContain("mainNavigation.slice(0, 5)");
    expect(dashboard).toContain("Promise.allSettled");
    expect(dashboard).toContain("AdminFeedStatus");
    expect(dashboard).toContain("feedUpdatedAt");
    expect(dashboard).toContain("actionError");
    expect(dashboard).not.toContain("Some live signals could not be refreshed");
    expect(dashboard).not.toContain("getAdminOrders({ ...auth, limit: 50 }).catch");
    expect(dashboard).toContain("visibilitychange");
    expect(dashboard).toContain("30_000");
    expect(styles).toContain("grid-template-columns: 232px minmax(0, 1fr)");
    expect(styles).toContain("@media (max-width: 900px)");
    expect(styles).toContain("@media (max-width: 480px)");
    expect(styles).toContain("@media (prefers-reduced-motion: reduce)");
    expect(styles).toContain("env(safe-area-inset-bottom)");
    expect(styles).toContain(":focus-visible");
    expect(readFileSync(new URL("./styles.css", import.meta.url), "utf8")).toContain(".admin-feed-status");
  });
});
