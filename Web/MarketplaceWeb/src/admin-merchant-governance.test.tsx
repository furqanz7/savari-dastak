import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("Admin Merchant governance workspace", () => {
  it("is permission-scoped, independently synchronized and wired into Admin navigation", () => {
    const dashboard = readFileSync(new URL("./AdminDashboard.tsx", import.meta.url), "utf8");
    const panel = readFileSync(new URL("./AdminMerchantGovernancePanel.tsx", import.meta.url), "utf8");
    const runtime = readFileSync(new URL("./adminRuntime.ts", import.meta.url), "utf8");

    expect(dashboard).toContain('id: "merchants"');
    expect(dashboard).toContain("<AdminMerchantGovernancePanel auth={auth}");
    expect(panel).toContain('useAdminWorkspaceRefresh("merchantGovernance"');
    expect(panel).toContain("new RefreshQueue()");
    expect(panel).toContain("new AbortController()");
    expect(runtime).toContain('"merchantGovernance"');
  });

  it("uses the privileged-action reconciliation framework for every governed mutation", () => {
    const panel = readFileSync(new URL("./AdminMerchantGovernancePanel.tsx", import.meta.url), "utf8");

    expect(panel).toContain("runAdminPrivilegedMutation");
    expect(panel).toContain("setV1AdminMerchantOrganizationStatus");
    expect(panel).toContain("setV1AdminMerchantBranchStatus");
    expect(panel).toContain("correctV1AdminMerchantBranchDetails");
    expect(panel).toContain("expectedVersion: row.organization.version");
    expect(panel).toContain("expectedVersion: row.branch.version");
    expect(panel).toContain("Active committed fulfilments or custody will block this action");
    expect(panel).toContain("Active pickup or return work will block this change");
  });

  it("replaces manual Merchant branch UUID entry with a governed branch picker", () => {
    const safety = readFileSync(new URL("./AdminOperationalSafetyPanel.tsx", import.meta.url), "utf8");

    expect(safety).toContain("getV1AdminMerchantGovernancePage");
    expect(safety).toContain('aria-label="Find Merchant branch"');
    expect(safety).toContain('aria-label="Merchant branch"');
    expect(safety).toContain("activeNonTerminalFulfilmentCount");
    expect(safety).toContain("activePickupReturnWorkCount");
    expect(safety).toContain("operationalPause?.active");
    expect(safety).toContain("setV1OperationalPause");
  });

  it("keeps the governed surface responsive without introducing a new visual system", () => {
    const styles = readFileSync(new URL("./design/v1-admin.css", import.meta.url), "utf8");

    expect(styles).toContain(".admin-governance-card");
    expect(styles).toContain(".admin-branch-correction-grid");
    expect(styles).toContain(".admin-safety-branch-picker");
    expect(styles).toContain("@media (max-width: 560px)");
    expect(styles).toContain("var(--dastak-accent)");
    expect(styles).toContain("var(--destructive)");
  });
});
