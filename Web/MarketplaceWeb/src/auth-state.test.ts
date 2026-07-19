import { describe, expect, it } from "vitest";
import type { Session } from "@supabase/supabase-js";
import { shouldPreserveAuthenticatedView } from "./auth-state";

const session = { user: { id: "passenger-1" } } as Session;

describe("shouldPreserveAuthenticatedView", () => {
  it("preserves the current screen during token refresh and repeat sign-in events", () => {
    expect(shouldPreserveAuthenticatedView("TOKEN_REFRESHED", session, "passenger-1")).toBe(true);
    expect(shouldPreserveAuthenticatedView("SIGNED_IN", session, "passenger-1")).toBe(true);
  });

  it("requires a full access check for a different user or material account event", () => {
    expect(shouldPreserveAuthenticatedView("SIGNED_IN", session, "passenger-2")).toBe(false);
    expect(shouldPreserveAuthenticatedView("USER_UPDATED", session, "passenger-1")).toBe(false);
    expect(shouldPreserveAuthenticatedView("SIGNED_OUT", null, "passenger-1")).toBe(false);
  });
});
