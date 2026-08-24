import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createApnsSender } from "./apns.ts";
import { createWebPushSender } from "./web-push.ts";
import {
  type CustomerAccountDeletionJob,
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
let sendWebPush: ReturnType<typeof createWebPushSender> | undefined;

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
    deliver: (job) => job.platform === "ios" ? sendApns(job) : webPushSender()(job),
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
    claimAccountDeletions: async () =>
      deletionJobs(
        await rpc("claim_customer_account_deletions", {
          p_worker_id: workerId,
          p_limit: 20,
        }),
      ),
    deleteAuthAccount,
    completeAccountDeletion: async (
      job: CustomerAccountDeletionJob,
      succeeded: boolean,
      error?: string,
    ) => {
      await rpc("complete_customer_account_deletion", {
        p_account_id: job.accountId,
        p_worker_id: workerId,
        p_succeeded: succeeded,
        p_error: error ?? null,
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
      !isText(source.deviceToken) || (platform !== "ios" && platform !== "web") ||
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

function deletionJobs(value: unknown): CustomerAccountDeletionJob[] {
  if (!Array.isArray(value)) throw new Error("invalid account deletion claim");
  return value.map((item) => {
    const source = record(item);
    if (
      !isText(source.accountId) || !Number.isInteger(source.attempt) ||
      (source.attempt as number) < 1
    ) {
      throw new Error("invalid account deletion job");
    }
    return { accountId: source.accountId, attempt: source.attempt as number };
  });
}

async function deleteAuthAccount(job: CustomerAccountDeletionJob) {
  const existing = await serviceClient.auth.admin.getUserById(job.accountId);
  if (existing.error) {
    if (isMissingAuthUser(existing.error)) return;
    throw existing.error;
  }
  if (!existing.data.user) return;
  const deletion = await serviceClient.auth.admin.deleteUser(job.accountId);
  if (deletion.error && !isMissingAuthUser(deletion.error)) throw deletion.error;
}

function isMissingAuthUser(error: unknown) {
  const source = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const message = typeof source.message === "string" ? source.message.toLowerCase() : "";
  return source.status === 404 || source.code === "user_not_found" ||
    message.includes("user not found");
}

function webPushSender() {
  if (!sendWebPush) {
    sendWebPush = createWebPushSender({
      subject: requiredEnv("WEB_PUSH_VAPID_SUBJECT"),
      publicKey: requiredEnv("WEB_PUSH_VAPID_PUBLIC_KEY"),
      privateKey: requiredEnv("WEB_PUSH_VAPID_PRIVATE_KEY"),
    });
  }
  return sendWebPush;
}

function isText(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
