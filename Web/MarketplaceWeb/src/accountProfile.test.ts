import { describe, expect, it } from "vitest";
import {
  accountDeletionIdempotencyKey,
  clearAccountDeletionIdempotencyKey,
  clearPendingIdentityLink,
  deleteAccount,
  beginCustomerIdentityLink,
  isValidAccountProfile,
  pendingIdentityLink,
  rememberPendingIdentityLink,
  snapshotAccountProfile,
  snapshotCustomerIdentities,
  updateAccountProfile,
} from "./accountProfile";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

describe("account profile", () => {
  it("loads the authenticated profile snapshot", async () => {
    const profile = await snapshotAccountProfile(auth, (_input, init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ operation: "snapshot" });
      return Promise.resolve(new Response(JSON.stringify({
        profile: { displayName: "Furqan", phoneNumber: "+919876543210" },
      }), { status: 200 }));
    });

    expect(profile).toEqual({ displayName: "Furqan", phoneNumber: "+919876543210" });
  });

  it("updates the authenticated profile", async () => {
    let body: unknown;
    const profile = await updateAccountProfile({
      ...auth,
      displayName: "Furqan",
      phoneNumber: "+919876543210",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({
        profile: { displayName: "Furqan", phoneNumber: "+919876543210" },
      }), { status: 200 }));
    });

    expect(body).toEqual({
      operation: "update",
      displayName: "Furqan",
      phoneNumber: "+919876543210",
    });
    expect(profile.displayName).toBe("Furqan");
  });

  it("deletes only after server confirmation", async () => {
    await expect(deleteAccount({ ...auth, idempotencyKey: "stable-delete-key" }, (_input, init) => {
      expect(new Headers(init?.headers).get("X-Idempotency-Key")).toBe("stable-delete-key");
      return Promise.resolve(new Response(JSON.stringify({ deleted: true }), { status: 200 }));
    })).resolves.toBeUndefined();
    await expect(deleteAccount(auth, () => Promise.resolve(
      new Response(JSON.stringify({ deleted: false }), { status: 200 }),
    ))).rejects.toThrow("confirm account deletion");
  });

  it("persists destructive retry identity and pending identity-link state", () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => { values.set(key, value); },
      removeItem: (key: string) => { values.delete(key); },
    };

    const deletionKey = accountDeletionIdempotencyKey(storage);
    expect(accountDeletionIdempotencyKey(storage)).toBe(deletionKey);
    clearAccountDeletionIdempotencyKey(storage);
    expect(accountDeletionIdempotencyKey(storage)).not.toBe(deletionKey);

    rememberPendingIdentityLink("google", storage);
    expect(pendingIdentityLink(storage)).toBe("google");
    clearPendingIdentityLink(storage);
    expect(pendingIdentityLink(storage)).toBeUndefined();
  });

  it("loads linked providers and starts an explicit link intent", async () => {
    const providers = await snapshotCustomerIdentities(auth, (_input, init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ operation: "identitySnapshot" });
      return Promise.resolve(new Response(JSON.stringify({
        providers: [{ provider: "apple", linkKind: "ORIGIN", linkedAt: "2026-08-23T00:00:00Z" }],
      }), { status: 200 }));
    });
    expect(providers.map((identity) => identity.provider)).toEqual(["apple"]);

    await beginCustomerIdentityLink({ ...auth, provider: "google" }, (_input, init) => {
      expect(JSON.parse(String(init?.body))).toEqual({
        operation: "beginIdentityLink",
        provider: "google",
      });
      return Promise.resolve(new Response(JSON.stringify({
        provider: "google",
        intentId: "intent-id",
      }), { status: 200 }));
    });
  });

  it("requires the shared name and E.164 phone contract", () => {
    expect(isValidAccountProfile({ displayName: "F", phoneNumber: "+919876543210" })).toBe(true);
    expect(isValidAccountProfile({ displayName: "F", phoneNumber: "9876543210" })).toBe(false);
    expect(isValidAccountProfile({ displayName: "F", phoneNumber: "+910000000000" })).toBe(false);
    expect(isValidAccountProfile({ displayName: "F".repeat(81), phoneNumber: "+919876543210" })).toBe(false);
  });

  it("preserves authentication errors for session recovery", async () => {
    const request = snapshotAccountProfile(auth, () => Promise.resolve(
      new Response(JSON.stringify({
        error: { code: "authentication_required", message: "Sign in again to continue." },
      }), { status: 401 }),
    ));

    await expect(request).rejects.toMatchObject({
      status: 401,
      code: "authentication_required",
    });
  });
});
