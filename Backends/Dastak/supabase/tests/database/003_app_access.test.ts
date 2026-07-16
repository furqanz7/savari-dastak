import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("app access migration is invoker-only and maps every Dastak target", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_resolve_app_access.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one resolve_app_access migration");
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );

  assertMatch(migration, /create or replace function public\.resolve_app_access\(/i);
  assertMatch(migration, /security invoker/i);
  assertMatch(migration, /set search_path = ''/i);
  assertMatch(migration, /'customer'::private\.membership_role/i);
  assertMatch(migration, /'merchant'::private\.membership_role/i);
  assertMatch(migration, /'owner'::private\.membership_role/i);
  assertMatch(
    migration,
    /revoke execute on function public\.resolve_app_access\(uuid, text\) from public, anon, authenticated/i,
  );
  assertMatch(
    migration,
    /grant execute on function public\.resolve_app_access\(uuid, text\) to service_role/i,
  );
});
