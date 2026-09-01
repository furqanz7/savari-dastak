import { assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260901054548_close_unstaffed_merchant_branches.sql",
    import.meta.url,
  ),
);

Deno.test("unstaffed Merchant branches fail closed without reopening on recovery", () => {
  assertMatch(
    migration,
    /after update of status on dastak_v1\.merchant_users[\s\S]*?close_unstaffed_merchant_branches_after_membership_change/i,
  );
  assertMatch(
    migration,
    /after delete on dastak_v1\.merchant_users[\s\S]*?close_unstaffed_merchant_branches_after_membership_change/i,
  );
  assertMatch(
    migration,
    /not exists[\s\S]*?merchant_user\.status = 'ACTIVE'[\s\S]*?is_open = false[\s\S]*?accepting_orders = false/i,
  );
  assertMatch(
    migration,
    /revoke all on function[\s\S]*?from public, anon, authenticated, service_role/i,
  );
});
