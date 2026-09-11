import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { DeliveryOperationsStatus } from "./DeliveryPartnerView";
import {
  deadlineDelay,
  deliveryDataIssue,
  deliveryFallbackCadence,
  deliveryFeedFailed,
  deliveryFeedsForRealtimeSignal,
  deliveryFeedStarted,
  deliveryFeedSucceeded,
  initialDeliveryFeedStates,
  isDeliveryConcurrencyReconciliation,
  isOfferExpired,
  isRiderEffectivelyOnline,
  isUncertainDeliveryMutation,
  shouldRunDeliveryFallback,
} from "./deliveryOperationsState";

describe("delivery operations runtime state", () => {
  it("isolates feed failures and preserves the last successful lane", () => {
    let states = initialDeliveryFeedStates();
    states = deliveryFeedSucceeded(states, "parcel", 1_000);
    states = deliveryFeedStarted(states, ["parcel", "legacy"]);
    states = deliveryFeedFailed(states, "legacy", { code: "network_error" });

    expect(states.parcel).toEqual({ loaded: true, loading: false, updatedAt: 1_000 });
    expect(states.legacy).toMatchObject({
      loaded: true,
      loading: false,
      issue: { kind: "offline", action: "retry" },
    });
    expect(states.v1).toEqual({ loaded: false, loading: true });
  });

  it("keeps content visible and reports a background refresh failure as stale", () => {
    let states = deliveryFeedSucceeded(initialDeliveryFeedStates(), "v1", 1_000);
    states = deliveryFeedFailed(states, "v1", { status: 503, code: "delivery_unavailable" });
    const markup = renderToStaticMarkup(
      <DeliveryOperationsStatus states={states} hasContent onRetry={() => undefined} />,
    );
    expect(states.v1.updatedAt).toBe(1_000);
    expect(markup).toContain("Previously loaded information remains visible");
    expect(markup).not.toContain("Loading delivery queue");
  });

  it("never presents an empty desk while an operational feed failed", () => {
    let states = initialDeliveryFeedStates();
    states = deliveryFeedFailed(states, "returns", { status: 503 });
    const markup = renderToStaticMarkup(
      <DeliveryOperationsStatus states={states} hasContent={false} />,
    );
    expect(markup).toContain("Returns could not update");
    expect(markup).not.toContain("Waiting for assignments");
  });

  it("routes session expiry through sign-in recovery classification", () => {
    expect(deliveryDataIssue({ status: 401, code: "jwt_expired" })).toMatchObject({
      kind: "session",
      action: "sign_in",
      title: "Your session expired",
    });
  });

  it("routes realtime invalidations only to their affected lanes", () => {
    const entityId = "fc67d2b1-7d38-4e99-970e-c973049e4794";
    expect(deliveryFeedsForRealtimeSignal({ entityKind: "parcel", entityId, stateVersion: 2 }))
      .toEqual(["parcel"]);
    expect(deliveryFeedsForRealtimeSignal({ entityKind: "merchant_order", entityId, stateVersion: 2 }))
      .toEqual(["legacy"]);
    expect(deliveryFeedsForRealtimeSignal()).toEqual([
      "partner", "v1", "returns", "legacy", "parcel",
    ]);
  });

  it("classifies quiet concurrency and uncertain mutation outcomes", () => {
    expect(isDeliveryConcurrencyReconciliation({ code: "STALE-VERSION" })).toBe(true);
    expect(isDeliveryConcurrencyReconciliation({ error: { code: "offer_expired" } })).toBe(true);
    expect(isDeliveryConcurrencyReconciliation({ code: "permission_denied" })).toBe(false);
    expect(isUncertainDeliveryMutation({ code: "request_timeout", status: 0 })).toBe(true);
    expect(isUncertainDeliveryMutation({ status: 503 })).toBe(true);
    expect(isUncertainDeliveryMutation({ code: "invalid_state", status: 409 })).toBe(false);
  });

  it("polls conservatively only while visible and online", () => {
    expect(shouldRunDeliveryFallback("visible", true)).toBe(true);
    expect(shouldRunDeliveryFallback("hidden", true)).toBe(false);
    expect(shouldRunDeliveryFallback("visible", false)).toBe(false);
    expect(deliveryFallbackCadence("subscribed")).toBe(60_000);
    expect(deliveryFallbackCadence("degraded")).toBe(30_000);
  });

  it("expires offers and rider availability at their authoritative deadlines", () => {
    const now = Date.parse("2026-09-11T10:00:00Z");
    expect(isOfferExpired("2026-09-11T09:59:59Z", now)).toBe(true);
    expect(isOfferExpired("2026-09-11T10:00:01Z", now)).toBe(false);
    expect(deadlineDelay("2026-09-11T10:00:01Z", now)).toBe(1_000);
    expect(isRiderEffectivelyOnline({
      status: "online",
      location: { latitude: 12.68, longitude: 78.62 },
      serviceZoneId: "77777777-7777-4777-8777-777777777777",
      availableUntil: "2026-09-11T10:00:01Z",
      stateVersion: 2,
    }, now)).toBe(true);
    expect(isRiderEffectivelyOnline({
      status: "online",
      location: { latitude: 12.68, longitude: 78.62 },
      serviceZoneId: "77777777-7777-4777-8777-777777777777",
      availableUntil: "2026-09-11T09:59:59Z",
      stateVersion: 2,
    }, now)).toBe(false);
  });
});
