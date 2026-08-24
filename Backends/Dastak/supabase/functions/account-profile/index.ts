import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerSession } from "../_shared/auth.ts";
import { callAuthenticatedRPC } from "../_shared/v1-rpc.ts";
import { type AccountProfile, handleAccountProfile } from "./handler.ts";

const supabaseUrl = requiredEnv("SUPABASE_URL");
const serviceRoleClient = createClient(supabaseUrl, requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { autoRefreshToken: false, persistSession: false },
});

Deno.serve((request) =>
  handleAccountProfile(request, {
    authenticateBearer: verifyBearerSession,
    snapshotProfile: readProfile,
    updateProfile,
    snapshotIdentities: (accessToken) =>
      callAuthenticatedRPC(accessToken, "dastak_customer_identity_snapshot", {}),
    beginIdentityLink: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_begin_customer_identity_link", {
        p_target_provider: input.provider,
        p_idempotency_key: input.idempotencyKey,
      }),
    deleteAccount,
  })
);

async function readProfile(accountId: string) {
  const { data, error } = await serviceRoleClient
    .from("accounts")
    .select("display_name,phone_number")
    .eq("id", accountId)
    .eq("account_state", "ACTIVE")
    .maybeSingle();
  if (error) throw error;
  return data ? mapProfile(data) : null;
}

async function updateProfile(accountId: string, profile: AccountProfile) {
  const { data, error } = await serviceRoleClient
    .from("accounts")
    .update({
      display_name: profile.displayName,
      phone_number: profile.phoneNumber,
      updated_at: new Date().toISOString(),
    })
    .eq("id", accountId)
    .eq("account_state", "ACTIVE")
    .select("display_name,phone_number")
    .maybeSingle();
  if (error) throw error;
  return data ? mapProfile(data) : null;
}

async function deleteAccount(input: {
  accountId: string;
  idempotencyKey: string;
}) {
  const prepared = await serviceRoleClient.rpc("prepare_customer_account_deletion", {
    p_account_id: input.accountId,
    p_idempotency_key: input.idempotencyKey,
  });
  if (prepared.error) throw prepared.error;
  // Preparation anonymises the business account and fails all product access
  // closed. The internal worker durably removes Auth credentials and finalises
  // history even if this client disconnects or signs out immediately.
}

function mapProfile(row: { display_name: string; phone_number: string }): AccountProfile {
  return { displayName: row.display_name, phoneNumber: row.phone_number };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
