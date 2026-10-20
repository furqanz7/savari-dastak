import { assertEquals, assertMatch } from "jsr:@std/assert";
import { handleMerchantSupport, type SupportDependencies } from "../../merchant-support/handler.ts";

const id = "11111111-1111-4111-8111-111111111111";
const token = "a".repeat(64);
const create = {
  operation: "create",
  ticketId: id,
  requestId: id,
  token,
  subject: "Cannot sign in",
  message: "Please help with my store access.",
  category: "ACCESS",
  consent: true,
};
const request = (body: unknown, headers: Record<string, string> = {}) =>
  new Request("https://local.test", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
function deps(overrides: Partial<SupportDependencies> = {}): SupportDependencies {
  return {
    enabled: true,
    authenticate: async () => ({ accountId: id }),
    command: async (_actor, input) => input,
    ...overrides,
  };
}
Deno.test("support disabled by default is fail closed", async () => {
  assertEquals(
    (await handleMerchantSupport(
      request(create),
      deps({
        enabled: false,
        command: () => {
          throw Error("should not call");
        },
      }),
    )).status,
    503,
  );
});
Deno.test("support preflight and methods", async () => {
  assertEquals(
    (await handleMerchantSupport(new Request("https://local.test", { method: "OPTIONS" }), deps()))
      .status,
    204,
  );
  assertEquals(
    (await handleMerchantSupport(new Request("https://local.test"), deps())).status,
    405,
  );
});
Deno.test("support hashes capability and strips actor, credentials and unexpected fields", async () => {
  let actor: unknown;
  let command: Record<string, unknown> = {};
  const result = await handleMerchantSupport(
    request({ ...create, actor: "pretend-admin", tokenHash: "pretend", extra: "secret" }),
    deps({
      command: async (a, b) => {
        actor = a;
        command = b;
        return {};
      },
    }),
  );
  assertEquals(result.status, 201);
  assertEquals(actor, null);
  assertMatch(command.tokenHash as string, /^[a-f0-9]{64}$/);
  assertEquals(command.tokenHash === token, false);
  assertEquals(command.token, undefined);
  assertEquals(command.actor, undefined);
  assertEquals(command.extra, undefined);
  assertEquals(result.headers.get("cache-control"), "no-store");
});
for (
  const [label, patch] of [
    ["consent", { consent: false }],
    ["honeypot", { website: "bot.test" }],
    ["subject", { subject: "x" }],
    ["category", { category: "ADMIN" }],
    ["message", { message: "x" }],
    ["request ID", { requestId: "x" }],
  ] as const
) {
  Deno.test(`support rejects invalid ${label}`, async () => {
    assertEquals(
      (await handleMerchantSupport(request({ ...create, ...patch }), deps())).status,
      400,
    );
  });
}
Deno.test("support invalid and missing capabilities are generic not found", async () => {
  for (const value of [undefined, "short", "A".repeat(64)]) {
    assertEquals(
      (await handleMerchantSupport(request({ ...create, token: value }), deps())).status,
      404,
    );
  }
});
Deno.test("support actual oversized streamed body rejected", async () => {
  assertEquals(
    (await handleMerchantSupport(request({ ...create, message: "x".repeat(13_000) }), deps()))
      .status,
    413,
  );
});
Deno.test("support malformed JSON and non-JSON rejected", async () => {
  assertEquals(
    (await handleMerchantSupport(
      new Request("https://local.test", { method: "POST", body: "{" }),
      deps(),
    )).status,
    400,
  );
  assertEquals((await handleMerchantSupport(request([]), deps())).status, 400);
});
Deno.test("support Admin rejects absent and expired bearer", async () => {
  assertEquals(
    (await handleMerchantSupport(request({ operation: "adminList" }), deps())).status,
    401,
  );
  assertEquals(
    (await handleMerchantSupport(
      request({ operation: "adminList" }, { authorization: "Bearer invalid" }),
      deps({
        authenticate: async () => {
          throw Error("expired");
        },
      }),
    )).status,
    401,
  );
});
Deno.test("support derives Admin actor from verified session only", async () => {
  let actor: unknown;
  const result = await handleMerchantSupport(
    request({ operation: "adminList", actor: "forged" }, { authorization: "Bearer actual" }),
    deps({
      command: async (a) => {
        actor = a;
        return {};
      },
    }),
  );
  assertEquals(result.status, 200);
  assertEquals(actor, id);
});
Deno.test("support replies require positive expected version", async () => {
  for (const version of [undefined, 0, -1, 1.1, "1"]) {
    assertEquals(
      (await handleMerchantSupport(request({ ...create, operation: "reply", version }), deps()))
        .status,
      400,
    );
  }
});
Deno.test("support cursor validation rejects incomplete and invalid paging", async () => {
  assertEquals(
    (await handleMerchantSupport(
      request({ operation: "adminList", cursorId: id }, { authorization: "Bearer actual" }),
      deps(),
    )).status,
    400,
  );
});
for (
  const [code, status] of Object.entries({
    support_forbidden: 403,
    support_not_found: 404,
    support_stale: 409,
    support_conflict: 409,
    support_rate_limited: 429,
    support_thread_full: 409,
    support_invalid: 400,
    "database-secret-details": 503,
  })
) {
  Deno.test(`support safely maps ${code}`, async () => {
    const result = await handleMerchantSupport(
      request(create),
      deps({
        command: async () => {
          throw Error(code);
        },
      }),
    );
    assertEquals(result.status, status);
    assertEquals(JSON.stringify(await result.json()).includes("database-secret-details"), false);
  });
}
