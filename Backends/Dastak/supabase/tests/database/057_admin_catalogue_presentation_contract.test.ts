import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260901112945_enrich_admin_catalogue_presentation.sql",
    import.meta.url,
  ),
);

Deno.test("Admin catalogue presentation remains permission-bound", () => {
  assertMatch(
    migration,
    /assert_platform_permission\([\s\S]*?'platform\.catalogue\.read'/,
  );
  assertMatch(migration, /security definer[\s\S]*?set search_path = ''/i);
  assertEquals(
    /grant\s+select\s+on\s+(?:table\s+)?dastak_v1\./i.test(migration),
    false,
  );
  assertEquals(
    /create\s+or\s+replace\s+function\s+public\./i.test(migration),
    false,
  );
});

Deno.test("Admin catalogue page exposes customer presentation and complete hierarchy", () => {
  for (
    const field of [
      "categoryTypeName",
      "categoryName",
      "subcategoryName",
      "description",
      "imageKey",
      "manufacturerName",
      "countryOfOriginCode",
      "hsnCode",
      "dietType",
      "shelfLifeDays",
      "selectionCount",
    ]
  ) {
    assert(migration.includes(`'${field}'`), `missing safe field ${field}`);
  }
  assertMatch(migration, /p_category_type_id uuid default null/);
  assertMatch(
    migration,
    /p_category_type_id is null[\s\S]*?category\.category_type_id = p_category_type_id/,
  );
});

Deno.test("Taxonomy entities carry refresh-safe timestamps", () => {
  for (const entity of ["category_type", "category", "subcategory", "brand"]) {
    assertMatch(
      migration,
      new RegExp(`'updatedAt', ${entity}\\.updated_at`),
    );
  }
});
