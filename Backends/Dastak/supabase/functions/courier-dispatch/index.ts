import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type CourierDispatchDeclineInput,
  type CourierDispatchMutationInput,
  type CourierJobMutationInput,
  handleCourierDispatch,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleCourierDispatch(request, {
    authenticateBearer: verifyBearerUser,
    getPartnerSnapshot,
    acceptOffer,
    declineOffer,
    advanceJob,
  })
);

async function getPartnerSnapshot(accountId: string) {
  const { data, error } = await serviceClient.rpc(
    "get_delivery_partner_dispatch_snapshot",
    { p_account_id: accountId },
  );
  if (error) throw error;
  return rpcResponse(data, "get_delivery_partner_dispatch_snapshot");
}

async function acceptOffer(input: CourierDispatchMutationInput) {
  const { data, error } = await serviceClient.rpc("accept_delivery_assignment", {
    p_account_id: input.accountId,
    p_assignment_id: input.assignmentId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "accept_delivery_assignment");
}

async function declineOffer(input: CourierDispatchDeclineInput) {
  const { data, error } = await serviceClient.rpc("decline_delivery_assignment", {
    p_account_id: input.accountId,
    p_assignment_id: input.assignmentId,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "decline_delivery_assignment");
}

async function advanceJob(input: CourierJobMutationInput) {
  const { data, error } = await serviceClient.rpc("advance_delivery_assignment", {
    p_account_id: input.accountId,
    p_assignment_id: input.assignmentId,
    p_action: input.action,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "advance_delivery_assignment");
}

function rpcResponse(data: unknown, functionName: string) {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return {
    responseBody: row.response_body,
    responseStatus: row.response_status,
  };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
