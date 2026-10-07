import { describe, expect, it } from "vitest";
import { assertBrowserSafeKey, readAppConfig } from "./config";

const anonJwt = makeJwt({ role: "anon" });
const customerEnvironment = {
  VITE_APP_VARIANT: "dastak-customer",
  VITE_SUPABASE_URL: "https://example.supabase.co",
  VITE_SUPABASE_PUBLISHABLE_KEY: anonJwt,
  VITE_DASTAK_PRIVACY_URL: "https://dastak.example/privacy",
  VITE_DASTAK_TERMS_URL: "https://dastak.example/terms",
  VITE_DASTAK_SUPPORT_URL: "https://dastak.example/support",
  VITE_DASTAK_WEB_PUSH_PUBLIC_KEY: "BNVx8M9WlK9nyJ8y8Q0XxPRm8sZ7CsYdlHBJtxMxoEQ8QXyzzYEbUnmdlsfKZQ1r6OUKo6IdHtVFwSXvbpC2ZIc",
  VITE_DASTAK_DELIVERY_URL: "https://delivery.dastak.example",
  VITE_DASTAK_MERCHANT_URL: "https://merchant.dastak.example",
};

describe("readAppConfig", () => {
  it("loads a supported app variant", () => {
    expect(readAppConfig({
      VITE_APP_VARIANT: "savari-rider",
      VITE_SUPABASE_URL: "https://example.supabase.co/",
      VITE_SUPABASE_PUBLISHABLE_KEY: anonJwt,
    })).toMatchObject({ product: "savari", role: "rider", supabaseUrl: "https://example.supabase.co" });
  });

  it("loads the owner-only Dastak Admin variant", () => {
    expect(readAppConfig({
      VITE_APP_VARIANT: "dastak-admin",
      VITE_SUPABASE_URL: "https://example.supabase.co",
      VITE_SUPABASE_PUBLISHABLE_KEY: anonJwt,
    })).toMatchObject({ product: "dastak", role: "admin", roleLabel: "Admin" });
  });

  it("rejects unsupported variants", () => {
    expect(() => readAppConfig({
      VITE_APP_VARIANT: "unsupported",
      VITE_SUPABASE_URL: "https://example.supabase.co",
      VITE_SUPABASE_PUBLISHABLE_KEY: anonJwt,
    })).toThrow(/supported web app/);
  });

  it("requires complete public trust and notification configuration for Customer Web", () => {
    expect(readAppConfig(customerEnvironment)).toMatchObject({
      legalLinks: {
        privacy: "https://dastak.example/privacy",
        terms: "https://dastak.example/terms",
        support: "https://dastak.example/support",
      },
      webPushPublicKey: customerEnvironment.VITE_DASTAK_WEB_PUSH_PUBLIC_KEY,
      deliveryPartnerUrl: "https://delivery.dastak.example/",
      merchantUrl: "https://merchant.dastak.example/",
    });
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_PRIVACY_URL: undefined }))
      .toThrow(/PRIVACY/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_WEB_PUSH_PUBLIC_KEY: "invalid" }))
      .toThrow(/VAPID/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_SUPPORT_URL: "mailto:help@dastak.example" }))
      .toThrow(/SUPPORT/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_DELIVERY_URL: undefined }))
      .toThrow(/DELIVERY/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_MERCHANT_URL: undefined }))
      .toThrow(/MERCHANT/);
  });

  it.each(["dastak-delivery", "dastak-merchant"])(
    "requires the shared Dastak web-push key for %s",
    (variant) => {
      expect(readAppConfig({ ...customerEnvironment, VITE_APP_VARIANT: variant })).toMatchObject({
        webPushPublicKey: customerEnvironment.VITE_DASTAK_WEB_PUSH_PUBLIC_KEY,
      });
      expect(() => readAppConfig({
        ...customerEnvironment,
        VITE_APP_VARIANT: variant,
        VITE_DASTAK_WEB_PUSH_PUBLIC_KEY: undefined,
      })).toThrow(/VAPID/);
    },
  );
});

describe("assertBrowserSafeKey", () => {
  it("accepts publishable and anon keys", () => {
    expect(() => assertBrowserSafeKey("sb_publishable_example")).not.toThrow();
    expect(() => assertBrowserSafeKey(anonJwt)).not.toThrow();
  });

  it("rejects secret and service-role keys", () => {
    expect(() => assertBrowserSafeKey("sb_secret_example")).toThrow(/secret key/);
    expect(() => assertBrowserSafeKey(makeJwt({ role: "service_role" }))).toThrow(/anon JWT/);
  });
});

describe("explicit development-only local Customer configuration", () => {
  const local = { ...customerEnvironment, VITE_DASTAK_LOCAL_SUPABASE: "1", VITE_SUPABASE_URL: "http://127.0.0.1:54321" };
  const context = { development: true, pageUrl: "http://127.0.0.1:5179/?reimagined=1" };
  it.each(["127.0.0.1", "localhost", "[::1]"])("accepts explicit local configuration on %s", host => {
    expect(readAppConfig({ ...local, VITE_SUPABASE_URL: `http://${host}:54321/` }, { ...context, pageUrl: `http://${host}:5179/` }).supabaseUrl).toBe(`http://${host}:54321`);
  });
  it("does not infer opt-in from a local page, environment DEV, or URL", () => {
    expect(() => readAppConfig({ ...local, VITE_DASTAK_LOCAL_SUPABASE: undefined }, context)).toThrow(/hosted/);
    expect(() => readAppConfig({ ...local, DEV: true })).toThrow(/development Customer/);
    expect(() => readAppConfig(local)).toThrow(/development Customer/);
  });
  it("rejects production even on loopback and rejects hosted targets under local opt-in", () => {
    expect(() => readAppConfig(local, { ...context, development: false })).toThrow(/development Customer/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_LOCAL_SUPABASE: "1" }, context)).toThrow(/loopback API/);
  });
  it.each(["https://dastak.example", "http://192.168.1.2:5179", "http://localhost.evil.example:5179", "file:///tmp/index.html", "http://user@localhost:5179", "not a URL"])("rejects unsafe page context %s", pageUrl => {
    expect(() => readAppConfig(local, { ...context, pageUrl })).toThrow(/development Customer/);
  });
  it.each(["https://example.supabase.co", "http://192.168.1.2:54321", "http://localhost.evil.example:54321", "http://user:pass@localhost:54321", "http://127.0.0.1:54322", "http://127.0.0.1:54321/functions/v1", "http://127.0.0.1:54321?target=remote", "http://127.0.0.1:54321#fragment", "http://2130706433:54321", "http://127.1:54321", "https://localhost:54321"])("rejects unsafe API target %s", VITE_SUPABASE_URL => {
    expect(() => readAppConfig({ ...local, VITE_SUPABASE_URL }, context)).toThrow(/loopback API/);
  });
  it.each(["true", "0", "yes"])("rejects ambiguous opt-in %s", VITE_DASTAK_LOCAL_SUPABASE => {
    expect(() => readAppConfig({ ...local, VITE_DASTAK_LOCAL_SUPABASE }, context)).toThrow(/must be 1/);
  });
  it.each(["dastak-admin", "dastak-merchant", "dastak-delivery", "savari-rider"])("does not expand the local Customer slice to %s", VITE_APP_VARIANT => {
    expect(() => readAppConfig({ ...local, VITE_APP_VARIANT }, context)).toThrow(/development Customer/);
  });
  it("preserves secret-key and complete public-configuration checks locally", () => {
    expect(() => readAppConfig({ ...local, VITE_SUPABASE_PUBLISHABLE_KEY: "sb_secret_test" }, context)).toThrow(/secret key/);
    expect(() => readAppConfig({ ...local, VITE_SUPABASE_PUBLISHABLE_KEY: makeJwt({ role: "service_role" }) }, context)).toThrow(/anon JWT/);
    expect(() => readAppConfig({ ...local, VITE_DASTAK_TERMS_URL: undefined }, context)).toThrow(/TERMS/);
    expect(() => readAppConfig({ ...local, VITE_DASTAK_WEB_PUSH_PUBLIC_KEY: "invalid" }, context)).toThrow(/VAPID/);
  });
  it("preserves hosted production configuration with no opt-in", () => {
    expect(readAppConfig(customerEnvironment, { development: false, pageUrl: "https://dastak.example" }).supabaseUrl).toBe(customerEnvironment.VITE_SUPABASE_URL);
  });
});

function makeJwt(payload: object) {
  return ["e30", Buffer.from(JSON.stringify(payload)).toString("base64url"), "signature"].join(".");
}
