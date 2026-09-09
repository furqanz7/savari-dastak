import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { customerRiderArrived, customerTrackingPresentation, parseCustomerDeliveryTracking } from "./customerDeliveryPresentation";
import { CustomerLiveDelivery } from "./CustomerLiveDelivery";
import { parseV1Order, type V1Order } from "./dastakV1";

const recordedAt = "2026-09-09T10:00:00Z";
const now = Date.parse(recordedAt);
const tracking = {
  missionId: "11111111-1111-4111-8111-111111111111", phase: "EN_ROUTE_TO_PICKUPS", riderName: "Delivery partner",
  transportType: "BICYCLE", location: { latitude: 12.68, longitude: 78.62 },
  recordedAt, receivedAt: recordedAt, liveUntil: "2026-09-09T10:00:30Z", accuracyMeters: 5,
  sequence: 4, serverTime: recordedAt,
};
const order: V1Order = {
  id: "22222222-2222-4222-8222-222222222222", displayOrderNumber: "DSK-TEST", orderType: "RETAIL", status: "PREPARING", version: 1,
  price: { snapshotKind: "FINAL_PAYABLE", subtotalPaise: 10000, deliveryFeePaise: 0, platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 10000, currencyCode: "INR" },
  lines: [], createdAt: recordedAt, updatedAt: recordedAt,
};

describe("Customer tracking parity with iOS", () => {
  it("reads the existing canonical backend projection without requiring it on older orders", () => {
    expect(parseV1Order({ ...order, tracking }).tracking).toEqual(parseCustomerDeliveryTracking(tracking));
    expect(parseV1Order(order).tracking).toBeUndefined();
    expect(parseV1Order({ ...order, tracking: { malformed: true } }).id).toBe(order.id);
  });

  it("shows the assigned rider through pickup as well as the final journey", () => {
    for (const status of ["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY"] as const) {
      const result = customerTrackingPresentation({ ...order, status, tracking }, now);
      expect(result?.riderName).toBe("Delivery partner");
      expect(result?.phase).toBe("Collecting your order");
      expect(result?.live).toBe(true);
    }
  });

  it("expires the live label at the server deadline, including offline and inaccurate fixes", () => {
    const current = { ...order, tracking };
    expect(customerTrackingPresentation(current, now + 29_999)?.live).toBe(true);
    expect(customerTrackingPresentation(current, now + 30_000)?.live).toBe(false);
    expect(customerTrackingPresentation(current, now, false)?.live).toBe(false);
    for (const accuracyMeters of [-1, 36, undefined]) {
      expect(customerTrackingPresentation({ ...order, tracking: { ...tracking, accuracyMeters } }, now)?.live).toBe(false);
    }
    expect(customerTrackingPresentation({ ...order, tracking: { ...tracking, recordedAt: "2026-09-09T10:00:06Z" } }, now)?.live).toBe(false);
  });

  it("distinguishes missing, malformed and legacy locations from live positions", () => {
    const withoutFix = parseCustomerDeliveryTracking({ ...tracking, location: null });
    expect(customerTrackingPresentation({ ...order, tracking: withoutFix }, now)?.freshness).toContain("first location");
    const invalid = parseCustomerDeliveryTracking({ ...tracking, location: { latitude: 95, longitude: 0 } });
    expect(invalid?.location).toBeUndefined();
    expect(customerTrackingPresentation({ ...order, status: "OUT_FOR_DELIVERY", delivery: {
      state: "ON_THE_WAY", verificationStatus: "ACTIVE", recipientAccountRequired: false,
      riderLocation: tracking.location, riderLocationUpdatedAt: recordedAt,
    } }, now)?.freshness).toBe("Last-known location · not live");
  });

  it("recognizes arrival without changing order state or showing completed tracking", () => {
    const arrived = { ...order, status: "OUT_FOR_DELIVERY" as const, tracking: { ...tracking, phase: "ARRIVED" } };
    expect(customerRiderArrived(arrived)).toBe(true);
    expect(customerTrackingPresentation(arrived, now)?.phase).toBe("At your delivery destination");
    for (const status of ["DELIVERED", "CANCELLED", "UNAVAILABLE"] as const) {
      expect(customerRiderArrived({ ...arrived, status })).toBe(false);
      expect(customerTrackingPresentation({ ...arrived, status }, now)).toBeUndefined();
    }
  });

  it("keeps the map marker in the map renderer instead of drawing a false road route", () => {
    const html = renderToStaticMarkup(<CustomerLiveDelivery order={{ ...order, tracking }} />);
    expect(html).toContain('title="Delivery map"');
    expect(html).toContain("marker=12.68%2C78.62");
    expect(html).toContain("Collecting your order");
    expect(html).not.toContain("customer-map-markers");
    expect(html).not.toContain("polyline");
  });
});
