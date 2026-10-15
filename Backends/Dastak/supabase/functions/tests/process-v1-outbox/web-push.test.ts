import { assertEquals } from "jsr:@std/assert";
import { createWebPushSender } from "../../process-v1-outbox/web-push.ts";
import type { V1NotificationJob } from "../../process-v1-outbox/handler.ts";

Deno.test("Web Push sends only safe customer notification fields", async () => {
  let configured: unknown;
  let request: unknown;
  const sender = createWebPushSender(configuration, {
    setVapidDetails: (subject, publicKey, privateKey) => {
      configured = { subject, publicKey, privateKey };
    },
    sendNotification: (subscription, payload, options) => {
      request = { subscription, payload: JSON.parse(String(payload ?? "{}")), options };
      return Promise.resolve({ statusCode: 201, body: "", headers: {} });
    },
  });

  const result = await sender(job());
  assertEquals(configured, configuration);
  assertEquals(result.succeeded, true);
  assertEquals((request as { payload: Record<string, unknown> }).payload, {
    title: "Your order is ready",
    body: "Follow its progress in Dastak.",
    payload: {
      entityType: "dastakV1Order",
      orderId: "94000000-0000-4000-8000-000000000004",
      eventId: "94000000-0000-4000-8000-000000000002",
      notificationType: "customer.ready",
    },
  });
});

Deno.test("Web Push classifies expired subscriptions without exposing endpoint details", async () => {
  const sender = createWebPushSender(configuration, {
    setVapidDetails: () => undefined,
    sendNotification: () => Promise.reject({ statusCode: 410, message: "secret endpoint" }),
  });
  const result = await sender(job());
  assertEquals(result.succeeded, false);
  assertEquals(result.permanentTokenFailure, true);
  assertEquals(result.providerResponse, "web push rejected (410)");
});

Deno.test("Web Push rejects malformed stored subscriptions permanently", async () => {
  const sender = createWebPushSender(configuration, {
    setVapidDetails: () => undefined,
    sendNotification: () => Promise.reject(new Error("must not be called")),
  });
  const result = await sender({ ...job(), deviceToken: "not-json" });
  assertEquals(result.providerStatus, 400);
  assertEquals(result.permanentTokenFailure, true);
});

const configuration = {
  subject: "mailto:notifications@dastak.example",
  publicKey: "public-key",
  privateKey: "private-key",
};

Deno.test("rider Web Push cannot outlive its offer or share another alert's topic", async () => {
  const options: Array<{ TTL?: number; topic?: string }> = [];
  let current = 1_800_000_000_000;
  const sender = createWebPushSender(configuration, {
    setVapidDetails: () => undefined,
    sendNotification: (_subscription, _payload, requestOptions) => {
      options.push(requestOptions ?? {});
      return Promise.resolve({ statusCode: 201, body: "", headers: {} });
    },
  }, () => current);
  const offer = {
    ...job(),
    notificationType: "rider.mission_offer",
    expiresAt: new Date(current + 20_000).toISOString(),
  };
  assertEquals((await sender(offer)).succeeded, true);
  assertEquals(options[0].TTL, 20);
  assertEquals(options[0].topic, offer.deliveryId.replaceAll("-", ""));
  const other = { ...job(), deliveryId: "94000000-0000-4000-8000-000000000005" };
  await sender(other);
  assertEquals(options[0].topic === options[1].topic, false);
  current += 20_000;
  assertEquals((await sender(offer)).suppressed, true);
  assertEquals(options.length, 2, "Expired retry never reaches Web Push either");
});

function job(): V1NotificationJob {
  return {
    deliveryId: "94000000-0000-4000-8000-000000000001",
    eventId: "94000000-0000-4000-8000-000000000002",
    notificationType: "customer.ready",
    recipientAccountId: "94000000-0000-4000-8000-000000000003",
    deviceToken: JSON.stringify({
      endpoint: "https://push.example.test/subscription/one",
      keys: { auth: "auth-key", p256dh: "p256dh-key" },
    }),
    platform: "web",
    title: "Your order is ready",
    body: "Follow its progress in Dastak.",
    payload: {
      entityType: "dastakV1Order",
      orderId: "94000000-0000-4000-8000-000000000004",
    },
    attempt: 1,
  };
}
