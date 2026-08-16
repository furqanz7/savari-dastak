import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerSession } from "../_shared/auth.ts";
import { handleAccountSessions } from "./handler.ts";

type Actor = Awaited<ReturnType<typeof verifyBearerSession>>;

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleAccountSessions(request, {
    authenticateBearer: verifyBearerSession,
    touch,
    snapshot,
    revokeOthers,
    endOthers,
    endCurrent,
  })
);

async function touch(actor: Actor, metadata: {
  deviceName: string;
  platform: "ios" | "web";
  appName: string;
  userAgent?: string;
}) {
  return callRpc("touch_account_session", {
    p_account_id: actor.accountId,
    p_session_id: actor.sessionId,
    p_device_name: metadata.deviceName,
    p_platform: metadata.platform,
    p_app_name: metadata.appName,
    p_user_agent: metadata.userAgent ?? null,
  });
}

async function snapshot(actor: Actor) {
  return callRpc("get_account_sessions", {
    p_account_id: actor.accountId,
    p_current_session_id: actor.sessionId,
  });
}

async function revokeOthers(accessToken: string) {
  const { error } = await serviceClient.auth.admin.signOut(accessToken, "others");
  if (error) throw error;
}

async function endOthers(actor: Actor) {
  return callRpc("end_other_account_sessions", {
    p_account_id: actor.accountId,
    p_current_session_id: actor.sessionId,
  });
}

async function endCurrent(actor: Actor) {
  return callRpc("end_account_session", {
    p_account_id: actor.accountId,
    p_session_id: actor.sessionId,
  });
}

async function callRpc(functionName: string, parameters: Record<string, unknown>) {
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
