import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824090000_customer_account_completion.sql",
    import.meta.url,
  ),
);
const sharedAuth = await Deno.readTextFile(
  new URL("../../functions/_shared/auth.ts", import.meta.url),
);
const profileHandler = await Deno.readTextFile(
  new URL("../../functions/account-profile/handler.ts", import.meta.url),
);
const sessionsHandler = await Deno.readTextFile(
  new URL("../../functions/account-sessions/handler.ts", import.meta.url),
);

Deno.test("customer device revocation is service-owned and enforced on requests and token refresh", () => {
  assertMatch(migration, /create table private\.revoked_account_sessions/i);
  assertMatch(migration, /create function public\.revoke_account_session/i);
  assertMatch(migration, /assert_dastak_session_active/i);
  assertMatch(migration, /create or replace function public\.end_other_account_sessions/i);
  assertMatch(migration, /Customer signed out all other devices/i);
  assertMatch(migration, /customer_account_session_revocation/i);
  assertMatch(migration, /Customer account access disabled/i);
  assertMatch(migration, /claims' ->> 'session_id'/i);
  assertMatch(sharedAuth, /is_account_session_revoked/i);
  assertMatch(sharedAuth, /This Dastak session has been revoked/i);
  assertMatch(sessionsHandler, /operation === "revoke"/i);
  assertNotMatch(
    migration,
    /delete\s+from\s+(?:auth\.sessions|public\.accounts|dastak_v1\.orders)/i,
  );
});

Deno.test("customer export is caller-scoped, explicit, and excludes authentication secrets", () => {
  assertMatch(migration, /create function public\.export_customer_account_data/i);
  assertMatch(migration, /where customer_order\.customer_id = p_account_id/i);
  assertMatch(migration, /where issue\.customer_id = p_account_id/i);
  assertMatch(migration, /CUSTOMER_ACCOUNT_DATA_EXPORTED/i);
  const exportFunction = migration.match(
    /create function public\.export_customer_account_data[\s\S]*?\$\$;/i,
  )?.[0] ?? "";
  assertNotMatch(exportFunction, /provider_subject_digest|user_agent|encrypted_password/i);
  assertMatch(profileHandler, /case "export"/i);
});

Deno.test("account deletion requires a recent OAuth authentication assertion", () => {
  assertMatch(profileHandler, /reauthentication_required/i);
  assertMatch(profileHandler, /10 \* 60/i);
  assertMatch(sharedAuth, /oauthAuthenticationTimestamp/i);
  assertMatch(sharedAuth, /record\.method === "oauth"/i);
});
