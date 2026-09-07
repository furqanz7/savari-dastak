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
    upsertToken: async (accountId, token, platform, applicationId, apnsEnvironment) => {
      const { error } = await serviceClient.rpc("dastak_v1_register_app_device_token", {
        p_account_id: accountId,
        p_device_token: token,
        p_platform: platform,
        p_application_id: applicationId,
        p_apns_environment: apnsEnvironment,
      });
      if (error) throw error;
    },
  })
);

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
