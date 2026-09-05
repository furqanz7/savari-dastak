import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260905170959_catalogue_taxonomy_parity_and_controlled_sections.sql",
    import.meta.url,
  ),
);

Deno.test("catalogue parity exposes the same non-inactive hierarchy to Customer and Merchant", () => {
  assertMatch(migration, /browse_catalogue_taxonomy/);
  assertMatch(migration, /category_type\.status <> 'INACTIVE'/);
  assertMatch(migration, /category\.status <> 'INACTIVE'/);
  assertMatch(migration, /subcategory\.status <> 'INACTIVE'/);
  assertMatch(migration, /p_limit integer default 5000/);
  assertMatch(migration, /least\(greatest\(coalesce\(p_limit, 5000\), 1\), 5000\)/);
});

Deno.test("controlled catalogue sections are present but cannot enter ordinary retail checkout", () => {
  for (const value of ["Pharmacy", "Medicines", "Paan Corner"]) {
    assert(migration.includes(`'${value}'`), `missing ${value}`);
  }
  assertMatch(migration, /requiresControlledFlow/);
  assertMatch(migration, /'DRAFT'[\s\S]*OTC Medicines/);
  assertEquals(/insert into dastak_v1\.skus/i.test(migration), false);
});

Deno.test("taxonomy previews remain restricted to customer-safe artwork", () => {
  assertMatch(migration, /sku\.status = 'ACTIVE'/);
  assertMatch(migration, /image\.status = 'VERIFIED'/);
  assertMatch(migration, /image\.rights_status = 'CLEARED'/);
});
