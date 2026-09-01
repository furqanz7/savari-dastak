import { assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260901054029_fix_admin_operational_safety_grants.sql",
    import.meta.url,
  ),
);

Deno.test("Admin safety projection and commands bridge only authenticated actors", () => {
  for (
    const signature of [
      "admin_operational_safety\\(uuid\\)",
      "manage_rider_escalation\\(uuid,uuid,text,text,bigint,text\\)",
      "set_operational_pause\\(uuid,text,uuid,boolean,text,bigint,text\\)",
    ]
  ) {
    assertMatch(
      migration,
      new RegExp(
        `${signature}[\\s\\S]*?to authenticated, service_role`,
        "i",
      ),
    );
  }
  assertMatch(
    migration,
    /revoke all on function[\s\S]*?from public, anon/i,
  );
});
