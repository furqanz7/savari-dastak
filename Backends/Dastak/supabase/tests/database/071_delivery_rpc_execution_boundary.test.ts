import { assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260908141125_repair_delivery_rpc_execution_boundary.sql",
    import.meta.url,
  ),
);

const courierCommands = [
  "dastak_v1_accept_delivery_offer",
  "dastak_v1_decline_delivery_offer",
  "dastak_v1_advance_delivery_mission",
  "dastak_v1_advance_final_delivery",
  "dastak_v1_rider_heartbeat",
  "dastak_v1_record_launch_payment_collection",
  "dastak_v1_advance_return_mission",
];

Deno.test("every courier command moves behind the internal execution boundary", () => {
  for (const command of courierCommands) {
    assertMatch(
      migration,
      new RegExp(
        `alter function public\\.${command}[\\s\\S]*?set schema dastak_v1_api`,
        "i",
      ),
    );
  }
});

Deno.test("public courier commands are recreated as invoker wrappers", () => {
  const wrappers = migration.match(/create function public\.dastak_v1_/gi) ??
    [];
  assertEquals(wrappers.length, courierCommands.length);
  assertEquals(
    (migration.match(/language sql\s+security invoker/gi) ?? []).length,
    courierCommands.length,
  );
});

Deno.test("courier commands stay service-only across both layers", () => {
  assertEquals(
    (migration.match(/from public, anon, authenticated/gi) ?? []).length,
    courierCommands.length * 2,
  );
  assertEquals(
    (migration.match(/to service_role/gi) ?? []).length,
    courierCommands.length * 2,
  );
});
