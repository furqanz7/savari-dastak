import { describe, expect, it } from "vitest";
import {
  EarningsRequestError,
  getAdminRoyaltyPayouts,
  getRoyalty,
  registerRoyaltyPayoutDestination,
  requestRoyaltyWithdrawal,
  retryRoyaltyWithdrawal,
} from "./earnings";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};
const subjectId = "95000000-0000-4000-8000-000000000001";

describe("Royalty", () => {
  it("preserves structured Edge error code and status", async () => {
    await expect(getAdminRoyaltyPayouts(auth, () => Promise.resolve(Response.json({
      error: { code: "authentication_required", message: "Sign in again." },
    }, { status: 401 })))).rejects.toEqual(new EarningsRequestError("authentication_required", "Sign in again.", 401));
  });

  it("enforces a request deadline while forwarding the abort signal", async () => {
    let signal: AbortSignal | undefined;
    const pending = getAdminRoyaltyPayouts({ ...auth, timeoutMs: 5 }, (_input, init) => {
      signal = init?.signal as AbortSignal;
      return new Promise<Response>((_resolve, reject) => {
        signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      });
    });
    await expect(pending).rejects.toMatchObject({ code: "request_timeout", status: 0 });
    expect(signal?.aborted).toBe(true);
  });

  it("parses positive and negative append-only ledger entries", async () => {
    let body: unknown;
    const snapshot = await getRoyalty(auth, "deliveryRoyaltySnapshot", (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(Response.json({
        currency: "INR",
        availablePaise: 4000,
        balancePaise: 4000,
        negativeBalancePaise: 0,
        lifetimeEarnedPaise: 9000,
        payoutAvailability: {
          destinationRegistrationAvailable: false,
          withdrawalExecutionAvailable: false,
        },
        subjects: [{
          subjectType: "RIDER",
          subjectId,
          currency: "INR",
          availablePaise: 4000,
          balancePaise: 4000,
          negativeBalancePaise: 0,
          lifetimeEarnedPaise: 9000,
          canWithdraw: true,
          payoutDestination: {
            id: "95000000-0000-4000-8000-000000000002",
            type: "BANK_ACCOUNT",
            displayLabel: "Bank account •••• 1234",
            status: "ACTIVE",
            version: 1,
          },
          entries: [{
            id: "95000000-0000-4000-8000-000000000003",
            type: "RIDER_ROYALTY_EARNING",
            amountPaise: 9000,
            orderId: "95000000-0000-4000-8000-000000000004",
            reason: "Verified delivery.",
            createdAt: "2026-08-23T00:00:00Z",
          }, {
            id: "95000000-0000-4000-8000-000000000005",
            type: "ROYALTY_FAULT_ADJUSTMENT",
            amountPaise: -5000,
            refundId: "95000000-0000-4000-8000-000000000006",
            reason: "Approved fault.",
            createdAt: "2026-08-23T01:00:00Z",
          }],
          adjustments: [{
            id: "95000000-0000-4000-8000-000000000005",
            type: "ROYALTY_FAULT_ADJUSTMENT",
            amountPaise: -5000,
            refundId: "95000000-0000-4000-8000-000000000006",
            reason: "Approved fault.",
            createdAt: "2026-08-23T01:00:00Z",
          }],
          withdrawals: [],
        }],
      }));
    });
    expect(body).toEqual({ operation: "deliveryRoyaltySnapshot" });
    expect(snapshot.subjects[0].entries.map((entry) => entry.amountPaise))
      .toEqual([9000, -5000]);
    expect(snapshot.availablePaise).toBe(4000);
    expect(snapshot.payoutAvailability).toEqual({
      destinationRegistrationAvailable: false,
      withdrawalExecutionAvailable: false,
    });
  });

  it("requests only a server-reserved withdrawal and forwards idempotency", async () => {
    let body: unknown;
    let headers: Headers | undefined;
    const result = await requestRoyaltyWithdrawal({
      ...auth,
      subjectType: "MERCHANT_ORGANIZATION",
      subjectId,
      amountPaise: 1500,
      idempotencyKey: "withdrawal-key",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      headers = new Headers(init?.headers);
      return Promise.resolve(Response.json({
        withdrawalId: "95000000-0000-4000-8000-000000000009",
        amountPaise: 1500,
        status: "REQUESTED",
      }));
    });
    expect(body).toEqual({
      operation: "requestRoyaltyWithdrawal",
      subjectType: "MERCHANT_ORGANIZATION",
      subjectId,
      amountPaise: 1500,
    });
    expect(headers?.get("x-idempotency-key")).toBe("withdrawal-key");
    expect(result.status).toBe("REQUESTED");
  });

  it("never accepts a false Paid status outside the locked lifecycle", async () => {
    await expect(requestRoyaltyWithdrawal({
      ...auth,
      subjectType: "RIDER",
      subjectId,
      amountPaise: 1500,
      idempotencyKey: "withdrawal-key-2",
    }, () =>
      Promise.resolve(Response.json({
        withdrawalId: "95000000-0000-4000-8000-000000000009",
        amountPaise: 1500,
        status: "COMPLETED",
      })))).rejects.toThrow("invalid");
  });

  it("submits confirmed bank details only through the authenticated earnings function", async () => {
    let body: unknown;
    await registerRoyaltyPayoutDestination({
      ...auth,
      subjectType: "MERCHANT_ORGANIZATION",
      subjectId,
      holderName: "Dastak Store",
      destination: {
        type: "BANK_ACCOUNT",
        accountNumber: "123456789012",
        confirmAccountNumber: "123456789012",
        ifsc: "HDFC0001234",
      },
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(Response.json({
        destinationId: "95000000-0000-4000-8000-000000000010",
        type: "BANK_ACCOUNT",
        displayLabel: "Bank account •••• 9012",
      }));
    });
    expect(body).toEqual({
      operation: "registerRoyaltyPayoutDestination",
      subjectType: "MERCHANT_ORGANIZATION",
      subjectId,
      holderName: "Dastak Store",
      destinationType: "BANK_ACCOUNT",
      accountNumber: "123456789012",
      confirmAccountNumber: "123456789012",
      ifsc: "HDFC0001234",
    });
  });

  it("supports UPI destination registration without Razorpay terminology", async () => {
    let body: Record<string, unknown> | undefined;
    await registerRoyaltyPayoutDestination({
      ...auth,
      subjectType: "RIDER",
      subjectId,
      holderName: "Dastak Rider",
      destination: { type: "UPI", vpa: "rider@okaxis" },
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(Response.json({
        destinationId: "95000000-0000-4000-8000-000000000011",
        type: "UPI",
        displayLabel: "UPI • ri***@okaxis",
      }));
    });
    expect(body).toMatchObject({
      operation: "registerRoyaltyPayoutDestination",
      destinationType: "UPI",
      vpa: "rider@okaxis",
    });
    expect(JSON.stringify(body)).not.toContain("Razorpay");
  });

  it("retries an existing reserved withdrawal using its version", async () => {
    let body: unknown;
    const result = await retryRoyaltyWithdrawal({
      ...auth,
      withdrawalId: "95000000-0000-4000-8000-000000000012",
      expectedVersion: 3,
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(Response.json({
        withdrawalId: "95000000-0000-4000-8000-000000000012",
        status: "PROCESSING",
      }));
    });
    expect(body).toEqual({
      operation: "retryRoyaltyWithdrawal",
      withdrawalId: "95000000-0000-4000-8000-000000000012",
      expectedVersion: 3,
    });
    expect(result.status).toBe("PROCESSING");
  });

  it("parses the Admin provider reconciliation trace separately from user Royalty", async () => {
    const payouts = await getAdminRoyaltyPayouts({ ...auth, limit: 25 }, () =>
      Promise.resolve(Response.json({
        withdrawals: [{
          id: "95000000-0000-4000-8000-000000000013",
          subjectType: "RIDER",
          subjectId,
          amountPaise: 1500,
          effectiveStatus: "PROCESSING",
          destinationSnapshot: {
            type: "UPI",
            displayLabel: "UPI • ri***@okaxis",
          },
          provider: "RAZORPAYX",
          providerPayoutReference: "pout_00000000000001",
          providerStatus: "PENDING",
          reconciliationState: "PENDING",
          requestedAt: "2026-08-23T00:00:00Z",
          attempts: [],
          providerRequests: [],
          webhookHistory: [],
        }],
        hasMore: false,
        nextCursor: null,
      })));
    expect(payouts.withdrawals[0].providerPayoutReference).toBe("pout_00000000000001");
    expect(payouts.withdrawals[0].destinationSnapshot.displayLabel).toBe("UPI • ri***@okaxis");
    expect(payouts.hasMore).toBe(false);
  });
});
