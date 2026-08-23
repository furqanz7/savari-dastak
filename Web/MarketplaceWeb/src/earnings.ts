export type EarningsSnapshot = {
  currency: "INR";
  completedPaise: number;
  pendingPaise: number;
  thisWeekPaise: number;
};

export type RoyaltyEntry = {
  id: string;
  type: string;
  amountPaise: number;
  orderId?: string;
  fulfilmentId?: string;
  missionId?: string;
  refundId?: string;
  withdrawalId?: string;
  reason: string;
  createdAt: string;
};

export type RoyaltyWithdrawal = {
  id: string;
  amountPaise: number;
  currency: "INR";
  status: "REQUESTED" | "PROCESSING" | "PAID" | "FAILED_RETRYABLE";
  destination?: { type: string; provider: string; displayLabel: string };
  providerPayoutReference?: string;
  requestedAt: string;
  processingAt?: string;
  paidAt?: string;
  failedAt?: string;
  failureCode?: string;
  version: number;
};

export type RoyaltySubject = {
  subjectType: "MERCHANT_ORGANIZATION" | "RIDER";
  subjectId: string;
  currency: "INR";
  balancePaise: number;
  availablePaise: number;
  negativeBalancePaise: number;
  lifetimeEarnedPaise: number;
  canWithdraw: boolean;
  payoutDestination?: {
    id: string;
    type: string;
    provider: string;
    displayLabel: string;
    status: "ACTIVE";
    version: number;
  };
  entries: RoyaltyEntry[];
  adjustments: RoyaltyEntry[];
  withdrawals: RoyaltyWithdrawal[];
};

export type RoyaltySnapshot = {
  currency: "INR";
  availablePaise: number;
  balancePaise: number;
  negativeBalancePaise: number;
  lifetimeEarnedPaise: number;
  subjects: RoyaltySubject[];
};

type Auth = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

export async function getEarnings(
  input: { supabaseUrl: string; publishableKey: string; accessToken: string },
  operation: "merchantSnapshot" | "deliveryPartnerSnapshot",
): Promise<EarningsSnapshot> {
  const response = await fetch(`${input.supabaseUrl}/functions/v1/earnings`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: input.publishableKey,
      authorization: `Bearer ${input.accessToken}`,
      "x-idempotency-key": crypto.randomUUID(),
    },
    body: JSON.stringify({ operation }),
  });
  const payload = await response.json().catch(() => undefined) as
    | Record<string, unknown>
    | undefined;
  if (
    !response.ok || !payload || payload.currency !== "INR" ||
    !validMoney(payload.completedPaise) ||
    !validMoney(payload.pendingPaise) || !validMoney(payload.thisWeekPaise)
  ) {
    throw new Error(
      typeof payload?.error === "object" && payload.error !== null &&
        typeof (payload.error as Record<string, unknown>).message === "string"
        ? (payload.error as Record<string, string>).message
        : "Earnings are unavailable.",
    );
  }
  return {
    currency: "INR",
    completedPaise: payload.completedPaise as number,
    pendingPaise: payload.pendingPaise as number,
    thisWeekPaise: payload.thisWeekPaise as number,
  };
}

function validMoney(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

export async function getRoyalty(
  input: Auth,
  operation: "merchantRoyaltySnapshot" | "deliveryRoyaltySnapshot",
  fetcher: typeof fetch = fetch,
): Promise<RoyaltySnapshot> {
  const payload = await callEarnings(
    input,
    { operation },
    crypto.randomUUID(),
    fetcher,
  );
  if (
    payload.currency !== "INR" || !validSignedMoney(payload.balancePaise) ||
    !validMoney(payload.availablePaise) ||
    !validMoney(payload.negativeBalancePaise) ||
    !validMoney(payload.lifetimeEarnedPaise) || !Array.isArray(payload.subjects)
  ) throw new Error("Royalty is unavailable.");
  return {
    currency: "INR",
    balancePaise: payload.balancePaise,
    availablePaise: payload.availablePaise,
    negativeBalancePaise: payload.negativeBalancePaise,
    lifetimeEarnedPaise: payload.lifetimeEarnedPaise,
    subjects: payload.subjects.map(parseRoyaltySubject),
  } as RoyaltySnapshot;
}

export async function requestRoyaltyWithdrawal(
  input: Auth & {
    subjectType: RoyaltySubject["subjectType"];
    subjectId: string;
    amountPaise: number;
    idempotencyKey: string;
  },
  fetcher: typeof fetch = fetch,
): Promise<
  {
    withdrawalId: string;
    amountPaise: number;
    status: RoyaltyWithdrawal["status"];
  }
> {
  const payload = await callEarnings(
    input,
    {
      operation: "requestRoyaltyWithdrawal",
      subjectType: input.subjectType,
      subjectId: input.subjectId,
      amountPaise: input.amountPaise,
    },
    input.idempotencyKey,
    fetcher,
  );
  if (
    typeof payload.withdrawalId !== "string" ||
    !validMoney(payload.amountPaise) ||
    !isWithdrawalStatus(payload.status)
  ) throw new Error("The withdrawal response was invalid.");
  return {
    withdrawalId: payload.withdrawalId,
    amountPaise: payload.amountPaise,
    status: payload.status,
  };
}

async function callEarnings(
  input: Auth,
  body: Record<string, unknown>,
  idempotencyKey: string = crypto.randomUUID(),
  fetcher: typeof fetch = fetch,
): Promise<Record<string, unknown>> {
  const response = await fetcher(`${input.supabaseUrl}/functions/v1/earnings`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: input.publishableKey,
      authorization: `Bearer ${input.accessToken}`,
      "x-idempotency-key": idempotencyKey,
    },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => undefined) as
    | Record<string, unknown>
    | undefined;
  if (!response.ok || !payload) {
    const error = payload?.error;
    throw new Error(
      typeof error === "object" && error !== null &&
        typeof (error as Record<string, unknown>).message === "string"
        ? (error as Record<string, string>).message
        : "Royalty is unavailable.",
    );
  }
  return payload;
}

function parseRoyaltySubject(value: unknown): RoyaltySubject {
  const subject = record(value);
  if (
    (subject.subjectType !== "MERCHANT_ORGANIZATION" &&
      subject.subjectType !== "RIDER") ||
    typeof subject.subjectId !== "string" || subject.currency !== "INR" ||
    !validSignedMoney(subject.balancePaise) ||
    !validMoney(subject.availablePaise) ||
    !validMoney(subject.negativeBalancePaise) ||
    !validMoney(subject.lifetimeEarnedPaise) ||
    typeof subject.canWithdraw !== "boolean" ||
    !Array.isArray(subject.entries) ||
    !Array.isArray(subject.adjustments) || !Array.isArray(subject.withdrawals)
  ) throw new Error("Royalty is unavailable.");
  const payout = subject.payoutDestination === null ||
      subject.payoutDestination === undefined
    ? undefined
    : record(subject.payoutDestination);
  if (
    payout && (
      typeof payout.id !== "string" || typeof payout.type !== "string" ||
      typeof payout.provider !== "string" ||
      typeof payout.displayLabel !== "string" ||
      payout.status !== "ACTIVE" || !validVersion(payout.version)
    )
  ) throw new Error("Royalty is unavailable.");
  return {
    subjectType: subject.subjectType,
    subjectId: subject.subjectId,
    currency: "INR",
    balancePaise: subject.balancePaise,
    availablePaise: subject.availablePaise,
    negativeBalancePaise: subject.negativeBalancePaise,
    lifetimeEarnedPaise: subject.lifetimeEarnedPaise,
    canWithdraw: subject.canWithdraw,
    payoutDestination: payout as RoyaltySubject["payoutDestination"],
    entries: subject.entries.map(parseRoyaltyEntry),
    adjustments: subject.adjustments.map(parseRoyaltyEntry),
    withdrawals: subject.withdrawals.map(parseWithdrawal),
  };
}

function parseRoyaltyEntry(value: unknown): RoyaltyEntry {
  const entry = record(value);
  if (
    typeof entry.id !== "string" || typeof entry.type !== "string" ||
    !validSignedMoney(entry.amountPaise) || typeof entry.reason !== "string" ||
    typeof entry.createdAt !== "string"
  ) throw new Error("Royalty is unavailable.");
  return {
    id: entry.id,
    type: entry.type,
    amountPaise: entry.amountPaise,
    orderId: optionalString(entry.orderId),
    fulfilmentId: optionalString(entry.fulfilmentId),
    missionId: optionalString(entry.missionId),
    refundId: optionalString(entry.refundId),
    withdrawalId: optionalString(entry.withdrawalId),
    reason: entry.reason,
    createdAt: entry.createdAt,
  };
}

function parseWithdrawal(value: unknown): RoyaltyWithdrawal {
  const withdrawal = record(value);
  if (
    typeof withdrawal.id !== "string" || !validMoney(withdrawal.amountPaise) ||
    withdrawal.currency !== "INR" || !isWithdrawalStatus(withdrawal.status) ||
    typeof withdrawal.requestedAt !== "string" ||
    !validVersion(withdrawal.version)
  ) throw new Error("Royalty is unavailable.");
  const destination =
    withdrawal.destination === null || withdrawal.destination === undefined
      ? undefined
      : record(withdrawal.destination);
  if (
    destination && (
      typeof destination.type !== "string" ||
      typeof destination.provider !== "string" ||
      typeof destination.displayLabel !== "string"
    )
  ) throw new Error("Royalty is unavailable.");
  return {
    id: withdrawal.id,
    amountPaise: withdrawal.amountPaise,
    currency: "INR",
    status: withdrawal.status,
    destination: destination as RoyaltyWithdrawal["destination"],
    providerPayoutReference: optionalString(withdrawal.providerPayoutReference),
    requestedAt: withdrawal.requestedAt,
    processingAt: optionalString(withdrawal.processingAt),
    paidAt: optionalString(withdrawal.paidAt),
    failedAt: optionalString(withdrawal.failedAt),
    failureCode: optionalString(withdrawal.failureCode),
    version: withdrawal.version,
  };
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Royalty is unavailable.");
  }
  return value as Record<string, unknown>;
}

function optionalString(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function validSignedMoney(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value);
}

function validVersion(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isWithdrawalStatus(
  value: unknown,
): value is RoyaltyWithdrawal["status"] {
  return value === "REQUESTED" || value === "PROCESSING" || value === "PAID" ||
    value === "FAILED_RETRYABLE";
}
