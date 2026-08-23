import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import {
  canonicalPayoutGatewayBody,
  PayoutGatewayClient,
  PayoutGatewayError,
  type PayoutGatewayRequest,
  payoutGatewaySignatureHeader,
  signPayoutGatewayBody,
} from "../../_shared/payout-gateway.ts";
import { RazorpayXApiError } from "../../_shared/razorpayx.ts";
import {
  handlePayoutGateway,
  type PayoutGatewayDependencies,
  type ReplayStore,
} from "../../../../infrastructure/razorpayx-payout-gateway/handler.ts";

const secret = "dastak-gateway-secret-with-32-bytes-minimum";
const now = new Date("2026-08-23T12:00:00.000Z");
const withdrawalId = "31000000-0000-4000-8000-000000000001";
const fundAccountReference = "fa_00000000000001";

Deno.test("gateway accepts a correctly signed canonical withdrawal and preserves its idempotency", async () => {
  let received: PayoutGatewayRequest | undefined;
  const response = await handlePayoutGateway(
    await signedRequest(payoutRequest()),
    dependencies({
      executeProviderPayout: async (request) => {
        received = request;
        return providerResult("processing");
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(received?.withdrawalId, withdrawalId);
  assertEquals(received?.idempotencyKey, withdrawalId);
  assertEquals(Object.keys(received ?? {}), [
    "withdrawalId",
    "amountPaise",
    "currency",
    "fundAccountReference",
    "idempotencyKey",
    "timestamp",
  ]);
});

Deno.test("bad signatures and signed-payload tampering never reach RazorpayX", async () => {
  let providerCalls = 0;
  const deps = dependencies({
    executeProviderPayout: async () => {
      providerCalls += 1;
      return providerResult("processing");
    },
  });
  const invalid = await handlePayoutGateway(
    requestWithBody(canonicalPayoutGatewayBody(payoutRequest()), "0".repeat(64)),
    deps,
  );
  assertEquals(invalid.status, 401);
  const originalBody = canonicalPayoutGatewayBody(payoutRequest());
  const signature = await signPayoutGatewayBody(secret, originalBody);
  const tampered = await handlePayoutGateway(
    requestWithBody(originalBody.replace('"amountPaise":1500', '"amountPaise":1600'), signature),
    deps,
  );
  assertEquals(tampered.status, 401);
  assertEquals(providerCalls, 0);
});

Deno.test("gateway rejects arbitrary paths and methods without becoming a provider proxy", async () => {
  let providerCalls = 0;
  const deps = dependencies({
    executeProviderPayout: async () => {
      providerCalls += 1;
      return providerResult("processing");
    },
  });
  assertEquals(
    (await handlePayoutGateway(
      new Request("https://payout-gateway.test/v1/refunds", { method: "POST" }),
      deps,
    )).status,
    404,
  );
  assertEquals(
    (await handlePayoutGateway(
      new Request("https://payout-gateway.test/v1/payouts", { method: "PATCH" }),
      deps,
    )).status,
    405,
  );
  assertEquals(providerCalls, 0);
});

Deno.test("expired signatures are rejected before provider execution", async () => {
  let called = false;
  const response = await handlePayoutGateway(
    await signedRequest(payoutRequest({ timestamp: "2026-08-23T11:57:59.999Z" })),
    dependencies({
      executeProviderPayout: async () => {
        called = true;
        return providerResult("processing");
      },
    }),
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error.code, "expired_request");
  assertEquals(called, false);
});

Deno.test("an exact replay is rejected while the provider executes only once", async () => {
  let calls = 0;
  const deps = dependencies({
    executeProviderPayout: async () => {
      calls += 1;
      return providerResult("processing");
    },
  });
  const first = await handlePayoutGateway(await signedRequest(payoutRequest()), deps);
  const second = await handlePayoutGateway(await signedRequest(payoutRequest()), deps);
  assertEquals(first.status, 200);
  assertEquals(second.status, 409);
  assertEquals((await second.json()).error, { code: "replayed_request", ambiguous: true });
  assertEquals(calls, 1);
});

Deno.test("Supabase gateway client signs the exact fixed contract", async () => {
  let observedBody = "";
  let observedSignature = "";
  const deps = dependencies();
  const client = new PayoutGatewayClient({
    baseUrl: "https://payout-gateway.test",
    secret,
    now: () => now,
  }, async (input, init) => {
    assertEquals(String(input), "https://payout-gateway.test/v1/payouts");
    observedBody = String(init?.body);
    observedSignature = new Headers(init?.headers).get(payoutGatewaySignatureHeader) ?? "";
    return await handlePayoutGateway(new Request(String(input), init), deps);
  });
  const result = await client.executePayout({
    withdrawalId,
    amountPaise: 1500,
    currency: "INR",
    fundAccountReference,
    idempotencyKey: withdrawalId,
  });
  assertEquals(result.providerPayoutReference, "pout_00000000000001");
  assertEquals(observedBody, canonicalPayoutGatewayBody(payoutRequest()));
  assertEquals(observedSignature.length, 64);
});

Deno.test("timeout after accepted payout retries with the same provider idempotency identity", async () => {
  const bodies: PayoutGatewayRequest[] = [];
  let attempts = 0;
  const times = [now, new Date(now.valueOf() + 1_000)];
  const client = new PayoutGatewayClient({
    baseUrl: "https://payout-gateway.test",
    secret,
    now: () => times.shift() ?? now,
  }, async (_input, init) => {
    attempts += 1;
    bodies.push(JSON.parse(String(init?.body)));
    if (attempts === 1) throw new TypeError("response lost after provider acceptance");
    return Response.json({ result: providerResult("processing") });
  });
  const input = {
    withdrawalId,
    amountPaise: 1500,
    currency: "INR" as const,
    fundAccountReference,
    idempotencyKey: withdrawalId,
  };
  const error = await assertRejects(() => client.executePayout(input), PayoutGatewayError);
  assertEquals(error.ambiguous, true);
  assertEquals((await client.executePayout(input)).status, "processing");
  assertEquals(bodies[0].idempotencyKey, withdrawalId);
  assertEquals(bodies[1].idempotencyKey, withdrawalId);
  assertEquals({ ...bodies[0], timestamp: undefined }, { ...bodies[1], timestamp: undefined });
});

Deno.test("malformed gateway success is ambiguous and cannot release reserved Royalty", async () => {
  const client = new PayoutGatewayClient({
    baseUrl: "https://payout-gateway.test",
    secret,
    now: () => now,
  }, async () => Response.json({ result: { status: "processed" } }));
  const error = await assertRejects(
    () =>
      client.executePayout({
        withdrawalId,
        amountPaise: 1500,
        fundAccountReference,
        idempotencyKey: withdrawalId,
      }),
    PayoutGatewayError,
  );
  assertEquals(error.code, "invalid_gateway_response");
  assertEquals(error.ambiguous, true);
});

Deno.test("provider failure and reversal remain explicit gateway results for ledger reconciliation", async () => {
  for (const status of ["failed", "reversed"] as const) {
    const client = new PayoutGatewayClient({
      baseUrl: "https://payout-gateway.test",
      secret,
      now: () => now,
    }, async () => Response.json({ result: providerResult(status) }));
    assertEquals(
      (await client.executePayout({
        withdrawalId,
        amountPaise: 1500,
        fundAccountReference,
        idempotencyKey: withdrawalId,
      })).status,
      status,
    );
  }
});

Deno.test("ambiguous provider errors remain ambiguous across the gateway boundary", async () => {
  const response = await handlePayoutGateway(
    await signedRequest(payoutRequest()),
    dependencies({
      executeProviderPayout: () =>
        Promise.reject(new RazorpayXApiError(0, true, "network_timeout")),
    }),
  );
  assertEquals(response.status, 502);
  assertEquals(await response.json(), {
    error: { code: "network_timeout", ambiguous: true },
  });
});

function dependencies(
  overrides: Partial<PayoutGatewayDependencies> = {},
): PayoutGatewayDependencies {
  return {
    secret,
    maxClockSkewMilliseconds: 120_000,
    replayStore: new MemoryReplayStore(() => now),
    executeProviderPayout: async () => providerResult("processing"),
    now: () => now,
    ...overrides,
  };
}

function payoutRequest(overrides: Partial<PayoutGatewayRequest> = {}): PayoutGatewayRequest {
  return {
    withdrawalId,
    amountPaise: 1500,
    currency: "INR",
    fundAccountReference,
    idempotencyKey: withdrawalId,
    timestamp: now.toISOString(),
    ...overrides,
  };
}

function providerResult(status: "processing" | "failed" | "reversed") {
  return {
    withdrawalId,
    providerPayoutReference: "pout_00000000000001",
    fundAccountReference,
    amountPaise: 1500,
    currency: "INR" as const,
    mode: "IMPS" as const,
    status,
    createdAt: now.toISOString(),
    statusDetails: {},
  };
}

async function signedRequest(body: PayoutGatewayRequest) {
  const canonical = canonicalPayoutGatewayBody(body);
  return requestWithBody(canonical, await signPayoutGatewayBody(secret, canonical));
}

function requestWithBody(body: string, signature: string) {
  return new Request("https://payout-gateway.test/v1/payouts", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      [payoutGatewaySignatureHeader]: signature,
    },
    body,
  });
}

class MemoryReplayStore implements ReplayStore {
  private readonly entries = new Map<string, number>();

  constructor(private readonly now: () => Date) {}

  claim(digest: string, expiresAt: Date) {
    const now = this.now().valueOf();
    if ((this.entries.get(digest) ?? 0) > now) return Promise.resolve(false);
    this.entries.set(digest, expiresAt.valueOf());
    return Promise.resolve(true);
  }
}
