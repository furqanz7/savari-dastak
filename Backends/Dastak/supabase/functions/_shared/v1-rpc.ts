import { createClient } from "npm:@supabase/supabase-js@2";

export class V1RequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export async function callAuthenticatedRPC(
  accessToken: string,
  functionName: string,
  parameters: Record<string, unknown>,
) {
  const client = createClient(requiredEnv("SUPABASE_URL"), publishableKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const { data, error } = await client.rpc(functionName, parameters);
  if (error) throw safeRPCError(error);
  return data;
}

function safeRPCError(error: { code?: string }) {
  switch (error.code) {
    case "42501":
      return new V1RequestError(403, "access_denied", "This account cannot perform that action.");
    case "P0002":
      return new V1RequestError(404, "not_found", "The requested Dastak record was not found.");
    case "40001":
      return new V1RequestError(
        409,
        "stale_version",
        "This information changed. Refresh and try again.",
      );
    case "55000":
      return new V1RequestError(
        409,
        "invalid_state",
        "That action is not available in the current state.",
      );
    case "22003":
    case "22023":
    case "22P02":
      return new V1RequestError(400, "validation_failed", "The request contains invalid values.");
    case "23505":
      return new V1RequestError(409, "conflict", "That catalogue value is already in use.");
    default:
      return new V1RequestError(
        500,
        "internal_error",
        "The Dastak request could not be processed.",
      );
  }
}

function publishableKey() {
  const direct = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY");
  if (direct) return direct;
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")
    ?.split(",")
    .map((key) => key.trim())
    .filter(Boolean);
  if (keys?.[0]) return keys[0];
  throw new Error("A Supabase publishable key is required.");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
