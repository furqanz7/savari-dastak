export type NotificationQueueEvent = {
  id: string;
  table: "dastak_order_notification_queue" | "dastak_parcel_notification_queue";
  entityType: "merchantOrder" | "parcel";
  entityId: string;
  accountId: string;
  status: string;
  paymentState: string;
  attempts: number;
  createdAt: string;
};

export function notificationPayload(event: NotificationQueueEvent) {
  return {
    entityType: event.entityType,
    entityId: event.entityId,
    ...(event.entityType === "parcel" ? { parcelId: event.entityId } : { orderId: event.entityId }),
  };
}

export function notificationCopy(event: NotificationQueueEvent) {
  const noun = event.entityType === "parcel" ? "Delivery" : "Order";
  const title = event.paymentState === "paid" ? "Payment confirmed" : `${noun} update`;
  if (event.paymentState === "refund_pending") {
    return { title: "Refund processing", body: "Your refund is being processed." };
  }
  if (event.paymentState === "refunded") {
    return { title: "Refund completed", body: "Your refund has been completed." };
  }

  const body = event.entityType === "parcel"
    ? parcelStatusMessage(event.status)
    : orderStatusMessage(event.status);
  return { title, body };
}

function orderStatusMessage(status: string) {
  switch (status) {
    case "paid":
      return "Your order is waiting for the store.";
    case "merchant_accepted":
      return "The store accepted your order.";
    case "ready":
      return "Your order is ready for pickup.";
    case "assigned":
      return "A delivery partner was assigned.";
    case "en_route_to_pickup":
      return "Your delivery partner is heading to the store.";
    case "at_store":
      return "Your delivery partner reached the store.";
    case "picked_up":
    case "in_transit":
      return "Your order is on the way.";
    case "delivered":
      return "Your order was delivered.";
    case "cancelled":
      return "Your order was cancelled.";
    case "returning_to_merchant":
      return "Your order is being returned to the store.";
    default:
      return "Your order status changed.";
  }
}

function parcelStatusMessage(status: string) {
  switch (status) {
    case "paid":
      return "Dastak is finding a delivery partner.";
    case "assigned":
      return "A delivery partner was assigned.";
    case "en_route_to_pickup":
      return "Your delivery partner is heading to pickup.";
    case "picked_up":
      return "Your parcel was collected.";
    case "in_transit":
      return "Your parcel is on the way.";
    case "delivered":
      return "Your parcel was delivered.";
    case "cancelled":
      return "Your parcel delivery was cancelled.";
    default:
      return "Your parcel delivery status changed.";
  }
}
