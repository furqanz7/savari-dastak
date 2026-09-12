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
  registerPayoutDestination: async () => ({
    destinationId: subjectId,
    type: "BANK_ACCOUNT",
    displayLabel: "Bank account •••• 1234",
  }),
  executeWithdrawal: async (_actorId, withdrawalId) => ({
    withdrawalId,
    status: "PROCESSING",
    providerStatus: "PENDING",
  }),
  payoutAvailability: () => ({
    destinationRegistrationAvailable: true,
    withdrawalExecutionAvailable: true,
  }),
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
  assertEquals((await response.json()).payoutAvailability, {
    destinationRegistrationAvailable: true,
    withdrawalExecutionAvailable: true,
  });
});

Deno.test("withdrawal reserves in Dastak then executes the same withdrawal externally", async () => {
  let call: [string, Record<string, unknown>] | undefined;
  let execution: [string, string, number] | undefined;
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
        return {
          withdrawalId: subjectId,
          status: "REQUESTED",
          amountPaise: 1500,
          version: 1,
        };
      },
      executeWithdrawal: async (actor, withdrawalId, version) => {
        execution = [actor, withdrawalId, version];
        return { withdrawalId, status: "PROCESSING", providerStatus: "queued" };
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
  assertEquals(execution, [accountId, subjectId, 1]);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    withdrawalId: subjectId,
    status: "PROCESSING",
    amountPaise: 1500,
    version: 1,
    providerStatus: "queued",
  });
});

Deno.test("withdrawal keeps the reservation and exposes retryable reconciliation on provider outage", async () => {
  const response = await handleEarnings(
    request(
      {
        operation: "requestRoyaltyWithdrawal",
        subjectType: "RIDER",
        subjectId,
        amountPaise: 1500,
      },
      "Bearer valid",
      "withdraw-provider-outage",
    ),
    dependencies({
      callRPC: async () => ({
        withdrawalId: subjectId,
        status: "REQUESTED",
        amountPaise: 1500,
        version: 1,
      }),
      executeWithdrawal: async () => Promise.reject(new Error("provider unavailable")),
    }),
  );
  assertEquals(response.status, 202);
  assertEquals(await response.json(), {
    withdrawalId: subjectId,
    status: "REQUESTED",
    amountPaise: 1500,
    version: 1,
    providerProcessingDeferred: true,
    reconciliationState: "RETRYABLE",
  });
});

Deno.test("bank payout registration confirms the account and forwards only authenticated subject input", async () => {
  let registration: unknown;
  const response = await handleEarnings(
    request({
      operation: "registerRoyaltyPayoutDestination",
      subjectType: "MERCHANT_ORGANIZATION",
      subjectId,
      destinationType: "BANK_ACCOUNT",
      holderName: "Dastak Store",
      accountNumber: "123456789012",
      confirmAccountNumber: "123456789012",
      ifsc: "HDFC0001234",
    }),
    dependencies({
      registerPayoutDestination: async (actor, input) => {
        registration = { actor, input };
        return { destinationId: subjectId, displayLabel: "Bank account •••• 9012" };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(registration, {
    actor: accountId,
    input: {
      subjectType: "MERCHANT_ORGANIZATION",
      subjectId,
      destination: {
        type: "BANK_ACCOUNT",
        holderName: "Dastak Store",
        accountNumber: "123456789012",
        ifsc: "HDFC0001234",
      },
    },
  });
});

Deno.test("UPI payout registration validates and normalizes the VPA", async () => {
  let registration: unknown;
  const response = await handleEarnings(
    request({
      operation: "registerRoyaltyPayoutDestination",
      subjectType: "RIDER",
      subjectId,
      destinationType: "UPI",
      holderName: "Dastak Rider",
      vpa: "Rider.Name@OKAXIS",
    }),
    dependencies({
      registerPayoutDestination: async (actor, input) => {
        registration = { actor, input };
        return { destinationId: subjectId, displayLabel: "UPI • ri***@okaxis" };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(registration, {
    actor: accountId,
    input: {
      subjectType: "RIDER",
      subjectId,
      destination: {
        type: "UPI",
        holderName: "Dastak Rider",
        vpa: "rider.name@okaxis",
      },
    },
  });
});

Deno.test("payout destination registration rejects mismatched bank confirmation", async () => {
  let called = false;
  const response = await handleEarnings(
    request({
      operation: "registerRoyaltyPayoutDestination",
      subjectType: "RIDER",
      subjectId,
      destinationType: "BANK_ACCOUNT",
      holderName: "Dastak Rider",
      accountNumber: "123456789012",
      confirmAccountNumber: "123456789013",
      ifsc: "HDFC0001234",
    }),
    dependencies({
      registerPayoutDestination: async () => {
        called = true;
        return undefined;
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(called, false);
});

Deno.test("retry executes an authenticated existing Dastak withdrawal", async () => {
  let execution: unknown;
  const response = await handleEarnings(
    request({
      operation: "retryRoyaltyWithdrawal",
      withdrawalId: subjectId,
      expectedVersion: 4,
    }),
    dependencies({
      executeWithdrawal: async (actor, withdrawalId, version) => {
        execution = { actor, withdrawalId, version };
        return { withdrawalId, status: "PROCESSING", providerStatus: "pending" };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(execution, { actor: accountId, withdrawalId: subjectId, version: 4 });
});

Deno.test("Admin payout trace remains platform-RBAC mediated by the database", async () => {
  let call: unknown;
  const response = await handleEarnings(
    request({ operation: "adminRoyaltyPayouts", limit: 25 }),
    dependencies({
      callRPC: async (rpc, args) => {
        call = [rpc, args];
        return [{ response_body: { withdrawals: [], hasMore: false, nextCursor: null }, response_status: 200 }];
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(call, ["dastak_v1_razorpayx_admin_page", {
    p_account_id: accountId,
    p_limit: 25,
    p_after_requested_at: null,
    p_after_withdrawal_id: null,
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
