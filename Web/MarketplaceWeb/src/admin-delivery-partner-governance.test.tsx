import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("Admin Delivery Partner governance workspace", () => {
  it("is independently synchronized and wired into Admin navigation", () => {
    const dashboard = readFileSync(new URL("./AdminDashboard.tsx", import.meta.url), "utf8");
    const panel = readFileSync(new URL("./AdminDeliveryPartnerGovernancePanel.tsx", import.meta.url), "utf8");
    const runtime = readFileSync(new URL("./adminRuntime.ts", import.meta.url), "utf8");
    expect(dashboard).toContain('id: "riders"');
    expect(dashboard).toContain("<AdminDeliveryPartnerGovernancePanel auth={auth}");
    expect(panel).toContain('useAdminWorkspaceRefresh("deliveryPartnerGovernance"');
    expect(panel).toContain("new RefreshQueue()");
    expect(panel).toContain("new AbortController()");
    expect(runtime).toContain('"deliveryPartnerGovernance"');
  });

  it("uses Group A2 reconciliation, exact identity, bounded reasons and custody guidance", () => {
    const panel = readFileSync(new URL("./AdminDeliveryPartnerGovernancePanel.tsx", import.meta.url), "utf8");
    expect(panel).toContain("runAdminPrivilegedMutation");
    expect(panel).toContain("setV1AdminDeliveryPartnerStatus");
    expect(panel).toContain("expectedGovernanceVersion: row.governance.version");
    expect(panel).toContain("Safety review");
    expect(panel).toContain("Suspected account compromise");
    expect(panel).toContain("Repeated custody failure");
    expect(panel).toContain("existing recovery or release workflow");
    expect(panel).toContain("confirmationValue: suspending ? row.rider.displayName");
  });

  it("does not expose evidence paths or add transport editing", () => {
    const panel = readFileSync(new URL("./AdminDeliveryPartnerGovernancePanel.tsx", import.meta.url), "utf8");
    expect(panel).not.toContain("objectPath");
    expect(panel).not.toContain("setTransport");
    expect(panel).toContain("hasIdentityEvidence");
    expect(panel).toContain("hasVehicleEvidence");
  });
});
