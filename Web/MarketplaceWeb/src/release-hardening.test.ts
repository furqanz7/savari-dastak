import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { metadataForVariant } from "./releaseMetadata";

describe("Dastak Web production release hardening", () => {
  it("publishes dedicated Admin branding without changing other variants", () => {
    expect(metadataForVariant("dastak-admin")).toEqual({
      title: "Dastak Admin — Operations Control",
      description: "Secure operational control for the Dastak marketplace.",
      applicationName: "Dastak Admin",
    });
    expect(metadataForVariant("dastak-customer").title).toBe("Dastak");
    expect(metadataForVariant("dastak-merchant").title).toBe("Dastak Merchant");
    expect(metadataForVariant("dastak-delivery").title).toBe("Dastak Delivery Partner");
  });

  it("sets an explicit restrictive production header contract", () => {
    const config = JSON.parse(readFileSync(new URL("../vercel.json", import.meta.url), "utf8"));
    const headers = new Map(config.headers[0].headers.map((header: { key: string; value: string }) => [header.key, header.value]));
    const csp = headers.get("Content-Security-Policy") ?? "";
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
    expect(csp).toContain("wss://*.supabase.co");
    expect(csp).toContain("https://www.openstreetmap.org");
    expect(csp).toContain("https://checkout.razorpay.com");
    expect(headers.get("X-Frame-Options")).toBe("DENY");
    expect(headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(headers.get("Referrer-Policy")).toBe("no-referrer");
    expect(headers.get("Permissions-Policy")).toContain("microphone=()");
    expect(headers.get("Strict-Transport-Security")).toContain("max-age=63072000");
  });

  it("embeds source and deployment provenance in the generated HTML contract", () => {
    const config = readFileSync(new URL("../vite.config.ts", import.meta.url), "utf8");
    expect(config).toContain("VERCEL_GIT_COMMIT_SHA");
    expect(config).toContain("VERCEL_DEPLOYMENT_ID");
    expect(config).toContain('name: "dastak:git-sha"');
    expect(config).toContain('name: "dastak:variant"');
    expect(config).toContain('name: "dastak:environment"');
    expect(config).toContain('name: "dastak:deployment-id"');
  });
});
