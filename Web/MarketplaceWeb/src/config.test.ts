import { describe, expect, it } from "vitest";
import { assertBrowserSafeKey, readAppConfig } from "./config";

const anonJwt = makeJwt({ role: "anon" });

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
