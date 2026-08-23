import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type EarningsOperation =
  | "merchantSnapshot"
  | "deliveryPartnerSnapshot"
  | "merchantRoyaltySnapshot"
  | "deliveryRoyaltySnapshot"
  | "requestRoyaltyWithdrawal";

type EarningsRPC =
  | "get_dastak_merchant_earnings"
  | "get_dastak_delivery_earnings"
  | "dastak_v1_get_royalty_snapshot"
  | "dastak_v1_request_royalty_withdrawal";

export type EarningsDependencies = {
  authenticateBearer: AuthenticateBearer;
  callRPC: (rpc: EarningsRPC, args: Record<string, unknown>) => Promise<unknown>;
};

type RequestBody = {
  operation?: unknown;
  subjectType?: unknown;
  subjectId?: unknown;
  amountPaise?: unknown;
  idempotencyKey?: unknown;
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
      return json(result, 200);
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

function snapshotResponse(data: unknown) {
  const result = (Array.isArray(data) ? data[0] : data) as
    | Record<string, unknown>
    | undefined;
  if (!result || !Number.isInteger(result.response_status)) {
    throw new Error("Invalid earnings response");
  }
  const status = result.response_status as number;
  if (status < 100 || status > 599) throw new Error("Invalid earnings status");
  return json(result.response_body, status);
}
