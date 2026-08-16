import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  handleCustomerAddresses,
  type AddressActionInput,
  type SaveCustomerAddressInput,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleCustomerAddresses(request, {
    authenticateBearer: verifyBearerUser,
    snapshot: getSnapshot,
    save,
    setDefault,
    deleteAddress,
  })
);

async function getSnapshot(accountId: string) {
  return callRpc("get_customer_delivery_addresses", { p_account_id: accountId });
}

async function save(input: SaveCustomerAddressInput) {
  return callRpc("save_customer_delivery_address", {
    p_account_id: input.accountId,
    p_address_id: input.addressId ?? null,
    p_label: input.label,
    p_address: input.address,
    p_building: input.building,
    p_floor: input.floor ?? null,
    p_landmark: input.landmark ?? null,
    p_delivery_notes: input.deliveryNotes ?? null,
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_make_default: input.makeDefault,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

async function setDefault(input: AddressActionInput) {
  return callRpc("set_default_customer_delivery_address", {
    p_account_id: input.accountId,
    p_address_id: input.addressId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

async function deleteAddress(input: AddressActionInput) {
  return callRpc("delete_customer_delivery_address", {
    p_account_id: input.accountId,
    p_address_id: input.addressId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

async function callRpc(functionName: string, parameters: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(functionName, parameters);
  if (error) throw error;
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
