import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("delivery partner foundation stays private, approved, and server-located", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_delivery_partner_onboarding_availability.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one delivery partner foundation migration");
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");
  const signatures = normalized
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")");

  for (
    const table of [
      "delivery_partner_applications",
      "delivery_partner_profiles",
      "delivery_partner_availability",
    ]
  ) {
    assertMatch(normalized, new RegExp(`create table private\\.${table}`, "i"));
    assertMatch(
      signatures,
      new RegExp(`alter table private\\.${table} enable row level security`, "i"),
    );
    assertMatch(
      normalized,
      new RegExp(`revoke all on table private\\.${table} from public, anon, authenticated`, "i"),
    );
  }

  for (
    const signature of [
      "submit_delivery_partner_application(uuid, text, text, text, text)",
      "get_delivery_partner_snapshot(uuid)",
      "list_delivery_partner_applications(uuid)",
      "review_delivery_partner_application(uuid, uuid, text, text, text, text)",
      "set_delivery_partner_availability(uuid, boolean, double precision, double precision, text, text)",
    ]
  ) {
    const escaped = signature.replace(/[()]/g, "\\$&");
    assertMatch(
      signatures,
      new RegExp(
        `revoke execute on function public\\.${escaped} from public, anon, authenticated`,
        "i",
      ),
    );
    assertMatch(
      signatures,
      new RegExp(`grant execute on function public\\.${escaped} to service_role`, "i"),
    );
  }

  for (const method of ["walking", "bicycle", "bike", "auto", "car"]) {
    assertMatch(normalized, new RegExp(`'${method}'`, "i"));
  }
  assertMatch(normalized, /drop policy if exists dastak_evidence_update_own/i);
  assertMatch(normalized, /role = 'dastak_partner'/i);
  assertMatch(normalized, /interval '15 minutes'/i);
  assertMatch(normalized, /extensions\.st_covers/i);
  assertMatch(normalized, /available_until > pg_catalog\.now\(\)/i);
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
  assert(!/security definer/i.test(normalized), "foundation must not introduce definer RPCs");
});
