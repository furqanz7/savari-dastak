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

Deno.test("APNs invalid device token with an explicit environment is permanent", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const sender = createApnsSender({
    environment: "production",
    teamId: "TEAM123",
    keyId: "KEY123",
    bundleId: "com.dastak.customer",
    privateKey: await exportPKCS8(privateKey),
  }, () => Promise.resolve(new Response('{"reason":"BadDeviceToken"}', { status: 400 })));
  const result = await sender({ ...job(), apnsEnvironment: "production" });
  assertEquals(result.succeeded, false);
  assertEquals(result.permanentTokenFailure, true);
});

Deno.test("APNs routes each application and environment independently", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const requests: Request[] = [];
  const sender = createApnsSender({
    environment: "sandbox",
    teamId: "TEAM123",
    keyId: "KEY123",
    bundleId: "com.dastak.app",
    privateKey: await exportPKCS8(privateKey),
  }, (input, init) => {
    requests.push(new Request(input, init));
    return Promise.resolve(new Response("", { status: 200 }));
  });
  await sender({ ...job(), applicationId: "com.dastak.merchant", apnsEnvironment: "production" });
  await sender({ ...job(), applicationId: "com.dastak.app", apnsEnvironment: "sandbox" });
  await sender(job());
  assertEquals(requests.map((r) => r.headers.get("apns-topic")), [
    "com.dastak.merchant",
    "com.dastak.app",
    "com.dastak.app",
  ]);
  assertEquals(requests.map((r) => new URL(r.url).hostname), [
    "api.push.apple.com",
    "api.sandbox.push.apple.com",
    "api.sandbox.push.apple.com",
  ]);
});

Deno.test("topic mismatch and unknown legacy environment do not retire a token", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const config = {
    environment: "production" as const,
    teamId: "TEAM123",
    keyId: "KEY123",
    bundleId: "com.dastak.app",
    privateKey: await exportPKCS8(privateKey),
  };
  for (const reason of ["DeviceTokenNotForTopic", "BadDeviceToken"]) {
    const sender = createApnsSender(config, () =>
      Promise.resolve(
        new Response(JSON.stringify({ reason }), { status: 400 }),
      ));
    assertEquals((await sender(job())).permanentTokenFailure, false);
    if (reason === "DeviceTokenNotForTopic") {
      assertEquals(
        (await sender({ ...job(), apnsEnvironment: "production" })).permanentTokenFailure,
        false,
      );
    }
  }
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
