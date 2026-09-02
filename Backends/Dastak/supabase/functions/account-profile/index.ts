import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerSession } from "../_shared/auth.ts";
import { callAuthenticatedRPC } from "../_shared/v1-rpc.ts";
import { type AccountProfile, type DastakPersona, handleAccountProfile } from "./handler.ts";

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
    exportAccount,
    deleteAccount,
  })
);

async function exportAccount(accountId: string) {
  const { data, error } = await serviceRoleClient.rpc("export_customer_account_data", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return data;
}

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

async function updateProfile(
  accountId: string,
  profile: AccountProfile,
) {
  const { data, error } = await serviceRoleClient.rpc("update_dastak_account_profile", {
    p_account_id: accountId,
    p_display_name: profile.displayName,
    p_phone_number: profile.phoneNumber,
  });
  if (error) throw error;
  const value = data as { displayName?: unknown; phoneNumber?: unknown } | null;
  return value && typeof value.displayName === "string" && typeof value.phoneNumber === "string"
    ? { displayName: value.displayName, phoneNumber: value.phoneNumber }
    : null;
}

async function deleteAccount(input: {
  accountId: string;
  idempotencyKey: string;
  persona: DastakPersona;
}) {
  const prepared = await serviceRoleClient.rpc("prepare_dastak_persona_deletion", {
    p_account_id: input.accountId,
    p_persona: input.persona,
    p_idempotency_key: input.idempotencyKey,
  });
  if (prepared.error) throw prepared.error;
  const value = prepared.data as {
    alreadyDeleted?: unknown;
    identityRecoveryEligible?: unknown;
  } | null;
  const identityRecoveryEligible = value?.identityRecoveryEligible === true;
  return {
    alreadyDeleted: value?.alreadyDeleted === true,
    identityRecoveryEligible,
  };
}

function mapProfile(row: { display_name: string; phone_number: string }): AccountProfile {
  return { displayName: row.display_name, phoneNumber: row.phone_number };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
