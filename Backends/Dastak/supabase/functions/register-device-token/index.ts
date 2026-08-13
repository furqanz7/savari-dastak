import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleRegisterDeviceToken } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleRegisterDeviceToken(request, {
    authenticateBearer: verifyBearerUser,
    upsertToken: async (accountId, token, platform) => {
      const { error } = await serviceClient.from("dastak_device_tokens").upsert({
        account_id: accountId,
        device_token: token,
        platform,
        last_seen_at: new Date().toISOString(),
      }, { onConflict: "device_token" });
      if (error) throw error;
    },
  })
);

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
