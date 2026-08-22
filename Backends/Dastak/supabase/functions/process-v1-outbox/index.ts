import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createApnsSender } from "./apns.ts";
import {
  handleV1OutboxWorker,
  type V1NotificationJob,
  type V1ProviderDelivery,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);
const workerId = Deno.env.get("DENO_DEPLOYMENT_ID") ?? `local-${crypto.randomUUID()}`;
const sendApns = createApnsSender({
  environment: Deno.env.get("APNS_ENVIRONMENT") === "production" ? "production" : "sandbox",
  teamId: requiredEnv("APNS_TEAM_ID"),
  keyId: requiredEnv("APNS_KEY_ID"),
  bundleId: requiredEnv("APNS_BUNDLE_ID"),
  privateKey: requiredEnv("APNS_PRIVATE_KEY"),
});

Deno.serve((request) =>
  handleV1OutboxWorker(request, {
    expectedSecret: requiredEnv("DASTAK_NOTIFICATION_SECRET"),
    workerId,
    fanout: async () =>
      record(
        await rpc("dastak_v1_fanout_outbox", {
          p_worker_id: workerId,
          p_limit: 100,
        }),
      ),
    claim: async () =>
      jobs(
        await rpc("dastak_v1_claim_notification_deliveries", {
          p_worker_id: workerId,
          p_limit: 100,
        }),
      ),
    deliver: sendApns,
    complete: async (job: V1NotificationJob, result: V1ProviderDelivery) => {
      await rpc("dastak_v1_complete_notification_delivery", {
        p_delivery_id: job.deliveryId,
        p_worker_id: workerId,
        p_succeeded: result.succeeded,
        p_permanent_token_failure: result.permanentTokenFailure,
        p_provider_status: result.providerStatus,
        p_provider_response: result.providerResponse,
      });
    },
    runInvariantMonitors: async () =>
      record(await rpc("dastak_v1_run_invariant_monitors", { p_worker_id: workerId })),
  })
);

async function rpc(name: string, parameters: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(name, parameters);
  if (error) throw error;
  return data;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid V1 worker response");
  }
  return value as Record<string, unknown>;
}

function jobs(value: unknown): V1NotificationJob[] {
  if (!Array.isArray(value)) throw new Error("invalid V1 notification claim");
  return value.map((item) => {
    const source = record(item);
    const payload = record(source.payload);
    const platform = source.platform;
    if (
      !isText(source.deliveryId) || !isText(source.eventId) ||
      !isText(source.notificationType) || !isText(source.recipientAccountId) ||
      !isText(source.deviceToken) || platform !== "ios" ||
      !isText(source.title) || !isText(source.body) ||
      !Number.isInteger(source.attempt) || (source.attempt as number) < 1
    ) throw new Error("invalid V1 notification job");
    return {
      deliveryId: source.deliveryId,
      eventId: source.eventId,
      notificationType: source.notificationType,
      recipientAccountId: source.recipientAccountId,
      deviceToken: source.deviceToken,
      platform,
      title: source.title,
      body: source.body,
      payload,
      attempt: source.attempt as number,
    };
  });
}

function isText(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
