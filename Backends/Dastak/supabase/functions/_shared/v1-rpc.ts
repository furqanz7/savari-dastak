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

export function safeRPCError(error: { code?: string; message?: string }) {
  if (error.code === "55000" && error.message === "ACTIVE_FULFILMENTS_REQUIRE_RESOLUTION") {
    return new V1RequestError(
      409,
      "active_fulfilments_require_resolution",
      "Pause new work and resolve every active fulfilment or custody journey before suspending this Merchant.",
    );
  }
  if (error.code === "55000" && error.message === "ACTIVE_PICKUP_OR_RETURN_WORK") {
    return new V1RequestError(
      409,
      "active_pickup_or_return_work",
      "Route-critical branch details cannot change while pickup or return work is active.",
    );
  }
  if (error.code === "P0001" && error.message === "RIDER_ACTIVE_WORK_CONFLICT") {
    return new V1RequestError(
      409,
      "rider_active_work_conflict",
      "This delivery partner must complete the active job before another can be assigned.",
    );
  }
  if (error.code === "P0001" && error.message === "RIDER_GOVERNANCE_SUSPENDED") {
    return new V1RequestError(
      409,
      "rider_governance_suspended",
      "This Delivery Partner is suspended and cannot become available or accept new work.",
    );
  }
  if (error.code === "55000" && error.message === "RIDER_ACTIVE_WORK_REQUIRES_RELEASE") {
    return new V1RequestError(
      409,
      "rider_active_work_requires_release",
      "Use the existing recovery or release workflow before suspending this Delivery Partner.",
    );
  }
  if (error.code === "23505" && error.message === "PHONE_NUMBER_ALREADY_CLAIMED") {
    return new V1RequestError(
      409,
      "phone_number_in_use",
      "That phone number is already claimed by another Dastak identity.",
    );
  }
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
