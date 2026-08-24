import { assertEquals } from "jsr:@std/assert";
import {
  type AccountProfileDependencies,
  handleAccountProfile,
} from "../../account-profile/handler.ts";

const accountId = "22222222-2222-4222-8222-222222222222";
const profile = { displayName: "Test User", phoneNumber: "+919876543210" };

Deno.test("account profile serves CORS preflight without authentication", async () => {
  let attempts = 0;
  const response = await handleAccountProfile(
    new Request("https://example.test", { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        attempts += 1;
        return Promise.resolve({ accountId, accessToken: "session-token" });
      },
    }),
  );
  assertEquals(response.status, 204);
  assertEquals(attempts, 0);
});

Deno.test("account profile requires a bearer token", async () => {
  const response = await handleAccountProfile(
    request({ operation: "snapshot" }, false),
    dependencies(),
  );
  assertEquals(response.status, 401);
});

Deno.test("account profile returns the caller profile", async () => {
  const response = await handleAccountProfile(request({ operation: "snapshot" }), dependencies());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { profile });
});

Deno.test("account profile normalizes updates", async () => {
  let updated: unknown;
  const response = await handleAccountProfile(
    request({ operation: "update", displayName: "  Test   User ", phoneNumber: " +919876543210 " }),
    dependencies({
      updateProfile: (_accountId, value) => {
        updated = value;
        return Promise.resolve(value);
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(updated, profile);
});

Deno.test("account profile rejects an invalid phone number", async () => {
  const response = await handleAccountProfile(
    request({ operation: "update", displayName: "Test User", phoneNumber: "9876543210" }),
    dependencies(),
  );
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error.code, "invalid_phone_number");
});

Deno.test("account profile rejects a nationally invalid E.164 phone number", async () => {
  const response = await handleAccountProfile(
    request({ operation: "update", displayName: "Test User", phoneNumber: "+910000000000" }),
    dependencies(),
  );
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error.code, "invalid_phone_number");
});

Deno.test("account profile deletes only the authenticated account", async () => {
  let deletion: { accountId: string; accessToken: string; idempotencyKey: string } | undefined;
  const response = await handleAccountProfile(
    request({ operation: "delete" }),
    dependencies({
      deleteAccount: (value) => {
        deletion = value;
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(deletion, {
    accountId,
    accessToken: "session-token",
    idempotencyKey: "profile-request-key",
  });
  assertEquals(await response.json(), { deleted: true, deletionQueued: true });
});

Deno.test("account profile exposes and begins only explicit Apple or Google links", async () => {
  const snapshot = await handleAccountProfile(
    request({ operation: "identitySnapshot" }),
    dependencies({
      snapshotIdentities: () =>
        Promise.resolve({
          providers: [{ provider: "apple", linkKind: "ORIGIN" }],
        }),
    }),
  );
  assertEquals(await snapshot.json(), {
    providers: [{ provider: "apple", linkKind: "ORIGIN" }],
  });

  let linkInput: unknown;
  const link = await handleAccountProfile(
    request({ operation: "beginIdentityLink", provider: "google" }),
    dependencies({
      beginIdentityLink: (input) => {
        linkInput = input;
        return Promise.resolve({ provider: "google", intentId: "intent" });
      },
    }),
  );
  assertEquals(link.status, 200);
  assertEquals(linkInput, {
    accessToken: "session-token",
    provider: "google",
    idempotencyKey: "profile-request-key",
  });
});

Deno.test("account profile rejects non-OAuth identity-link providers", async () => {
  const response = await handleAccountProfile(
    request({ operation: "beginIdentityLink", provider: "email" }),
    dependencies(),
  );
  assertEquals(response.status, 400);
});

function request(body: unknown, authenticated = true) {
  return new Request("https://example.test/functions/v1/account-profile", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Idempotency-Key": "profile-request-key",
      ...(authenticated ? { authorization: "Bearer session-token" } : {}),
    },
    body: JSON.stringify(body),
  });
}

function dependencies(
  overrides: Partial<AccountProfileDependencies> = {},
): AccountProfileDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId, accessToken: "session-token" })),
    snapshotProfile: overrides.snapshotProfile ?? (() => Promise.resolve(profile)),
    updateProfile: overrides.updateProfile ?? ((_accountId, value) => Promise.resolve(value)),
    snapshotIdentities: overrides.snapshotIdentities ?? (() => Promise.resolve({ providers: [] })),
    beginIdentityLink: overrides.beginIdentityLink ?? (() => Promise.resolve({})),
    deleteAccount: overrides.deleteAccount ?? (() => Promise.resolve()),
  };
}
