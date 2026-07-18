import { assert, assertEquals } from "jsr:@std/assert";
import {
  handlePaymentLedger,
  type OwnerFinancialRateCardInput,
  type PaymentLedgerDependencies,
} from "../../payment-ledger/handler.ts";

Deno.test("payment ledger rejects missing authorization", async () => {
  let authenticationAttempts = 0;
  const response = await handlePaymentLedger(
    request({ operation: "ownerOrderSnapshot", orderId }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("owner config forwards only authenticated server-pricing terms", async () => {
  let recorded: OwnerFinancialRateCardInput | undefined;
  const response = await handlePaymentLedger(
    request(
      {
        operation: "ownerUpsertRateCard",
        accountId: otherAccountId,
        serviceZoneId,
        deliveryFeePaise: 4_000,
        merchantCommissionBps: 1_000,
        courierPayoutPaise: 3_000,
        active: true,
        merchantPayablePaise: 1,
        platformMarginPaise: 99_999,
      },
      "Bearer owner-session",
      "rate-key-1",
    ),
    dependencies({
      upsertRateCard: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: rateCard, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.serviceZoneId, serviceZoneId);
  assertEquals(recorded?.deliveryFeePaise, 4_000);
  assertEquals(recorded?.merchantCommissionBps, 1_000);
  assertEquals(recorded?.courierPayoutPaise, 3_000);
  assertEquals(recorded?.active, true);
  assertEquals(recorded?.idempotencyKey, "rate-key-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
  assertEquals("merchantPayablePaise" in (recorded ?? {}), false);
  assertEquals("platformMarginPaise" in (recorded ?? {}), false);
});

Deno.test("owner config rejects impossible money splits", async () => {
  for (
    const values of [
      { deliveryFeePaise: 4_000, merchantCommissionBps: 10_001, courierPayoutPaise: 3_000 },
      { deliveryFeePaise: 4_000, merchantCommissionBps: 1_000, courierPayoutPaise: 4_001 },
      { deliveryFeePaise: -1, merchantCommissionBps: 1_000, courierPayoutPaise: 0 },
      { deliveryFeePaise: 4_000.5, merchantCommissionBps: 1_000, courierPayoutPaise: 3_000 },
    ]
  ) {
    const response = await handlePaymentLedger(
      request(
        { operation: "ownerUpsertRateCard", serviceZoneId, active: true, ...values },
        "Bearer owner-session",
        "invalid-rate-key",
      ),
      dependencies(),
    );
    assertEquals(response.status, 400);
  }
});

Deno.test("owner snapshot uses authenticated account and order only", async () => {
  const requested: string[] = [];
  const response = await handlePaymentLedger(
    request(
      { operation: "ownerOrderSnapshot", accountId: otherAccountId, orderId },
      "Bearer owner-session",
    ),
    dependencies({
      getOrderSnapshot: (requestedAccountId, requestedOrderId) => {
        requested.push(`${requestedAccountId}:${requestedOrderId}`);
        return Promise.resolve({ responseBody: financialSnapshot, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(requested, [`${accountId}:${orderId}`]);
});

Deno.test("provider financial mutations are not exposed to authenticated apps", async () => {
  const response = await handlePaymentLedger(
    request(
      {
        operation: "recordProviderEvent",
        orderId,
        provider: "razorpay",
        providerEventId: "forged-event",
        amountPaise: 14_000,
      },
      "Bearer owner-session",
      "forged-provider-key",
    ),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "validation_failed");
});

Deno.test("payment ledger dependency failures do not leak details", async () => {
  const response = await handlePaymentLedger(
    request({ operation: "ownerOrderSnapshot", orderId }, "Bearer owner-session"),
    dependencies({
      getOrderSnapshot: () => Promise.reject(new Error("provider ledger unavailable")),
    }),
  );

  assertEquals(response.status, 500);
  assertEquals(await jsonBody(response), {
    error: {
      code: "internal_error",
      message: "The payment ledger request could not be processed.",
    },
  });
});

const accountId = "82000000-0000-4000-8000-000000000001";
const otherAccountId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const serviceZoneId = "82000000-0000-4000-8000-000000000010";
const orderId = "82000000-0000-4000-8000-000000000080";

const rateCard = {
  serviceZoneId,
  deliveryFee: { paise: 4_000 },
  merchantCommissionBps: 1_000,
  courierPayout: { paise: 3_000 },
  active: true,
  version: 2,
};

const financialSnapshot = {
  orderId,
  paymentState: "captured",
  settlementState: "settled",
  currency: "INR",
  gross: { paise: 14_000 },
  captured: { paise: 14_000 },
  refundReserved: { paise: 0 },
  refunded: { paise: 0 },
  merchantPayable: { paise: 9_000 },
  courierPayout: { paise: 3_000 },
  platformMerchantCommission: { paise: 1_000 },
  platformDeliveryMargin: { paise: 1_000 },
  version: 3,
  updatedAt: "2026-07-17T12:00:00+00:00",
};

function dependencies(
  overrides: Partial<PaymentLedgerDependencies> = {},
): PaymentLedgerDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId })),
    upsertRateCard: overrides.upsertRateCard ??
      (() => Promise.resolve({ responseBody: rateCard, responseStatus: 200 })),
    getOrderSnapshot: overrides.getOrderSnapshot ??
      (() => Promise.resolve({ responseBody: financialSnapshot, responseStatus: 200 })),
  };
}

function request(
  body: unknown,
  authorization?: string,
  idempotencyKey?: string,
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request("http://localhost/functions/v1/payment-ledger", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function jsonBody(response: Response) {
  return await response.json();
}
