import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleEarnings } from "./handler.ts";
import {
  payoutGatewayFromEnvironment,
  razorpayXTestDestinationClientFromEnvironment,
} from "./provider-clients.ts";
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
        client: razorpayXTestDestinationClientFromEnvironment(),
        callRPC,
      }),
    executeWithdrawal: (actorId, withdrawalId, expectedVersion) =>
      executeRazorpayXWithdrawal({
        actorId,
        withdrawalId,
        expectedVersion,
        client: payoutGatewayFromEnvironment(),
        callRPC,
      }),
  })
);

async function callRPC(rpc: string, args: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(rpc, args);
  if (error) throw error;
  return data;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
