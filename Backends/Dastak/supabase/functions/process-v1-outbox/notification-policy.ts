import type { V1NotificationJob, V1ProviderDelivery } from "./handler.ts";

export function offerExpiration(job: V1NotificationJob, now = Date.now()) {
  if (job.notificationType !== "rider.mission_offer") return undefined;
  const epoch = Math.floor(Date.parse(job.expiresAt ?? "") / 1_000);
  return Number.isFinite(epoch) && epoch > Math.floor(now / 1_000) ? epoch : 0;
}

export function suppressedOffer(): V1ProviderDelivery {
  return {
    succeeded: false,
    suppressed: true,
    permanentTokenFailure: false,
    providerStatus: null,
    providerResponse: "delivery offer is no longer actionable",
  };
}

type RPC = (name: string, parameters: Record<string, unknown>) => Promise<unknown>;

/// Each job gets checked when its concurrency slot starts, not when the batch
/// was claimed. A failed preflight is retryable and never fails open to a push.
export function guardedNotificationSender(
  rpc: RPC,
  workerId: string,
  send: (job: V1NotificationJob) => Promise<V1ProviderDelivery>,
) {
  return async (job: V1NotificationJob): Promise<V1ProviderDelivery> => {
    if (job.notificationType !== "rider.mission_offer") return send(job);
    const value = await rpc("dastak_v1_prepare_notification_delivery", {
      p_delivery_id: job.deliveryId,
      p_worker_id: workerId,
    });
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid notification preflight");
    }
    const gate = value as Record<string, unknown>;
    if (gate.deliver === false) return suppressedOffer();
    if (
      gate.deliver !== true || typeof gate.expiresAt !== "string" ||
      !Number.isFinite(Date.parse(gate.expiresAt))
    ) throw new Error("invalid offer deadline");
    return send({ ...job, expiresAt: gate.expiresAt });
  };
}
