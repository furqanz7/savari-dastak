import { assert } from "jsr:@std/assert@1";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20260831171328_retire_existing_dastak_personas.sql",
    import.meta.url,
  ),
);

Deno.test("existing identity retirement is guarded, recoverable and Superadmin-safe", () => {
  assert(sql.includes("exactly one immutable Superadmin"));
  assert(sql.includes("Complete or cancel all active Dastak work"));
  assert(sql.includes("where persona.state = 'ACTIVE'"));
  assert(sql.includes("claim_state = 'RECOVERY_ELIGIBLE'"));
  assert(sql.includes("where identity.user_id <> v_superadmin_id"));
  assert(sql.includes("where auth_user.id <> v_superadmin_id"));
  assert(sql.includes("canonicalHistoryPreserved"));
  assert(
    sql.includes(
      "revoke execute on function private.retire_existing_dastak_personas()",
    ),
  );
  assert(!sql.includes("delete from public.accounts"));
  assert(!sql.includes("delete from auth.users"));
});
