import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type EarningsOperation =
  | "merchantSnapshot"
  | "deliveryPartnerSnapshot"
  | "merchantRoyaltySnapshot"
  | "deliveryRoyaltySnapshot"
  | "requestRoyaltyWithdrawal"
  | "registerRoyaltyPayoutDestination"
  | "retryRoyaltyWithdrawal"
  | "adminRoyaltyPayouts";

type EarningsRPC =
  | "get_dastak_merchant_earnings"
  | "get_dastak_delivery_earnings"
  | "dastak_v1_get_royalty_snapshot"
  | "dastak_v1_request_royalty_withdrawal"
  | "dastak_v1_razorpayx_admin_page";

export type EarningsDependencies = {
  authenticateBearer: AuthenticateBearer;
  callRPC: (rpc: EarningsRPC, args: Record<string, unknown>) => Promise<unknown>;
  registerPayoutDestination: (
    actorId: string,
    input: PayoutDestinationRequest,
  ) => Promise<unknown>;
  executeWithdrawal: (
    actorId: string,
    withdrawalId: string,
    expectedVersion: number,
  ) => Promise<unknown>;
  payoutAvailability: () => {
    destinationRegistrationAvailable: boolean;
    withdrawalExecutionAvailable: boolean;
  };
};

type RequestBody = {
  operation?: unknown;
  subjectType?: unknown;
  subjectId?: unknown;
  amountPaise?: unknown;
  idempotencyKey?: unknown;
  destinationType?: unknown;
  holderName?: unknown;
  accountNumber?: unknown;
  confirmAccountNumber?: unknown;
  ifsc?: unknown;
  vpa?: unknown;
  withdrawalId?: unknown;
  expectedVersion?: unknown;
  limit?: unknown;
  cursor?: unknown;
};

export type PayoutDestinationRequest = {
  subjectType: "MERCHANT_ORGANIZATION" | "RIDER";
  subjectId: string;
  destination:
    | { type: "BANK_ACCOUNT"; holderName: string; accountNumber: string; ifsc: string }
    | { type: "UPI"; holderName: string; vpa: string };
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleEarnings(request: Request, dependencies: EarningsDependencies) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") {
    return json({ error: { code: "method_not_allowed", message: "Use POST." } }, 405);
  }

  const authorization = request.headers.get("authorization") ?? "";
  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return json(
      { error: { code: "authentication_required", message: "Sign in is required." } },
      401,
    );
  }

  const body = await request.json().catch(() => null) as RequestBody | null;
  const operation = body?.operation as EarningsOperation | undefined;
  try {
    if (operation === "merchantSnapshot" || operation === "deliveryPartnerSnapshot") {
      const rpc = operation === "merchantSnapshot"
        ? "get_dastak_merchant_earnings" as const
        : "get_dastak_delivery_earnings" as const;
      return snapshotResponse(
        await dependencies.callRPC(rpc, {
          p_account_id: actor.accountId,
        }),
      );
    }
    if (operation === "merchantRoyaltySnapshot" || operation === "deliveryRoyaltySnapshot") {
      return snapshotResponse(
        await dependencies.callRPC(
          "dastak_v1_get_royalty_snapshot",
          {
            p_account_id: actor.accountId,
            p_kind: operation === "merchantRoyaltySnapshot" ? "MERCHANT" : "RIDER",
          },
        ),
        { payoutAvailability: dependencies.payoutAvailability() },
      );
    }
    if (operation === "requestRoyaltyWithdrawal") {
      const idempotencyKey = request.headers.get("x-idempotency-key") ??
        body?.idempotencyKey;
      if (
        (body?.subjectType !== "MERCHANT_ORGANIZATION" &&
          body?.subjectType !== "RIDER") ||
        typeof body.subjectId !== "string" || !uuidPattern.test(body.subjectId) ||
        typeof body.amountPaise !== "number" ||
        !Number.isSafeInteger(body.amountPaise) ||
        body.amountPaise <= 0 || typeof idempotencyKey !== "string" ||
        idempotencyKey.length < 1 || idempotencyKey.length > 200
      ) {
        return json({
          error: { code: "invalid_withdrawal", message: "Enter a valid withdrawal amount." },
        }, 400);
      }
      const result = await dependencies.callRPC("dastak_v1_request_royalty_withdrawal", {
        p_account_id: actor.accountId,
        p_subject_type: body.subjectType,
        p_subject_id: body.subjectId,
        p_amount_paise: body.amountPaise,
        p_idempotency_key: idempotencyKey,
      });
      const withdrawal = record(result);
      if (
        !withdrawal || typeof withdrawal.withdrawalId !== "string" ||
        !uuidPattern.test(withdrawal.withdrawalId) ||
        typeof withdrawal.version !== "number" ||
        !Number.isSafeInteger(withdrawal.version) || withdrawal.version < 1
      ) throw new Error("invalid withdrawal response");
      try {
        const processed = record(
          await dependencies.executeWithdrawal(
            actor.accountId,
            withdrawal.withdrawalId,
            withdrawal.version,
          ),
        );
        if (!processed) throw new Error("invalid payout response");
        return json({ ...withdrawal, ...processed }, 200);
      } catch {
        return json({
          ...withdrawal,
          providerProcessingDeferred: true,
          reconciliationState: "RETRYABLE",
        }, 202);
      }
    }
    if (operation === "registerRoyaltyPayoutDestination") {
      const payoutDestination = parsePayoutDestination(body);
      if (!payoutDestination) {
        return json({
          error: {
            code: "invalid_payout_destination",
            message: "Enter a valid Indian bank account or UPI ID.",
          },
        }, 400);
      }
      return json(
        await dependencies.registerPayoutDestination(
          actor.accountId,
          payoutDestination,
        ),
        200,
      );
    }
    if (operation === "retryRoyaltyWithdrawal") {
      if (
        typeof body?.withdrawalId !== "string" ||
        !uuidPattern.test(body.withdrawalId) ||
        typeof body.expectedVersion !== "number" ||
        !Number.isSafeInteger(body.expectedVersion) || body.expectedVersion < 1
      ) {
        return json({
          error: { code: "invalid_withdrawal", message: "The withdrawal cannot be retried." },
        }, 400);
      }
      return json(
        await dependencies.executeWithdrawal(
          actor.accountId,
          body.withdrawalId,
          body.expectedVersion,
        ),
        200,
      );
    }
    if (operation === "adminRoyaltyPayouts") {
      const limit = body?.limit === undefined ? 50 : body.limit;
      const cursor = record(body?.cursor);
      const afterRequestedAt = cursor && validTimestamp(cursor.requestedAt)
        ? cursor.requestedAt as string
        : null;
      const afterWithdrawalId = cursor && typeof cursor.withdrawalId === "string" &&
          uuidPattern.test(cursor.withdrawalId)
        ? cursor.withdrawalId
        : null;
      if (typeof limit !== "number" || !Number.isSafeInteger(limit) || limit < 1 || limit > 100 ||
        (body?.cursor !== null && body?.cursor !== undefined && !cursor) ||
        (cursor !== undefined && (!afterRequestedAt || !afterWithdrawalId))) {
        return json({ error: { code: "invalid_limit", message: "Invalid payout limit." } }, 400);
      }
      return snapshotResponse(
        await dependencies.callRPC("dastak_v1_razorpayx_admin_page", {
          p_account_id: actor.accountId,
          p_limit: limit,
          p_after_requested_at: afterRequestedAt,
          p_after_withdrawal_id: afterWithdrawalId,
        }),
      );
    }
    return json({
      error: { code: "invalid_operation", message: "Invalid earnings operation." },
    }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    if (message.includes("PAYOUT_DESTINATION_REQUIRED")) {
      return json({
        error: {
          code: "payout_destination_required",
          message: "A payout destination must be registered before withdrawing.",
        },
      }, 409);
    }
    if (
      message.includes("RazorpayX") || message.includes("RAZORPAYX_") ||
      message.includes("provider")
    ) {
      return json({
        error: {
          code: "payout_provider_unavailable",
          message: "The payout service is temporarily unavailable. No Royalty was lost.",
        },
      }, 503);
    }
    if (
      message.includes("POSITIVE_ROYALTY_BALANCE_REQUIRED") ||
      message.includes("WITHDRAWAL_EXCEEDS_AVAILABLE_ROYALTY")
    ) {
      return json({
        error: {
          code: "royalty_balance_unavailable",
          message: "The withdrawal exceeds the currently available Royalty.",
        },
      }, 409);
    }
    return json({
      error: { code: "earnings_unavailable", message: "Royalty is temporarily unavailable." },
    }, 503);
  }
}

function parsePayoutDestination(body: RequestBody | null): PayoutDestinationRequest | undefined {
  if (
    !body || (body.subjectType !== "MERCHANT_ORGANIZATION" && body.subjectType !== "RIDER") ||
    typeof body.subjectId !== "string" || !uuidPattern.test(body.subjectId) ||
    typeof body.holderName !== "string"
  ) return undefined;
  const holderName = body.holderName.trim().replace(/\s+/g, " ");
  if (
    holderName.length < 3 || holderName.length > 50 ||
    !/^[A-Za-z0-9 ._()/'-]+$/.test(holderName) || /[^A-Za-z0-9.]$/.test(holderName)
  ) return undefined;
  if (body.destinationType === "BANK_ACCOUNT") {
    if (
      typeof body.accountNumber !== "string" ||
      typeof body.confirmAccountNumber !== "string" ||
      body.accountNumber.replace(/\s+/g, "") !== body.confirmAccountNumber.replace(/\s+/g, "") ||
      typeof body.ifsc !== "string"
    ) return undefined;
    const accountNumber = body.accountNumber.replace(/\s+/g, "");
    const ifsc = body.ifsc.trim().toUpperCase();
    if (!/^[0-9]{6,34}$/.test(accountNumber) || !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc)) {
      return undefined;
    }
    return {
      subjectType: body.subjectType,
      subjectId: body.subjectId,
      destination: { type: "BANK_ACCOUNT", holderName, accountNumber, ifsc },
    };
  }
  if (body.destinationType === "UPI" && typeof body.vpa === "string") {
    const vpa = body.vpa.trim().toLowerCase();
    if (vpa.length <= 120 && /^[a-z0-9._-]{2,64}@[a-z0-9.-]{2,64}$/.test(vpa)) {
      return {
        subjectType: body.subjectType,
        subjectId: body.subjectId,
        destination: { type: "UPI", holderName, vpa },
      };
    }
  }
  return undefined;
}

function snapshotResponse(
  data: unknown,
  additions?: Record<string, unknown>,
) {
  const result = (Array.isArray(data) ? data[0] : data) as
    | Record<string, unknown>
    | undefined;
  if (!result || !Number.isInteger(result.response_status)) {
    throw new Error("Invalid earnings response");
  }
  const status = result.response_status as number;
  if (status < 100 || status > 599) throw new Error("Invalid earnings status");
  const responseBody = record(result.response_body);
  return json(
    additions && responseBody ? { ...responseBody, ...additions } : result.response_body,
    status,
  );
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function validTimestamp(value: unknown) {
  return typeof value === "string" && value.length <= 50 && Number.isFinite(Date.parse(value));
}
