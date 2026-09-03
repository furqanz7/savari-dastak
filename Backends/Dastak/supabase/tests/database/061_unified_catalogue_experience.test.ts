import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260902190813_unified_catalogue_experience.sql",
    import.meta.url,
  ),
);

Deno.test("unified catalogue keeps all role surfaces on one safe hierarchy", () => {
  for (
    const field of [
      "categoryTypes",
      "categories",
      "subcategories",
      "previewImageKeys",
      "galleryImageKeys",
      "quantityValue",
      "quantityUnit",
      "packCount",
    ]
  ) assert(migration.includes(`'${field}'`), `missing ${field}`);
  assertMatch(migration, /sku_search_aliases[\s\S]*sku_identifiers/);
  assertMatch(migration, /status = 'VERIFIED'[\s\S]*rights_status = 'CLEARED'/);
});

Deno.test("Merchant remains selection-only and Admin SKU edits remain audited", () => {
  assertMatch(migration, /merchant\.catalogue\.selection\.manage/);
  assertMatch(migration, /assert_platform_permission\(p_actor_id, 'platform\.catalogue\.manage'\)/);
  assertMatch(migration, /p_expected_version[\s\S]*stale SKU version/);
  assertMatch(migration, /CATALOGUE_SKU_UPDATED[\s\S]*idempotency_records/);
  assertEquals(/grant\s+update\s+on\s+(?:table\s+)?dastak_v1\.skus/i.test(migration), false);
});

Deno.test("activation constraint errors are not hidden by generic exception handling", () => {
  assertEquals(/exception when[\s\S]*check_violation/.test(migration), false);
  assertEquals(/exception when[\s\S]*foreign_key_violation/.test(migration), false);
});
