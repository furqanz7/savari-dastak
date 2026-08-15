import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  handleMerchantApplications,
  type MerchantApplication,
  type ReviewMerchantApplicationInput,
  type SubmitMerchantApplicationInput,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleMerchantApplications(request, {
    authenticateBearer: verifyBearerUser,
    isActiveOwner,
    submitMerchantApplication,
    getMerchantApplicationSnapshot,
    listMerchantApplications,
    reviewMerchantApplication,
  })
);

async function isActiveOwner(accountId: string) {
  const { data, error } = await serviceClient.rpc("is_active_owner", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return data === true;
}

async function submitMerchantApplication(input: SubmitMerchantApplicationInput) {
  const { data, error } = await serviceClient.rpc("submit_merchant_application", {
    p_account_id: input.accountId,
    p_business_name: input.businessName,
    p_business_address: input.businessAddress,
    p_evidence_object_path: input.evidenceObjectPath,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "submit_merchant_application");
}

async function getMerchantApplicationSnapshot(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_merchant_application_snapshot", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_merchant_application_snapshot");
}

async function listMerchantApplications(ownerId: string) {
  const { data, error } = await serviceClient.rpc("list_merchant_applications", {
    p_owner_id: ownerId,
  });
  if (error) throw error;
  if (!Array.isArray(data)) {
    throw new Error("list_merchant_applications returned an invalid response");
  }
  return data.map((value): MerchantApplication => {
    const row = value as Record<string, unknown>;
    const status = row.status;
    if (
      typeof row.application_id !== "string" ||
      typeof row.account_id !== "string" ||
      typeof row.business_name !== "string" ||
      typeof row.business_address !== "string" ||
      typeof row.evidence_object_path !== "string" ||
      (status !== "pending" && status !== "approved" && status !== "rejected")
    ) {
      throw new Error("list_merchant_applications returned an invalid row");
    }
    return {
      applicationId: row.application_id,
      accountId: row.account_id,
      businessName: row.business_name,
      businessAddress: row.business_address,
      evidenceObjectPath: row.evidence_object_path,
      status,
    };
  });
}

async function reviewMerchantApplication(input: ReviewMerchantApplicationInput) {
  const { data, error } = await serviceClient.rpc("review_merchant_application", {
    p_owner_id: input.ownerId,
    p_application_id: input.applicationId,
    p_decision: input.decision,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "review_merchant_application");
}

function rpcResponse(data: unknown, functionName: string) {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (
    !row || !("response_body" in row) ||
    typeof row.response_status !== "number"
  ) {
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
