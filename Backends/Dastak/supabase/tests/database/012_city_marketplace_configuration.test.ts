import {
  assert,
  assertEquals,
  assertExists,
  assertMatch,
} from "jsr:@std/assert";

Deno.test("city marketplace configuration is bounded, versioned, and owner managed", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (
      entry.isFile && entry.name.endsWith("_city_marketplace_configuration.sql")
    ) {
      migrations.push(entry.name);
    }
  }

  assertEquals(
    migrations.length,
    1,
    "expected one city marketplace configuration migration",
  );
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");
  const signatures = normalized
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")");

  for (const column of ["center", "coverage_radius_m"]) {
    assertMatch(normalized, new RegExp(`add column ${column}`, "i"));
  }
  assertMatch(normalized, /coverage_radius_m between 10000 and 30000/i);

  for (
    const column of [
      "included_distance_m",
      "base_delivery_fee_paise",
      "delivery_fee_per_started_km_paise",
      "base_courier_payout_paise",
      "courier_payout_per_started_km_paise",
    ]
  ) {
    assertMatch(normalized, new RegExp(`add column ${column}`, "i"));
  }

  assertMatch(normalized, /default 3000/i);
  assertMatch(normalized, /default 3500/i);
  assertMatch(normalized, /default 800/i);
  assertMatch(normalized, /default 700/i);
  assertMatch(normalized, /merchant_commission_bps[^;]+default 1000/is);
  assertMatch(normalized, /ceil\([^;]+\/ 1000/is);

  for (
    const signature of [
      "upsert_city_service_zone(uuid, uuid, text, double precision, double precision, integer, boolean, text, text)",
      "upsert_merchant_order_distance_rate_card(uuid, uuid, integer, integer, integer, integer, integer, integer, boolean, text, text)",
      "browse_catalogue(uuid, double precision, double precision, integer)",
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
      new RegExp(
        `grant execute on function public\\.${escaped} to service_role`,
        "i",
      ),
    );
  }

  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
  const statementsOnly = normalized.replace(/as \$\$.*?\$\$;/gis, "");
  assert(
    !/insert into public\.service_zones/i.test(statementsOnly),
    "migration must not seed a city",
  );
  assert(
    !/insert into private\.merchant_stores/i.test(statementsOnly),
    "migration must not seed a merchant",
  );
});
