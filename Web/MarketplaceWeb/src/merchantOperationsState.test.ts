import { describe, expect, it } from "vitest";
import {
  initialMerchantFeedStates,
  isMerchantConcurrencyReconciliation,
  merchantDataIssue,
  merchantFallbackCadence,
  merchantFeedFailed,
  merchantFeedStarted,
  merchantFeedSucceeded,
  merchantFeedsSettledWithoutErrors,
  shouldRunMerchantFallback,
  type MerchantFeedKey,
} from "./merchantOperationsState";

describe("merchant operations state", () => {
  it("isolates feed failures and preserves successful feed truth", () => {
    let states = initialMerchantFeedStates();
    states = merchantFeedSucceeded(states, "retail");
    states = merchantFeedFailed(states, "restaurant", { code: "network_error" });

    expect(states.retail).toEqual({ loaded: true, loading: false });
    expect(states.restaurant).toMatchObject({
      loaded: true,
      loading: false,
      issue: { kind: "offline", action: "retry" },
    });
    expect(states.fulfilments).toEqual({ loaded: false, loading: true });
  });

  it("does not replace a settled feed with a blocking loader during background refresh", () => {
    let states = merchantFeedSucceeded(initialMerchantFeedStates(), "retail");
    states = merchantFeedStarted(states, ["retail"]);
    expect(states.retail).toEqual({ loaded: true, loading: false });
  });

  it("reports a completely successful empty desk only after every feed settles", () => {
    let states = initialMerchantFeedStates();
    expect(merchantFeedsSettledWithoutErrors(states)).toBe(false);
    const feeds: MerchantFeedKey[] = ["retail", "restaurant", "fulfilments", "recovery", "returns", "settlements", "legacy"];
    feeds.forEach((feed) => { states = merchantFeedSucceeded(states, feed); });
    expect(merchantFeedsSettledWithoutErrors(states)).toBe(true);
  });

  it("routes structured session expiry to sign-in recovery", () => {
    expect(merchantDataIssue({ status: 401, code: "jwt_expired" })).toMatchObject({
      kind: "session",
      action: "sign_in",
      title: "Your session expired",
    });
  });

  it("classifies normal optimistic-concurrency outcomes for reconciliation", () => {
    expect(isMerchantConcurrencyReconciliation({ code: "invalid_state" })).toBe(true);
    expect(isMerchantConcurrencyReconciliation({ code: "STALE-VERSION" })).toBe(true);
    expect(isMerchantConcurrencyReconciliation({ error: { code: "not_found" } })).toBe(true);
    expect(isMerchantConcurrencyReconciliation({ code: "permission_denied" })).toBe(false);
  });

  it("runs conservative fallback only while visible and online", () => {
    expect(shouldRunMerchantFallback("visible", true)).toBe(true);
    expect(shouldRunMerchantFallback("hidden", true)).toBe(false);
    expect(shouldRunMerchantFallback("visible", false)).toBe(false);
    expect(merchantFallbackCadence("subscribed")).toBe(60_000);
    expect(merchantFallbackCadence("degraded")).toBe(30_000);
  });
});
