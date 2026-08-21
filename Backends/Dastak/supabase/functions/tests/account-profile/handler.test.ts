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
        return Promise.resolve({ accountId });
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

Deno.test("account profile deletes only the authenticated account", async () => {
  let deletedAccountId: string | undefined;
  const response = await handleAccountProfile(
    request({ operation: "delete" }),
    dependencies({
      deleteAccount: (value) => {
        deletedAccountId = value;
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(deletedAccountId, accountId);
  assertEquals(await response.json(), { deleted: true });
});

function request(body: unknown, authenticated = true) {
  return new Request("https://example.test/functions/v1/account-profile", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(authenticated ? { authorization: "Bearer session-token" } : {}),
    },
    body: JSON.stringify(body),
  });
}

function dependencies(
  overrides: Partial<AccountProfileDependencies> = {},
): AccountProfileDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ?? (() => Promise.resolve({ accountId })),
    snapshotProfile: overrides.snapshotProfile ?? (() => Promise.resolve(profile)),
    updateProfile: overrides.updateProfile ?? ((_accountId, value) => Promise.resolve(value)),
    deleteAccount: overrides.deleteAccount ?? (() => Promise.resolve()),
  };
}
