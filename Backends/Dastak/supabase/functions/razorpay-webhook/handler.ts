import { json } from "../_shared/http.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type RazorpayWebhookEvent = {
  providerEventId: string;
  eventType: "payment_captured" | "refund_succeeded";
  providerOrderReference?: string;
  providerPaymentReference: string;
  providerRefundReference?: string;
  amountPaise: number;
  occurredAt: string;
  requestDigest: string;
};

export type RazorpayWebhookDependencies = {
  webhookSecret: string;
  recordEvent: (event: RazorpayWebhookEvent) => Promise<RpcResult>;
};

export async function handleRazorpayWebhook(
  request: Request,
  dependencies: RazorpayWebhookDependencies,
) {
  if (request.method !== "POST") return json({ error: { code: "method_not_allowed" } }, 405);
  const signature = request.headers.get("x-razorpay-signature") ?? "";
  const providerEventId = normalizedHeader(request.headers.get("x-razorpay-event-id"), 200);
  const rawBody = await request.text();
  if (!providerEventId || !await validSignature(rawBody, signature, dependencies.webhookSecret)) {
    return json({
      error: {
        code: "invalid_webhook_signature",
        message: "The Razorpay webhook signature is invalid.",
      },
    }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    const parsed = JSON.parse(rawBody);
    const result = record(parsed);
    if (!result) throw new Error("invalid payload");
    payload = result;
  } catch {
    return validationError();
  }

  if (payload.event !== "payment.captured" && payload.event !== "refund.processed") {
    return json({ received: true, processed: false }, 200);
  }

  const event = await parseEvent(payload, providerEventId, rawBody);
  if (!event) return validationError();
  try {
    const result = await dependencies.recordEvent(event);
    return json(result.responseBody, result.responseStatus);
  } catch {
    return json({
      error: { code: "internal_error", message: "The payment event could not be recorded." },
    }, 500);
  }
}

async function parseEvent(
  payload: Record<string, unknown>,
  providerEventId: string,
  rawBody: string,
): Promise<RazorpayWebhookEvent | undefined> {
  const createdAt = payload.created_at;
  if (typeof createdAt !== "number" || !Number.isSafeInteger(createdAt) || createdAt <= 0) {
    return undefined;
  }
  const occurredAt = new Date(createdAt * 1000).toISOString();
  const requestDigest = await sha256(rawBody);
  const payloadRecord = record(payload.payload);

  if (payload.event === "payment.captured") {
    const payment = record(record(payloadRecord?.payment)?.entity);
    const amountPaise = validMoney(payment?.amount);
    const providerPaymentReference = providerId(payment?.id, "pay");
    const providerOrderReference = providerId(payment?.order_id, "order");
    if (
      !amountPaise || !providerPaymentReference || !providerOrderReference ||
      payment?.currency !== "INR" || payment.status !== "captured" || payment.captured !== true
    ) return undefined;
    return {
      providerEventId,
      eventType: "payment_captured",
      providerOrderReference,
      providerPaymentReference,
      amountPaise,
      occurredAt,
      requestDigest,
    };
  }

  const refund = record(record(payloadRecord?.refund)?.entity);
  const payment = record(record(payloadRecord?.payment)?.entity);
  const amountPaise = validMoney(refund?.amount);
  const providerPaymentReference = providerId(refund?.payment_id, "pay");
  const providerRefundReference = providerId(refund?.id, "rfnd");
  const providerOrderReference = providerId(payment?.order_id, "order");
  if (
    !amountPaise || !providerPaymentReference || !providerRefundReference ||
    refund?.currency !== "INR" || refund.status !== "processed"
  ) return undefined;
  return {
    providerEventId,
    eventType: "refund_succeeded",
    providerOrderReference,
    providerPaymentReference,
    providerRefundReference,
    amountPaise,
    occurredAt,
    requestDigest,
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

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function providerId(value: unknown, prefix: "order" | "pay" | "rfnd") {
  return typeof value === "string" && new RegExp(`^${prefix}_[A-Za-z0-9]+$`).test(value) &&
      value.length <= 200
    ? value
    : undefined;
}

function validMoney(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 &&
      value <= 100_000_000
    ? value
    : undefined;
}

function normalizedHeader(value: string | null, maximum: number) {
  const normalized = value?.trim() ?? "";
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "The Razorpay webhook payload is invalid." },
  }, 400);
}
