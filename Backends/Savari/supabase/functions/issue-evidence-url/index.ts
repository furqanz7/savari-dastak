import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { handleIssueEvidenceUrl } from "./handler.ts";
import { verifyBearerUser } from "../_shared/auth.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  {
    auth: { autoRefreshToken: false, persistSession: false },
  },
);

Deno.serve((request) =>
  handleIssueEvidenceUrl(request, {
    authenticateBearer: verifyBearerUser,
    isActiveOwner: (accountId) => isActiveOwner(accountId),
    signDownload: (input) => signDownload(input),
  })
);

async function isActiveOwner(accountId: string) {
  const { data, error } = await serviceClient.rpc("is_active_owner", { p_account_id: accountId });
  if (error) throw error;
  return data === true;
}

async function signDownload(input: { bucket: string; objectPath: string; expiresIn: number }) {
  const { data, error } = await serviceClient.storage
    .from(input.bucket)
    .createSignedUrl(input.objectPath, input.expiresIn);
  if (error || !data?.signedUrl) throw error ?? new Error("Storage did not return a signed URL.");
  return data.signedUrl;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
