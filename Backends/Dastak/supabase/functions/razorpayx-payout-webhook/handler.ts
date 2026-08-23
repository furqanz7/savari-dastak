import { json } from "../_shared/http.ts";
import { sha256 } from "../_shared/razorpayx.ts";

export type RazorpayXPayoutWebhookEvent = {
  providerEventId: string;
  providerEventType: string;
  withdrawalId: string;
  providerPayoutReference: string;
  providerStatus: string;
  amountPaise: number;
  currency: "INR";
  fundAccountReference: string;
  occurredAt: string;
  providerCreatedAt: string;
  requestDigest: string;
  payloadMetadata: Record<string, unknown>;
  utr?: string;
  statusDetails: Record<string, unknown>;
};

export type RazorpayXPayoutWebhookDependencies = {
  webhookSecret: string;
  recordEvent: (event: RazorpayXPayoutWebhookEvent) => Promise<unknown>;
};

const supportedEvents = new Set([
  "payout.pending",
  "payout.queued",
  "payout.initiated",
  "payout.processed",
  "payout.updated",
  "payout.reversed",
  "payout.failed",
  "payout.rejected",
]);

export async function handleRazorpayXPayoutWebhook(
  request: Request,
  dependencies: RazorpayXPayoutWebhookDependencies,
) {
  if (request.method !== "POST") return json({ error: { code: "method_not_allowed" } }, 405);
  const rawBody = await request.text();
  const signature = request.headers.get("x-razorpay-signature") ?? "";
  const providerEventId = normalizedHeader(request.headers.get("x-razorpay-event-id"), 200);
  if (
    !providerEventId ||
    !await validSignature(rawBody, signature, dependencies.webhookSecret)
  ) {
    return json({
      error: {
        code: "invalid_webhook_signature",
        message: "The RazorpayX payout webhook signature is invalid.",
      },
    }, 401);
  }
  let payload: Record<string, unknown>;
  try {
    payload = requiredRecord(JSON.parse(rawBody));
  } catch {
    return validationError();
  }
  if (typeof payload.event !== "string" || !supportedEvents.has(payload.event)) {
    return json({ received: true, processed: false }, 200);
  }
  const event = await parseEvent(payload, providerEventId, rawBody);
  if (!event) return validationError();
  try {
    const result = await dependencies.recordEvent(event);
    return json({ received: true, processed: true, result }, 200);
  } catch {
    return json({
      error: {
        code: "payout_event_recording_failed",
        message: "The payout event could not be recorded.",
      },
    }, 500);
  }
}

async function parseEvent(
  payload: Record<string, unknown>,
  providerEventId: string,
  rawBody: string,
): Promise<RazorpayXPayoutWebhookEvent | undefined> {
  const payout = record(record(record(payload.payload)?.payout)?.entity);
  const notes = record(payout?.notes);
  const withdrawalId = uuid(notes?.dastak_withdrawal_id);
  const providerPayoutReference = providerId(payout?.id, "pout");
  const fundAccountReference = providerId(payout?.fund_account_id, "fa");
  const amountPaise = money(payout?.amount);
  const providerStatus = payoutStatus(payout?.status);
  const providerCreatedAt = unixTimestamp(payout?.created_at);
  const eventOccurredAt = unixTimestamp(payload.created_at) ?? providerCreatedAt;
  if (
    !withdrawalId || !providerPayoutReference || !fundAccountReference ||
    !amountPaise || !providerStatus || payout?.currency !== "INR" ||
    !providerCreatedAt || !eventOccurredAt ||
    notes?.dastak_subject_id !== undefined && !uuid(notes.dastak_subject_id)
  ) return undefined;
  const statusDetails = safeStatusDetails(payout.status_details);
  const utr = optionalText(payout.utr, 120);
  return {
    providerEventId,
    providerEventType: payload.event as string,
    withdrawalId,
    providerPayoutReference,
    providerStatus,
    amountPaise,
    currency: "INR",
    fundAccountReference,
    occurredAt: eventOccurredAt,
    providerCreatedAt,
    requestDigest: await sha256(rawBody),
    payloadMetadata: {
      providerPayoutReference,
      fundAccountReference,
      amountPaise,
      currency: "INR",
      providerStatus,
      ...(utr ? { utr } : {}),
      statusDetails,
    },
    utr,
    statusDetails,
  };
}

async function validSignature(body: string, received: string, secret: string) {
  if (!/^[0-9a-f]{64}$/i.test(received) || secret.length < 8) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(body),
      ),
    ),
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  let mismatch = expected.length ^ received.length;
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= expected.charCodeAt(index) ^ (received.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

function safeStatusDetails(value: unknown) {
  const source = record(value);
  if (!source) return {};
  const result: Record<string, unknown> = {};
  for (const key of ["description", "source", "reason"]) {
    const candidate = optionalText(source[key], 500);
    if (candidate) result[key] = candidate;
  }
  return result;
}

function payoutStatus(value: unknown) {
  return typeof value === "string" && [
      "queued",
      "pending",
      "processing",
      "processed",
      "failed",
      "reversed",
      "rejected",
      "cancelled",
    ].includes(value)
    ? value
    : undefined;
}

function money(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 100
    ? value
    : undefined;
}

function unixTimestamp(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? new Date(value * 1000).toISOString()
    : undefined;
}

function uuid(value: unknown) {
  return typeof value === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : undefined;
}

function providerId(value: unknown, prefix: "pout" | "fa") {
  return typeof value === "string" && new RegExp(`^${prefix}_[A-Za-z0-9]+$`).test(value)
    ? value
    : undefined;
}

function normalizedHeader(value: string | null, maximum: number) {
  const normalized = value?.trim() ?? "";
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : undefined;
}

function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum
    ? value
    : undefined;
}

function requiredRecord(value: unknown) {
  const result = record(value);
  if (!result) throw new Error("invalid record");
  return result;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "The payout webhook payload is invalid." },
  }, 400);
}
