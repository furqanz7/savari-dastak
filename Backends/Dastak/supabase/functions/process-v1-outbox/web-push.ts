// @deno-types="npm:@types/web-push@3.6.4"
import webPush from "npm:web-push@3.6.7";
import type { V1NotificationJob, V1ProviderDelivery } from "./handler.ts";

export type WebPushConfiguration = {
  subject: string;
  publicKey: string;
  privateKey: string;
};

type WebPushProvider = Pick<typeof webPush, "setVapidDetails" | "sendNotification">;

export function createWebPushSender(
  configuration: WebPushConfiguration,
  provider: WebPushProvider = webPush,
) {
  if (
    !configuration.subject.startsWith("mailto:") && !configuration.subject.startsWith("https://")
  ) {
    throw new Error("WEB_PUSH_VAPID_SUBJECT must be a mailto or HTTPS URI");
  }
  provider.setVapidDetails(
    configuration.subject,
    configuration.publicKey,
    configuration.privateKey,
  );

  return async (job: V1NotificationJob): Promise<V1ProviderDelivery> => {
    let subscription: webPush.PushSubscription;
    try {
      subscription = parseSubscription(job.deviceToken);
    } catch {
      return failure(400, true, "invalid web push subscription");
    }

    try {
      const response = await provider.sendNotification(
        subscription,
        JSON.stringify({
          title: job.title,
          body: job.body,
          payload: {
            ...job.payload,
            eventId: job.eventId,
            notificationType: job.notificationType,
          },
        }),
        {
          TTL: 300,
          urgency: "high",
          topic: job.eventId.replaceAll("-", "").slice(0, 32),
        },
      );
      return {
        succeeded: response.statusCode >= 200 && response.statusCode < 300,
        permanentTokenFailure: response.statusCode === 404 || response.statusCode === 410,
        providerStatus: response.statusCode,
        providerResponse: "web push accepted",
      };
    } catch (error) {
      const statusCode = providerStatus(error);
      return failure(
        statusCode,
        statusCode === 404 || statusCode === 410,
        statusCode ? `web push rejected (${statusCode})` : "web push request failed",
      );
    }
  };
}

function parseSubscription(value: string): webPush.PushSubscription {
  const parsed = JSON.parse(value) as Record<string, unknown>;
  const keys = parsed.keys && typeof parsed.keys === "object"
    ? parsed.keys as Record<string, unknown>
    : undefined;
  if (
    typeof parsed.endpoint !== "string" || !/^https:\/\/\S+$/.test(parsed.endpoint) ||
    typeof keys?.auth !== "string" || !keys.auth ||
    typeof keys.p256dh !== "string" || !keys.p256dh
  ) throw new Error("invalid web push subscription");
  return {
    endpoint: parsed.endpoint,
    keys: { auth: keys.auth, p256dh: keys.p256dh },
  };
}

function providerStatus(error: unknown) {
  const statusCode = error && typeof error === "object"
    ? (error as Record<string, unknown>).statusCode
    : undefined;
  return typeof statusCode === "number" && Number.isInteger(statusCode) ? statusCode : null;
}

function failure(
  status: number | null,
  permanentTokenFailure: boolean,
  response: string,
): V1ProviderDelivery {
  return {
    succeeded: false,
    permanentTokenFailure,
    providerStatus: status,
    providerResponse: response,
  };
}
