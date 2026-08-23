import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import {
  destinationFingerprint,
  RazorpayXClient,
  safeDestinationPresentation,
} from "../../_shared/razorpayx.ts";
import { PayoutGatewayError } from "../../_shared/payout-gateway.ts";
import {
  executeRazorpayXWithdrawal,
  registerRazorpayXDestination,
} from "../../earnings/razorpayx.ts";

const withdrawalId = "31000000-0000-4000-8000-000000000001";
const attemptId = "31000000-0000-4000-8000-000000000002";
const actorId = "31000000-0000-4000-8000-000000000003";
const subjectId = "31000000-0000-4000-8000-000000000004";
const contactId = "cont_00000000000001";
const bankFundAccountId = "fa_00000000000001";
const upiFundAccountId = "fa_00000000000002";
const payoutId = "pout_00000000000001";

const testOptions = {
  keyId: "rzp_test_Dastak123",
  keySecret: "test-secret-value",
  accountNumber: "1234567890",
  mode: "TEST" as const,
  apiBaseUrl: "https://razorpayx.test/v1",
};

Deno.test("RazorpayX bank Contact and Fund Account creation are replay-safe", async () => {
  const requests: Array<{ path: string; body?: unknown }> = [];
  const client = new RazorpayXClient(testOptions, async (input, init) => {
    const path = new URL(String(input)).pathname;
    requests.push({ path, body: init?.body ? JSON.parse(String(init.body)) : undefined });
    if (path.endsWith("/contacts")) {
      return Response.json({
        id: contactId,
        active: true,
        reference_id: subjectId,
      });
    }
    return Response.json({
      id: bankFundAccountId,
      contact_id: contactId,
      account_type: "bank_account",
      active: true,
    });
  });
  for (let replay = 0; replay < 2; replay += 1) {
    assertEquals(
      await client.createContact({ name: "Dastak Store", referenceId: subjectId }),
      { id: contactId },
    );
    assertEquals(
      await client.createFundAccount(contactId, {
        type: "BANK_ACCOUNT",
        holderName: "Dastak Store",
        accountNumber: "123456789012",
        ifsc: "HDFC0001234",
      }),
      { id: bankFundAccountId, contactId, type: "BANK_ACCOUNT", active: true },
    );
  }
  assertEquals(requests[0], requests[2]);
  assertEquals(requests[1], requests[3]);
  assertEquals(requests[1].body, {
    contact_id: contactId,
    account_type: "bank_account",
    bank_account: {
      name: "Dastak Store",
      ifsc: "HDFC0001234",
      account_number: "123456789012",
    },
  });
});

Deno.test("RazorpayX UPI Fund Account creation is replay-safe", async () => {
  const bodies: unknown[] = [];
  const client = new RazorpayXClient(testOptions, async (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)));
    return Response.json({
      id: upiFundAccountId,
      contact_id: contactId,
      account_type: "vpa",
      active: true,
    });
  });
  for (let replay = 0; replay < 2; replay += 1) {
    await client.createFundAccount(contactId, {
      type: "UPI",
      holderName: "Dastak Rider",
      vpa: "Rider.Name@OKAXIS",
    });
  }
  assertEquals(bodies, [{
    contact_id: contactId,
    account_type: "vpa",
    vpa: { address: "rider.name@okaxis" },
  }, {
    contact_id: contactId,
    account_type: "vpa",
    vpa: { address: "rider.name@okaxis" },
  }]);
});

Deno.test("fixed-egress gateway resolves bank and UPI payout mode from the provider destination", async () => {
  const types = ["bank_account", "vpa"];
  const client = new RazorpayXClient(testOptions, async (input) => {
    const type = types.shift();
    return Response.json({
      id: String(input).includes(upiFundAccountId) ? upiFundAccountId : bankFundAccountId,
      account_type: type,
      active: true,
    });
  });
  assertEquals(await client.fetchFundAccountType(bankFundAccountId), "BANK_ACCOUNT");
  assertEquals(await client.fetchFundAccountType(upiFundAccountId), "UPI");
});

Deno.test("destination storage presentation is masked and fingerprinted without raw details", async () => {
  const destination = {
    type: "BANK_ACCOUNT" as const,
    holderName: "Dastak Store",
    accountNumber: "123456789012",
    ifsc: "HDFC0001234",
  };
  const presentation = safeDestinationPresentation(destination);
  assertEquals(presentation, {
    displayLabel: "Bank account •••• 9012",
    metadata: { last4: "9012", ifsc: "HDFC0001234" },
  });
  assert(!JSON.stringify(presentation).includes(destination.accountNumber));
  assertEquals(
    await destinationFingerprint("dastak-fingerprint-secret", destination),
    await destinationFingerprint("dastak-fingerprint-secret", destination),
  );
});

Deno.test("live mode refuses to start without confirmed fixed-egress allowlisting", () => {
  assertThrows(
    () =>
      new RazorpayXClient({
        ...testOptions,
        keyId: "rzp_live_Dastak123",
        mode: "LIVE",
        apiBaseUrl: "https://api.razorpay.com/v1",
      }),
    Error,
    "allowlisting",
  );
});

Deno.test("destination orchestration reuses the persisted Contact and snapshots only safe details", async () => {
  let createContactCalls = 0;
  let finalized: Record<string, unknown> | undefined;
  const client = {
    createContact: async () => {
      createContactCalls += 1;
      return { id: contactId };
    },
    createFundAccount: async () => ({
      id: upiFundAccountId,
      contactId,
      type: "UPI" as const,
      active: true,
    }),
  } as unknown as RazorpayXClient;
  const result = await registerRazorpayXDestination({
    actorId,
    subjectType: "RIDER",
    subjectId,
    destination: { type: "UPI", holderName: "Dastak Rider", vpa: "rider@okaxis" },
    fingerprintSecret: "dastak-fingerprint-secret",
    client,
    callRPC: async (rpc, args) => {
      if (rpc.endsWith("destination_context")) {
        return {
          contactName: "Dastak Rider",
          providerReferenceId: subjectId,
          providerContactReference: contactId,
        };
      }
      finalized = args;
      return { destinationId: subjectId, displayLabel: args.p_display_label };
    },
  });
  assertEquals(createContactCalls, 0);
  assertEquals(result, { destinationId: subjectId, displayLabel: "UPI • ri***@okaxis" });
  assertEquals(finalized?.p_provider_contact_reference, contactId);
  assertEquals(finalized?.p_provider_fund_account_reference, upiFundAccountId);
  assertEquals(finalized?.p_safe_metadata, { maskedAddress: "ri***@okaxis" });
  assert(!JSON.stringify(finalized).includes("rider@okaxis"));
});

Deno.test("payout creation uses the Dastak withdrawal UUID as mandatory provider idempotency", async () => {
  const calls: Array<{ headers: Headers; body: Record<string, unknown> }> = [];
  const client = new RazorpayXClient(testOptions, async (_input, init) => {
    calls.push({
      headers: new Headers(init?.headers),
      body: JSON.parse(String(init?.body)),
    });
    return Response.json(providerPayout("pending"));
  });
  for (let replay = 0; replay < 2; replay += 1) {
    await client.createPayout({
      withdrawalId,
      fundAccountId: bankFundAccountId,
      amountPaise: 1500,
      mode: "IMPS",
      idempotencyKey: withdrawalId,
    });
  }
  assertEquals(calls.length, 2);
  assertEquals(calls[0].headers.get("x-payout-idempotency"), withdrawalId);
  assertEquals(calls[0].body, calls[1].body);
  assertEquals(calls[0].body.reference_id, withdrawalId);
  assertEquals((calls[0].body.notes as Record<string, unknown>).dastak_withdrawal_id, withdrawalId);
});

Deno.test("timeout after provider acceptance retries the identical payout without releasing Royalty", async () => {
  const payoutBodies: string[] = [];
  const idempotencyKeys: string[] = [];
  let providerCalls = 0;
  const client = {
    executePayout: async (input: Record<string, unknown>) => {
      providerCalls += 1;
      payoutBodies.push(JSON.stringify(input));
      idempotencyKeys.push(String(input.idempotencyKey));
      if (providerCalls === 1) {
        throw new PayoutGatewayError(0, true, "gateway_unreachable");
      }
      return gatewayPayout("processing");
    },
  };
  const records: Array<{ rpc: string; args: Record<string, unknown> }> = [];
  const callRPC = async (rpc: string, args: Record<string, unknown>) => {
    if (rpc.endsWith("claim_razorpayx_withdrawal")) return executionContext();
    records.push({ rpc, args });
    if (rpc.endsWith("apply_razorpayx_payout_status")) {
      return { withdrawalId, status: "PROCESSING", providerStatus: "PROCESSING" };
    }
    return { recorded: true };
  };
  const first = await executeRazorpayXWithdrawal({
    actorId,
    withdrawalId,
    expectedVersion: 2,
    client,
    callRPC,
    requestId: () => "31000000-0000-4000-8000-000000000011",
  });
  assertEquals(first, {
    withdrawalId,
    status: "PROCESSING",
    providerStatus: "CREATING",
    reconciliationState: "PENDING",
    retryable: true,
  });
  assert(!records.some((entry) => entry.rpc.endsWith("mark_razorpayx_submission_retryable")));
  await executeRazorpayXWithdrawal({
    actorId,
    withdrawalId,
    expectedVersion: 2,
    client,
    callRPC,
    requestId: () => "31000000-0000-4000-8000-000000000012",
  });
  assertEquals(payoutBodies[0], payoutBodies[1]);
  assertEquals(idempotencyKeys, [withdrawalId, withdrawalId]);
  assertEquals(
    records.filter((entry) => entry.rpc.endsWith("apply_razorpayx_payout_status")).length,
    1,
  );
});

Deno.test("known pre-accept provider rejection releases through the Dastak retryable command", async () => {
  const client = {
    executePayout: () => Promise.reject(new PayoutGatewayError(422, false, "bad_request_error")),
  };
  const calls: string[] = [];
  const result = await executeRazorpayXWithdrawal({
    actorId,
    withdrawalId,
    expectedVersion: 2,
    client,
    callRPC: async (rpc) => {
      calls.push(rpc);
      if (rpc.endsWith("claim_razorpayx_withdrawal")) return executionContext();
      if (rpc.endsWith("mark_razorpayx_submission_retryable")) {
        return { withdrawalId, status: "FAILED_RETRYABLE", providerStatus: "SUBMISSION_RETRYABLE" };
      }
      return { recorded: true };
    },
    requestId: () => "31000000-0000-4000-8000-000000000013",
  });
  assertEquals(result, {
    withdrawalId,
    status: "FAILED_RETRYABLE",
    providerStatus: "SUBMISSION_RETRYABLE",
  });
  assert(calls.some((rpc) => rpc.endsWith("mark_razorpayx_submission_retryable")));
});

Deno.test("provider payout ownership mismatch preserves the reservation for reconciliation", async () => {
  const client = {
    executePayout: async () => ({ ...gatewayPayout("processed"), amountPaise: 1600 }),
  };
  const calls: string[] = [];
  const result = await executeRazorpayXWithdrawal({
    actorId,
    withdrawalId,
    expectedVersion: 2,
    client,
    callRPC: async (rpc) => {
      calls.push(rpc);
      if (rpc.endsWith("claim_razorpayx_withdrawal")) return executionContext();
      if (rpc.endsWith("mark_razorpayx_reconciliation_required")) {
        return {
          withdrawalId,
          status: "PROCESSING",
          providerStatus: "CREATING",
          reconciliationState: "REVIEW_REQUIRED",
          retryable: false,
        };
      }
      return { recorded: true };
    },
  });
  assertEquals(result, {
    withdrawalId,
    status: "PROCESSING",
    providerStatus: "CREATING",
    reconciliationState: "REVIEW_REQUIRED",
    retryable: false,
  });
  assert(!calls.some((rpc) => rpc.endsWith("apply_razorpayx_payout_status")));
  assert(!calls.some((rpc) => rpc.endsWith("mark_razorpayx_submission_retryable")));
  assert(calls.some((rpc) => rpc.endsWith("mark_razorpayx_reconciliation_required")));
});

function executionContext() {
  return {
    withdrawalId,
    attemptId,
    subjectType: "RIDER",
    subjectId,
    amountPaise: 1500,
    currency: "INR",
    fundAccountReference: bankFundAccountId,
    payoutMode: "IMPS",
    payoutIdempotencyKey: withdrawalId,
    requestDigest: "a".repeat(64),
    providerPayoutReference: null,
    providerStatus: "CREATING",
    status: "PROCESSING",
    version: 2,
  };
}

function providerPayout(status: string) {
  return {
    id: payoutId,
    fund_account_id: bankFundAccountId,
    amount: 1500,
    currency: "INR",
    mode: "IMPS",
    status,
    created_at: 1_787_478_400,
    status_details: {},
  };
}

function gatewayPayout(status: "processing" | "processed") {
  return {
    withdrawalId,
    providerPayoutReference: payoutId,
    fundAccountReference: bankFundAccountId,
    amountPaise: 1500,
    currency: "INR" as const,
    mode: "IMPS" as const,
    status,
    createdAt: "2026-08-23T00:00:00.000Z",
    statusDetails: {},
  };
}
