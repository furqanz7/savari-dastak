import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { type BootstrapAccountInput, handleBootstrapAccount } from "./handler.ts";
import { verifyBearerUser } from "../_shared/auth.ts";

const supabaseUrl = requiredEnv("SUPABASE_URL");
const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

const serviceRoleClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

Deno.serve((request) =>
  handleBootstrapAccount(request, {
    authenticateBearer: verifyBearerUser,
    bootstrapAccount: (input) => callBootstrapAccountRpc(serviceRoleClient, input),
  })
);

async function callBootstrapAccountRpc(
  client: {
    rpc: (
      functionName: "bootstrap_dastak_persona",
      args: Record<string, string>,
    ) => PromiseLike<{ data: unknown; error: unknown }>;
  },
  input: BootstrapAccountInput,
) {
  const { data, error } = await client.rpc("bootstrap_dastak_persona", {
    p_account_id: input.accountId,
    p_application: input.application,
    p_display_name: input.displayName,
    p_phone_number: input.phoneNumber,
    p_verified_phone_number: input.verifiedPhoneNumber,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });

  if (error) {
    throw error;
  }

  const row = (Array.isArray(data) ? data[0] : data) as {
    response_body?: unknown;
    response_status?: unknown;
  };
  if (
    !row ||
    typeof row !== "object" ||
    !("response_body" in row) ||
    !("response_status" in row)
  ) {
    throw new Error("bootstrap_dastak_persona returned an invalid response");
  }

  const responseBody = row.response_body as Record<string, unknown>;
  const errorBody = responseBody?.error as Record<string, unknown> | undefined;
  if (Number(row.response_status) === 409 && errorBody?.code === "identity_recovery_required") {
    const recoveryAccountId = responseBody.recoveryAccountId;
    if (typeof recoveryAccountId !== "string") {
      throw new Error("Identity recovery target is unavailable.");
    }
    await recoverIdentity(input, recoveryAccountId);
    return {
      responseBody: {
        error: {
          code: "identity_reauthentication_required",
          message: "Your Dastak identity was recovered. Continue with Apple or Google once more.",
        },
      },
      responseStatus: 409,
    };
  }

  return {
    responseBody,
    responseStatus: Number(row.response_status),
  };
}

async function recoverIdentity(input: BootstrapAccountInput, recoveryAccountId: string) {
  const digest = await sha256(input.email.trim().toLowerCase());
  const prepared = await serviceRoleClient.rpc("prepare_dastak_identity_recovery", {
    p_temporary_auth_user_id: input.accountId,
    p_account_id: recoveryAccountId,
    p_verified_phone_number: input.verifiedPhoneNumber,
    p_requested_email_digest: digest,
    p_application: input.application,
    p_display_name: input.displayName,
    p_request_digest: input.requestDigest,
  });
  if (prepared.error || typeof prepared.data !== "string") {
    throw prepared.error ?? new Error("Recovery preparation failed.");
  }
  const eventId = prepared.data;
  try {
    const completed = await serviceRoleClient.rpc("complete_dastak_identity_recovery", {
      p_event_id: eventId,
      p_succeeded: true,
      p_failure_code: null,
    });
    if (completed.error) throw completed.error;
  } catch (error) {
    await serviceRoleClient.rpc("complete_dastak_identity_recovery", {
      p_event_id: eventId,
      p_succeeded: false,
      p_failure_code: "IDENTITY_TRANSFER_FAILED",
    });
    throw error;
  }
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}
