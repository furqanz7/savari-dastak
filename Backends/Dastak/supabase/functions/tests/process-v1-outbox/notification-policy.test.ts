import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  guardedNotificationSender,
  offerExpiration,
} from "../../process-v1-outbox/notification-policy.ts";
import type { V1NotificationJob } from "../../process-v1-outbox/handler.ts";

const offer: V1NotificationJob = {
  deliveryId: "94000000-0000-4000-8000-000000000001",
  eventId: "94000000-0000-4000-8000-000000000002",
  notificationType: "rider.mission_offer",
  recipientAccountId: "94000000-0000-4000-8000-000000000003",
  deviceToken: "test-only",
  platform: "ios",
  title: "New delivery",
  body: "Review the offer",
  payload: {},
  attempt: 2,
};
const accepted = {
  succeeded: true,
  permanentTokenFailure: false,
  providerStatus: 200,
  providerResponse: "",
};

Deno.test("offer preflight suppresses expired/resolved claims before calling the provider", async () => {
  const calls: unknown[] = [];
  const sender = guardedNotificationSender(
    (name, args) => {
      calls.push([name, args]);
      return Promise.resolve({ deliver: false });
    },
    "worker",
    () => {
      throw new Error("Must never send obsolete offer");
    },
  );
  assertEquals((await sender(offer)).suppressed, true);
  assertEquals(calls, [["dastak_v1_prepare_notification_delivery", {
    p_delivery_id: offer.deliveryId,
    p_worker_id: "worker",
  }]]);
});

Deno.test("preflight failure or malformed deadline cannot fail open to a notification", async () => {
  for (const gate of [null, [], {}, { deliver: true }, { deliver: true, expiresAt: "bad" }]) {
    await assertRejects(() =>
      guardedNotificationSender(() => Promise.resolve(gate), "worker", () => {
        throw new Error("Should not send");
      })(offer)
    );
  }
  await assertRejects(
    () =>
      guardedNotificationSender(() => Promise.reject(new Error("read failed")), "worker", () => {
        throw new Error("Should not send");
      })(offer),
    Error,
    "read failed",
  );
});

Deno.test("preflight forwards exact deadline and preserves the original job identity", async () => {
  const expiresAt = "2026-10-15T16:00:00Z";
  const sender = guardedNotificationSender(
    () => Promise.resolve({ deliver: true, expiresAt }),
    "worker",
    (job) => {
      assertEquals(job, { ...offer, expiresAt });
      return Promise.resolve(accepted);
    },
  );
  assertEquals(await sender(offer), accepted);
});

Deno.test("non-offer alerts do not depend on the offer preflight service", async () => {
  const sender = guardedNotificationSender(
    () => {
      throw new Error("Offer guard must be isolated");
    },
    "worker",
    () => Promise.resolve(accepted),
  );
  assertEquals(await sender({ ...offer, notificationType: "rider.assigned" }), accepted);
  assertEquals(offerExpiration({ ...offer, notificationType: "customer.preparing" }), undefined);
});
