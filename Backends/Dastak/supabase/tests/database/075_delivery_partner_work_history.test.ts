import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260911183000_delivery_partner_work_history.sql",
    import.meta.url,
  ),
);

Deno.test("rider history is a bounded read-only projection over existing domains", () => {
  assertMatch(
    migration,
    /create or replace function public\.dastak_delivery_partner_work_history\(/i,
  );
  assertMatch(migration, /limit greatest\(1, least\(/i);
  assertMatch(migration, /from dastak_v1\.delivery_missions/i);
  assertMatch(migration, /from dastak_v1\.return_missions/i);
  assertMatch(migration, /from private\.delivery_assignment_attempts/i);
  assertMatch(migration, /from private\.parcel_assignment_attempts/i);
  assertMatch(migration, /delivery_missions_terminal_rider_history_idx/i);
  assertMatch(migration, /return_missions_terminal_rider_history_idx/i);
  assertMatch(migration, /delivery_assignment_partner_history_idx/i);
  assertMatch(migration, /parcel_assignment_partner_history_idx/i);
  assertNotMatch(migration, /create\s+table/i);
  assertNotMatch(migration, /pickup_address|dropoff_address|recipient_phone_number/i);
});

Deno.test("rider history remains behind the authenticated Edge service boundary", () => {
  assertMatch(
    migration,
    /revoke all on function public\.dastak_delivery_partner_work_history\(uuid, integer\)[\s\S]*?from public, anon, authenticated/i,
  );
  assertMatch(
    migration,
    /grant execute on function public\.dastak_delivery_partner_work_history\(uuid, integer\)[\s\S]*?to service_role/i,
  );
});
