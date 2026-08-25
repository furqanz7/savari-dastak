import { describe, expect, it } from "vitest";
import { resolveAuthenticatedEmail } from "./authenticatedEmail";

describe("resolveAuthenticatedEmail", () => {
  it("uses the canonical authenticated user email", () => {
    expect(resolveAuthenticatedEmail({
      email: " customer@example.com ",
      user_metadata: {},
      identities: [],
    })).toBe("customer@example.com");
  });

  it("recovers Apple or Google email from authenticated identity metadata", () => {
    expect(resolveAuthenticatedEmail({
      email: undefined,
      user_metadata: {},
      identities: [{ identity_data: { email: "relay@privaterelay.appleid.com" } } as never],
    })).toBe("relay@privaterelay.appleid.com");
  });

  it("never invents a missing email", () => {
    expect(resolveAuthenticatedEmail({
      email: undefined,
      user_metadata: { phone: "+919999999999" },
      identities: [],
    })).toBeUndefined();
  });
});
