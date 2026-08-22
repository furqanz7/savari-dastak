import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type CourierDispatchDeclineInput,
  type CourierDispatchMutationInput,
  type CourierJobMutationInput,
  handleCourierDispatch,
  type V1DeliveryMissionMutationInput,
  type V1RiderOfferDeclineInput,
  type V1RiderOfferMutationInput,
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
    getAssignmentControlledScope,
    acceptOffer,
    declineOffer,
    advanceJob,
    getV1PartnerSnapshot,
    acceptV1Offer,
    declineV1Offer,
    advanceV1Mission,
  })
);

async function getV1PartnerSnapshot(accountId: string) {
  const { data, error } = await serviceClient.rpc(
    "dastak_v1_delivery_partner_snapshot",
    { p_account_id: accountId },
  );
  if (error) throw error;
  return rpcResponse(data, "dastak_v1_delivery_partner_snapshot");
}

async function acceptV1Offer(input: V1RiderOfferMutationInput) {
  const { data, error } = await serviceClient.rpc("dastak_v1_accept_delivery_offer", {
    p_account_id: input.accountId,
    p_offer_id: input.offerId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "dastak_v1_accept_delivery_offer");
}

async function declineV1Offer(input: V1RiderOfferDeclineInput) {
  const { data, error } = await serviceClient.rpc("dastak_v1_decline_delivery_offer", {
    p_account_id: input.accountId,
    p_offer_id: input.offerId,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "dastak_v1_decline_delivery_offer");
}

async function advanceV1Mission(input: V1DeliveryMissionMutationInput) {
  const { data, error } = await serviceClient.rpc("dastak_v1_advance_delivery_mission", {
    p_account_id: input.accountId,
    p_mission_id: input.missionId,
    p_action: input.action,
    p_stop_id: input.stopId,
    p_accounted_package_count: input.accountedPackageCount,
    p_verification_code: input.verificationCode,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "dastak_v1_advance_delivery_mission");
}

async function getPartnerSnapshot(accountId: string) {
  const { data, error } = await serviceClient.rpc(
    "get_delivery_partner_dispatch_snapshot",
    { p_account_id: accountId },
  );
  if (error) throw error;
  return rpcResponse(data, "get_delivery_partner_dispatch_snapshot");
}

async function getAssignmentControlledScope(accountId: string, assignmentId: string) {
  const { data, error } = await serviceClient.rpc(
    "get_delivery_assignment_controlled_scope",
    { p_account_id: accountId, p_assignment_id: assignmentId },
  );
  if (error) throw error;
  return data === "general" || data === "medicine" || data === "tobacco" ? data : null;
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
    p_verification_code: input.verificationCode,
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
