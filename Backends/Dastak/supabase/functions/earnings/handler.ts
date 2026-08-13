import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type EarningsOperation = "merchantSnapshot" | "deliveryPartnerSnapshot";
type EarningsRPC = "get_dastak_merchant_earnings" | "get_dastak_delivery_earnings";

export type EarningsDependencies = {
  authenticateBearer: AuthenticateBearer;
  fetchSnapshot: (rpc: EarningsRPC, accountId: string) => Promise<unknown>;
};

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

  const body = await request.json().catch(() => null) as { operation?: unknown } | null;
  const operation = body?.operation as EarningsOperation | undefined;
  const rpc: EarningsRPC | undefined = operation === "merchantSnapshot"
    ? "get_dastak_merchant_earnings"
    : operation === "deliveryPartnerSnapshot"
    ? "get_dastak_delivery_earnings"
    : undefined;
  if (!rpc) {
    return json({
      error: { code: "invalid_operation", message: "Invalid earnings operation." },
    }, 400);
  }

  try {
    const data = await dependencies.fetchSnapshot(rpc, actor.accountId);
    const result = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
    if (!result || !Number.isInteger(result.response_status)) {
      throw new Error("Invalid earnings response");
    }
    const status = result.response_status as number;
    if (status < 100 || status > 599) throw new Error("Invalid earnings status");
    return json(result.response_body, status);
  } catch {
    return json({
      error: { code: "earnings_unavailable", message: "Earnings are temporarily unavailable." },
    }, 503);
  }
}
