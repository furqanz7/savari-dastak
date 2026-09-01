import { assert, assertFalse } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260901105137_repair_admin_royalty_snapshot_service_access.sql",
    import.meta.url,
  ),
);

Deno.test("Admin Royalty snapshot grants only the Edge service its missing internal hop", () => {
  assert(
    migration.includes(
      "grant execute on function dastak_v1_api.razorpayx_admin_snapshot(uuid, integer)\n  to service_role",
    ),
  );
  assert(
    migration.includes(
      "revoke execute on function dastak_v1_api.razorpayx_admin_snapshot(uuid, integer)\n  from public, anon, authenticated",
    ),
  );
  assertFalse(migration.includes("to anon"));
  assertFalse(migration.includes("to authenticated"));
});
