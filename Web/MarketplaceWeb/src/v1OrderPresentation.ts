import type { V1Order } from "./dastakV1";

const matchingStatuses = new Set<V1Order["status"]>(["CREATED", "MATCHING"]);

export const orderJourneySteps = [
  "Finding items", "Ready for payment", "Preparing", "Picking up", "On the way", "Delivered",
] as const;

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
    return "We’re checking availability for every exact item in your basket. You’ll pay only after everything is secured.";
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

export function orderJourneyStep(status: V1Order["status"]) {
  if (status === "CREATED" || status === "MATCHING") return 0;
  if (status === "FULLY_SECURED" || status === "AWAITING_PAYMENT") return 1;
  if (status === "PAID" || status === "PREPARING") return 2;
  if (status === "PICKUP_IN_PROGRESS") return 3;
  if (status === "OUT_FOR_DELIVERY") return 4;
  if (status === "DELIVERED") return 5;
  return undefined;
}

export function orderJourneyLabel(status: V1Order["status"]) {
  const step = orderJourneyStep(status);
  return step === undefined ? undefined : orderJourneySteps[step];
}

export function deliveryAddressLine(address: NonNullable<V1Order["deliveryAddress"]>) {
  const seen = new Set<string>();
  return [address.line2, address.line1, address.landmark, address.city, address.state,
    address.postalCode]
    .map(normalizeAddressComponent)
    .flatMap((value) => value?.split(",").map((segment) => segment.trim()).filter(Boolean) ?? [])
    .filter((value): value is string => {
      if (!value || seen.has(value.toLocaleLowerCase())) return false;
      seen.add(value.toLocaleLowerCase());
      return true;
    })
    .join(", ");
}

export function customerPhoneNumber(value: string) {
  const digits = value.replace(/\D/g, "");
  const local = digits.length === 12 && digits.startsWith("91")
    ? digits.slice(2)
    : digits.length === 10 ? digits : undefined;
  return local ? `+91 ${local.slice(0, 5)} ${local.slice(5)}` : value;
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

export function orderItemCount(order: V1Order) {
  return order.lines.reduce((total, line) => total + line.quantity, 0);
}

export function canReorderV1Order(status: V1Order["status"]) {
  return ["DELIVERED", "UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT"].includes(status);
}

export function deliveredDurationLabel(order: V1Order) {
  const started = Date.parse(order.submittedAt ?? order.createdAt);
  const finished = Date.parse(order.deliveredAt ?? order.delivery?.deliveredAt ?? "");
  if (!Number.isFinite(started) || !Number.isFinite(finished)) return undefined;
  const minutes = Math.max(1, Math.round((finished - started) / 60_000));
  if (minutes < 60) return `Delivered in ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder ? `Delivered in ${hours} hr ${remainder} min` : `Delivered in ${hours} hr`;
}

export function orderSearchText(order: V1Order) {
  return [
    order.displayOrderNumber,
    order.restaurant?.name,
    order.restaurant?.branchName,
    order.recipient?.name,
    order.deliveryAddress && [
      order.deliveryAddress.line1,
      order.deliveryAddress.line2,
      order.deliveryAddress.landmark,
      order.deliveryAddress.city,
      order.deliveryAddress.state,
      order.deliveryAddress.postalCode,
    ].filter(Boolean).join(" "),
    ...order.lines.map((line) => line.name),
  ].filter(Boolean).join(" ").toLowerCase();
}

export function isIssueEvidenceRequired(category: string) {
  return !["DELIVERY_PROBLEM", "OTHER"].includes(category);
}

function normalizeAddressComponent(value: string | undefined) {
  const normalized = value?.replace(/(?:\s*,\s*)+/g, ", ").replace(/^\s*,|,\s*$/g, "").trim();
  return normalized || undefined;
}
