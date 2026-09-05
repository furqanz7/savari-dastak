import { assert, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260905200941_curate_catalogue_navigation_and_artwork.sql",
    import.meta.url,
  ),
);

Deno.test("catalogue navigation keeps the canonical hierarchy behind five storefront sections", () => {
  for (
    const section of [
      "Grocery & Kitchen",
      "Snacks & Drinks",
      "Beauty & Wellness",
      "Household Essentials",
      "Hobbies & Interests",
    ]
  ) assert(migration.includes(`'name', '${section}'`), `missing ${section}`);
  assertMatch(migration, /'pharmacy'[\s\S]*'beauty-wellness'/);
  assertMatch(migration, /'paan-corner'[\s\S]*'snacks-drinks'/);
  assertMatch(migration, /category_type\.status <> 'INACTIVE'/);
  assertMatch(migration, /subcategory\.status <> 'INACTIVE'/);
});

Deno.test("category collages use only bounded rights-cleared active artwork", () => {
  assertMatch(migration, /sku\.status = 'ACTIVE'/);
  assertMatch(migration, /image\.status = 'VERIFIED'/);
  assertMatch(migration, /image\.rights_status = 'CLEARED'/);
  assertMatch(migration, /category_type_rank <= 2/);
  assertMatch(migration, /category_rank <= 2/);
  assertMatch(migration, /subcategory_rank <= 1/);
  assertMatch(migration, /'previewImageKeys'/);
});

Deno.test("navigation helper remains internal and Admin reuses the shared projection", () => {
  assertMatch(
    migration,
    /revoke all on function dastak_v1_api\.catalogue_navigation_section\(text\)[\s\S]*from public, anon, authenticated/,
  );
  assertMatch(
    migration,
    /catalogue_taxonomy_snapshot[\s\S]*browse_catalogue_taxonomy/,
  );
  assertMatch(migration, /security definer[\s\S]*set search_path = ''/);
});
