import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { recoverCustomerSession } from "./customerSessionRecovery";

function fixture(error?: { status: number }) {
  const auth = {
    getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "current" } }, error: null }),
    getUser: vi.fn().mockResolvedValue({ data: { user: error ? null : { id: "customer" } }, error }),
    signOut: vi.fn().mockResolvedValue({ error: null }),
  };
  return { auth, client: { auth } as unknown as SupabaseClient };
}

describe("automatic customer session recovery", () => {
  it("keeps a valid login after any feature endpoint denies access", async () => {
    const { client, auth } = fixture();
    await recoverCustomerSession(client, "current");
    expect(auth.getUser).toHaveBeenCalledWith("current");
    expect(auth.signOut).not.toHaveBeenCalled();
  });
  it.each([0, 429, 500, 503])("keeps the login when auth verification fails with %s", async status => {
    const { client, auth } = fixture({ status });
    await recoverCustomerSession(client, "current");
    expect(auth.signOut).not.toHaveBeenCalled();
  });
  it("keeps the login on a thrown network failure", async () => {
    const { client, auth } = fixture();
    auth.getUser.mockRejectedValue(new Error("offline"));
    await recoverCustomerSession(client, "current");
    expect(auth.signOut).not.toHaveBeenCalled();
  });
  it.each([401, 403])("clears only local auth after auth itself confirms rejection %s", async status => {
    const { client, auth } = fixture({ status });
    await recoverCustomerSession(client, "current");
    expect(auth.signOut).toHaveBeenCalledExactlyOnceWith({ scope: "local" });
  });
  it("ignores failures for an older token", async () => {
    const { client, auth } = fixture({ status: 401 });
    await recoverCustomerSession(client, "old");
    expect(auth.getUser).not.toHaveBeenCalled();
    expect(auth.signOut).not.toHaveBeenCalled();
  });
  it("does not clear a session refreshed while verification is pending", async () => {
    const { client, auth } = fixture({ status: 401 });
    auth.getSession.mockResolvedValueOnce({ data: { session: { access_token: "current" } }, error: null })
      .mockResolvedValueOnce({ data: { session: { access_token: "refreshed" } }, error: null });
    await recoverCustomerSession(client, "current");
    expect(auth.signOut).not.toHaveBeenCalled();
  });
});
