import type { V1Order } from "./dastakV1";

const matchingStatuses = new Set<V1Order["status"]>(["CREATED", "MATCHING"]);

export function statusTitle(status: V1Order["status"]) {
  switch (status) {
    case "CREATED":
    case "MATCHING":
      return "Finding every item";
    case "FULLY_SECURED":
    case "AWAITING_PAYMENT":
      return "Your basket is secured";
    case "PAID":
    case "PREPARING":
      return "Preparing your order";
    case "PICKUP_IN_PROGRESS":
      return "Picking up your order";
    case "OUT_FOR_DELIVERY":
      return "On the way";
    case "DELIVERED":
      return "Delivered";
    case "UNAVAILABLE":
      return "Basket unavailable";
    case "PAYMENT_EXPIRED":
      return "Payment window expired";
    case "CANCELLED_PREPAYMENT":
      return "Order cancelled";
    case "DASTAK_FULFILMENT_FAILURE":
      return "Order needs attention";
  }
}

export function statusMessage(status: V1Order["status"]) {
  if (matchingStatuses.has(status)) {
    return "Dastak is matching every exact item. Retail merchant identities stay private.";
  }
  if (status === "FULLY_SECURED" || status === "AWAITING_PAYMENT") {
    return "Every item is reserved. Payment is requested before preparation begins.";
  }
  if (status === "PAID" || status === "PREPARING") {
    return "Payment is confirmed and your complete order is being prepared.";
  }
  if (status === "PICKUP_IN_PROGRESS") {
    return "Your delivery partner is collecting your complete order.";
  }
  if (status === "OUT_FOR_DELIVERY") {
    return "Every required package is with your delivery partner and heading to you.";
  }
  if (status === "DELIVERED") {
    return "Every package was securely handed over. Your order is complete.";
  }
  if (status === "UNAVAILABLE") {
    return "Dastak could not secure the complete basket. You were not charged.";
  }
  if (status === "CANCELLED_PREPAYMENT") {
    return "This order was cancelled before payment.";
  }
  if (status === "PAYMENT_EXPIRED") {
    return "The reservation ended before payment completed. Reserved items were released.";
  }
  return "Dastak is protecting your payment and coordinating recovery. Follow the updates below.";
}

export function statusAssurance(status: V1Order["status"]) {
  if (["CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT"].includes(status)) {
    return "No charge until the complete basket is secured";
  }
  if (["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY", "DELIVERED"].includes(status)) {
    return "Secure package custody is tracked by Dastak";
  }
  if (status === "DASTAK_FULFILMENT_FAILURE") {
    return "Payment protection and recovery remain with Dastak";
  }
  return "No completed payment is attached to this order";
}

export function isV1OrderActive(status: V1Order["status"]) {
  return ![
    "DELIVERED",
    "UNAVAILABLE",
    "PAYMENT_EXPIRED",
    "CANCELLED_PREPAYMENT",
    "DASTAK_FULFILMENT_FAILURE",
  ].includes(status);
}

export function orderKindLabel(orderType: string) {
  if (orderType === "FOOD_ONLY") return "Restaurant order";
  if (orderType === "MIXED") return "Food + retail order";
  return "Retail order";
}

export function humanizeV1State(value: string) {
  return value.toLowerCase().replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function orderLineDetail(line: V1Order["lines"][number]) {
  const options = line.foodSelection?.options.map((option) => option.name) ?? [];
  return (options.length ? options : [line.variant, line.packSize].filter(Boolean)).join(" · ");
}

export function isIssueEvidenceRequired(category: string) {
  return !["DELIVERY_PROBLEM", "OTHER"].includes(category);
}
