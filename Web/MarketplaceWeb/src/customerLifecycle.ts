import type { MerchantOrderPaymentState, MerchantOrderStatus } from "./orders";
import type { CustomerParcelDelivery, ParcelDelivery, ParcelStatus } from "./parcels";

export type CustomerPrimaryAction = "pay" | "cancel" | "request_cancellation" | "none";

export type CustomerLifecyclePresentation = {
  title: string;
  message: string;
  primaryAction: CustomerPrimaryAction;
};

const orderCopy: Record<MerchantOrderStatus, Pick<CustomerLifecyclePresentation, "title" | "message">> = {
  payment_pending: { title: "Payment pending", message: "Complete payment to send the order to the store." },
  paid: { title: "Sent to store", message: "The store is reviewing your order." },
  merchant_accepted: { title: "Being prepared", message: "The store is preparing your items." },
  ready: { title: "Ready for pickup", message: "Your order is packed and ready." },
  assigned: { title: "Partner assigned", message: "A delivery partner is assigned." },
  en_route_to_pickup: { title: "Heading to store", message: "Your partner is heading to the store." },
  at_store: { title: "At the store", message: "Your partner has reached the store." },
  picked_up: { title: "Picked up", message: "Your partner has collected the order." },
  in_transit: { title: "Arriving soon", message: "Your order is on the way." },
  delivered: { title: "Delivered", message: "Your order was delivered." },
  cancelled: { title: "Cancelled", message: "This order was cancelled." },
  returning_to_merchant: { title: "Returning to store", message: "The order is being returned to the store." },
};

const parcelCopy: Record<ParcelStatus, Pick<CustomerLifecyclePresentation, "title" | "message">> = {
  payment_pending: { title: "Payment pending", message: "Complete payment to request pickup." },
  paid: { title: "Finding a partner", message: "Dastak is finding a delivery partner." },
  assigned: { title: "Partner assigned", message: "A delivery partner is assigned." },
  en_route_to_pickup: { title: "Heading to pickup", message: "Your partner is heading to pickup." },
  picked_up: { title: "Picked up", message: "Your parcel has been collected." },
  in_transit: { title: "Arriving soon", message: "Your parcel is on the way." },
  delivered: { title: "Delivered", message: "Your parcel was delivered." },
  cancelled: { title: "Cancelled", message: "This parcel delivery was cancelled." },
};

export function merchantOrderPresentation(
  status: MerchantOrderStatus,
  paymentState: MerchantOrderPaymentState,
): CustomerLifecyclePresentation {
  const primaryAction: CustomerPrimaryAction = paymentState === "payment_pending"
    ? "pay"
    : status === "paid"
      ? "cancel"
      : ["merchant_accepted", "ready", "assigned", "en_route_to_pickup", "at_store", "picked_up", "in_transit"].includes(status)
        ? "request_cancellation"
        : "none";
  return { ...orderCopy[status], primaryAction };
}

export function parcelPresentation(
  status: ParcelStatus,
  paymentStatus: ParcelDelivery["paymentStatus"],
  audience: CustomerParcelDelivery["audience"],
): CustomerLifecyclePresentation {
  const primaryAction: CustomerPrimaryAction = audience === "recipient"
    ? "none"
    : paymentStatus === "pending" || paymentStatus === "failed"
      ? "pay"
      : ["paid", "assigned", "en_route_to_pickup"].includes(status)
        ? "cancel"
        : "none";
  return { ...parcelCopy[status], primaryAction };
}

export function paymentStateLabel(state: MerchantOrderPaymentState) {
  return ({
    payment_pending: "Payment pending",
    paid: "Paid",
    not_collected: "Not charged",
    refund_pending: "Refund processing",
    refunded: "Refunded",
  } as const)[state];
}

export function parcelPaymentStateLabel(state: ParcelDelivery["paymentStatus"]) {
  return ({
    pending: "Payment pending",
    paid: "Paid",
    failed: "Payment failed",
    refund_pending: "Refund processing",
    refunded: "Refunded",
    cancelled: "Not charged",
  } as const)[state];
}
