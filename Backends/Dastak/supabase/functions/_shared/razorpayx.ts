type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export type RazorpayXMode = "TEST" | "LIVE";
export type RazorpayXDestinationInput =
  | { type: "BANK_ACCOUNT"; holderName: string; accountNumber: string; ifsc: string }
  | { type: "UPI"; holderName: string; vpa: string };

export type RazorpayXFundAccount = {
  id: string;
  contactId: string;
  type: "BANK_ACCOUNT" | "UPI";
  active: boolean;
};

export type RazorpayXPayoutStatus =
  | "queued"
  | "pending"
  | "processing"
  | "processed"
  | "failed"
  | "reversed"
  | "rejected"
  | "cancelled";

export type RazorpayXPayout = {
  id: string;
  fundAccountId: string;
  amountPaise: number;
  currency: "INR";
  mode: "IMPS" | "UPI";
  status: RazorpayXPayoutStatus;
  createdAt: string;
  utr?: string;
  statusDetails: Record<string, unknown>;
};

export class RazorpayXApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly ambiguous: boolean,
    public readonly providerCode = "provider_request_failed",
    public readonly safeMetadata: Record<string, unknown> = {},
  ) {
    super("RazorpayX API request failed");
    this.name = "RazorpayXApiError";
  }
}

export class RazorpayXClient {
  private readonly authorization: string;
  private readonly apiBaseUrl: string;

  constructor(
    options: {
      keyId: string;
      keySecret: string;
      accountNumber: string;
      mode: RazorpayXMode;
      liveEgressAllowlistConfirmed?: boolean;
      apiBaseUrl?: string;
    },
    private readonly fetcher: Fetcher = fetch,
  ) {
    const expectedPrefix = options.mode === "TEST" ? "rzp_test_" : "rzp_live_";
    if (
      !options.keyId.startsWith(expectedPrefix) ||
      !/^rzp_(test|live)_[A-Za-z0-9]+$/.test(options.keyId) ||
      options.keySecret.length < 8 || !/^[0-9]{6,40}$/.test(options.accountNumber)
    ) throw new Error("Valid RazorpayX credentials and source account are required");
    if (options.mode === "LIVE" && options.liveEgressAllowlistConfirmed !== true) {
      throw new Error("RazorpayX live egress IP allowlisting must be confirmed");
    }
    const apiBaseUrl = (options.apiBaseUrl ?? "https://api.razorpay.com/v1").replace(/\/$/, "");
    if (
      options.mode === "LIVE" && apiBaseUrl !== "https://api.razorpay.com/v1" ||
      !apiBaseUrl.startsWith("https://")
    ) throw new Error("Invalid RazorpayX API endpoint");
    this.authorization = `Basic ${btoa(`${options.keyId}:${options.keySecret}`)}`;
    this.accountNumber = options.accountNumber;
    this.apiBaseUrl = apiBaseUrl;
  }

  private readonly accountNumber: string;

  async createContact(input: { name: string; referenceId: string }) {
    const payload = record(
      await this.request("/contacts", {
        method: "POST",
        body: JSON.stringify({
          name: validateContactName(input.name),
          type: "vendor",
          reference_id: validateReferenceId(input.referenceId),
          notes: { dastak_subject_reference: input.referenceId },
        }),
      }),
    );
    const id = providerId(payload?.id, "cont");
    if (!id || payload?.active !== true || payload.reference_id !== input.referenceId) {
      throw invalidProviderResponse();
    }
    return { id };
  }

  async createFundAccount(contactId: string, destination: RazorpayXDestinationInput) {
    const normalized = normalizeDestination(destination);
    const body = normalized.type === "BANK_ACCOUNT"
      ? {
        contact_id: providerId(contactId, "cont"),
        account_type: "bank_account",
        bank_account: {
          name: normalized.holderName,
          ifsc: normalized.ifsc,
          account_number: normalized.accountNumber,
        },
      }
      : {
        contact_id: providerId(contactId, "cont"),
        account_type: "vpa",
        vpa: { address: normalized.vpa },
      };
    if (!body.contact_id) throw new Error("Invalid RazorpayX contact reference");
    return parseFundAccount(
      await this.request("/fund_accounts", {
        method: "POST",
        body: JSON.stringify(body),
      }),
      contactId,
      normalized.type,
    );
  }

  async createPayout(input: {
    withdrawalId: string;
    subjectType: "MERCHANT_ORGANIZATION" | "RIDER";
    subjectId: string;
    fundAccountId: string;
    amountPaise: number;
    mode: "IMPS" | "UPI";
    idempotencyKey: string;
  }) {
    validateUuid(input.withdrawalId);
    validateUuid(input.subjectId);
    if (
      input.idempotencyKey !== input.withdrawalId ||
      input.idempotencyKey.length > 36 ||
      !Number.isSafeInteger(input.amountPaise) || input.amountPaise < 100 ||
      !providerId(input.fundAccountId, "fa")
    ) throw new Error("Invalid RazorpayX payout input");
    const payload = await this.request("/payouts", {
      method: "POST",
      headers: { "X-Payout-Idempotency": input.idempotencyKey },
      body: JSON.stringify({
        account_number: this.accountNumber,
        fund_account_id: input.fundAccountId,
        amount: input.amountPaise,
        currency: "INR",
        mode: input.mode,
        purpose: "payout",
        queue_if_low_balance: true,
        reference_id: input.withdrawalId,
        narration: "Dastak Royalty",
        notes: {
          dastak_withdrawal_id: input.withdrawalId,
          dastak_subject_type: input.subjectType,
          dastak_subject_id: input.subjectId,
        },
      }),
    });
    return assertPayoutMatches(parsePayout(payload), input);
  }

  async fetchPayout(providerPayoutId: string) {
    const id = providerId(providerPayoutId, "pout");
    if (!id) throw new Error("Invalid RazorpayX payout reference");
    return parsePayout(await this.request(`/payouts/${encodeURIComponent(id)}`, {}));
  }

  private async request(path: string, init: RequestInit) {
    let response: Response;
    try {
      response = await this.fetcher(`${this.apiBaseUrl}${path}`, {
        ...init,
        headers: {
          authorization: this.authorization,
          accept: "application/json",
          ...(init.body ? { "content-type": "application/json" } : {}),
          ...(init.headers ?? {}),
        },
      });
    } catch {
      throw new RazorpayXApiError(0, true, "network_timeout");
    }
    const payload = await response.json().catch(() => undefined);
    if (!response.ok || payload === undefined) {
      const metadata = safeErrorMetadata(payload);
      throw new RazorpayXApiError(
        response.status || 502,
        response.status >= 500,
        typeof metadata.code === "string" ? metadata.code : "provider_request_failed",
        metadata,
      );
    }
    return payload;
  }
}

export async function destinationFingerprint(
  secret: string,
  destination: RazorpayXDestinationInput,
) {
  if (secret.length < 16) throw new Error("RazorpayX destination fingerprint secret is required");
  const normalized = normalizeDestination(destination);
  const identity = normalized.type === "BANK_ACCOUNT"
    ? `BANK_ACCOUNT|${normalized.accountNumber}|${normalized.ifsc}`
    : `UPI|${normalized.vpa}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(identity),
  );
  return hex(digest);
}

export function normalizeDestination(input: RazorpayXDestinationInput): RazorpayXDestinationInput {
  const holderName = validateContactName(input.holderName);
  if (input.type === "BANK_ACCOUNT") {
    const accountNumber = input.accountNumber.replace(/\s+/g, "");
    const ifsc = input.ifsc.trim().toUpperCase();
    if (!/^[0-9]{6,34}$/.test(accountNumber) || !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc)) {
      throw new Error("Enter a valid Indian bank account and IFSC.");
    }
    return { type: "BANK_ACCOUNT", holderName, accountNumber, ifsc };
  }
  const vpa = input.vpa.trim().toLowerCase();
  if (vpa.length > 120 || !/^[a-z0-9._-]{2,64}@[a-z0-9.-]{2,64}$/.test(vpa)) {
    throw new Error("Enter a valid UPI ID.");
  }
  return { type: "UPI", holderName, vpa };
}

export function safeDestinationPresentation(destination: RazorpayXDestinationInput) {
  const normalized = normalizeDestination(destination);
  if (normalized.type === "BANK_ACCOUNT") {
    const last4 = normalized.accountNumber.slice(-4);
    return {
      displayLabel: `Bank account •••• ${last4}`,
      metadata: { last4, ifsc: normalized.ifsc },
    };
  }
  const [user, handle] = normalized.vpa.split("@");
  const maskedUser = user.length <= 2 ? `${user[0] ?? "*"}*` : `${user.slice(0, 2)}***`;
  const maskedAddress = `${maskedUser}@${handle}`;
  return { displayLabel: `UPI • ${maskedAddress}`, metadata: { maskedAddress } };
}

export async function sha256(value: string) {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

function parseFundAccount(
  value: unknown,
  expectedContactId: string,
  expectedType: RazorpayXFundAccount["type"],
): RazorpayXFundAccount {
  const source = record(value);
  const id = providerId(source?.id, "fa");
  const contactId = providerId(source?.contact_id, "cont");
  const type = source?.account_type === "bank_account"
    ? "BANK_ACCOUNT"
    : source?.account_type === "vpa"
    ? "UPI"
    : undefined;
  if (!id || contactId !== expectedContactId || type !== expectedType || source?.active !== true) {
    throw invalidProviderResponse();
  }
  return { id, contactId, type, active: true };
}

function parsePayout(value: unknown): RazorpayXPayout {
  const source = record(value);
  const id = providerId(source?.id, "pout");
  const fundAccountId = providerId(source?.fund_account_id, "fa");
  const status = source?.status;
  const mode = source?.mode;
  const createdAt = source?.created_at;
  if (
    !id || !fundAccountId || !validMoney(source?.amount) || source?.currency !== "INR" ||
    (mode !== "IMPS" && mode !== "UPI") || !isPayoutStatus(status) ||
    typeof createdAt !== "number" || !Number.isSafeInteger(createdAt) || createdAt <= 0
  ) throw invalidProviderResponse();
  return {
    id,
    fundAccountId,
    amountPaise: source.amount as number,
    currency: "INR",
    mode,
    status,
    createdAt: new Date(createdAt * 1000).toISOString(),
    utr: optionalText(source.utr, 120),
    statusDetails: safeStatusDetails(source.status_details),
  };
}

function assertPayoutMatches(
  payout: RazorpayXPayout,
  expected: { fundAccountId: string; amountPaise: number; mode: "IMPS" | "UPI" },
) {
  if (
    payout.fundAccountId !== expected.fundAccountId ||
    payout.amountPaise !== expected.amountPaise || payout.mode !== expected.mode
  ) {
    throw new RazorpayXApiError(409, true, "idempotency_payload_mismatch", {
      providerPayoutReference: payout.id,
      providerStatus: payout.status,
      fundAccountReference: payout.fundAccountId,
      amountPaise: payout.amountPaise,
      mode: payout.mode,
    });
  }
  return payout;
}

function validateContactName(value: string) {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (
    normalized.length < 3 || normalized.length > 50 ||
    !/^[A-Za-z0-9 ._()/'-]+$/.test(normalized) || /[^A-Za-z0-9.]$/.test(normalized)
  ) throw new Error("Enter a valid payout account holder name.");
  return normalized;
}

function validateReferenceId(value: string) {
  if (value.length < 4 || value.length > 40 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("Invalid RazorpayX contact reference");
  }
  return value;
}

function validateUuid(value: string) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error("Invalid Dastak identifier");
  }
}

function safeErrorMetadata(value: unknown): Record<string, unknown> {
  const error = record(record(value)?.error);
  const metadata: Record<string, unknown> = {};
  for (const key of ["code", "description", "source", "step", "reason", "field"]) {
    const candidate = optionalText(error?.[key], 300);
    if (candidate) metadata[key] = candidate;
  }
  return metadata;
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

function isPayoutStatus(value: unknown): value is RazorpayXPayoutStatus {
  return value === "queued" || value === "pending" || value === "processing" ||
    value === "processed" || value === "failed" || value === "reversed" ||
    value === "rejected" || value === "cancelled";
}

function providerId(value: unknown, prefix: "cont" | "fa" | "pout") {
  return typeof value === "string" &&
      new RegExp(`^${prefix}_[A-Za-z0-9]+$`).test(value) && value.length <= 200
    ? value
    : undefined;
}

function validMoney(value: unknown) {
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

function invalidProviderResponse() {
  return new RazorpayXApiError(502, true, "invalid_provider_response");
}

function hex(value: ArrayBuffer) {
  return Array.from(new Uint8Array(value))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
