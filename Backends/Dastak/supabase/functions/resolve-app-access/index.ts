import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type AppAccessRoute,
  handleResolveAppAccess,
  type ResolveAppAccessInput,
} from "./handler.ts";

const supabaseUrl = requiredEnv("SUPABASE_URL");
const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

const serviceRoleClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

Deno.serve((request) =>
  handleResolveAppAccess(request, {
    authenticateBearer: verifyBearerUser,
    resolveAppAccess: (input) => callResolveAppAccessRpc(serviceRoleClient, input),
  })
);

async function callResolveAppAccessRpc(
  client: {
    rpc: (
      functionName: "resolve_app_access",
      args: Record<string, string>,
    ) => PromiseLike<{ data: unknown; error: unknown }>;
  },
  input: ResolveAppAccessInput,
) {
  const { data, error } = await client.rpc("resolve_app_access", {
    p_account_id: input.accountId,
    p_application: input.application,
  });

  if (error) {
    throw error;
  }

  const row = (Array.isArray(data) ? data[0] : data) as {
    route?: unknown;
  } | null;
  if (!row || typeof row.route !== "string" || !isAppAccessRoute(row.route)) {
    throw new Error("resolve_app_access returned an invalid response");
  }

  return { route: row.route };
}

function isAppAccessRoute(value: string): value is AppAccessRoute {
  return [
    "needs_profile",
    "pending_approval",
    "suspended",
    "access_denied",
    "active",
  ].includes(value);
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}
