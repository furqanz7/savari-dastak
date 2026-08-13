import { assertEquals } from "jsr:@std/assert@1";
import {
  notificationCopy,
  notificationPayload,
  type NotificationQueueEvent,
} from "../../process-order-notification-queue/notification.ts";

const base: NotificationQueueEvent = {
  id: "1",
  table: "dastak_parcel_notification_queue",
  entityType: "parcel",
  entityId: "11111111-1111-4111-8111-111111111111",
  accountId: "22222222-2222-4222-8222-222222222222",
  status: "in_transit",
  paymentState: "paid",
  attempts: 0,
  createdAt: "2026-08-13T10:00:00Z",
};

Deno.test("parcel notification deep-links to the exact parcel", () => {
  assertEquals(notificationPayload(base), {
    entityType: "parcel",
    entityId: base.entityId,
    parcelId: base.entityId,
  });
  assertEquals(notificationCopy(base).body, "Your parcel is on the way.");
});

Deno.test("merchant notification deep-links to the exact order", () => {
  const order: NotificationQueueEvent = {
    ...base,
    table: "dastak_order_notification_queue",
    entityType: "merchantOrder",
    status: "delivered",
  };
  assertEquals(notificationPayload(order), {
    entityType: "merchantOrder",
    entityId: order.entityId,
    orderId: order.entityId,
  });
  assertEquals(notificationCopy(order).body, "Your order was delivered.");
});
