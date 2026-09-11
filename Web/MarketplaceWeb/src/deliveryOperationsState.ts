import { customerDataIssue, type CustomerDataIssue } from "./customerDataState";
import type { PartnerAvailability } from "./delivery";
import type { OrderChangeSignal, OrderRealtimeHealth } from "./orderRealtime";

export type DeliveryFeedKey = "partner" | "v1" | "returns" | "legacy" | "parcel";

export type DeliveryFeedState = {
  loaded: boolean;
  loading: boolean;
  updatedAt?: number;
  issue?: CustomerDataIssue;
};

export type DeliveryFeedStates = Record<DeliveryFeedKey, DeliveryFeedState>;

export const deliveryOperationalFeedKeys: DeliveryFeedKey[] = [
  "v1",
  "returns",
  "legacy",
  "parcel",
];

export const deliveryFeedLabels: Record<DeliveryFeedKey, string> = {
  partner: "Availability",
  v1: "Dastak deliveries",
  returns: "Returns",
  legacy: "Earlier deliveries",
  parcel: "Parcels",
};

export function initialDeliveryFeedStates(): DeliveryFeedStates {
  return {
    partner: { loaded: false, loading: true },
    v1: { loaded: false, loading: true },
    returns: { loaded: false, loading: true },
    legacy: { loaded: false, loading: true },
    parcel: { loaded: false, loading: true },
  };
}

export function deliveryFeedStarted(
  states: DeliveryFeedStates,
  keys: DeliveryFeedKey[],
): DeliveryFeedStates {
  return updateFeeds(states, keys, (state) => ({
    ...state,
    loading: !state.loaded,
  }));
}

export function deliveryFeedSucceeded(
  states: DeliveryFeedStates,
  key: DeliveryFeedKey,
  updatedAt = Date.now(),
): DeliveryFeedStates {
  return {
    ...states,
    [key]: { loaded: true, loading: false, updatedAt },
  };
}

export function deliveryFeedFailed(
  states: DeliveryFeedStates,
  key: DeliveryFeedKey,
  error: unknown,
): DeliveryFeedStates {
  return {
    ...states,
    [key]: {
      ...states[key],
      loaded: true,
      loading: false,
      issue: deliveryDataIssue(error),
    },
  };
}

export function deliveryDataIssue(error: unknown): CustomerDataIssue {
  const issue = customerDataIssue(error);
  if (issue.kind === "session") return issue;
  if (issue.kind === "offline") {
    return {
      ...issue,
      message: "Reconnect to receive current offers, routes, returns, and parcel updates.",
    };
  }
  if (issue.kind === "access") {
    return {
      ...issue,
      title: "Delivery access unavailable",
      message: "This account cannot load delivery work right now. Sign in again if the issue continues.",
    };
  }
  return {
    ...issue,
    title: "Delivery updates are unavailable",
    message: "Dastak could not refresh this part of your delivery desk. It will retry automatically.",
  };
}

export function deliveryFeedFailures(states: DeliveryFeedStates) {
  return (Object.keys(states) as DeliveryFeedKey[])
    .filter((key) => states[key].issue)
    .map((key) => ({ key, label: deliveryFeedLabels[key], issue: states[key].issue! }));
}

export function deliveryFeedsInitiallyLoading(states: DeliveryFeedStates) {
  return deliveryOperationalFeedKeys.every((key) => !states[key].loaded);
}

export function deliveryOperationalFeedsSettledWithoutErrors(states: DeliveryFeedStates) {
  return deliveryOperationalFeedKeys.every((key) => states[key].loaded && !states[key].issue);
}

export function deliveryFeedsForRealtimeSignal(signal?: OrderChangeSignal): DeliveryFeedKey[] {
  if (!signal) return ["partner", ...deliveryOperationalFeedKeys];
  return signal.entityKind === "parcel" ? ["parcel"] : ["legacy"];
}

export function isDeliveryConcurrencyReconciliation(error: unknown) {
  const code = errorCode(error);
  return code === "invalid_state" || code === "stale_version" || code === "not_found" ||
    code === "offer_expired" || code === "assignment_expired";
}

export function isUncertainDeliveryMutation(error: unknown) {
  const details = errorDetails(error);
  return details.code === "network_error" || details.code === "request_timeout" ||
    details.status === 0 || details.status === 408 ||
    (typeof details.status === "number" && details.status >= 500);
}

export function shouldRunDeliveryFallback(
  visibility: DocumentVisibilityState,
  online: boolean,
) {
  return visibility === "visible" && online;
}

export function deliveryFallbackCadence(health: OrderRealtimeHealth) {
  return health === "subscribed" ? 60_000 : 30_000;
}

export function isOfferExpired(respondBy: string, now = Date.now()) {
  const deadline = Date.parse(respondBy);
  return !Number.isFinite(deadline) || deadline <= now;
}

export function deadlineDelay(deadline: string, now = Date.now()) {
  const timestamp = Date.parse(deadline);
  if (!Number.isFinite(timestamp)) return 0;
  return Math.max(0, timestamp - now);
}

export function isRiderEffectivelyOnline(
  availability: PartnerAvailability | null | undefined,
  now = Date.now(),
) {
  return availability?.status === "online" && availability.availableUntil !== null &&
    Date.parse(availability.availableUntil) > now;
}

function updateFeeds(
  states: DeliveryFeedStates,
  keys: DeliveryFeedKey[],
  update: (state: DeliveryFeedState) => DeliveryFeedState,
) {
  const next = { ...states };
  keys.forEach((key) => { next[key] = update(states[key]); });
  return next;
}

function errorCode(error: unknown) {
  return errorDetails(error).code.trim().toLowerCase().replaceAll("-", "_");
}

function errorDetails(error: unknown): { code: string; status?: number } {
  if (!error || typeof error !== "object") return { code: "" };
  const value = error as { code?: unknown; status?: unknown; error?: unknown };
  if (value.error && typeof value.error === "object" && !Array.isArray(value.error)) {
    const nested = value.error as { code?: unknown; status?: unknown };
    return {
      code: typeof nested.code === "string" ? nested.code.trim().toLowerCase().replaceAll("-", "_") : "",
      status: typeof nested.status === "number" ? nested.status :
        typeof value.status === "number" ? value.status : undefined,
    };
  }
  return {
    code: typeof value.code === "string" ? value.code.trim().toLowerCase().replaceAll("-", "_") : "",
    status: typeof value.status === "number" ? value.status : undefined,
  };
}
