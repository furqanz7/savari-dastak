import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import { corsPreflight, json } from "../_shared/http.ts";

const supabase = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  {
    auth: { autoRefreshToken: false, persistSession: false },
  },
);

Deno.serve(async (request) => {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (
    request.headers.get("x-dastak-internal-secret") !== requiredEnv("DASTAK_NOTIFICATION_SECRET")
  ) {
    return json({ error: { code: "forbidden" } }, 403);
  }

  const { data: events, error } = await supabase
    .from("dastak_order_notification_queue")
    .select("id, order_id, account_id, status, payment_state, attempts")
    .is("processed_at", null)
    .lt("attempts", 5)
    .order("created_at", { ascending: true })
    .limit(1);
  if (error) {
    return json({
      error: { code: "queue_read_failed", message: error.message, details: error.details },
    }, 500);
  }

  let processed = 0;
  const diagnostics: Array<{ id: string; sent: boolean; responses: string[] }> = [];
  for (const event of events) {
    const result = await sendNotification(event);
    const sent = result.sent;
    diagnostics.push({ id: event.id, sent, responses: result.responses });
    await supabase.from("dastak_order_notification_queue")
      .update({ attempts: event.attempts + 1 })
      .eq("id", event.id);
    if (sent) {
      await supabase.from("dastak_order_notification_queue")
        .update({ processed_at: new Date().toISOString() })
        .eq("id", event.id);
      processed += 1;
    }
  }
  return json({ claimed: events.length, processed, diagnostics }, 200);
});

type QueueEvent = {
  id: string;
  order_id: string;
  account_id: string;
  status: string;
  payment_state: string;
  attempts: number;
};

async function sendNotification(
  event: QueueEvent,
): Promise<{ sent: boolean; responses: string[] }> {
  const { data: tokens, error } = await supabase
    .from("dastak_device_tokens")
    .select("device_token")
    .eq("account_id", event.account_id)
    .eq("platform", "ios");
  if (error) throw error;
  if (!tokens || tokens.length === 0) return { sent: true, responses: [] };

  const jwt = await providerToken();
  const endpoint = Deno.env.get("APNS_ENVIRONMENT") === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const title = event.payment_state === "paid" ? "Payment confirmed" : "Order update";
  const message = statusMessage(event.status, event.payment_state);
  let successful = false;
  const responses: string[] = [];
  for (const { device_token: token } of tokens) {
    const response = await fetch(`${endpoint}/3/device/${token}`, {
      method: "POST",
      signal: AbortSignal.timeout(8_000),
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": requiredEnv("APNS_BUNDLE_ID"),
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: { alert: { title, body: message }, sound: "default", badge: 1 },
        orderId: event.order_id,
      }),
    });
    responses.push(`${response.status}:${await response.text()}`);
    if (response.ok) successful = true;
    if (response.status === 400 || response.status === 410) {
      await supabase.from("dastak_device_tokens").delete().eq("device_token", token);
    }
  }
  return { sent: successful, responses };
}

function statusMessage(status: string, paymentState: string) {
  if (paymentState === "refund_pending") return "Your refund is being processed.";
  if (paymentState === "refunded") return "Your refund has been completed.";
  switch (status) {
    case "paid":
      return "Your order is waiting for the store.";
    case "merchant_accepted":
      return "The store accepted your order.";
    case "ready":
      return "Your order is ready for pickup.";
    case "assigned":
      return "A delivery partner was assigned.";
    case "en_route_to_pickup":
      return "Your delivery partner is heading to the store.";
    case "at_store":
      return "Your delivery partner reached the store.";
    case "returning_to_merchant":
      return "Your order is being returned to the store.";
    case "picked_up":
    case "in_transit":
      return "Your order is on the way.";
    case "delivered":
      return "Your order was delivered.";
    case "cancelled":
      return "Your order was cancelled.";
    default:
      return "Your order status changed.";
  }
}

async function providerToken() {
  const key = await importPKCS8(requiredEnv("APNS_PRIVATE_KEY"), "ES256");
  return new SignJWT({ iss: requiredEnv("APNS_TEAM_ID") })
    .setProtectedHeader({ alg: "ES256", kid: requiredEnv("APNS_KEY_ID") })
    .setIssuedAt()
    .sign(key);
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
