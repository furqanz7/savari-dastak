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
    });
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_PRIVACY_URL: undefined }))
      .toThrow(/PRIVACY/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_WEB_PUSH_PUBLIC_KEY: "invalid" }))
      .toThrow(/VAPID/);
    expect(() => readAppConfig({ ...customerEnvironment, VITE_DASTAK_SUPPORT_URL: "mailto:help@dastak.example" }))
      .toThrow(/SUPPORT/);
  });
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

function makeJwt(payload: object) {
  return ["e30", Buffer.from(JSON.stringify(payload)).toString("base64url"), "signature"].join(".");
}
