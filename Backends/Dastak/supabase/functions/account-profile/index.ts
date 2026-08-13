import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleAccountProfile, type AccountProfile } from "./handler.ts";

const supabaseUrl = requiredEnv("SUPABASE_URL");
const serviceRoleClient = createClient(supabaseUrl, requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { autoRefreshToken: false, persistSession: false },
});

Deno.serve((request) =>
  handleAccountProfile(request, {
    authenticateBearer: verifyBearerUser,
    snapshotProfile: readProfile,
    updateProfile,
    deleteAccount,
  })
);

async function readProfile(accountId: string) {
  const { data, error } = await serviceRoleClient
    .from("accounts")
    .select("display_name,phone_number")
    .eq("id", accountId)
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
    .select("display_name,phone_number")
    .maybeSingle();
  if (error) throw error;
  return data ? mapProfile(data) : null;
}

async function deleteAccount(accountId: string) {
  const { error } = await serviceRoleClient.auth.admin.deleteUser(accountId);
  if (error) throw error;
}

function mapProfile(row: { display_name: string; phone_number: string }): AccountProfile {
  return { displayName: row.display_name, phoneNumber: row.phone_number };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
