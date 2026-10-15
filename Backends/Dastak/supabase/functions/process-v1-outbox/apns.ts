import { importPKCS8, SignJWT } from "npm:jose@5";
import type { V1NotificationJob, V1ProviderDelivery } from "./handler.ts";
import { offerExpiration, suppressedOffer } from "./notification-policy.ts";

export type ApnsConfiguration = {
  environment: "sandbox" | "production";
  teamId: string;
  keyId: string;
  bundleId: string;
  privateKey: string;
};

export function createApnsSender(
  configuration: ApnsConfiguration,
  fetcher: typeof fetch = fetch,
  now: () => number = Date.now,
) {
  let cachedToken: { createdAt: number; value: Promise<string> } | undefined;
  const providerToken = () => {
    const currentTime = now();
    if (!cachedToken || currentTime - cachedToken.createdAt >= 50 * 60 * 1_000) {
      cachedToken = {
        createdAt: currentTime,
        value: signProviderToken(configuration, Math.floor(currentTime / 1_000)),
      };
    }
    return cachedToken.value;
  };
  return async (job: V1NotificationJob): Promise<V1ProviderDelivery> => {
    if (offerExpiration(job, now()) === 0) return suppressedOffer();
    const authorization = `bearer ${await providerToken()}`;
    const expiration = offerExpiration(job, now());
    if (expiration === 0) return suppressedOffer();
    const environment = job.apnsEnvironment ?? configuration.environment;
    const topic = job.applicationId ?? configuration.bundleId;
    const endpoint = environment === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";
    const response = await fetcher(`${endpoint}/3/device/${job.deviceToken}`, {
      method: "POST",
      signal: AbortSignal.timeout(8_000),
      headers: {
        authorization,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-id": job.deliveryId,
        // Stable across retries of this alert, distinct across Customer/Rider
        // alerts originating from the same domain event on the same device.
        "apns-collapse-id": job.deliveryId,
        ...(expiration === undefined ? {} : { "apns-expiration": String(expiration) }),
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: { title: job.title, body: job.body },
          sound: "default",
          badge: 1,
        },
        ...job.payload,
        notificationType: job.notificationType,
      }),
    });
    const responseBody = await response.text();
    const reason = apnsReason(responseBody);
    return {
      succeeded: response.ok,
      // A topic/environment mismatch is configuration failure, not permission
      // to retire a token. Old registrations do not know their environment.
      permanentTokenFailure: (response.status === 410 && reason === "Unregistered") ||
        (response.status === 400 && reason === "BadDeviceToken" && job.apnsEnvironment != null),
      providerStatus: response.status,
      providerResponse: responseBody,
    };
  };
}

function apnsReason(body: string) {
  try {
    const value = JSON.parse(body) as { reason?: unknown };
    return typeof value.reason === "string" ? value.reason : "";
  } catch {
    return "";
  }
}

async function signProviderToken(configuration: ApnsConfiguration, issuedAt: number) {
  const key = await importPKCS8(configuration.privateKey, "ES256");
  return new SignJWT({ iss: configuration.teamId })
    .setProtectedHeader({ alg: "ES256", kid: configuration.keyId })
    .setIssuedAt(issuedAt)
    .sign(key);
}
