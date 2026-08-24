import { assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824193109_fix_v1_admin_execution_projection_contract.sql",
    import.meta.url,
  ),
);
const grantRepair = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824202546_restore_v1_admin_execution_authenticated_grants.sql",
    import.meta.url,
  ),
);
const client = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/dastakV1.ts", import.meta.url),
);

Deno.test("Admin order list emits every strict client projection field", () => {
  for (
    const field of [
      "orderType",
      "updatedAt",
      "deliveredAt",
    ]
  ) {
    assertMatch(migration, new RegExp(`'${field}'`));
    assertMatch(client, new RegExp(`source\\.${field}`));
  }
});

Deno.test("Admin trace augments the current authoritative trace instead of replacing it", () => {
  assertMatch(migration, /admin_execution_trace_pre_projection_contract/);
  assertMatch(migration, /v_trace -> 'order'/);
  assertMatch(migration, /assert_platform_permission|previous function remains authoritative/i);
});

Deno.test("Admin internal projection remains permission checked and reachable by its invoker wrapper", () => {
  assertMatch(
    grantRepair,
    /grant execute on function dastak_v1_api\.admin_execution_trace\(uuid, uuid\)[\s\S]*?to authenticated/i,
  );
  assertMatch(
    grantRepair,
    /grant execute on function dastak_v1_api\.admin_execution_orders\(uuid, integer\)[\s\S]*?to authenticated/i,
  );
  assertMatch(grantRepair, /validate auth\.uid\(\)|platform\.orders\.trace/i);
  assertMatch(migration, /security invoker/i);
});
