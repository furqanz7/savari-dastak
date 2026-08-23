type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export const payoutGatewayPath = "/v1/payouts";
export const payoutGatewaySignatureHeader = "x-dastak-payout-signature";

export type PayoutGatewayRequest = {
  withdrawalId: string;
  amountPaise: number;
  currency: "INR";
  fundAccountReference: string;
  idempotencyKey: string;
  timestamp: string;
};

export type PayoutGatewayResult = {
  withdrawalId: string;
  providerPayoutReference: string;
  fundAccountReference: string;
  amountPaise: number;
  currency: "INR";
  mode: "IMPS" | "UPI";
  status:
    | "queued"
    | "pending"
    | "processing"
    | "processed"
    | "failed"
    | "reversed"
    | "rejected"
    | "cancelled";
  createdAt: string;
  utr?: string;
  statusDetails: Record<string, unknown>;
};

export class PayoutGatewayError extends Error {
  constructor(
    public readonly status: number,
    public readonly ambiguous: boolean,
    public readonly code = "payout_gateway_failed",
    public readonly safeMetadata: Record<string, unknown> = {},
  ) {
    super("Payout gateway request failed");
    this.name = "PayoutGatewayError";
  }
}

export class PayoutGatewayClient {
  private readonly endpoint: string;
  private readonly timeoutMilliseconds: number;

  constructor(
    options: {
      baseUrl: string;
      secret: string;
      timeoutMilliseconds?: number;
      now?: () => Date;
    },
    private readonly fetcher: Fetcher = fetch,
  ) {
    const url = validatedGatewayUrl(options.baseUrl);
    requireGatewaySecret(options.secret);
    const timeout = options.timeoutMilliseconds ?? 20_000;
    if (!Number.isSafeInteger(timeout) || timeout < 1_000 || timeout > 120_000) {
      throw new Error("Invalid payout gateway timeout");
    }
    this.endpoint = `${url.origin}${payoutGatewayPath}`;
    this.secret = options.secret;
    this.timeoutMilliseconds = timeout;
    this.now = options.now ?? (() => new Date());
  }

  private readonly secret: string;
  private readonly now: () => Date;

  async executePayout(
    input: Omit<PayoutGatewayRequest, "timestamp" | "currency"> & { currency?: "INR" },
  ) {
    const request = parsePayoutGatewayRequest({
      withdrawalId: input.withdrawalId,
      amountPaise: input.amountPaise,
      currency: input.currency ?? "INR",
      fundAccountReference: input.fundAccountReference,
      idempotencyKey: input.idempotencyKey,
      timestamp: this.now().toISOString(),
    });
    const body = canonicalPayoutGatewayBody(request);
    const signature = await signPayoutGatewayBody(this.secret, body);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMilliseconds);
    let response: Response;
    try {
      response = await this.fetcher(this.endpoint, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          [payoutGatewaySignatureHeader]: signature,
        },
        body,
        signal: controller.signal,
      });
    } catch {
      throw new PayoutGatewayError(0, true, "gateway_unreachable");
    } finally {
      clearTimeout(timeout);
    }
    const payload = await boundedJson(response);
    if (!response.ok) throw gatewayResponseError(response.status, payload);
    return parsePayoutGatewayResult(payload, request);
  }
}

export function canonicalPayoutGatewayBody(input: PayoutGatewayRequest) {
  return JSON.stringify({
    withdrawalId: input.withdrawalId,
    amountPaise: input.amountPaise,
    currency: input.currency,
    fundAccountReference: input.fundAccountReference,
    idempotencyKey: input.idempotencyKey,
    timestamp: input.timestamp,
  });
}

export function parsePayoutGatewayRequest(value: unknown): PayoutGatewayRequest {
  const source = record(value);
  const keys = source ? Object.keys(source).sort() : [];
  const expectedKeys = [
    "amountPaise",
    "currency",
    "fundAccountReference",
    "idempotencyKey",
    "timestamp",
    "withdrawalId",
  ];
  if (
    !source || keys.length !== expectedKeys.length ||
    keys.some((key, index) => key !== expectedKeys[index]) ||
    !uuid(source.withdrawalId) || !money(source.amountPaise) || source.currency !== "INR" ||
    !providerId(source.fundAccountReference, "fa") ||
    source.idempotencyKey !== source.withdrawalId || !isoTimestamp(source.timestamp)
  ) throw new Error("Invalid payout gateway request");
  return source as PayoutGatewayRequest;
}

export async function signPayoutGatewayBody(secret: string, canonicalBody: string) {
  requireGatewaySecret(secret);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", key, signatureBytes(canonicalBody)));
}

export async function verifyPayoutGatewaySignature(
  secret: string,
  canonicalBody: string,
  received: string,
) {
  if (!/^[0-9a-f]{64}$/i.test(received)) return false;
  const expected = await signPayoutGatewayBody(secret, canonicalBody);
  return constantTimeHexEquals(expected, received.toLowerCase());
}

export function constantTimeHexEquals(expected: string, received: string) {
  let mismatch = expected.length ^ received.length;
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= expected.charCodeAt(index) ^ (received.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

export async function sha256Hex(value: string) {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

function signatureBytes(body: string) {
  return new TextEncoder().encode(`dastak-payout-gateway-v1\nPOST\n${payoutGatewayPath}\n${body}`);
}

function parsePayoutGatewayResult(
  value: unknown,
  request: PayoutGatewayRequest,
): PayoutGatewayResult {
  const source = record(record(value)?.result);
  const status = source?.status;
  const mode = source?.mode;
  const createdAt = source?.createdAt;
  const providerPayoutReference = providerId(source?.providerPayoutReference, "pout");
  if (
    !source || source.withdrawalId !== request.withdrawalId || !providerPayoutReference ||
    source.fundAccountReference !== request.fundAccountReference ||
    source.amountPaise !== request.amountPaise || source.currency !== "INR" ||
    (mode !== "IMPS" && mode !== "UPI") || !payoutStatus(status) ||
    !isoTimestamp(createdAt) || !record(source.statusDetails)
  ) throw new PayoutGatewayError(502, true, "invalid_gateway_response");
  return {
    withdrawalId: request.withdrawalId,
    providerPayoutReference,
    fundAccountReference: request.fundAccountReference,
    amountPaise: request.amountPaise,
    currency: "INR",
    mode,
    status,
    createdAt,
    ...(optionalText(source.utr, 120) ? { utr: source.utr as string } : {}),
    statusDetails: safeStatusDetails(source.statusDetails),
  };
}

function gatewayResponseError(status: number, value: unknown) {
  const error = record(record(value)?.error);
  const code = optionalText(error?.code, 120) ?? "gateway_request_failed";
  const ambiguous = typeof error?.ambiguous === "boolean" ? error.ambiguous : status >= 500;
  return new PayoutGatewayError(status, ambiguous, code, { gatewayStatus: status, code });
}

async function boundedJson(response: Response) {
  const raw = await response.text();
  if (raw.length > 32_768) {
    throw new PayoutGatewayError(response.status || 502, true, "invalid_gateway_response");
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new PayoutGatewayError(response.status || 502, true, "invalid_gateway_response");
  }
}

function validatedGatewayUrl(value: string) {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Invalid payout gateway URL");
  }
  if (
    url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
    url.pathname !== "/" || url.hostname === "razorpay.com" ||
    url.hostname.endsWith(".razorpay.com")
  ) throw new Error("Invalid payout gateway URL");
  return url;
}

function requireGatewaySecret(value: string) {
  if (new TextEncoder().encode(value).length < 32) {
    throw new Error("Payout gateway secret must contain at least 32 bytes");
  }
}

function payoutStatus(value: unknown): value is PayoutGatewayResult["status"] {
  return value === "queued" || value === "pending" || value === "processing" ||
    value === "processed" || value === "failed" || value === "reversed" ||
    value === "rejected" || value === "cancelled";
}

function safeStatusDetails(value: unknown) {
  const source = record(value) ?? {};
  const result: Record<string, unknown> = {};
  for (const key of ["description", "source", "reason"]) {
    const candidate = optionalText(source[key], 500);
    if (candidate) result[key] = candidate;
  }
  return result;
}

function isoTimestamp(value: unknown): value is string {
  if (typeof value !== "string" || value.length !== 24) return false;
  const parsed = new Date(value);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString() === value;
}

function uuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function providerId(value: unknown, prefix: "fa" | "pout") {
  return typeof value === "string" &&
      new RegExp(`^${prefix}_[A-Za-z0-9]+$`).test(value) && value.length <= 200
    ? value
    : undefined;
}

function money(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 100 &&
    value <= 100_000_000_000;
}

function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum
    ? value
    : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function hex(value: ArrayBuffer) {
  return Array.from(new Uint8Array(value))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
