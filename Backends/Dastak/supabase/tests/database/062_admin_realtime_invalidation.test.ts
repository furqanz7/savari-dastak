import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260904220540_admin_realtime_invalidation.sql",
    import.meta.url,
  ),
);

Deno.test("Admin Realtime is private, role-bound, and carries invalidations only", () => {
  assertMatch(migration, /'admin_changed'[\s\S]*'admin-control'[\s\S]*true/);
  assertMatch(migration, /realtime\.messages\.extension = 'broadcast'/);
  assertMatch(migration, /is_active_admin_actor\(\)/);
  assertEquals(/using\s*\(\s*true\s*\)/i.test(migration), false);
  assertEquals(/row_to_json|to_jsonb\(new\).*realtime\.send/is.test(migration), false);
});

Deno.test("approvals and live orders emit targeted Admin invalidations", () => {
  for (const table of [
    "private.merchant_applications",
    "private.delivery_partner_applications",
    "dastak_v1.orders",
    "dastak_v1.fulfilments",
    "dastak_v1.delivery_missions",
  ]) {
    assert(migration.includes(`on ${table}`), `missing trigger for ${table}`);
  }
  for (const workspace of [
    "merchantApprovals",
    "deliveryApprovals",
    "operations",
    "liveOrders",
    "commandCenter",
  ]) {
    assert(migration.includes(`'${workspace}'`), `missing ${workspace}`);
  }
});

Deno.test("Admin invalidation functions are not directly callable by clients", () => {
  assertMatch(
    migration,
    /revoke all on function private\.send_admin_change\(text\[\], uuid\)[\s\S]*from public, anon, authenticated, service_role/,
  );
  assertMatch(
    migration,
    /revoke all on function private\.broadcast_admin_change\(\)[\s\S]*from public, anon, authenticated, service_role/,
  );
});
