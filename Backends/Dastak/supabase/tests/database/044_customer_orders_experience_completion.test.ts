import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824100000_customer_orders_experience_completion.sql",
    import.meta.url,
  ),
);

Deno.test("Customer Orders projection exposes only final-mile live tracking", () => {
  assertMatch(migration, /v_status = 'OUT_FOR_DELIVERY'/i);
  assertMatch(migration, /private\.delivery_partner_availability/i);
  assertMatch(migration, /distanceToDestinationMeters/i);
  assertMatch(migration, /riderLocationUpdatedAt/i);
  assertMatch(migration, /estimatedReadyAt/i);
  assertMatch(migration, /runningLate/i);
  assertNotMatch(migration, /pickupStops|pickupRoute|merchantBranches/i);
});

Deno.test("Customer Orders projection retains hardened execution privileges", () => {
  assertMatch(migration, /security definer[\s\S]*?set search_path = ''/i);
  assertMatch(
    migration,
    /revoke all on function[\s\S]*?order_json_pre_customer_orders_completion[\s\S]*?from public, anon, authenticated/i,
  );
  assertMatch(
    migration,
    /grant execute on function dastak_v1_api\.order_json\(uuid, uuid\)[\s\S]*?to authenticated/i,
  );
});
