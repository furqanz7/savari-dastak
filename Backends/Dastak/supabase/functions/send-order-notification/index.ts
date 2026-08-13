import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import { corsPreflight, json } from "../_shared/http.ts";

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
  ) {
    return json({ error: { code: "forbidden" } }, 403);
  }

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const accountId = text(body?.accountId);
  const title = text(body?.title);
  const message = text(body?.message);
  const orderId = text(body?.orderId);
  if (!accountId || !title || !message || !orderId) {
    return json({ error: { code: "invalid_notification" } }, 400);
  }

  const { data: tokens, error } = await supabase
    .from("dastak_device_tokens")
    .select("device_token")
    .eq("account_id", accountId)
    .eq("platform", "ios");
  if (error) return json({ error: { code: "token_lookup_failed" } }, 500);

  const jwt = await providerToken();
  const endpoint = Deno.env.get("APNS_ENVIRONMENT") === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  let sent = 0;
  const invalidTokens: string[] = [];

  for (const row of tokens ?? []) {
    const token = text(row.device_token);
    if (!token) continue;
    const response = await fetch(`${endpoint}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": requiredEnv("APNS_BUNDLE_ID"),
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: { alert: { title, body: message }, sound: "default", badge: 1 },
        orderId,
      }),
    });
    if (response.ok) sent += 1;
    else if (response.status === 400 || response.status === 410) invalidTokens.push(token);
  }

  if (invalidTokens.length > 0) {
    await supabase.from("dastak_device_tokens").delete().in("device_token", invalidTokens);
  }
  return json({ sent, removed: invalidTokens.length }, 200);
});

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

function text(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}
