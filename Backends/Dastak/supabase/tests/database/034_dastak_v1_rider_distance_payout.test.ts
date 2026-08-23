import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const files = await Promise.all([
  "20260822232358_dastak_v1_rider_distance_band_payout.sql",
  "20260823001500_dastak_v1_launch_failure_financial_completion.sql",
  "20260823001501_dastak_v1_launch_failure_financial_runtime.sql",
].map((name) => Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url))));
const migration = files.join("\n");

function functionBlock(name: string): string {
  const blocks = [...migration.matchAll(
    new RegExp(
      `create (?:or replace )?function ${name}\\s*\\([\\s\\S]*?\\$\\$;`,
      "gi",
    ),
  )];
  const block = blocks.at(-1)?.[0];
  assert(block, `missing function ${name}`);
  return block;
}

Deno.test("rider payout uses immutable authoritative distance-band snapshots", () => {
  assertNotMatch(migration, /settlement\.rider_flat_payout_paise/i);
  assertMatch(migration, /settlement\.rider_distance_payout/i);
  assertMatch(
    migration,
    /settlement\.merchant_commission_bps[\s\S]*?"minimum":0,"maximum":0/i,
  );
  assertMatch(
    migration,
    /delivery_distance_meters bigint not null[\s\S]*rider_payout_quote_paise bigint not null[\s\S]*rider_payout_quote_snapshot jsonb not null/i,
  );

  const calculator = functionBlock(
    "dastak_v1_api\\.calculate_rider_distance_payout",
  );
  assertMatch(calculator, /pg_catalog\.ceil/i);
  assertMatch(
    calculator,
    /STARTED_DISTANCE_BAND|is_valid_rider_distance_payout/i,
  );

  const quote = functionBlock("dastak_v1\\.quote_delivery_mission_payout");
  assertMatch(quote, /pickup_route_distance_meters/i);
  assertMatch(quote, /rider_distance_payout_configuration/i);
  assertMatch(quote, /quotedPayoutPaise/i);

  const missionGuard = functionBlock(
    "dastak_v1\\.guard_delivery_mission_payout_snapshot",
  );
  assertMatch(missionGuard, /payout quote cannot change/i);

  const settlement = functionBlock(
    "dastak_v1\\.mark_settlements_after_delivery",
  );
  assertMatch(settlement, /v_mission\.rider_payout_quote_paise/i);
  assertMatch(settlement, /v_mission\.rider_payout_quote_snapshot/i);
  assertNotMatch(
    settlement,
    /effective_setting_json|required_setting_integer/i,
  );

  const finalize = functionBlock(
    "dastak_v1_api\\.finalize_settlement_calculation",
  );
  assertMatch(finalize, /mission\.rider_payout_quote_paise/i);
  assertMatch(finalize, /mission\.rider_payout_quote_snapshot/i);
});
