import type { V1Order } from "./dastakV1";

/** Existing, access-controlled order projection, shared with Customer iOS. */
export type CustomerDeliveryTracking = {
  missionId: string;
  phase: string;
  riderName: string;
  transportType?: string;
  location?: { latitude: number; longitude: number };
  recordedAt?: string;
  liveUntil?: string;
  accuracyMeters?: number;
};

/** Optional map data must never prevent a valid order or receipt from opening. */
export function parseCustomerDeliveryTracking(value: unknown): CustomerDeliveryTracking | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const source = value as Record<string, unknown>;
  if (typeof source.missionId !== "string" || !/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(source.missionId)
    || typeof source.phase !== "string" || !source.phase) return undefined;
  const location = source.location as Record<string, unknown> | null | undefined;
  const point = location && typeof location.latitude === "number" && Number.isFinite(location.latitude)
    && Math.abs(location.latitude) <= 90 && typeof location.longitude === "number"
    && Number.isFinite(location.longitude) && Math.abs(location.longitude) <= 180
    ? { latitude: location.latitude, longitude: location.longitude } : undefined;
  const timestamp = (input: unknown) => typeof input === "string" && Number.isFinite(Date.parse(input)) ? input : undefined;
  return {
    missionId: source.missionId, phase: source.phase,
    riderName: typeof source.riderName === "string" && source.riderName.trim() ? source.riderName.slice(0, 160) : "Your delivery partner",
    transportType: typeof source.transportType === "string" ? source.transportType : undefined,
    location: point, recordedAt: timestamp(source.recordedAt), liveUntil: timestamp(source.liveUntil),
    accuracyMeters: typeof source.accuracyMeters === "number" && Number.isFinite(source.accuracyMeters) ? source.accuracyMeters : undefined,
  };
}

export function customerRiderArrived(order: V1Order) {
  return order.status === "OUT_FOR_DELIVERY" && (order.tracking?.phase === "ARRIVED" || Boolean(order.delivery?.riderArrivedAt));
}

export function customerTrackingPresentation(order: V1Order, now: number, connected = true) {
  if (!["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY"].includes(order.status)) return undefined;
  const tracking = order.tracking;
  if (!tracking && order.status !== "OUT_FOR_DELIVERY") return undefined;
  // A legacy coordinate has no precision/expiry authority. Show it as last-known.
  const location = tracking ? tracking.location : order.delivery?.riderLocation;
  const recordedAt = tracking ? tracking.recordedAt : order.delivery?.riderLocationUpdatedAt;
  const live = Boolean(connected && location && tracking?.recordedAt && tracking.liveUntil
    && tracking.accuracyMeters !== undefined && tracking.accuracyMeters >= 0 && tracking.accuracyMeters <= 35
    && Date.parse(tracking.liveUntil) > now && Date.parse(tracking.recordedAt) <= now + 5_000);
  const phases: Record<string, string> = {
    ASSIGNED: "Your delivery partner is assigned", EN_ROUTE_TO_PICKUPS: "Collecting your order",
    PICKUP_IN_PROGRESS: "Collecting your order", ALL_PACKAGES_PICKED_UP: "Every package is collected",
    OUT_FOR_DELIVERY: "On the way to you", ARRIVED: "At your delivery destination",
    DELIVERY_RECOVERY: "Your delivery needs assistance",
  };
  return {
    location, recordedAt, live, riderName: tracking?.riderName ?? "Your delivery partner",
    phase: customerRiderArrived(order) ? "At your delivery destination" : phases[tracking?.phase ?? "OUT_FOR_DELIVERY"] ?? "Delivery in progress",
    freshness: !connected ? "Updates delayed · last-known information" : !location ? "Waiting for the rider’s first location" : live ? "Location updates automatically" : "Last-known location · not live",
  };
}
