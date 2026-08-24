import { assertEquals, assertThrows } from "jsr:@std/assert";
import {
  payoutGatewayFromEnvironment,
  razorpayXTestDestinationClientFromEnvironment,
  royaltyPayoutAvailability,
} from "../../earnings/provider-clients.ts";

const withdrawalId = "31000000-0000-4000-8000-000000000001";

Deno.test("live Supabase execution cannot construct a direct RazorpayX client", () => {
  let fetchCalls = 0;
  const values: Record<string, string> = {
    RAZORPAYX_MODE: "LIVE",
    RAZORPAYX_TEST_KEY_ID: "rzp_test_Dastak123",
    RAZORPAYX_TEST_KEY_SECRET: "test-secret-value",
    RAZORPAYX_TEST_ACCOUNT_NUMBER: "1234567890",
  };
  assertThrows(
    () =>
      razorpayXTestDestinationClientFromEnvironment(
        (name) => values[name],
        async () => {
          fetchCalls += 1;
          return Response.json({});
        },
      ),
    Error,
    "disabled outside TEST",
  );
  assertEquals(fetchCalls, 0);
});

Deno.test("Supabase payout execution requires only gateway credentials and never targets Razorpay", async () => {
  let target = "";
  const values: Record<string, string> = {
    DASTAK_PAYOUT_GATEWAY_URL: "https://payout-gateway.dastak.example",
    DASTAK_PAYOUT_GATEWAY_SECRET: "dastak-gateway-secret-with-32-bytes-minimum",
  };
  const client = payoutGatewayFromEnvironment((name) => values[name], async (input) => {
    target = String(input);
    return Response.json({
      result: {
        withdrawalId,
        providerPayoutReference: "pout_00000000000001",
        fundAccountReference: "fa_00000000000001",
        amountPaise: 1500,
        currency: "INR",
        mode: "IMPS",
        status: "processing",
        createdAt: "2026-08-23T12:00:00.000Z",
        statusDetails: {},
      },
    });
  });
  await client.executePayout({
    withdrawalId,
    amountPaise: 1500,
    fundAccountReference: "fa_00000000000001",
    idempotencyKey: withdrawalId,
  });
  assertEquals(target, "https://payout-gateway.dastak.example/v1/payouts");
});

Deno.test("Razorpay provider origins cannot be configured as the Dastak gateway", () => {
  const values: Record<string, string> = {
    DASTAK_PAYOUT_GATEWAY_URL: "https://api.razorpay.com",
    DASTAK_PAYOUT_GATEWAY_SECRET: "dastak-gateway-secret-with-32-bytes-minimum",
  };
  assertThrows(
    () => payoutGatewayFromEnvironment((name) => values[name]),
    Error,
    "Invalid payout gateway URL",
  );
});

Deno.test("production reports unavailable payout actions instead of attempting direct live egress", () => {
  const values: Record<string, string> = { RAZORPAYX_MODE: "LIVE" };
  assertEquals(royaltyPayoutAvailability((name) => values[name]), {
    destinationRegistrationAvailable: false,
    withdrawalExecutionAvailable: false,
  });
});

Deno.test("test destination setup and fixed gateway availability are explicit capabilities", () => {
  const values: Record<string, string> = {
    RAZORPAYX_MODE: "TEST",
    RAZORPAYX_TEST_KEY_ID: "rzp_test_Dastak123",
    RAZORPAYX_TEST_KEY_SECRET: "test-secret-value",
    RAZORPAYX_TEST_ACCOUNT_NUMBER: "1234567890",
    RAZORPAYX_DESTINATION_FINGERPRINT_SECRET: "fingerprint-secret-value",
    DASTAK_PAYOUT_GATEWAY_URL: "https://payout-gateway.dastak.example",
    DASTAK_PAYOUT_GATEWAY_SECRET: "dastak-gateway-secret-with-32-bytes-minimum",
  };
  assertEquals(royaltyPayoutAvailability((name) => values[name]), {
    destinationRegistrationAvailable: true,
    withdrawalExecutionAvailable: true,
  });
});
