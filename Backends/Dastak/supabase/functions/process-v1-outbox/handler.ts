import { corsPreflight, json } from "../_shared/http.ts";

export type V1NotificationJob = {
  deliveryId: string;
  eventId: string;
  notificationType: string;
  recipientAccountId: string;
  deviceToken: string;
  platform: "ios";
  title: string;
  body: string;
  payload: Record<string, unknown>;
  attempt: number;
};

export type V1ProviderDelivery = {
  succeeded: boolean;
  permanentTokenFailure: boolean;
  providerStatus: number | null;
  providerResponse: string;
};

export type V1OutboxWorkerDependencies = {
  expectedSecret: string;
  workerId: string;
  fanout: () => Promise<Record<string, unknown>>;
  claim: () => Promise<V1NotificationJob[]>;
  deliver: (job: V1NotificationJob) => Promise<V1ProviderDelivery>;
  complete: (job: V1NotificationJob, result: V1ProviderDelivery) => Promise<void>;
  runInvariantMonitors: () => Promise<Record<string, unknown>>;
};

export async function handleV1OutboxWorker(
  request: Request,
  dependencies: V1OutboxWorkerDependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") {
    return json({ error: { code: "method_not_allowed" } }, 405);
  }
  if (
    !dependencies.expectedSecret ||
    request.headers.get("x-dastak-internal-secret") !== dependencies.expectedSecret
  ) {
    return json({ error: { code: "forbidden" } }, 403);
  }

  try {
    const fanout = await dependencies.fanout();
    const jobs = await dependencies.claim();
    const outcomes = await mapWithConcurrency(jobs, 10, async (job) => {
      let result: V1ProviderDelivery;
      try {
        result = await dependencies.deliver(job);
      } catch (error) {
        result = {
          succeeded: false,
          permanentTokenFailure: false,
          providerStatus: null,
          providerResponse: error instanceof Error ? error.message : "provider request failed",
        };
      }
      await dependencies.complete(job, result);
      return result.succeeded;
    });
    const sent = outcomes.filter(Boolean).length;
    const retriedOrDeadLettered = outcomes.length - sent;
    const invariants = await dependencies.runInvariantMonitors();
    return json({
      workerId: dependencies.workerId,
      fanout,
      claimed: jobs.length,
      sent,
      retriedOrDeadLettered,
      invariants,
    });
  } catch (error) {
    console.error("Dastak V1 outbox processing failed", error);
    return json({ error: { code: "v1_outbox_processing_failed" } }, 500);
  }
}

async function mapWithConcurrency<T, R>(
  values: T[],
  limit: number,
  operation: (value: T) => Promise<R>,
) {
  const results = new Array<R>(values.length);
  let nextIndex = 0;
  const worker = async () => {
    while (nextIndex < values.length) {
      const index = nextIndex++;
      results[index] = await operation(values[index]);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(limit, values.length) }, () => worker()),
  );
  return results;
}
