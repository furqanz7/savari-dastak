export type DastakWebPushStatus =
  | "checking"
  | "prompt"
  | "enabling"
  | "enabled"
  | "dismissed"
  | "blocked"
  | "unsupported"
  | "error";

export type WebPushAuthentication = {
  accountId: string;
  accessToken: string;
  supabaseUrl: string;
  publishableKey: string;
  publicKey: string;
};

export function webPushOnboardingStorageKey(accountId: string) {
  return `dastak.webPushOnboarding.v1.${accountId.toLowerCase()}`;
}

export function applicationServerKey(value: string) {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
  if (bytes.length !== 65 || bytes[0] !== 4) throw new Error("Dastak web notifications are not configured.");
  return bytes;
}

export function canonicalPushSubscription(subscription: PushSubscription) {
  const value = subscription.toJSON();
  if (!value.endpoint || !value.keys?.auth || !value.keys.p256dh) {
    throw new Error("The browser returned an invalid notification subscription.");
  }
  return JSON.stringify({
    endpoint: value.endpoint,
    expirationTime: value.expirationTime ?? null,
    keys: { auth: value.keys.auth, p256dh: value.keys.p256dh },
  });
}

export async function registerWebPushSubscription(
  authentication: WebPushAuthentication,
  subscription: PushSubscription,
  fetcher: typeof fetch = fetch,
) {
  const response = await fetcher(
    `${authentication.supabaseUrl.replace(/\/$/, "")}/functions/v1/register-device-token`,
    {
      method: "POST",
      headers: {
        apikey: authentication.publishableKey,
        authorization: `Bearer ${authentication.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ token: canonicalPushSubscription(subscription), platform: "web" }),
    },
  );
  if (!response.ok) throw new Error("Dastak could not save browser notifications.");
}

export function webPushSupported(scope: typeof globalThis = globalThis) {
  const candidate = scope as typeof globalThis & {
    Notification?: typeof Notification;
    PushManager?: typeof PushManager;
    navigator?: Navigator;
  };
  return Boolean(
    candidate.Notification && candidate.PushManager && candidate.navigator?.serviceWorker,
  );
}
