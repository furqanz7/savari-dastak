import { describe, expect, it } from "vitest";
import { customerDataIssue } from "./customerDataState";

describe("customerDataIssue", () => {
  it("keeps offline failures recoverable", () => {
    expect(customerDataIssue({ code: "network_error" })).toMatchObject({
      kind: "offline",
      action: "retry",
    });
  });

  it("requires sign-in after an expired session", () => {
    expect(customerDataIssue({ status: 401 })).toMatchObject({
      kind: "session",
      action: "sign_in",
    });
  });

  it("does not hide an access-denied account as a generic failure", () => {
    expect(customerDataIssue({ status: 403 })).toMatchObject({
      kind: "access",
      action: "sign_in",
    });
  });

  it("makes unknown failures retryable", () => {
    Object.defineProperty(navigator, "onLine", { configurable: true, value: true });
    expect(customerDataIssue(new Error("temporary backend failure"))).toMatchObject({
      kind: "unavailable",
      action: "retry",
    });
  });
});
