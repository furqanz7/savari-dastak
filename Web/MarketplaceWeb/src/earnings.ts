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
  status: "REQUESTED" | "PROCESSING" | "PAID" | "FAILED_RETRYABLE" | "FAILED" | "REVERSED";
  destination?: { type: "BANK_ACCOUNT" | "UPI" | string; displayLabel: string };
  providerStatus?: string;
  reconciliationState?: "PENDING" | "IN_SYNC" | "RETRYABLE" | "REVIEW_REQUIRED";
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

export async function registerRoyaltyPayoutDestination(
  input: Auth & {
    subjectType: RoyaltySubject["subjectType"];
    subjectId: string;
    holderName: string;
    destination:
      | { type: "BANK_ACCOUNT"; accountNumber: string; confirmAccountNumber: string; ifsc: string }
      | { type: "UPI"; vpa: string };
  },
  fetcher: typeof fetch = fetch,
) {
  return await callEarnings(
    input,
    {
      operation: "registerRoyaltyPayoutDestination",
      subjectType: input.subjectType,
      subjectId: input.subjectId,
      holderName: input.holderName,
      destinationType: input.destination.type,
      ...(input.destination.type === "BANK_ACCOUNT"
        ? {
          accountNumber: input.destination.accountNumber,
          confirmAccountNumber: input.destination.confirmAccountNumber,
          ifsc: input.destination.ifsc,
        }
        : { vpa: input.destination.vpa }),
    },
    crypto.randomUUID(),
    fetcher,
  );
}

export async function retryRoyaltyWithdrawal(
  input: Auth & { withdrawalId: string; expectedVersion: number },
  fetcher: typeof fetch = fetch,
) {
  const payload = await callEarnings(
    input,
    {
      operation: "retryRoyaltyWithdrawal",
      withdrawalId: input.withdrawalId,
      expectedVersion: input.expectedVersion,
    },
    crypto.randomUUID(),
    fetcher,
  );
  if (typeof payload.withdrawalId !== "string") {
    throw new Error("The withdrawal response was invalid.");
  }
  return payload;
}

export type AdminRoyaltyPayout = {
  id: string;
  subjectType: string;
  subjectId: string;
  amountPaise: number;
  effectiveStatus: string;
  destinationSnapshot: { type: string; displayLabel: string };
  provider?: string;
  providerPayoutReference?: string;
  providerStatus?: string;
  reconciliationState?: string;
  utr?: string;
  requestedAt: string;
  attempts: Array<Record<string, unknown>>;
  providerRequests: Array<Record<string, unknown>>;
  webhookHistory: Array<Record<string, unknown>>;
};

export async function getAdminRoyaltyPayouts(
  input: Auth & { limit?: number },
  fetcher: typeof fetch = fetch,
): Promise<AdminRoyaltyPayout[]> {
  const payload = await callEarnings(
    input,
    { operation: "adminRoyaltyPayouts", limit: input.limit ?? 100 },
    crypto.randomUUID(),
    fetcher,
  );
  if (!Array.isArray(payload.withdrawals)) throw new Error("Payouts are unavailable.");
  return payload.withdrawals.map((value) => {
    const payout = record(value);
    const destination = record(payout.destinationSnapshot);
    if (
      typeof payout.id !== "string" || typeof payout.subjectType !== "string" ||
      typeof payout.subjectId !== "string" || !validMoney(payout.amountPaise) ||
      typeof payout.effectiveStatus !== "string" || typeof payout.requestedAt !== "string" ||
      typeof destination.type !== "string" || typeof destination.displayLabel !== "string" ||
      !Array.isArray(payout.attempts) || !Array.isArray(payout.providerRequests) ||
      !Array.isArray(payout.webhookHistory)
    ) throw new Error("Payouts are unavailable.");
    return {
      id: payout.id,
      subjectType: payout.subjectType,
      subjectId: payout.subjectId,
      amountPaise: payout.amountPaise,
      effectiveStatus: payout.effectiveStatus,
      destinationSnapshot: {
        type: destination.type,
        displayLabel: destination.displayLabel,
      },
      provider: optionalString(payout.provider),
      providerPayoutReference: optionalString(payout.providerPayoutReference),
      providerStatus: optionalString(payout.providerStatus),
      reconciliationState: optionalString(payout.reconciliationState),
      utr: optionalString(payout.utr),
      requestedAt: payout.requestedAt,
      attempts: payout.attempts.map(record),
      providerRequests: payout.providerRequests.map(record),
      webhookHistory: payout.webhookHistory.map(record),
    };
  });
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
      typeof destination.displayLabel !== "string"
    )
  ) throw new Error("Royalty is unavailable.");
  return {
    id: withdrawal.id,
    amountPaise: withdrawal.amountPaise,
    currency: "INR",
    status: withdrawal.status,
    destination: destination as RoyaltyWithdrawal["destination"],
    providerStatus: optionalString(withdrawal.providerStatus),
    reconciliationState: isReconciliationState(withdrawal.reconciliationState)
      ? withdrawal.reconciliationState
      : undefined,
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
    value === "FAILED_RETRYABLE" || value === "FAILED" || value === "REVERSED";
}

function isReconciliationState(
  value: unknown,
): value is NonNullable<RoyaltyWithdrawal["reconciliationState"]> {
  return value === "PENDING" || value === "IN_SYNC" || value === "RETRYABLE" ||
    value === "REVIEW_REQUIRED";
}
