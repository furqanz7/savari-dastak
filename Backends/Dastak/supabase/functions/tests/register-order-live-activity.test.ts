import { assertEquals } from "jsr:@std/assert@1";
import { handleRegistration } from "../register-order-live-activity/handler.ts";
const input = {
  orderId: "11111111-1111-1111-1111-111111111111",
  activityId: "activity",
  token: "a".repeat(64),
  environment: "sandbox",
};
const request = (body: unknown, authorized = true) =>
  new Request("https://test/register", {
    method: "POST",
    headers: authorized ? { authorization: "Bearer token" } : {},
    body: JSON.stringify(body),
  });
Deno.test("registration binds verified actor and session, ignores spoofed account", async () => {
  let received;
  const response = await handleRegistration(request({ ...input, accountId: "attacker" }), {
    authenticate: () => Promise.resolve({ accountId: "owner", sessionId: "session" }),
    register: (actor) => {
      received = actor;
      return Promise.resolve();
    },
  });
  assertEquals(response.status, 200);
  assertEquals(received, { accountId: "owner", sessionId: "session" });
});
Deno.test("unauthorized, malformed and non-owned orders cannot register", async () => {
  const dependencies = {
    authenticate: () => Promise.resolve({ accountId: "owner", sessionId: "session" }),
    register: () => Promise.reject(new Error("not owned")),
  };
  assertEquals((await handleRegistration(request(input, false), dependencies)).status, 401);
  assertEquals(
    (await handleRegistration(request({ ...input, token: "bad" }), dependencies)).status,
    400,
  );
  assertEquals((await handleRegistration(request(input), dependencies)).status, 403);
});
