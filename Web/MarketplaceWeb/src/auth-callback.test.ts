import { describe, expect, it } from "vitest";
import {
  callbackFailureMessage,
  readAuthCallback,
  sanitizedAuthCallbackUrl,
} from "./auth-callback";

describe("auth callback handling", () => {
  it("detects and removes legacy implicit-grant credentials", () => {
    const href = "https://dastak.example/#access_token=secret&refresh_token=refresh&expires_in=3600&token_type=bearer";

    expect(readAuthCallback(href)).toEqual({ kind: "implicit" });
    expect(sanitizedAuthCallbackUrl(href)).toBe("https://dastak.example/");
  });

  it("detects PKCE callbacks and removes only auth query parameters", () => {
    const href = "https://dastak.example/?source=account&code=temporary-code";

    expect(readAuthCallback(href)).toEqual({ kind: "pkce" });
    expect(sanitizedAuthCallbackUrl(href)).toBe("https://dastak.example/?source=account");
  });

  it("does not mistake customer hash navigation for an auth callback", () => {
    const href = "https://dastak.example/#/account";

    expect(readAuthCallback(href)).toBeNull();
    expect(sanitizedAuthCallbackUrl(href)).toBe(href);
  });

  it("returns a safe message and strips failed callback details", () => {
    const href = "https://dastak.example/#error=access_denied&error_description=The+request+was+cancelled";
    const callback = readAuthCallback(href);

    expect(callback).toEqual({ kind: "error", errorCode: "access_denied" });
    expect(callbackFailureMessage(callback!)).toBe("Sign-in was cancelled. No account changes were made.");
    expect(sanitizedAuthCallbackUrl(href)).toBe("https://dastak.example/");
  });

  it("never reflects technical provider descriptions into customer copy", () => {
    const callback = readAuthCallback(
      "https://dastak.example/?error=server_error&error_description=%3Cscript%3Einternal+provider+detail%3C%2Fscript%3E",
    );

    expect(callbackFailureMessage(callback!)).toBe("Sign-in could not be completed. Please try again.");
  });
});
