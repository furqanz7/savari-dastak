import { assert, assertEquals, assertExists } from "jsr:@std/assert";

Deno.test("bootstrap identity migration locks bootstrap attempts by account and function", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715090000_bootstrap_identity.sql",
      import.meta.url,
    ),
  );
  const lockMatch = migration.match(
    /pg_catalog\.pg_advisory_xact_lock\(\s*pg_catalog\.hashtextextended\(\s*([\s\S]*?)\s*,\s*0\s*\)\s*\)/,
  );

  assertExists(lockMatch);
  const lockExpression = lockMatch[1];
  assertEquals(
    lockExpression.replace(/\s+/g, " ").trim(),
    "p_account_id::text || ':' || v_function_name",
  );

  const lockStart = lockMatch.index;
  assertExists(lockStart);
  const lockEnd = lockStart + lockMatch[0].length;
  const deduplicationLookup = migration.indexOf(
    "from private.request_deduplication",
  );
  const accountExistenceCheck = migration.indexOf(
    "if exists (select 1 from public.accounts where id = p_account_id) then",
  );

  assert(
    deduplicationLookup >= lockEnd,
    "advisory lock must precede the request deduplication lookup",
  );
  assert(
    accountExistenceCheck >= lockEnd,
    "advisory lock must precede the account existence check",
  );
});
