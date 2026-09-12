import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("Admin Audit History workspace", () => {
  it("is wired into Admin navigation and scoped realtime invalidation", () => {
    const dashboard = readFileSync(new URL("./AdminDashboard.tsx", import.meta.url), "utf8");
    const panel = readFileSync(new URL("./AdminAuditHistoryPanel.tsx", import.meta.url), "utf8");
    const runtime = readFileSync(new URL("./adminRuntime.ts", import.meta.url), "utf8");

    expect(dashboard).toContain('id: "audit"');
    expect(dashboard).toContain("<AdminAuditHistoryPanel auth={auth}");
    expect(panel).toContain('useAdminWorkspaceRefresh("auditHistory"');
    expect(runtime).toContain('"auditHistory"');
  });

  it("preserves the proven request, reconciliation, and truthful-state primitives", () => {
    const panel = readFileSync(new URL("./AdminAuditHistoryPanel.tsx", import.meta.url), "utf8");

    expect(panel).toContain("new RefreshQueue()");
    expect(panel).toContain("new AbortController()");
    expect(panel).toContain("adminFeedStarted");
    expect(panel).toContain("adminFeedSucceeded");
    expect(panel).toContain("adminFeedFailed");
    expect(panel).toContain('phase === "failed-with-content"');
    expect(panel).toContain('phase === "failed-without-content"');
    expect(panel).toContain("Load older events");
  });

  it("offers the governed filters and responsive long-list treatment", () => {
    const panel = readFileSync(new URL("./AdminAuditHistoryPanel.tsx", import.meta.url), "utf8");
    const styles = readFileSync(new URL("./design/v1-admin.css", import.meta.url), "utf8");

    for (const label of [
      "From",
      "To",
      "Actor name or account ID",
      "Action",
      "Resource type",
      "Event ID",
      "Resource ID",
      "Order ID",
      "Branch ID",
      "Account ID",
    ]) expect(panel).toContain(label);

    expect(styles).toContain(".admin-audit-event");
    expect(styles).toContain("content-visibility: auto");
    expect(styles).toContain("@media (max-width: 900px)");
    expect(styles).toContain("@media (max-width: 480px)");
  });
});
