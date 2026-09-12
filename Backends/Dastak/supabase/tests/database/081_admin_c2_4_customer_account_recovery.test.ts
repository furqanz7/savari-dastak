import { assert, assertMatch } from "jsr:@std/assert";

Deno.test("Admin C2.4 migration reuses governed session and phone-claim primitives", async () => {
  const migration = await Deno.readTextFile(new URL(
    "../../migrations/20260912215157_admin_c2_4_customer_account_recovery.sql",
    import.meta.url,
  ));
  const normalized = migration.replace(/\s+/g, " ");
  assertMatch(normalized, /platform\.accounts\.recover/i);
  assertMatch(normalized, /active Admin assignment required/i);
  assertMatch(normalized, /customer_active_session_projection/i);
  assertMatch(normalized, /revoked_account_sessions/i);
  assertMatch(normalized, /least\(v_current, v_replacement\).*greatest\(v_current, v_replacement\)/i);
  assertMatch(normalized, /stale Customer phone claim version/i);
  assertMatch(normalized, /PHONE_NUMBER_ALREADY_CLAIMED/i);
  assertMatch(normalized, /ADMIN_ACCOUNT_SESSIONS_REVOKED/i);
  assertMatch(normalized, /ADMIN_ACCOUNT_PHONE_CORRECTED/i);
  assert(!/refresh_token_hmac_key|refresh_token_counter|raw_app_meta_data|raw_user_meta_data/i.test(
    normalized.match(/admin_customer_recovery_page[\s\S]*?create or replace function dastak_v1_api\.admin_revoke_customer_sessions/i)?.[0] ?? "",
  ), "Customer recovery projection must not expose Auth tokens or raw Auth metadata");
  assert(!/update\s+auth\.users|insert\s+into\s+auth\.identities|delete\s+from\s+auth\.identities/i.test(normalized),
    "phone correction must preserve OAuth/Auth identity");
});
