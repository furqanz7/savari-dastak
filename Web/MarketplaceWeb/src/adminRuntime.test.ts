import { describe, expect, it } from "vitest";
import {
  adminFallbackCadence,
  adminFeedFailed,
  adminFeedHasContent,
  adminFeedStarted,
  adminFeedStale,
  adminFeedSucceeded,
  initialAdminFeedState,
  isAdminSessionExpired,
  parseAdminChangeSignal,
  shouldRunAdminFallback,
} from "./adminRuntime";

describe("Admin runtime contracts", () => {
  it("accepts only authorized workspace invalidations and strips untrusted payload", () => {
    expect(parseAdminChangeSignal({ payload: {
      workspaces: ["liveOrders", "network", "liveOrders", "not-a-workspace"],
      entityId: "fc67d2b1-7d38-4e99-970e-c973049e4794",
      secret: "must-not-propagate",
    } })).toEqual({
      workspaces: ["liveOrders", "network"],
      entityId: "fc67d2b1-7d38-4e99-970e-c973049e4794",
    });
    expect(parseAdminChangeSignal({ payload: { workspaces: ["unknown"] } })).toBeUndefined();
  });

  it("keeps feed state truthful while retaining last-valid content", () => {
    const initial = initialAdminFeedState();
    expect(adminFeedStarted(initial).phase).toBe("loading");
    const ready = adminFeedSucceeded(initial, 123);
    expect(adminFeedHasContent(ready)).toBe(true);
    expect(adminFeedStarted(ready).phase).toBe("refreshing");
    const failed = adminFeedFailed(ready, { code: "network_error" });
    expect(failed).toMatchObject({ phase: "failed-with-content", updatedAt: 123 });
    expect(adminFeedStale(ready).phase).toBe("stale");
    expect(adminFeedFailed(initial, new Error("down")).phase).toBe("failed-without-content");
  });

  it("runs fallback only in a visible online document and at conservative cadence", () => {
    expect(shouldRunAdminFallback("visible", true)).toBe(true);
    expect(shouldRunAdminFallback("hidden", true)).toBe(false);
    expect(shouldRunAdminFallback("visible", false)).toBe(false);
    expect(adminFallbackCadence("subscribed")).toBe(60_000);
    expect(adminFallbackCadence("degraded")).toBe(30_000);
  });

  it("classifies only structured authoritative session expiry", () => {
    expect(isAdminSessionExpired({ status: 401, code: "authentication_required" })).toBe(true);
    expect(isAdminSessionExpired({ error: { code: "jwt_expired", status: 403 } })).toBe(true);
    expect(isAdminSessionExpired(new Error("session text in a server error"))).toBe(false);
    expect(isAdminSessionExpired({ status: 403, code: "permission_denied" })).toBe(false);
  });
});
