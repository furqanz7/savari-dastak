import { assert, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822030230_dastak_v1_rider_matching_pickup_custody.sql",
    import.meta.url,
  ),
);

Deno.test("Step 4A migration preserves mission, custody and privacy contracts", () => {
  for (
    const required of [
      "delivery_missions_one_active_order_uidx",
      "delivery_missions_one_active_rider_uidx",
      "delivery_offers_one_accepted_mission_uidx",
      "SYSTEM_CONFIGURATION_ERROR",
      "package pickup requires consumed verification by the assigned rider",
      "current_custody_owner_type = 'RIDER'",
      "status = 'CONSUMED'",
      "RIDER_REASSIGNING",
      "DELIVERY_RECOVERY_REQUIRED",
    ]
  ) assert(migration.includes(required), `missing ${required}`);
  assertMatch(migration, /customerState}', '"PICKING_UP"'/);
  assert(!/customerState[^;]+branch\.display_name/s.test(migration));
});
