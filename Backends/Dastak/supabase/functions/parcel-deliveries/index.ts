import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  handleParcelDeliveries,
  type ParcelAssignmentDeclineInput,
  type ParcelAssignmentMutationInput,
  type ParcelCancellationInput,
  type ParcelCreateInput,
  type ParcelLifecycleInput,
  type ParcelQuoteInput,
  type ParcelRouteInput,
  ParcelRoutingUnavailableError,
  type ParcelSafetyIncidentInput,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleParcelDeliveries(request, {
    authenticateBearer: verifyBearerUser,
    routeParcel,
    quoteParcel,
    createParcel,
    getParcelSnapshot,
    getPartnerSnapshot,
    acknowledgeAssignment,
    declineAssignment,
    advanceParcel,
    cancelParcel,
    reportSafetyIncident,
  })
);

async function routeParcel(input: ParcelRouteInput) {
  const endpoint = Deno.env.get("DASTAK_ROUTE_PROVIDER_URL");
  const token = Deno.env.get("DASTAK_ROUTE_PROVIDER_TOKEN");
  if (!endpoint || !token) {
    throw new ParcelRoutingUnavailableError("Route provider is not configured");
  }

  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(input),
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new ParcelRoutingUnavailableError("Route provider is unavailable");
  }
  if (!response.ok) throw new ParcelRoutingUnavailableError("Route provider rejected request");
  const route = await response.json() as Record<string, unknown>;
  if (!Number.isInteger(route.distanceMeters) || !Number.isInteger(route.durationSeconds)) {
    throw new ParcelRoutingUnavailableError("Route provider returned invalid data");
  }
  return {
    distanceMeters: route.distanceMeters as number,
    durationSeconds: route.durationSeconds as number,
  };
}

async function quoteParcel(input: ParcelQuoteInput) {
  return rpc("quote_parcel_delivery", {
    p_account_id: input.accountId,
    p_delivery_method: input.deliveryMethod,
    p_pickup_latitude: input.pickup.latitude,
    p_pickup_longitude: input.pickup.longitude,
    p_pickup_address: input.pickupAddress,
    p_dropoff_latitude: input.dropoff.latitude,
    p_dropoff_longitude: input.dropoff.longitude,
    p_dropoff_address: input.dropoffAddress,
    p_route_distance_meters: input.routeDistanceMeters,
    p_route_duration_seconds: input.routeDurationSeconds,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

async function createParcel(input: ParcelCreateInput) {
  return rpc("create_parcel_delivery", {
    p_account_id: input.accountId,
    p_quote_id: input.quoteId,
    p_recipient_phone_number: input.recipientPhoneNumber,
    p_recipient_name: input.recipientName,
    p_declared_contents: input.declaredContents,
    p_declared_value_paise: input.declaredValuePaise,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

async function getParcelSnapshot(accountId: string, parcelId: string) {
  return rpc("get_parcel_delivery_snapshot", {
    p_account_id: accountId,
    p_parcel_id: parcelId,
  });
}

async function getPartnerSnapshot(accountId: string) {
  return rpc("get_parcel_partner_snapshot", { p_account_id: accountId });
}

async function acknowledgeAssignment(input: ParcelAssignmentMutationInput) {
  return rpc("acknowledge_parcel_assignment", assignmentParameters(input));
}

async function declineAssignment(input: ParcelAssignmentDeclineInput) {
  return rpc("decline_parcel_assignment", {
    ...assignmentParameters(input),
    p_reason: input.reason,
  });
}

async function advanceParcel(input: ParcelLifecycleInput) {
  return rpc("advance_parcel_delivery", {
    ...assignmentParameters(input),
    p_action: input.action,
    p_verification_code: input.verificationCode,
  });
}

async function cancelParcel(input: ParcelCancellationInput) {
  return rpc("cancel_parcel_delivery", {
    p_account_id: input.accountId,
    p_parcel_id: input.parcelId,
    p_reason: input.reason,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

async function reportSafetyIncident(input: ParcelSafetyIncidentInput) {
  return rpc("report_parcel_safety_incident", {
    p_account_id: input.accountId,
    p_parcel_id: input.parcelId,
    p_incident_type: input.incidentType,
    p_report_text: input.reportText,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
}

function assignmentParameters(input: ParcelAssignmentMutationInput) {
  return {
    p_account_id: input.accountId,
    p_assignment_id: input.assignmentId,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  };
}

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
