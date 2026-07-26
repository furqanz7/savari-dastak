import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import { handleControlledCategories } from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleControlledCategories(request, {
    authenticateBearer: verifyBearerUser,
    attestAdult: (input) =>
      rpc("record_adult_attestation", {
        p_account_id: input.accountId,
        p_policy_version: input.policyVersion,
        p_affirmed_adult: input.affirmedAdult,
        p_affirmed_not_for_minor: input.affirmedNotForMinor,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    browseCatalogue: (input) =>
      rpc("browse_controlled_catalogue", {
        p_account_id: input.accountId,
        p_scope: input.scope,
        p_latitude: input.latitude,
        p_longitude: input.longitude,
      }),
    quoteOrder: (input) =>
      rpc("quote_controlled_merchant_order", {
        p_account_id: input.accountId,
        p_scope: input.scope,
        p_store_id: input.storeId,
        p_lines: input.lines,
        p_dropoff_latitude: input.dropoffLatitude,
        p_dropoff_longitude: input.dropoffLongitude,
        p_prescription_evidence_path: input.prescriptionEvidencePath,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    createOrder: (input) =>
      rpc("create_controlled_merchant_order", {
        p_account_id: input.accountId,
        p_quote_id: input.quoteId,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    getOrderSnapshot: (input) =>
      rpc("get_controlled_order_snapshot", {
        p_account_id: input.accountId,
        p_order_id: input.orderId,
      }),
    submitStoreCompliance: (input) =>
      rpc("submit_controlled_store_compliance", {
        p_account_id: input.accountId,
        p_scope: input.scope,
        p_evidence_object_path: input.evidenceObjectPath,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    reviewStoreCompliance: (input) =>
      rpc("review_controlled_store_compliance", {
        p_owner_id: input.accountId,
        p_compliance_id: input.complianceId,
        p_decision: input.decision,
        p_valid_until: input.validUntil,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    submitProduct: (input) =>
      rpc("submit_controlled_product", {
        p_account_id: input.accountId,
        p_product_id: input.productId,
        p_tobacco_kind: input.tobaccoKind,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    reviewProduct: (input) =>
      rpc("review_controlled_product", {
        p_owner_id: input.accountId,
        p_product_id: input.productId,
        p_decision: input.decision,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    upsertPolicy: (input) =>
      rpc("upsert_controlled_category_policy", {
        p_owner_id: input.accountId,
        p_version: input.version,
        p_allowed_tobacco_kinds: input.allowedTobaccoKinds,
        p_active: input.active,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    upsertExclusionZone: (input) =>
      rpc("upsert_restricted_exclusion_zone", {
        p_owner_id: input.accountId,
        p_zone_id: input.zoneId,
        p_name: input.name,
        p_kind: input.kind,
        p_latitude: input.latitude,
        p_longitude: input.longitude,
        p_radius_meters: input.radiusMeters,
        p_active: input.active,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    verifyRestrictedHandoff: (input) =>
      rpc("verify_restricted_handoff", {
        p_account_id: input.accountId,
        p_assignment_id: input.assignmentId,
        p_verification_code: input.verificationCode,
        p_visual_age_check: input.visualAgeCheck,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    confirmRestrictedReturn: (input) =>
      rpc("confirm_restricted_return", {
        p_account_id: input.accountId,
        p_order_id: input.orderId,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
        p_request_digest: input.requestDigest,
      }),
    getPrescriptionEvidencePath: async (input) => {
      const { data, error } = await serviceClient.rpc(
        "get_order_prescription_evidence_path",
        { p_account_id: input.accountId, p_order_id: input.orderId },
      );
      if (error) throw error;
      return typeof data === "string" ? data : null;
    },
    signEvidenceDownload: async (objectPath) => {
      const { data, error } = await serviceClient.storage
        .from("dastak-evidence")
        .createSignedUrl(objectPath, 300);
      if (error || !data?.signedUrl) throw error ?? new Error("Missing signed URL");
      return data.signedUrl;
    },
  })
);

async function rpc(functionName: string, parameters: Record<string, unknown>) {
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
