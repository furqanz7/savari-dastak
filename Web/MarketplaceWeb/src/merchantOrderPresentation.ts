import type { V1MerchantFulfilment, V1MerchantOpportunity, V1RestaurantRequest } from "./dastakV1";

export type MerchantOperationalQueue = "all" | "new" | "preparing" | "ready" | "history";

const finalOrderStatuses = new Set([
  "DELIVERED", "CANCELLED", "CANCELLED_PREPAYMENT", "PAYMENT_EXPIRED", "UNAVAILABLE",
  "DELIVERY_FAILED", "RETURNED", "REFUNDED", "DASTAK_FULFILMENT_FAILURE",
]);

export function merchantFulfilmentQueue(fulfilment: V1MerchantFulfilment): "preparing" | "ready" | "history" | undefined {
  if (fulfilment.status === "RELEASED" || finalOrderStatuses.has(fulfilment.orderStatus)) return "history";
  if (fulfilment.status === "PREPARING") return "preparing";
  if (fulfilment.status === "READY") return "ready";
  return undefined;
}

export function merchantQueueCounts(input: {
  opportunities: V1MerchantOpportunity[];
  restaurantRequests: V1RestaurantRequest[];
  fulfilments: V1MerchantFulfilment[];
}) {
  const incoming = input.opportunities.filter((item) => item.status === "OFFERED").length
      + input.restaurantRequests.filter((item) => item.status === "OFFERED").length;
  const active = input.fulfilments.filter((item) => merchantFulfilmentQueue(item) !== "history"
    && ["PREPARING", "READY", "PICKED_UP"].includes(item.status));
  return {
    all: incoming + active.length,
    new: incoming,
    preparing: input.fulfilments.filter((item) => merchantFulfilmentQueue(item) === "preparing").length,
    ready: input.fulfilments.filter((item) => merchantFulfilmentQueue(item) === "ready").length,
    history: input.fulfilments.filter((item) => merchantFulfilmentQueue(item) === "history").length,
  };
}

export function merchantReadyActionState(fulfilment: V1MerchantFulfilment, irreversibleConfirmed: boolean) {
  return {
    canDeclarePackages: fulfilment.canDeclarePackages,
    canAddEvidence: fulfilment.canAddEvidence,
    canMarkReady: fulfilment.canMarkReady && (!fulfilment.readyIsIrreversible || irreversibleConfirmed),
  };
}

export function merchantPaymentPresentation() {
  return {
    state: "Pay at delivery",
    detail: "The customer will pay the delivery partner by UPI or cash at the doorstep. No merchant payment action is required.",
  };
}
