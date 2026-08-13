import { describe, expect, it } from "vitest";
import { deleteAccount, isValidAccountProfile, updateAccountProfile } from "./accountProfile";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

describe("account profile", () => {
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
    await expect(deleteAccount(auth, () => Promise.resolve(
      new Response(JSON.stringify({ deleted: true }), { status: 200 }),
    ))).resolves.toBeUndefined();
    await expect(deleteAccount(auth, () => Promise.resolve(
      new Response(JSON.stringify({ deleted: false }), { status: 200 }),
    ))).rejects.toThrow("confirm account deletion");
  });

  it("requires the shared name and E.164 phone contract", () => {
    expect(isValidAccountProfile({ displayName: "F", phoneNumber: "+919876543210" })).toBe(true);
    expect(isValidAccountProfile({ displayName: "F", phoneNumber: "9876543210" })).toBe(false);
    expect(isValidAccountProfile({ displayName: "F".repeat(81), phoneNumber: "+919876543210" })).toBe(false);
  });
});
