import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { type BootstrapAccountInput, handleBootstrapAccount } from "./handler.ts";
import { verifyBearerUser } from "../_shared/auth.ts";

const supabaseUrl = requiredEnv("SUPABASE_URL");
const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

const serviceRoleClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

Deno.serve((request) =>
  handleBootstrapAccount(request, {
    authenticateBearer: verifyBearerUser,
    bootstrapAccount: (input) => callBootstrapAccountRpc(serviceRoleClient, input),
  })
);

async function callBootstrapAccountRpc(
  client: {
    rpc: (
      functionName: "bootstrap_account",
      args: Record<string, string>,
    ) => PromiseLike<{ data: unknown; error: unknown }>;
  },
  input: BootstrapAccountInput,
) {
  const { data, error } = await client.rpc("bootstrap_account", {
    p_account_id: input.accountId,
    p_display_name: input.displayName,
    p_phone_number: input.phoneNumber,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });

  if (error) {
    throw error;
  }

  const row = (Array.isArray(data) ? data[0] : data) as {
    response_body?: unknown;
    response_status?: unknown;
  };
  if (
    !row ||
    typeof row !== "object" ||
    !("response_body" in row) ||
    !("response_status" in row)
  ) {
    throw new Error("bootstrap_account returned an invalid response");
  }

  return {
    responseBody: row.response_body,
    responseStatus: Number(row.response_status),
  };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}
