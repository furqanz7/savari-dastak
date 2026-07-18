import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handlePaymentLedger, type OwnerFinancialRateCardInput } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handlePaymentLedger(request, {
    authenticateBearer: verifyBearerUser,
    upsertRateCard,
    getOrderSnapshot,
  })
);

async function upsertRateCard(input: OwnerFinancialRateCardInput) {
  const { data, error } = await serviceClient.rpc(
    "upsert_merchant_order_financial_rate_card",
    {
      p_account_id: input.accountId,
      p_service_zone_id: input.serviceZoneId,
      p_delivery_fee_paise: input.deliveryFeePaise,
      p_merchant_commission_bps: input.merchantCommissionBps,
      p_courier_payout_paise: input.courierPayoutPaise,
      p_active: input.active,
      p_idempotency_key: input.idempotencyKey,
      p_request_digest: input.requestDigest,
    },
  );
  if (error) throw error;
  return rpcResponse(data, "upsert_merchant_order_financial_rate_card");
}

async function getOrderSnapshot(accountId: string, orderId: string) {
  const { data, error } = await serviceClient.rpc(
    "get_owner_merchant_order_financial_snapshot",
    { p_account_id: accountId, p_order_id: orderId },
  );
  if (error) throw error;
  return rpcResponse(data, "get_owner_merchant_order_financial_snapshot");
}

function rpcResponse(data: unknown, functionName: string) {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return {
    responseBody: row.response_body,
    responseStatus: row.response_status,
  };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
