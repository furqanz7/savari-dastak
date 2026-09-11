import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260911203106_admin_network_permission_hardening.sql",
    import.meta.url,
  ),
);

Deno.test("Admin identity directory has a dedicated permission and active-assignment gate", () => {
  assertMatch(migration, /'platform\.network\.read'/);
  assertMatch(
    migration,
    /bundle\.bundle_key in \('platform_super_admin', 'executive_admin'\)/,
  );
  assertMatch(migration, /admin_role_for_actor\(p_actor_id\) is null/);

  const functionBody = migration.match(
    /create or replace function dastak_v1_api\.admin_network_page[\s\S]*?\n\$\$;/i,
  )?.[0];
  assert(functionBody, "missing hardened Admin network function");
  assertMatch(functionBody, /'platform\.network\.read'/);
  assertEquals(functionBody.includes("platform.orders.trace"), false);
});

Deno.test("Admin identity directory execution remains caller-bound and unavailable to anonymous roles", () => {
  assertMatch(
    migration,
    /revoke all on function dastak_v1_api\.admin_network_page\([\s\S]*?from public, anon/i,
  );
  assertMatch(
    migration,
    /revoke all on function public\.dastak_v1_admin_network_page\([\s\S]*?from public, anon/i,
  );
  assertMatch(
    migration,
    /assert_authenticated_actor\(p_actor_id\)/,
  );
});
