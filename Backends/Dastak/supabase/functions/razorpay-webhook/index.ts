import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import { handleRazorpayWebhook, type RazorpayWebhookEvent } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) => {
  const liveWebhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  const testWebhookSecret = Deno.env.get("RAZORPAY_TEST_WEBHOOK_SECRET");
  if (!liveWebhookSecret || !testWebhookSecret || liveWebhookSecret === testWebhookSecret) {
    return json({
      error: {
        code: "provider_configuration_missing",
        message: "Razorpay webhook modes are not configured independently.",
      },
    }, 503);
  }
  return handleRazorpayWebhook(request, {
    liveWebhookSecret,
    testWebhookSecret,
    recordEvent,
  });
});

async function recordEvent(event: RazorpayWebhookEvent) {
  const parameters = {
    p_provider_mode: event.providerMode,
    p_provider_event_id: event.providerEventId,
    p_event_type: event.eventType,
    p_provider_order_reference: event.providerOrderReference ?? null,
    p_provider_payment_reference: event.providerPaymentReference,
    p_provider_refund_reference: event.providerRefundReference ?? null,
    p_amount_paise: event.amountPaise,
    p_occurred_at: event.occurredAt,
    p_request_digest: event.requestDigest,
  };
  const v1 = await rpc("dastak_v1_record_razorpay_event_mode", parameters);
  if (v1.responseStatus !== 404) return v1;
  if (event.providerMode === "TEST") return v1;
  const { p_provider_mode: _providerMode, ...legacyParameters } = parameters;
  const merchant = await rpc("record_razorpay_merchant_order_event", legacyParameters);
  if (merchant.responseStatus !== 404) return merchant;
  return await rpc("record_razorpay_parcel_event", legacyParameters);
}

async function rpc(functionName: string, parameters: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(functionName, parameters);
  if (error) throw error;
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return { responseBody: row.response_body, responseStatus: row.response_status };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
