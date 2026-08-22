import { assertEquals } from "jsr:@std/assert";
import { exportPKCS8, generateKeyPair } from "npm:jose@5";
import { createApnsSender } from "../../process-v1-outbox/apns.ts";
import type { V1NotificationJob } from "../../process-v1-outbox/handler.ts";

Deno.test("APNs request carries only the safe V1 order route and deterministic delivery id", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const pem = await exportPKCS8(privateKey);
  let request: Request | undefined;
  const sender = createApnsSender({
    environment: "sandbox",
    teamId: "TEAM123",
    keyId: "KEY123",
    bundleId: "com.dastak.customer",
    privateKey: pem,
  }, (input, init) => {
    request = new Request(input, init);
    return Promise.resolve(new Response("", { status: 200 }));
  });
  const result = await sender(job());
  const payload = await request?.json() as Record<string, unknown>;
  assertEquals(result.succeeded, true);
  assertEquals(request?.headers.get("apns-id"), job().deliveryId);
  assertEquals(payload.entityType, "dastakV1Order");
  assertEquals(payload.orderId, job().payload.orderId);
  assertEquals("branchId" in payload, false);
});

Deno.test("APNs invalid device token is classified as permanent", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const sender = createApnsSender({
    environment: "production",
    teamId: "TEAM123",
    keyId: "KEY123",
    bundleId: "com.dastak.customer",
    privateKey: await exportPKCS8(privateKey),
  }, () => Promise.resolve(new Response('{"reason":"BadDeviceToken"}', { status: 400 })));
  const result = await sender(job());
  assertEquals(result.succeeded, false);
  assertEquals(result.permanentTokenFailure, true);
});

Deno.test("APNs provider token is reused briefly and refreshed before Apple expiry", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  let currentTime = 1_800_000_000_000;
  const authorizations: string[] = [];
  const sender = createApnsSender({
    environment: "production",
    teamId: "TEAM123",
    keyId: "KEY123",
    bundleId: "com.dastak.customer",
    privateKey: await exportPKCS8(privateKey),
  }, (_input, init) => {
    authorizations.push(new Headers(init?.headers).get("authorization") ?? "");
    return Promise.resolve(new Response("", { status: 200 }));
  }, () => currentTime);

  await sender(job());
  currentTime += 49 * 60 * 1_000;
  await sender(job());
  currentTime += 60 * 1_000;
  await sender(job());

  assertEquals(authorizations[0], authorizations[1]);
  assertEquals(authorizations[0] === authorizations[2], false);
});

function job(): V1NotificationJob {
  return {
    deliveryId: "94000000-0000-4000-8000-000000000001",
    eventId: "94000000-0000-4000-8000-000000000002",
    notificationType: "customer.out_for_delivery",
    recipientAccountId: "94000000-0000-4000-8000-000000000003",
    deviceToken: "device-token",
    platform: "ios",
    title: "Your order is on the way",
    body: "Keep your code ready.",
    payload: {
      entityType: "dastakV1Order",
      entityId: "94000000-0000-4000-8000-000000000004",
      orderId: "94000000-0000-4000-8000-000000000004",
      eventType: "ORDER_OUT_FOR_DELIVERY",
    },
    attempt: 1,
  };
}
