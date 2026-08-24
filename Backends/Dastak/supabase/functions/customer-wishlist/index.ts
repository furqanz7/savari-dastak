import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleCustomerWishlist, type WishlistMutation } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleCustomerWishlist(request, {
    authenticateBearer: verifyBearerUser,
    snapshot,
    setItem,
  })
);

async function snapshot(accountId: string) {
  return callRpc("get_customer_wishlist", { p_account_id: accountId });
}

async function setItem(input: WishlistMutation) {
  return callRpc("set_customer_wishlist_item", {
    p_account_id: input.accountId,
    p_item_kind: input.itemKind,
    p_item_id: input.itemId,
    p_wished: input.wished,
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
