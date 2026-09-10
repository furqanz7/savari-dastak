import { describe, expect, it } from "vitest";
import type { V1MerchantFulfilment, V1MerchantOpportunity, V1RestaurantRequest } from "./dastakV1";
import { renderToStaticMarkup } from "react-dom/server";
import { MerchantLiveDelivery } from "./MerchantLiveDelivery";
import {
  merchantFulfilmentQueue,
  merchantPaymentPresentation,
  merchantQueueCounts,
  merchantReadyActionState,
} from "./merchantOrderPresentation";

const fulfilment = (status: V1MerchantFulfilment["status"], orderStatus: string = status) => ({
  status,
  orderStatus,
  canDeclarePackages: false,
  canAddEvidence: false,
  canMarkReady: false,
  readyIsIrreversible: true,
} as V1MerchantFulfilment);

describe("merchant order presentation", () => {
  it("categorizes current and final lifecycle states like the operational queues", () => {
    expect(merchantFulfilmentQueue(fulfilment("PREPARING"))).toBe("preparing");
    expect(merchantFulfilmentQueue(fulfilment("READY"))).toBe("ready");
    expect(merchantFulfilmentQueue(fulfilment("PICKED_UP"))).toBeUndefined();
    expect(merchantFulfilmentQueue(fulfilment("RELEASED"))).toBe("history");
    expect(merchantFulfilmentQueue(fulfilment("PICKED_UP", "DELIVERED"))).toBe("history");
  });

  it("counts New, Preparing, Ready, History and the active All queue independently", () => {
    const counts = merchantQueueCounts({
      opportunities: [{ status: "OFFERED" }, { status: "ACCEPTED" }] as V1MerchantOpportunity[],
      restaurantRequests: [{ status: "OFFERED" }] as V1RestaurantRequest[],
      fulfilments: [
        fulfilment("PREPARING"), fulfilment("READY"), fulfilment("PICKED_UP"),
        fulfilment("RELEASED"), fulfilment("PICKED_UP", "DELIVERED"),
      ],
    });
    expect(counts).toEqual({ all: 5, new: 2, preparing: 1, ready: 1, history: 2 });
  });

  it("uses server capabilities as the primary readiness gates", () => {
    const preparing = {
      ...fulfilment("PREPARING"),
      canDeclarePackages: true,
      canAddEvidence: false,
      canMarkReady: true,
      readyIsIrreversible: true,
    };
    expect(merchantReadyActionState(preparing, false)).toEqual({
      canDeclarePackages: true,
      canAddEvidence: false,
      canMarkReady: false,
    });
    expect(merchantReadyActionState(preparing, true).canMarkReady).toBe(true);
    expect(merchantReadyActionState({ ...preparing, canMarkReady: false }, true).canMarkReady).toBe(false);
  });

  it("describes launch payment as customer pay at delivery, never merchant receipt", () => {
    const presentation = merchantPaymentPresentation();
    expect(`${presentation.state} ${presentation.detail}`).toContain("pay the delivery partner");
    expect(`${presentation.state} ${presentation.detail}`.toLowerCase()).not.toMatch(/merchant (has )?(received|paid)/);
  });

  it("renders the shared map primitive from merchant-safe rider tracking", () => {
    const tracked = {
      ...fulfilment("PREPARING"),
      tracking: {
        missionId: "11111111-1111-4111-8111-111111111111",
        phase: "EN_ROUTE_TO_PICKUPS",
        riderName: "Founder Rider",
        location: { latitude: 12.68, longitude: 78.62 },
        recordedAt: "2026-09-10T00:00:00Z",
        liveUntil: "2026-09-10T00:00:30Z",
        accuracyMeters: 5,
      },
    } as V1MerchantFulfilment;
    const markup = renderToStaticMarkup(<MerchantLiveDelivery fulfilment={tracked} delayed />);
    expect(markup).toContain('aria-label="Rider tracking"');
    expect(markup).toContain('title="Delivery map"');
    expect(markup).toContain("Founder Rider");
    expect(markup).toContain("Rider heading to pickup");
    expect(markup).toContain("Delayed");
    expect(markup).not.toContain("customerDestination");
  });
});
