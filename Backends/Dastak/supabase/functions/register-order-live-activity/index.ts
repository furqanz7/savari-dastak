import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerSession } from "../_shared/auth.ts";
import { handleRegistration } from "./handler.ts";
const client = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { autoRefreshToken: false, persistSession: false },
  },
);
Deno.serve((request) =>
  handleRegistration(request, {
    authenticate: verifyBearerSession,
    register: async (actor, input) => {
      const { error } = await client.rpc("dastak_register_order_live_activity", {
        p_account_id: actor.accountId,
        p_session_id: actor.sessionId,
        p_order_id: input.orderId,
        p_activity_id: input.activityId,
        p_token: input.token,
        p_environment: input.environment,
      });
      if (error) throw error;
    },
  })
);
