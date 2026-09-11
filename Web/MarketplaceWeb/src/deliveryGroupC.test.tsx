// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  DeliveryNotificationStatus,
  deliveryNotificationTarget,
  deliveryTrackingMessages,
  recoveryOptions,
} from "./DeliveryPartnerView";
import {
  classifyPositionFix,
  useDeliveryGeolocationController,
  type DeliveryGeolocationController,
  type DeliveryGeolocationMode,
} from "./deliveryGeolocation";

describe("Delivery Web Group C operations", () => {
  it("routes rider notification clicks without disturbing existing order routes", () => {
    expect(deliveryNotificationTarget("#/deliveries")).toEqual({ kind: "workspace" });
    expect(deliveryNotificationTarget("#/deliveries/offer/offer%201")).toEqual({
      kind: "offer", entityId: "offer 1",
    });
    expect(deliveryNotificationTarget("#/deliveries/return/return-id")).toEqual({
      kind: "return", entityId: "return-id",
    });
    expect(deliveryNotificationTarget("#/v1-orders/order-id")).toBeUndefined();
    expect(deliveryNotificationTarget("#/deliveries/mission/%E0%A4%A")).toBeUndefined();
  });

  it("presents explicit push and browser-tracking limitations", () => {
    const markup = renderToStaticMarkup(<DeliveryNotificationStatus controller={{
      status: "prompt", shouldPrompt: true,
      enable: async () => undefined, dismiss: () => undefined, refresh: async () => undefined,
    }} />);
    expect(markup).toContain("Get delivery alerts");
    expect(markup).toContain("Enable alerts");
    expect(deliveryTrackingMessages("background_limited", "unsupported", true, "degraded")
      .map((message) => message.text).join(" ")).toContain("cannot guarantee background GPS");
    expect(renderToStaticMarkup(<DeliveryNotificationStatus controller={{
      status: "dismissed", shouldPrompt: false,
      enable: async () => undefined, dismiss: () => undefined, refresh: async () => undefined,
    }} />)).toBe("");
  });

  it("uses bounded reasons for every high-consequence recovery action", () => {
    expect(recoveryOptions("v1CancelBeforePickup")).toContain("Safety concern");
    expect(recoveryOptions("v1ReportCustomerUnreachable")).toContain("Customer not answering");
    expect(recoveryOptions("v1ReportDeliveryProblem")).toContain("Package damaged");
  });

  it("classifies stale and inaccurate fixes before publication", () => {
    const now = Date.parse("2026-09-11T10:00:00Z");
    expect(classifyPositionFix({ accuracyMeters: 18, timestamp: now }, now)).toBe("tracking");
    expect(classifyPositionFix({ accuracyMeters: 250, timestamp: now }, now)).toBe("inaccurate");
    expect(classifyPositionFix({ accuracyMeters: 18, timestamp: now - 26_000 }, now)).toBe("stale");
  });
});

describe("mission-aware geolocation ownership", () => {
  let host: HTMLDivElement;
  let root: Root;
  let positionHandler!: PositionCallback;
  const watchPosition = vi.fn((success: PositionCallback) => {
    positionHandler = success;
    return watchPosition.mock.calls.length;
  });
  const clearWatch = vi.fn();

  beforeEach(() => {
    (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean })
      .IS_REACT_ACT_ENVIRONMENT = true;
    host = document.createElement("div");
    document.body.append(host);
    root = createRoot(host);
    vi.stubGlobal("navigator", {
      ...window.navigator,
      onLine: true,
      geolocation: { watchPosition, clearWatch, getCurrentPosition: vi.fn() },
    });
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    host.remove();
    vi.unstubAllGlobals();
    vi.clearAllMocks();
    (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean })
      .IS_REACT_ACT_ENVIRONMENT = false;
  });

  function Harness({ mode, onReady, publishMission, publishAvailability }: {
    mode: DeliveryGeolocationMode;
    onReady: (controller: DeliveryGeolocationController) => void;
    publishMission: (missionId: string) => Promise<void>;
    publishAvailability: () => Promise<void>;
  }) {
    const controller = useDeliveryGeolocationController({
      mode,
      publishMission: (missionId) => publishMission(missionId),
      publishAvailability,
      onForegroundReconcile: () => undefined,
    });
    onReady(controller);
    return null;
  }

  it("keeps one watcher and hands publication ownership from availability to a mission", async () => {
    const publishMission = vi.fn().mockResolvedValue(undefined);
    const publishAvailability = vi.fn().mockResolvedValue(undefined);
    let controller: DeliveryGeolocationController | undefined;
    const render = async (mode: DeliveryGeolocationMode) => {
      await act(async () => root.render(<Harness
        mode={mode}
        publishMission={publishMission}
        publishAvailability={publishAvailability}
        onReady={(value) => { controller = value; }}
      />));
    };
    await render({ kind: "availability" });
    expect(watchPosition).toHaveBeenCalledTimes(1);
    await act(async () => positionHandler(position()));
    expect(publishAvailability).toHaveBeenCalledTimes(1);

    await render({ kind: "mission", missionId: "mission-1" });
    expect(clearWatch).toHaveBeenCalledTimes(1);
    expect(watchPosition).toHaveBeenCalledTimes(2);
    await act(async () => positionHandler(position()));
    expect(publishMission).toHaveBeenCalledWith("mission-1");
    expect(controller).toBeDefined();

    await render({ kind: "mission", missionId: "mission-1" });
    expect(watchPosition).toHaveBeenCalledTimes(2);

    publishMission.mockClear();
    act(() => controller?.handleVisibilityChange(false));
    await act(async () => positionHandler(position()));
    expect(publishMission).not.toHaveBeenCalled();
    await act(async () => controller?.handleVisibilityChange(true));
    expect(publishMission).toHaveBeenCalledWith("mission-1");
  });
});

function position(): GeolocationPosition {
  return {
    coords: {
      latitude: 12.6819, longitude: 78.6201, accuracy: 18,
      altitude: null, altitudeAccuracy: null, heading: null, speed: null,
      toJSON: () => ({}),
    },
    timestamp: Date.now(),
    toJSON: () => ({}),
  };
}
