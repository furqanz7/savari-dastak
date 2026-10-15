import { importPKCS8, SignJWT } from "npm:jose@5";
import type { ApnsConfiguration } from "./apns.ts";

export type LiveActivityJob = {
  id: string;
  leaseId: string;
  tokenVersion: number;
  token: string;
  environment: "sandbox" | "production";
  status: string;
  version: number;
  updatedAt: number;
  timestamp: number;
};
export function isTerminal(status: string) {
  return [
    "DELIVERED",
    "UNAVAILABLE",
    "PAYMENT_EXPIRED",
    "CANCELLED_PREPAYMENT",
    "CANCELLED",
    "DASTAK_FULFILMENT_FAILURE",
    "ENDED",
  ].includes(status);
}
export function liveActivityPayload(job: LiveActivityJob) {
  const terminal = isTerminal(job.status);
  return {
    aps: {
      timestamp: job.timestamp,
      event: terminal ? "end" : "update",
      "content-state": { status: job.status, version: job.version, updatedAt: job.updatedAt },
      ...(terminal
        ? { "dismissal-date": job.timestamp + (job.status === "ENDED" ? 0 : 300) }
        : { "stale-date": job.timestamp + 180 }),
    },
  };
}
export function createLiveActivityWorker(
  configuration: ApnsConfiguration,
  rpc: (name: string, params: Record<string, unknown>) => Promise<unknown>,
  fetcher: typeof fetch = fetch,
) {
  let cachedToken: { at: number; value: Promise<string> } | undefined;
  const providerToken = () => {
    if (!cachedToken || Date.now() - cachedToken.at > 50 * 60 * 1000) {
      cachedToken = {
        at: Date.now(),
        value: (async () => {
          const key = await importPKCS8(configuration.privateKey, "ES256");
          return new SignJWT({ iss: configuration.teamId })
            .setProtectedHeader({ alg: "ES256", kid: configuration.keyId }).setIssuedAt().sign(key);
        })(),
      };
    }
    return cachedToken.value;
  };
  return async () => {
    const jobs = await rpc("dastak_claim_order_live_activities", {}) as LiveActivityJob[];
    if (!jobs.length) return;
    const jwt = await providerToken();
    // Bounded batches prevent a notification pass from spawning unbounded requests.
    for (let offset = 0; offset < jobs.length; offset += 5) {
      await Promise.all(
        jobs.slice(offset, offset + 5).map(async (job) => {
          let succeeded = false, retire = false;
          try {
            const endpoint = job.environment === "production"
              ? "https://api.push.apple.com"
              : "https://api.sandbox.push.apple.com";
            const response = await fetcher(`${endpoint}/3/device/${job.token}`, {
              method: "POST",
              signal: AbortSignal.timeout(8000),
              headers: {
                authorization: `bearer ${jwt}`,
                "apns-topic": "com.dastak.app.push-type.liveactivity",
                "apns-push-type": "liveactivity",
                "apns-priority": "5",
                "apns-collapse-id": job.id,
                "apns-expiration": String(job.timestamp + 180),
                "content-type": "application/json",
              },
              body: JSON.stringify(liveActivityPayload(job)),
            });
            succeeded = response.ok;
            const body = await response.json().catch(() => ({}));
            retire = (succeeded && isTerminal(job.status)) ||
              (response.status === 410 && body.reason === "Unregistered");
          } catch { /* lease is retried; tokens and provider credentials never enter logs */ }
          await rpc("dastak_complete_order_live_activity", {
            p_id: job.id,
            p_lease_id: job.leaseId,
            p_token_version: job.tokenVersion,
            p_status: job.status,
            p_succeeded: succeeded,
            p_retire: retire,
          });
        }),
      );
    }
  };
}
