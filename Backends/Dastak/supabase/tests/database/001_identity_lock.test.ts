import { assertEquals, assertExists } from "jsr:@std/assert";

Deno.test("bootstrap identity migration locks bootstrap attempts by account and function", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260715090000_bootstrap_identity.sql", import.meta.url),
  );
  const lockExpression = migration.match(
    /pg_catalog\.pg_advisory_xact_lock\(\s*pg_catalog\.hashtextextended\(\s*([\s\S]*?)\s*,\s*0\s*\)\s*\)/,
  )?.[1];

  assertExists(lockExpression);
  assertEquals(
    lockExpression.replace(/\s+/g, " ").trim(),
    "p_account_id::text || ':' || v_function_name",
  );
});
