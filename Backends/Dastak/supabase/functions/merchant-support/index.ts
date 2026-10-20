import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleMerchantSupport } from "./handler.ts";
import { supportBulkhead } from "./limits.ts";

const client = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (url, init) =>
        fetch(url, {
          ...init,
          signal: init?.signal
            ? AbortSignal.any([init.signal, AbortSignal.timeout(6000)])
            : AbortSignal.timeout(6000),
        }),
    },
  },
);
const enter = supportBulkhead();
Deno.serve((request) =>
  handleMerchantSupport(request, {
    // Fail closed until separately approved for production activation.
    enabled: Deno.env.get("MERCHANT_SUPPORT_ENABLED") === "true",
    enter,
    authenticate: (bearer, signal) => verifyBearerUser(bearer, { signal }),
    command: async (actor, input, signal) => {
      const { data, error } = await client.rpc("merchant_support_command", {
        p_actor: actor,
        p_input: input,
      }).abortSignal(signal ?? AbortSignal.timeout(6000));
      if (error) throw new Error(error.message);
      return data;
    },
  })
);
