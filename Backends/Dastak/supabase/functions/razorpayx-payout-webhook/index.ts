import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import { handleRazorpayXPayoutWebhook, type RazorpayXPayoutWebhookEvent } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) => {
  const webhookSecret = Deno.env.get("RAZORPAYX_WEBHOOK_SECRET");
  if (!webhookSecret) {
    return json({
      error: {
        code: "provider_configuration_missing",
        message: "RazorpayX payout webhooks are not configured.",
      },
    }, 503);
  }
  return handleRazorpayXPayoutWebhook(request, {
    webhookSecret,
    recordEvent,
  });
});

async function recordEvent(event: RazorpayXPayoutWebhookEvent) {
  const { data, error } = await serviceClient.rpc(
    "dastak_v1_apply_razorpayx_payout_status",
    {
      p_provider_event_id: event.providerEventId,
      p_source: "WEBHOOK",
      p_withdrawal_id: event.withdrawalId,
      p_attempt_id: null,
      p_provider_payout_reference: event.providerPayoutReference,
      p_provider_event_type: event.providerEventType,
      p_provider_status: event.providerStatus,
      p_amount_paise: event.amountPaise,
      p_currency_code: event.currency,
      p_fund_account_reference: event.fundAccountReference,
      p_request_digest: event.requestDigest,
      p_payload_metadata: event.payloadMetadata,
      p_occurred_at: event.occurredAt,
      p_provider_created_at: event.providerCreatedAt,
      p_utr: event.utr ?? null,
      p_status_details: event.statusDetails,
    },
  );
  if (error) throw error;
  return data;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
