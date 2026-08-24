import { assertEquals } from "jsr:@std/assert@1";
import { handleAccountSessions } from "../../account-sessions/handler.ts";

const actor = {
  accountId: "11111111-1111-4111-8111-111111111111",
  sessionId: "22222222-2222-4222-8222-222222222222",
  accessToken: "access-token",
};
type Dependencies = Parameters<typeof handleAccountSessions>[1];

Deno.test("account sessions registers the current device before returning a snapshot", async () => {
  const calls: string[] = [];
  const response = await handleAccountSessions(
    request({
      operation: "snapshot",
      deviceName: "iPhone",
      platform: "ios",
      appName: "Customer",
    }),
    dependencies({
      touch: async (_actor, metadata) => {
        calls.push(`touch:${metadata.deviceName}`);
        return ok({ registered: true });
      },
      snapshot: async () => {
        calls.push("snapshot");
        return ok({ sessions: [] });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, ["touch:iPhone", "snapshot"]);
});

Deno.test("account sessions revokes auth sessions before hiding other devices", async () => {
  const calls: string[] = [];
  const response = await handleAccountSessions(
    request({
      operation: "signOutOthers",
      deviceName: "Safari on Mac",
      platform: "web",
      appName: "Merchant",
    }),
    dependencies({
      revokeOthers: async (token) => {
        calls.push(`revoke:${token}`);
      },
      endOthers: async () => {
        calls.push("endOthers");
        return ok({ ended: true });
      },
      snapshot: async () => {
        calls.push("snapshot");
        return ok({ sessions: [] });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, ["revoke:access-token", "endOthers", "snapshot"]);
});

Deno.test("account sessions can close the current registry entry without device metadata", async () => {
  let ended = "";
  const response = await handleAccountSessions(
    request({ operation: "endCurrent" }),
    dependencies({
      endCurrent: async (value) => {
        ended = value.sessionId;
        return ok({ ended: true });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(ended, actor.sessionId);
});

Deno.test("account sessions revokes only the requested non-current session", async () => {
  const target = "33333333-3333-4333-8333-333333333333";
  let revoked = "";
  const response = await handleAccountSessions(
    request({ operation: "revoke", sessionId: target }),
    dependencies({
      revokeOne: async (_actor, value) => {
        revoked = value;
        return ok({ sessions: [] });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(revoked, target);
});

Deno.test("account sessions rejects malformed revoke targets", async () => {
  const response = await handleAccountSessions(
    request({ operation: "revoke", sessionId: "not-a-session" }),
    dependencies(),
  );
  assertEquals(response.status, 400);
});

Deno.test("account sessions rejects unrecognized metadata", async () => {
  const response = await handleAccountSessions(
    request({
      operation: "snapshot",
      deviceName: "Browser",
      platform: "android",
      appName: "Customer",
    }),
    dependencies(),
  );
  assertEquals(response.status, 400);
});

function request(body: unknown) {
  return new Request("https://example.test/functions/v1/account-sessions", {
    method: "POST",
    headers: { authorization: "Bearer token", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function dependencies(overrides: Partial<Dependencies> = {}): Dependencies {
  return {
    authenticateBearer: async () => actor,
    touch: async () => ok({ registered: true }),
    snapshot: async () => ok({ sessions: [] }),
    revokeOthers: async () => undefined,
    endOthers: async () => ok({ ended: true }),
    endCurrent: async () => ok({ ended: true }),
    revokeOne: async () => ok({ sessions: [] }),
    ...overrides,
  };
}

function ok(responseBody: unknown) {
  return { responseBody, responseStatus: 200 };
}
