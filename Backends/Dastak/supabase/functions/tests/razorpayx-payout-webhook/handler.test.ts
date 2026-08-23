import { assertEquals } from "jsr:@std/assert";
import {
  handleRazorpayXPayoutWebhook,
  type RazorpayXPayoutWebhookEvent,
} from "../../razorpayx-payout-webhook/handler.ts";

const secret = "razorpayx-webhook-test-secret";
const withdrawalId = "32000000-0000-4000-8000-000000000001";
const subjectId = "32000000-0000-4000-8000-000000000002";

Deno.test("RazorpayX payout webhook rejects missing or incorrect signatures", async () => {
  let called = false;
  for (const signature of [undefined, "0".repeat(64)]) {
    const response = await handleRazorpayXPayoutWebhook(
      request(eventPayload("payout.processed", "processed"), "evt_invalid", signature),
      {
        webhookSecret: secret,
        recordEvent: async () => {
          called = true;
          return undefined;
        },
      },
    );
    assertEquals(response.status, 401);
  }
  assertEquals(called, false);
});

Deno.test("verified success webhook preserves authoritative provider identity and metadata", async () => {
  let recorded: RazorpayXPayoutWebhookEvent | undefined;
  const payload = eventPayload("payout.processed", "processed", {
    utr: "UTR123456",
    status_details: { source: "beneficiary_bank", reason: "processed" },
  });
  const response = await handleRazorpayXPayoutWebhook(
    await signedRequest(payload, "evt_success_1"),
    {
      webhookSecret: secret,
      recordEvent: async (event) => {
        recorded = event;
        return { applicationResult: "APPLIED" };
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(recorded?.providerEventId, "evt_success_1");
  assertEquals(recorded?.withdrawalId, withdrawalId);
  assertEquals(recorded?.providerStatus, "processed");
  assertEquals(recorded?.utr, "UTR123456");
  assertEquals(recorded?.statusDetails, {
    source: "beneficiary_bank",
    reason: "processed",
  });
});

Deno.test("duplicate webhook delivery keeps the same provider event identity for DB deduplication", async () => {
  const payload = eventPayload("payout.pending", "pending");
  const eventIds: string[] = [];
  let calls = 0;
  for (let duplicate = 0; duplicate < 2; duplicate += 1) {
    const response = await handleRazorpayXPayoutWebhook(
      await signedRequest(payload, "evt_duplicate_1"),
      {
        webhookSecret: secret,
        recordEvent: async (event) => {
          calls += 1;
          eventIds.push(event.providerEventId);
          return { replayed: calls > 1 };
        },
      },
    );
    assertEquals(response.status, 200);
  }
  assertEquals(eventIds, ["evt_duplicate_1", "evt_duplicate_1"]);
});

Deno.test("out-of-order payload timestamps are forwarded rather than rewritten", async () => {
  const occurredAt: string[] = [];
  for (
    const [eventType, status, timestamp] of [
      ["payout.updated", "processing", 1_787_478_500],
      ["payout.pending", "pending", 1_787_478_400],
    ] as const
  ) {
    const payload = eventPayload(eventType, status);
    payload.created_at = timestamp;
    await handleRazorpayXPayoutWebhook(
      await signedRequest(payload, `evt_${status}`),
      {
        webhookSecret: secret,
        recordEvent: async (event) => {
          occurredAt.push(event.occurredAt);
          return {};
        },
      },
    );
  }
  assertEquals(occurredAt, [
    "2026-08-23T09:48:20.000Z",
    "2026-08-23T09:46:40.000Z",
  ]);
});

Deno.test("failure and reversal remain distinct provider events", async () => {
  const recorded: Array<[string, string]> = [];
  for (
    const [eventType, status] of [
      ["payout.failed", "failed"],
      ["payout.reversed", "reversed"],
    ] as const
  ) {
    const response = await handleRazorpayXPayoutWebhook(
      await signedRequest(eventPayload(eventType, status), `evt_${status}`),
      {
        webhookSecret: secret,
        recordEvent: async (event) => {
          recorded.push([event.providerEventType, event.providerStatus]);
          return {};
        },
      },
    );
    assertEquals(response.status, 200);
  }
  assertEquals(recorded, [
    ["payout.failed", "failed"],
    ["payout.reversed", "reversed"],
  ]);
});

Deno.test("webhook rejects malformed Dastak ownership notes before privileged RPC", async () => {
  let called = false;
  const payload = eventPayload("payout.processed", "processed");
  const entity = payoutEntity(payload);
  entity.notes = {
    dastak_withdrawal_id: "not-a-withdrawal",
    dastak_subject_id: subjectId,
  };
  const response = await handleRazorpayXPayoutWebhook(
    await signedRequest(payload, "evt_bad_owner"),
    {
      webhookSecret: secret,
      recordEvent: async () => {
        called = true;
        return {};
      },
    },
  );
  assertEquals(response.status, 400);
  assertEquals(called, false);
});

function eventPayload(
  event: string,
  status: string,
  overrides: Record<string, unknown> = {},
) {
  return {
    event,
    created_at: 1_787_478_500,
    payload: {
      payout: {
        entity: {
          id: "pout_00000000000001",
          fund_account_id: "fa_00000000000001",
          amount: 1500,
          currency: "INR",
          mode: "IMPS",
          status,
          created_at: 1_787_478_400,
          notes: {
            dastak_withdrawal_id: withdrawalId,
            dastak_subject_type: "RIDER",
            dastak_subject_id: subjectId,
          },
          ...overrides,
        },
      },
    },
  };
}

function payoutEntity(payload: ReturnType<typeof eventPayload>) {
  return payload.payload.payout.entity as Record<string, unknown>;
}

function request(payload: unknown, eventId: string, signature?: string) {
  return new Request("https://example.test/razorpayx-payout-webhook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-razorpay-event-id": eventId,
      ...(signature ? { "x-razorpay-signature": signature } : {}),
    },
    body: JSON.stringify(payload),
  });
}

async function signedRequest(payload: unknown, eventId: string) {
  const body = JSON.stringify(payload);
  return new Request("https://example.test/razorpayx-payout-webhook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-razorpay-event-id": eventId,
      "x-razorpay-signature": await signature(body),
    },
    body,
  });
}

async function signature(body: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(body),
      ),
    ),
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
