import { assertEquals, assertMatch, assertNotMatch } from "jsr:@std/assert";

Deno.test("merchant checkout snapshots server-measured distance pricing", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrationNames = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (
      entry.isFile &&
      entry.name.endsWith("_apply_distance_pricing_to_merchant_quotes.sql")
    ) {
      migrationNames.push(entry.name);
    }
  }

  if (migrationNames.length !== 1) {
    throw new Error("expected one distance-priced checkout migration");
  }

  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationNames[0]}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");

  assertMatch(normalized, /merchant_order_quotes add column delivery_distance_m integer/i);
  assertMatch(normalized, /merchant_orders add column delivery_distance_m integer/i);
  assertMatch(normalized, /st_distance\([^;]+store\.location[^;]+dropoff/is);
  assertMatch(normalized, /calculate_merchant_order_distance_terms\(/i);
  assertMatch(normalized, /new\.delivery_fee_paise :=/i);
  assertMatch(normalized, /new\.total_paise := new\.item_subtotal_paise \+ new\.delivery_fee_paise/i);
  assertMatch(normalized, /'deliveryDistanceMeters'/i);
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
});

Deno.test("distance-priced order creation revalidates computed terms", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrationNames = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (
      entry.isFile &&
      entry.name.endsWith("_harden_distance_priced_order_creation.sql")
    ) {
      migrationNames.push(entry.name);
    }
  }

  assertEquals(migrationNames.length, 1);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationNames[0]}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");

  assertMatch(normalized, /create or replace function public\.create_merchant_order/i);
  assertMatch(normalized, /calculate_merchant_order_distance_terms\( v_rate, v_quote\.delivery_distance_m \)/i);
  assertMatch(normalized, /is distinct from v_quote\.delivery_fee_paise/i);
  assertMatch(normalized, /is distinct from v_quote\.courier_payout_paise/i);
  assertNotMatch(normalized, /rate\.delivery_fee_paise\s*=\s*v_quote\.delivery_fee_paise/i);
  assertMatch(normalized, /security invoker/i);
  assertMatch(normalized, /set search_path = ''/i);
});
