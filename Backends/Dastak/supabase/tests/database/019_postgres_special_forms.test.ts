import { assertMatch } from "jsr:@std/assert";

Deno.test("deployed functions repair schema-qualified PostgreSQL special forms", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260722120000_fix_qualified_postgres_special_forms.sql",
      import.meta.url,
    ),
  );
  const sql = migration.replace(/\s+/g, " ");

  assertMatch(sql, /namespace\.nspname in \('public', 'private'\)/i);
  for (const form of ["coalesce", "nullif", "greatest", "least"]) {
    assertMatch(
      sql,
      new RegExp(
        `replace\\(v_definition, 'pg_catalog\\.' \\|\\| '${form}\\(', '${form}\\('\\)`,
        "i",
      ),
    );
  }
});
