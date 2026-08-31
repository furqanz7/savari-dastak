import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260831183759_admin_command_center_network_and_catalogue_page.sql",
    import.meta.url,
  ),
);
const securityMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260831190000_admin_catalogue_security_hardening.sql",
    import.meta.url,
  ),
);
const readinessMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260831191000_admin_catalogue_activation_readiness.sql",
    import.meta.url,
  ),
);

Deno.test("Admin command center and network projections are permission-bound", () => {
  assertMatch(
    migration,
    /assert_platform_permission\([\s\S]*?'platform\.orders\.trace'/,
  );
  assertMatch(migration, /assert_authenticated_actor\(p_actor_id\)/);
  assertMatch(
    migration,
    /revoke all on function public\.dastak_v1_admin_command_center\(\)[\s\S]*?from public, anon/i,
  );
  assertMatch(
    migration,
    /grant execute on function public\.dastak_v1_admin_command_center\(\)[\s\S]*?to authenticated, service_role/i,
  );
});

Deno.test("Admin network exposes connected summaries without private evidence fields", () => {
  for (
    const expected of [
      "displayName",
      "adminRole",
      "personas",
      "customer",
      "merchant",
      "delivery",
      "activeMissionCount",
    ]
  ) {
    assert(
      migration.includes(`'${expected}'`),
      `missing safe field ${expected}`,
    );
  }

  assertEquals(
    /evidenceObjectPath|evidence_object_path/.test(migration),
    false,
  );
  assertMatch(migration, /private\.account_personas/);
  assertMatch(migration, /private\.merchant_applications/);
  assertMatch(migration, /private\.delivery_partner_applications/);
});

Deno.test("Admin network enforces bounded filters and a complete keyset cursor", () => {
  assertMatch(migration, /char_length\(v_query\) > 80/);
  assertMatch(migration, /'CUSTOMER', 'MERCHANT', 'DELIVERY', 'ADMIN'/);
  assertMatch(migration, /'ACTIVE', 'DELETED'/);
  assertMatch(migration, /complete network cursor required/);
  assertMatch(migration, /limit v_limit \+ 1/);
  assertMatch(migration, /account\.updated_at, account\.id/);
});

Deno.test("Admin catalogue raw source rules remain private and supporting foreign keys are indexed", () => {
  assertMatch(
    securityMigration,
    /alter table dastak_v1\.catalogue_source_brand_aliases\s+enable row level security/i,
  );
  assertMatch(
    securityMigration,
    /alter table dastak_v1\.catalogue_source_taxonomy_rules\s+enable row level security/i,
  );
  assertMatch(
    securityMigration,
    /revoke all on table dastak_v1\.catalogue_source_brand_aliases[\s\S]*?from public, anon, authenticated/i,
  );
  assertMatch(
    securityMigration,
    /catalogue_import_items_canonical_sku_fk_idx/i,
  );
});

Deno.test("Admin catalogue exposes database-authoritative activation readiness", () => {
  for (
    const field of ["activationReady", "activationBlockers", "rightsStatus"]
  ) {
    assert(
      readinessMigration.includes(`'${field}'`),
      `missing governed field ${field}`,
    );
  }
  assertMatch(
    readinessMigration,
    /assert_platform_permission\([\s\S]*?'platform\.catalogue\.read'/,
  );
  assertMatch(readinessMigration, /CATEGORY_TYPE_ACTIVE_REQUIRED/);
  assertMatch(readinessMigration, /categoryTypeId', row\.category_type_id/);
});
