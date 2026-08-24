import { describe, expect, it } from "vitest";
import {
  applicationServerKey,
  canonicalPushSubscription,
  registerWebPushSubscription,
  webPushOnboardingStorageKey,
} from "./webPush";

const publicKey = "BNVx8M9WlK9nyJ8y8Q0XxPRm8sZ7CsYdlHBJtxMxoEQ8QXyzzYEbUnmdlsfKZQ1r6OUKo6IdHtVFwSXvbpC2ZIc";

describe("Customer Web push", () => {
  it("validates and decodes the configured VAPID public key", () => {
    const bytes = applicationServerKey(publicKey);
    expect(bytes).toHaveLength(65);
    expect(bytes[0]).toBe(4);
    expect(() => applicationServerKey("invalid")).toThrow(/not configured/);
  });

  it("serializes only the standard browser subscription fields", () => {
    const subscription = {
      toJSON: () => ({
        endpoint: "https://push.example.test/subscriptions/one",
        expirationTime: null,
        keys: { auth: "auth-key", p256dh: "public-key" },
      }),
    } as unknown as PushSubscription;

    expect(JSON.parse(canonicalPushSubscription(subscription))).toEqual({
      endpoint: "https://push.example.test/subscriptions/one",
      expirationTime: null,
      keys: { auth: "auth-key", p256dh: "public-key" },
    });
  });

  it("registers a Web subscription only as the authenticated account", async () => {
    const subscription = {
      toJSON: () => ({
        endpoint: "https://push.example.test/subscriptions/one",
        keys: { auth: "auth-key", p256dh: "public-key" },
      }),
    } as unknown as PushSubscription;
    await registerWebPushSubscription({
      accountId: "account-one",
      accessToken: "access-token",
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "publishable-key",
      publicKey,
    }, subscription, (_input, init) => {
      const headers = new Headers(init?.headers);
      expect(headers.get("authorization")).toBe("Bearer access-token");
      expect(JSON.parse(String(init?.body))).toMatchObject({ platform: "web" });
      return Promise.resolve(new Response(null, { status: 200 }));
    });
  });

  it("scopes prompt dismissal to one account", () => {
    expect(webPushOnboardingStorageKey("ACCOUNT-One")).toBe("dastak.webPushOnboarding.v1.account-one");
  });
});
