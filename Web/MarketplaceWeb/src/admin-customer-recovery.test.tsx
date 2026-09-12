import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("Admin Customer recovery workspace", () => {
  it("is permission-bounded, independently synchronized and wired into Admin navigation", () => {
    const dashboard = readFileSync(new URL("./AdminDashboard.tsx", import.meta.url), "utf8");
    const panel = readFileSync(new URL("./AdminCustomerRecoveryPanel.tsx", import.meta.url), "utf8");
    const runtime = readFileSync(new URL("./adminRuntime.ts", import.meta.url), "utf8");
    expect(dashboard).toContain('id: "customers"');
    expect(dashboard).toContain("<AdminCustomerRecoveryPanel auth={auth}");
    expect(panel).toContain('useAdminWorkspaceRefresh("customerRecovery"');
    expect(panel).toContain("new RefreshQueue()");
    expect(panel).toContain("new AbortController()");
    expect(runtime).toContain('"customerRecovery"');
  });

  it("uses Group A2 reconciliation for exact reviewed session and phone targets", () => {
    const panel = readFileSync(new URL("./AdminCustomerRecoveryPanel.tsx", import.meta.url), "utf8");
    expect(panel).toContain("runAdminPrivilegedMutation");
    expect(panel).toContain("session?.sessionId");
    expect(panel).toContain("expectedPhoneClaimVersion: row.phoneClaim.version");
    expect(panel).toContain("reviewedCurrentPhone: row.account.currentPhoneNumber");
    expect(panel).toContain("row.phoneClaim.version < 1");
    expect(panel).toContain("Customer-reported lost device");
    expect(panel).toContain("Suspected account compromise");
    expect(panel).toContain("confirmationValue: replacement");
    expect(panel).toContain("idempotencyKey");
  });

  it("never renders tokens, raw Auth metadata or identity mutation controls", () => {
    const panel = readFileSync(new URL("./AdminCustomerRecoveryPanel.tsx", import.meta.url), "utf8");
    expect(panel).not.toContain("access_token");
    expect(panel).not.toContain("refresh_token");
    expect(panel).not.toContain("raw_user_meta_data");
    expect(panel).not.toContain("updateEmail");
    expect(panel).not.toContain("mergeAccount");
  });
});
