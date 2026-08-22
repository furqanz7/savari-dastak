import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  type DeliveryPartnerApplication,
  handleDeliveryPartners,
  type PublishDeliveryPartnerLocationInput,
  type ReviewDeliveryPartnerApplicationInput,
  type SetDeliveryPartnerAvailabilityInput,
  type SubmitDeliveryPartnerApplicationInput,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleDeliveryPartners(request, {
    authenticateBearer: verifyBearerUser,
    isActiveOwner,
    submitApplication,
    getSelfSnapshot,
    listPendingApplications,
    reviewApplication,
    setAvailability,
    publishLocation,
  })
);

async function isActiveOwner(accountId: string) {
  const { data, error } = await serviceClient.rpc("is_active_owner", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return data === true;
}

async function submitApplication(input: SubmitDeliveryPartnerApplicationInput) {
  const { data, error } = await serviceClient.rpc("submit_delivery_partner_application_v3", {
    p_account_id: input.accountId,
    p_delivery_method: input.deliveryMethod,
    p_identity_evidence_object_path: input.identityEvidenceObjectPath,
    p_vehicle_registration_number: input.vehicleRegistrationNumber,
    p_vehicle_make_model: input.vehicleMakeModel,
    p_vehicle_evidence_object_path: input.vehicleEvidenceObjectPath,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "submit_delivery_partner_application_v3");
}

async function getSelfSnapshot(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_delivery_partner_snapshot", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_delivery_partner_snapshot");
}

async function listPendingApplications(ownerId: string) {
  const { data, error } = await serviceClient.rpc("list_delivery_partner_applications", {
    p_owner_id: ownerId,
  });
  if (error) throw error;
  if (!Array.isArray(data)) {
    throw new Error("list_delivery_partner_applications returned an invalid response");
  }
  return data.map((value): DeliveryPartnerApplication => {
    const row = value as Record<string, unknown>;
    const deliveryMethod = row.delivery_method;
    const status = row.status;
    if (
      typeof row.application_id !== "string" ||
      typeof row.account_id !== "string" ||
      typeof row.display_name !== "string" ||
      typeof row.phone_number !== "string" ||
      !isDeliveryMethod(deliveryMethod) ||
      typeof row.identity_evidence_object_path !== "string" ||
      !(row.vehicle_registration_number === null ||
        typeof row.vehicle_registration_number === "string") ||
      !(row.vehicle_make_model === null || typeof row.vehicle_make_model === "string") ||
      !(row.vehicle_evidence_object_path === null ||
        typeof row.vehicle_evidence_object_path === "string") ||
      (status !== "pending" && status !== "approved" && status !== "rejected") ||
      typeof row.submitted_at !== "string"
    ) {
      throw new Error("list_delivery_partner_applications returned an invalid row");
    }
    return {
      applicationId: row.application_id,
      accountId: row.account_id,
      displayName: row.display_name,
      phoneNumber: row.phone_number,
      deliveryMethod,
      identityEvidenceObjectPath: row.identity_evidence_object_path,
      vehicleRegistrationNumber: row.vehicle_registration_number as string | null,
      vehicleMakeModel: row.vehicle_make_model as string | null,
      vehicleEvidenceObjectPath: row.vehicle_evidence_object_path as string | null,
      status,
      submittedAt: row.submitted_at,
    };
  });
}

async function reviewApplication(input: ReviewDeliveryPartnerApplicationInput) {
  const { data, error } = await serviceClient.rpc("review_delivery_partner_application", {
    p_owner_id: input.ownerId,
    p_application_id: input.applicationId,
    p_decision: input.decision,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "review_delivery_partner_application");
}

async function setAvailability(input: SetDeliveryPartnerAvailabilityInput) {
  const { data, error } = await serviceClient.rpc("set_delivery_partner_availability", {
    p_account_id: input.accountId,
    p_online: input.online,
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "set_delivery_partner_availability");
}

async function publishLocation(input: PublishDeliveryPartnerLocationInput) {
  const { data, error } = await serviceClient.rpc("publish_delivery_partner_location", {
    p_account_id: input.accountId,
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "publish_delivery_partner_location");
}

function isDeliveryMethod(value: unknown): value is DeliveryPartnerApplication["deliveryMethod"] {
  return value === "walking" || value === "bicycle" || value === "bike" ||
    value === "motorbike" || value === "scooter" || value === "auto" || value === "car";
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
