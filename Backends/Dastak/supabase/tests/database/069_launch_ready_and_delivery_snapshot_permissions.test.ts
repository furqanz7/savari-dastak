import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260908113424_repair_launch_ready_and_delivery_snapshot_permissions.sql",
    import.meta.url,
  ),
);

Deno.test("Ready accepts launch authority without weakening legacy payment authority", () => {
  assertMatch(migration, /v_order\.status\s*<>\s*'PREPARING'/i);
  assertMatch(migration, /launch_payment_commitments[\s\S]*?PAY_VIA_UPI_OR_CASH_ON_DELIVERY/i);
  assertMatch(migration, /payments[\s\S]*?status\s*=\s*'SUCCEEDED'/i);
  assertNotMatch(migration, /update\s+dastak_v1\.payments/i);
});

Deno.test("delivery snapshot stays behind the authenticated edge boundary", () => {
  assertMatch(
    migration,
    /revoke all on function dastak_v1_api\.delivery_partner_snapshot\(uuid\)[\s\S]*?from public, anon, authenticated/i,
  );
  assertMatch(
    migration,
    /grant execute on function dastak_v1_api\.delivery_partner_snapshot\(uuid\)[\s\S]*?to service_role/i,
  );
});
