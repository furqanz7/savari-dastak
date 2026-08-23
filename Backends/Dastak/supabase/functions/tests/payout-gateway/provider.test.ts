import { assertEquals } from "jsr:@std/assert";
import { RazorpayXClient } from "../../_shared/razorpayx.ts";
import { executeRazorpayXPayout } from "../../../../infrastructure/razorpayx-payout-gateway/provider.ts";

const withdrawalId = "31000000-0000-4000-8000-000000000001";
const fundAccountReference = "fa_00000000000001";

Deno.test("gateway preserves the Dastak withdrawal id through every RazorpayX retry", async () => {
  const payoutBodies: string[] = [];
  const idempotencyKeys: string[] = [];
  const client = new RazorpayXClient({
    keyId: "rzp_test_Dastak123",
    keySecret: "test-secret-value",
    accountNumber: "1234567890",
    mode: "TEST",
    apiBaseUrl: "https://razorpayx.test/v1",
  }, async (input, init) => {
    const path = new URL(String(input)).pathname;
    if (path.includes("/fund_accounts/")) {
      return Response.json({
        id: fundAccountReference,
        account_type: "bank_account",
        active: true,
      });
    }
    payoutBodies.push(String(init?.body));
    idempotencyKeys.push(new Headers(init?.headers).get("x-payout-idempotency") ?? "");
    return Response.json({
      id: "pout_00000000000001",
      fund_account_id: fundAccountReference,
      amount: 1500,
      currency: "INR",
      mode: "IMPS",
      status: "processing",
      created_at: 1_787_478_400,
      status_details: {},
    });
  });
  const request = {
    withdrawalId,
    amountPaise: 1500,
    currency: "INR" as const,
    fundAccountReference,
    idempotencyKey: withdrawalId,
    timestamp: "2026-08-23T12:00:00.000Z",
  };
  const first = await executeRazorpayXPayout(client, request);
  const second = await executeRazorpayXPayout(client, {
    ...request,
    timestamp: "2026-08-23T12:00:01.000Z",
  });
  assertEquals(first.providerPayoutReference, second.providerPayoutReference);
  assertEquals(idempotencyKeys, [withdrawalId, withdrawalId]);
  assertEquals(payoutBodies[0], payoutBodies[1]);
  assertEquals(JSON.parse(payoutBodies[0]).reference_id, withdrawalId);
});
