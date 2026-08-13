import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleCustomerAddresses, type SaveCustomerAddressInput } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleCustomerAddresses(request, {
    authenticateBearer: verifyBearerUser,
    snapshot: getSnapshot,
    saveDefault,
  })
);

async function getSnapshot(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_customer_delivery_addresses", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_customer_delivery_addresses");
}

async function saveDefault(input: SaveCustomerAddressInput) {
  const { data, error } = await serviceClient.rpc("save_default_customer_delivery_address", {
    p_account_id: input.accountId,
    p_label: input.label,
    p_address: input.address,
    p_details: input.details,
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "save_default_customer_delivery_address");
}

function rpcResponse(data: unknown, functionName: string) {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return { responseBody: row.response_body, responseStatus: row.response_status };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
