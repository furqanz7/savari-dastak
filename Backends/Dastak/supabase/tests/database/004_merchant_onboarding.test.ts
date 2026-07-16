import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("merchant onboarding stays server-owned and owner-reviewed", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_merchant_onboarding.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one merchant_onboarding migration");
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );

  assertMatch(migration, /create table private\.merchant_applications/i);
  assertMatch(migration, /alter table private\.merchant_applications enable row level security/i);
  assertMatch(
    migration,
    /revoke all on table private\.merchant_applications from public, anon, authenticated/i,
  );
  for (
    const signature of [
      "submit_merchant_application(uuid, text, text, text, text, text)",
      "list_merchant_applications(uuid)",
      "review_merchant_application(uuid, uuid, text, text, text, text)",
    ]
  ) {
    const escaped = signature.replace(/[()]/g, "\\$&");
    assertMatch(
      migration,
      new RegExp(
        `revoke execute on function public\\.${escaped} from public, anon, authenticated`,
        "i",
      ),
    );
    assertMatch(
      migration,
      new RegExp(`grant execute on function public\\.${escaped} to service_role`, "i"),
    );
  }
  assertMatch(migration, /security invoker/gi);
  assertMatch(migration, /set search_path = ''/gi);
  assertMatch(migration, /create policy dastak_merchant_evidence_insert_own/i);
  assertMatch(migration, /create policy dastak_merchant_evidence_select_own/i);
  assertMatch(migration, /merchant_application_submitted/i);
  assertMatch(migration, /merchant_application_reviewed/i);
  assertMatch(migration, /status = 'pending'/i);
  assertMatch(migration, /role[^\n]*=[^\n]*'merchant'/i);
});
