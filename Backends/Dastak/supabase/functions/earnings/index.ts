import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { RazorpayXClient, type RazorpayXMode } from "../_shared/razorpayx.ts";
import { handleEarnings } from "./handler.ts";
import { executeRazorpayXWithdrawal, registerRazorpayXDestination } from "./razorpayx.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleEarnings(request, {
    authenticateBearer: verifyBearerUser,
    callRPC,
    registerPayoutDestination: (actorId, input) =>
      registerRazorpayXDestination({
        actorId,
        ...input,
        fingerprintSecret: requiredEnv("RAZORPAYX_DESTINATION_FINGERPRINT_SECRET"),
        client: razorpayXClient(),
        callRPC,
      }),
    executeWithdrawal: (actorId, withdrawalId, expectedVersion) =>
      executeRazorpayXWithdrawal({
        actorId,
        withdrawalId,
        expectedVersion,
        client: razorpayXClient(),
        callRPC,
      }),
  })
);

async function callRPC(rpc: string, args: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(rpc, args);
  if (error) throw error;
  return data;
}

function razorpayXClient() {
  const mode = requiredEnv("RAZORPAYX_MODE") as RazorpayXMode;
  if (mode !== "TEST" && mode !== "LIVE") throw new Error("Invalid RazorpayX mode");
  return new RazorpayXClient({
    keyId: requiredEnv("RAZORPAYX_KEY_ID"),
    keySecret: requiredEnv("RAZORPAYX_KEY_SECRET"),
    accountNumber: requiredEnv("RAZORPAYX_ACCOUNT_NUMBER"),
    mode,
    liveEgressAllowlistConfirmed:
      Deno.env.get("RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED") === "true",
  });
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
