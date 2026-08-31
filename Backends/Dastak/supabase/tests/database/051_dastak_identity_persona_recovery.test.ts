import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260831170000_dastak_identity_persona_recovery.sql",
    import.meta.url,
  ),
);
const bootstrap = migration.slice(
  migration.indexOf("create function public.bootstrap_dastak_persona"),
  migration.indexOf("create function public.prepare_dastak_persona_deletion"),
);
const deletion = migration.slice(
  migration.indexOf("create function public.prepare_dastak_persona_deletion"),
  migration.indexOf("create function private.sync_admin_identity_phone_claim"),
);

Deno.test("persona and verified-phone authorities are private and RLS protected", () => {
  assertMatch(migration, /create table private\.account_personas/i);
  assertMatch(migration, /create table private\.account_phone_claims/i);
  assertMatch(migration, /alter table private\.account_personas enable row level security/i);
  assertMatch(migration, /alter table private\.account_phone_claims enable row level security/i);
  assertMatch(migration, /revoke all[\s\S]*?from public, anon, authenticated/i);
  assertNotMatch(migration, /grant select[\s\S]*?account_personas[\s\S]*?to authenticated/i);
});

Deno.test("bootstrap requires matching verified phone and creates only the requested app persona", () => {
  assertMatch(
    bootstrap,
    /p_verified_phone_number is null or p_verified_phone_number <> p_phone_number/i,
  );
  assertMatch(bootstrap, /phone_number_in_use/i);
  assertMatch(bootstrap, /identity_recovery_required/i);
  assertMatch(bootstrap, /if p_application = 'customer'/i);
  assertMatch(bootstrap, /elsif p_application = 'merchant' and coalesce\(v_was_deleted, false\)/i);
  assertMatch(bootstrap, /elsif p_application = 'delivery' and coalesce\(v_was_deleted, false\)/i);
  assertNotMatch(bootstrap, /values \(p_account_id, 'merchant', null\)/i);
  assertNotMatch(bootstrap, /values \(p_account_id, 'dastak_partner', null\)/i);
});

Deno.test("persona deletion is isolated and full deletion alone releases identity recovery", () => {
  assertMatch(deletion, /persona = v_persona/i);
  assertMatch(deletion, /role = v_role/i);
  assertMatch(deletion, /if v_persona = 'MERCHANT'/i);
  assertMatch(deletion, /elsif v_persona = 'DELIVERY'/i);
  assertMatch(deletion, /if not private\.identity_has_active_access\(p_account_id\)/i);
  assertMatch(deletion, /claim_state = 'RECOVERY_ELIGIBLE'/i);
  assertNotMatch(deletion, /delete from public\.accounts|delete from auth\.users/i);
});

Deno.test("superadmin identity remains outside persona deletion and recovery transfer", () => {
  assertMatch(migration, /assignment\.account_id = v_claim\.account_id and assignment\.slot = 0/i);
  assertMatch(
    migration,
    /exists \([\s\S]*?admin_role_assignments assignment[\s\S]*?assignment\.account_id = p_account_id/i,
  );
});
