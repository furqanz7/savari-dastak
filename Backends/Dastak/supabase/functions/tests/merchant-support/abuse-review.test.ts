// Regression tests replacing the initial review's weakness characterizations.
import { deepStrictEqual as assertEquals } from "node:assert";
import { handleMerchantSupport, type SupportDependencies } from "../../merchant-support/handler.ts";
import { supportBulkhead } from "../../merchant-support/limits.ts";
const body = {
  operation: "create",
  ticketId: "11111111-1111-4111-8111-111111111111",
  requestId: "22222222-2222-4222-8222-222222222222",
  token: "a".repeat(64),
  subject: "Fixture review question",
  message: "Please help with this fixture question",
  consent: true,
  category: "OTHER",
};
const deps: SupportDependencies = {
  enabled: true,
  authenticate: () => Promise.resolve({ accountId: body.ticketId }),
  command: () => Promise.resolve({}),
};
function request(value: unknown, signal?: AbortSignal) {
  return new Request("https://local.test", {
    method: "POST",
    signal,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(value),
  });
}
Deno.test("incomplete body is cancelled at server deadline without DB work", async () => {
  let cancelled = false;
  let calls = 0;
  const payload = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode("{"));
    },
    cancel() {
      cancelled = true;
      return new Promise(() => {});
    },
  });
  const result = await handleMerchantSupport(
    new Request("https://local.test", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: payload,
    }),
    {
      ...deps,
      bodyDeadlineMs: 10,
      command: () => {
        calls++;
        return Promise.resolve({});
      },
    },
  );
  assertEquals(result.status, 400);
  assertEquals(cancelled, true);
  assertEquals(calls, 0);
});
for (const value of ["hello\u0000there", "hello\ud800there", "hello\udc00there"]) {
  Deno.test(`unsupported text rejected before DB: ${JSON.stringify(value)}`, async () => {
    let calls = 0;
    for (const field of ["message", "subject"]) {
      const result = await handleMerchantSupport(request({ ...body, [field]: value }), {
        ...deps,
        command: () => {
          calls++;
          return Promise.resolve({});
        },
      });
      assertEquals(result.status, 400);
    }
    assertEquals(calls, 0);
  });
}
Deno.test("valid emoji and Urdu text are retained", async () => {
  let received = "";
  const result = await handleMerchantSupport(request({ ...body, message: "دستک مدد please 🛍️" }), {
    ...deps,
    command: (_actor, input) => {
      received = String(input.message);
      return Promise.resolve({});
    },
  });
  assertEquals(result.status, 201);
  assertEquals(received, "دستک مدد please 🛍️");
});
Deno.test("stuck DB dependency gets deadline, abort and safe uncertain response", async () => {
  let aborted = false;
  const result = await handleMerchantSupport(request(body), {
    ...deps,
    operationDeadlineMs: 10,
    command: (_actor, _input, signal) => {
      signal!.addEventListener("abort", () => aborted = true);
      return new Promise(() => {});
    },
  });
  assertEquals(result.status, 503);
  assertEquals(aborted, true);
});
Deno.test("stuck auth never invokes the command", async () => {
  let calls = 0;
  const input = request({ operation: "adminList" });
  input.headers.set("Authorization", "Bearer fixture");
  const result = await handleMerchantSupport(input, {
    ...deps,
    operationDeadlineMs: 10,
    authenticate: () => new Promise(() => {}),
    command: () => {
      calls++;
      return Promise.resolve({});
    },
  });
  assertEquals(result.status, 503);
  assertEquals(calls, 0);
});
Deno.test("caller abort before entry never invokes DB", async () => {
  const controller = new AbortController();
  controller.abort();
  let calls = 0;
  const result = await handleMerchantSupport(request(body, controller.signal), {
    ...deps,
    command: () => {
      calls++;
      return Promise.resolve({});
    },
  });
  assertEquals(result.status, 400);
  assertEquals(calls, 0);
});
Deno.test("bounded per-worker burst rejects before DB and refills without caller data", async () => {
  let time = 0;
  const enter = supportBulkhead(() => time);
  let calls = 0;
  const configured = {
    ...deps,
    enter,
    command: () => {
      calls++;
      return Promise.reject(Error("support_not_found"));
    },
  };
  for (let i = 0; i < 30; i++) {
    assertEquals(
      (await handleMerchantSupport(request({ ...body, operation: "read" }), configured)).status,
      404,
    );
  }
  assertEquals((await handleMerchantSupport(request(body), configured)).status, 429);
  assertEquals(calls, 30);
  time = 1000;
  assertEquals(
    (await handleMerchantSupport(request({ ...body, operation: "read" }), configured)).status,
    404,
  );
});
Deno.test("concurrency bulkhead releases exactly once", () => {
  const enter = supportBulkhead(() => 0);
  const leases = Array.from({ length: 8 }, () => enter()!);
  assertEquals(enter(), undefined);
  leases[0]();
  leases[0]();
  assertEquals(typeof enter(), "function");
  assertEquals(enter(), undefined);
});
Deno.test("lock contention is safe and explicit, not raw database output", async () => {
  const result = await handleMerchantSupport(request(body), {
    ...deps,
    command: () => Promise.reject(Error("support_busy")),
  });
  assertEquals(result.status, 409);
  assertEquals(await result.json(), { error: { code: "support_busy" } });
});
