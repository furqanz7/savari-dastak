import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("merchant catalogue stays private, server-priced, and restricted by default", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_merchant_catalogue.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one merchant_catalogue migration");
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );
  const normalizedMigration = migration.replace(/\s+/g, " ");
  const signatureMigration = normalizedMigration
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")");

  for (
    const table of [
      "merchant_stores",
      "catalogue_categories",
      "catalogue_products",
    ]
  ) {
    assertMatch(normalizedMigration, new RegExp(`create table private\\.${table}`, "i"));
    assertMatch(
      signatureMigration,
      new RegExp(`alter table private\\.${table} enable row level security`, "i"),
    );
  }

  for (
    const signature of [
      "upsert_merchant_store(uuid, text, text, double precision, double precision, boolean, boolean, text, text)",
      "upsert_catalogue_category(uuid, uuid, text, integer, boolean, text, text)",
      "upsert_catalogue_product(uuid, uuid, uuid, text, text, text, integer, text, text, text, boolean, text, text)",
      "get_merchant_catalogue(uuid)",
      "browse_catalogue(uuid, double precision, double precision)",
    ]
  ) {
    const escaped = signature.replace(/[()]/g, "\\$&");
    assertMatch(
      signatureMigration,
      new RegExp(
        `revoke execute on function public\\.${escaped} from public, anon, authenticated`,
        "i",
      ),
    );
    assertMatch(
      signatureMigration,
      new RegExp(`grant execute on function public\\.${escaped} to service_role`, "i"),
    );
  }

  assertMatch(normalizedMigration, /price_paise integer not null/i);
  assertMatch(
    normalizedMigration,
    /catalogue_kind in \(\s*'general', 'otc_medicine', 'prescription_medicine', 'paan_corner'\s*\)/i,
  );
  assertMatch(normalizedMigration, /restricted_approval_state[^;]*'pending'/is);
  assertMatch(normalizedMigration, /product\.catalogue_kind = 'general'/i);
  assertMatch(normalizedMigration, /create policy dastak_catalogue_image_insert_own/i);
  assertMatch(normalizedMigration, /create policy dastak_catalogue_image_select_own/i);
  assertMatch(normalizedMigration, /create policy dastak_catalogue_image_update_own/i);
  assert(!/create policy dastak_catalogue_image_delete_own/i.test(normalizedMigration));
  assertMatch(normalizedMigration, /merchant_store_upserted/i);
  assertMatch(normalizedMigration, /catalogue_category_upserted/i);
  assertMatch(normalizedMigration, /catalogue_product_upserted/i);
  assertMatch(normalizedMigration, /security invoker/gi);
  assertMatch(normalizedMigration, /set search_path = ''/gi);
});
