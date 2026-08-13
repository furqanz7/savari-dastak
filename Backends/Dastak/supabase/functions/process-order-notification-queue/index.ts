import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import { corsPreflight, json } from "../_shared/http.ts";
import {
  notificationCopy,
  notificationPayload,
  type NotificationQueueEvent,
} from "./notification.ts";

const supabase = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve(async (request) => {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (
    request.headers.get("x-dastak-internal-secret") !== requiredEnv("DASTAK_NOTIFICATION_SECRET")
  ) return json({ error: { code: "forbidden" } }, 403);

  try {
    const events = await readPendingEvents();
    const diagnostics: Array<{ id: string; sent: boolean; responses: string[] }> = [];
    let processed = 0;

    for (const event of events) {
      const result = await sendNotification(event);
      diagnostics.push({ id: event.id, sent: result.sent, responses: result.responses });
      await updateEvent(event, result.sent);
      if (result.sent) processed += 1;
    }

    return json({ claimed: events.length, processed, diagnostics }, 200);
  } catch (error) {
    console.error("Notification queue processing failed", error);
    return json({ error: { code: "notification_processing_failed" } }, 500);
  }
});

async function readPendingEvents(): Promise<NotificationQueueEvent[]> {
  const [orders, parcels] = await Promise.all([
    readQueue("dastak_order_notification_queue", "merchantOrder", "order_id"),
    readQueue("dastak_parcel_notification_queue", "parcel", "parcel_id"),
  ]);
  return [...orders, ...parcels]
    .sort((left, right) => left.createdAt.localeCompare(right.createdAt))
    .slice(0, 4);
}

async function readQueue(
  table: NotificationQueueEvent["table"],
  entityType: NotificationQueueEvent["entityType"],
  entityColumn: "order_id" | "parcel_id",
): Promise<NotificationQueueEvent[]> {
  const { data, error } = await supabase
    .from(table)
    .select(`id, ${entityColumn}, account_id, status, payment_state, attempts, created_at`)
    .is("processed_at", null)
    .lt("attempts", 5)
    .order("created_at", { ascending: true })
    .limit(2);
  if (error) throw error;

  return (data ?? []).map((row) => {
    const record = row as unknown as Record<string, string | number>;
    return {
      id: String(record.id),
      table,
      entityType,
      entityId: String(record[entityColumn]),
      accountId: String(record.account_id),
      status: String(record.status),
      paymentState: String(record.payment_state),
      attempts: Number(record.attempts),
      createdAt: String(record.created_at),
    };
  });
}

async function updateEvent(event: NotificationQueueEvent, sent: boolean) {
  const changes: Record<string, unknown> = { attempts: event.attempts + 1 };
  if (sent) changes.processed_at = new Date().toISOString();
  const { error } = await supabase.from(event.table).update(changes).eq("id", event.id);
  if (error) throw error;
}

async function sendNotification(
  event: NotificationQueueEvent,
): Promise<{ sent: boolean; responses: string[] }> {
  const { data: tokens, error } = await supabase
    .from("dastak_device_tokens")
    .select("device_token")
    .eq("account_id", event.accountId)
    .eq("platform", "ios");
  if (error) throw error;
  if (!tokens?.length) return { sent: true, responses: [] };

  const jwt = await providerToken();
  const endpoint = Deno.env.get("APNS_ENVIRONMENT") === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const copy = notificationCopy(event);
  const responses: string[] = [];
  let successful = false;

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
        aps: { alert: copy, sound: "default", badge: 1 },
        ...notificationPayload(event),
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
