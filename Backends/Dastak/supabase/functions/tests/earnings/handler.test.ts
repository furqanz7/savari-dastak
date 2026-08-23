import { assertEquals } from "jsr:@std/assert";
import { type EarningsDependencies, handleEarnings } from "../../earnings/handler.ts";

const accountId = "10000000-0000-4000-8000-000000000001";
const subjectId = "20000000-0000-4000-8000-000000000001";
const request = (body: unknown, authorization = "Bearer valid", idempotencyKey?: string) =>
  new Request("https://example.test/earnings", {
    method: "POST",
    headers: {
      authorization,
      "content-type": "application/json",
      ...(idempotencyKey ? { "x-idempotency-key": idempotencyKey } : {}),
    },
    body: JSON.stringify(body),
  });

const dependencies = (
  overrides: Partial<EarningsDependencies> = {},
): EarningsDependencies => ({
  authenticateBearer: async () => ({ accountId, accessToken: "valid" }),
  callRPC: async () => [{
    response_body: {
      currency: "INR",
      completedPaise: 100,
      pendingPaise: 20,
      thisWeekPaise: 100,
    },
    response_status: 200,
  }],
  ...overrides,
});

Deno.test("earnings accepts browser CORS preflight", async () => {
  const response = await handleEarnings(
    new Request("https://example.test/earnings", { method: "OPTIONS" }),
    dependencies(),
  );
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("earnings rejects unauthenticated callers", async () => {
  let called = false;
  const response = await handleEarnings(
    request({ operation: "merchantRoyaltySnapshot" }, ""),
    dependencies({
      authenticateBearer: async () => Promise.reject(new Error("invalid")),
      callRPC: async () => {
        called = true;
        return undefined;
      },
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(called, false);
});

Deno.test("earnings preserves the legacy delivery snapshot contract", async () => {
  let call: [string, Record<string, unknown>] | undefined;
  const response = await handleEarnings(
    request({ operation: "deliveryPartnerSnapshot" }),
    dependencies({
      callRPC: async (rpc, args) => {
        call = [rpc, args];
        return [{ response_body: { currency: "INR" }, response_status: 200 }];
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(call, ["get_dastak_delivery_earnings", { p_account_id: accountId }]);
});

Deno.test("merchant Royalty snapshot uses authenticated account ownership", async () => {
  let call: [string, Record<string, unknown>] | undefined;
  const response = await handleEarnings(
    request({ operation: "merchantRoyaltySnapshot" }),
    dependencies({
      callRPC: async (rpc, args) => {
        call = [rpc, args];
        return [{
          response_body: { currency: "INR", subjects: [] },
          response_status: 200,
        }];
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(call, ["dastak_v1_get_royalty_snapshot", {
    p_account_id: accountId,
    p_kind: "MERCHANT",
  }]);
});

Deno.test("withdrawal forwards subject, amount, and idempotency key", async () => {
  let call: [string, Record<string, unknown>] | undefined;
  const response = await handleEarnings(
    request(
      {
        operation: "requestRoyaltyWithdrawal",
        subjectType: "MERCHANT_ORGANIZATION",
        subjectId,
        amountPaise: 1500,
      },
      "Bearer valid",
      "withdraw-1",
    ),
    dependencies({
      callRPC: async (rpc, args) => {
        call = [rpc, args];
        return { withdrawalId: subjectId, status: "REQUESTED", amountPaise: 1500 };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(call, ["dastak_v1_request_royalty_withdrawal", {
    p_account_id: accountId,
    p_subject_type: "MERCHANT_ORGANIZATION",
    p_subject_id: subjectId,
    p_amount_paise: 1500,
    p_idempotency_key: "withdraw-1",
  }]);
});

Deno.test("withdrawal rejects malformed requests before privileged RPC", async () => {
  let called = false;
  const response = await handleEarnings(
    request({
      operation: "requestRoyaltyWithdrawal",
      subjectType: "RIDER",
      subjectId: "not-a-uuid",
      amountPaise: -1,
    }),
    dependencies({
      callRPC: async () => {
        called = true;
        return undefined;
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(called, false);
});

Deno.test("withdrawal reports missing destination without leaking internals", async () => {
  const response = await handleEarnings(
    request(
      {
        operation: "requestRoyaltyWithdrawal",
        subjectType: "RIDER",
        subjectId,
        amountPaise: 1500,
      },
      "Bearer valid",
      "withdraw-2",
    ),
    dependencies({
      callRPC: async () => Promise.reject(new Error("PAYOUT_DESTINATION_REQUIRED: private")),
    }),
  );
  assertEquals(response.status, 409);
  assertEquals(await response.json(), {
    error: {
      code: "payout_destination_required",
      message: "A payout destination must be registered before withdrawing.",
    },
  });
});

Deno.test("earnings rejects unsupported operations", async () => {
  const response = await handleEarnings(
    request({ operation: "ownerSnapshot" }),
    dependencies(),
  );
  assertEquals(response.status, 400);
});

Deno.test("earnings maps invalid RPC responses without leaking details", async () => {
  const response = await handleEarnings(
    request({ operation: "merchantRoyaltySnapshot" }),
    dependencies({ callRPC: async () => ({ response_status: "200" }) }),
  );
  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error: {
      code: "earnings_unavailable",
      message: "Royalty is temporarily unavailable.",
    },
  });
});
