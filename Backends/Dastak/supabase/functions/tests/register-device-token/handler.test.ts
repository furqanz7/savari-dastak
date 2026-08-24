import { assertEquals } from "jsr:@std/assert";
import {
  handleRegisterDeviceToken,
  type RegisterDeviceTokenDependencies,
} from "../../register-device-token/handler.ts";

const subscription = JSON.stringify({
  endpoint: "https://push.example.test/subscriptions/customer-one",
  expirationTime: null,
  keys: { auth: "auth-key", p256dh: "p256dh-key" },
});

Deno.test("device token registration accepts an authenticated Web Push subscription", async () => {
  let registered: unknown;
  const response = await handleRegisterDeviceToken(
    request({ token: subscription, platform: "web" }),
    dependencies({
      upsertToken: (accountId, token, platform) => {
        registered = { accountId, token, platform };
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(registered, { accountId: "account-one", token: subscription, platform: "web" });
});

Deno.test("device token registration rejects malformed or insecure Web Push subscriptions", async () => {
  for (
    const token of [
      "not-json",
      JSON.stringify({ endpoint: "http://push.example.test", keys: { auth: "a", p256dh: "b" } }),
      JSON.stringify({ endpoint: "https://push.example.test", keys: { auth: "a" } }),
    ]
  ) {
    const response = await handleRegisterDeviceToken(
      request({ token, platform: "web" }),
      dependencies(),
    );
    assertEquals(response.status, 400);
  }
});

Deno.test("device token registration rejects useful work without authentication", async () => {
  const response = await handleRegisterDeviceToken(
    new Request("https://example.test", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: subscription, platform: "web" }),
    }),
    dependencies(),
  );
  assertEquals(response.status, 401);
});

function request(body: unknown) {
  return new Request("https://example.test", {
    method: "POST",
    headers: { authorization: "Bearer token", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function dependencies(
  overrides: Partial<RegisterDeviceTokenDependencies> = {},
): RegisterDeviceTokenDependencies {
  return {
    authenticateBearer: () => Promise.resolve({ accountId: "account-one" }),
    upsertToken: () => Promise.resolve(),
    ...overrides,
  };
}
