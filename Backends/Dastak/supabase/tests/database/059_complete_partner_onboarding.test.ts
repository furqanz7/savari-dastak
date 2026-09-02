import { assert, assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260902074940_dastak_complete_partner_onboarding.sql",
    import.meta.url,
  ),
);

Deno.test("merchant submission requires the complete business and location contract", () => {
  for (
    const field of [
      "merchant_type",
      "legal_name",
      "location",
      "service_zone_id",
      "provisioned_organization_id",
      "provisioned_branch_id",
    ]
  ) {
    assert(migration.includes(field), `missing onboarding field ${field}`);
  }
  assertMatch(migration, /st_covers\(zone\.boundary, v_location\)/i);
  assertMatch(migration, /outside_service_area/);
});

Deno.test("merchant approval provisions the authoritative V1 runtime atomically", () => {
  for (
    const table of [
      "dastak_v1.merchant_organizations",
      "dastak_v1.merchant_branches",
      "dastak_v1.merchant_users",
      "dastak_v1.merchant_permission_grants",
      "dastak_v1.branch_operational_states",
    ]
  ) {
    assert(migration.includes(`insert into ${table}`), `missing ${table}`);
  }
  assertMatch(migration, /10000000-0000-4000-8000-000000000001/);
  assertMatch(migration, /values \(v_branch_id, false, false/);
});

Deno.test("onboarding RPCs stay behind the verified service boundary", () => {
  for (
    const signature of [
      "submit_merchant_application_v2",
      "get_merchant_application_snapshot",
      "list_merchant_applications",
      "review_merchant_application",
      "review_delivery_partner_application",
    ]
  ) {
    assertMatch(
      migration,
      new RegExp(
        `revoke execute on function public\\.${signature}[\\s\\S]*?from public, anon, authenticated`,
        "i",
      ),
    );
  }
  assertEquals(/grant execute[\s\S]*?to authenticated/i.test(migration), false);
});

Deno.test("review operations serialize and remain idempotent", () => {
  assertMatch(migration, /pg_advisory_xact_lock/);
  assertMatch(migration, /private\.request_deduplication/);
  assertMatch(migration, /for update/);
  assertMatch(migration, /idempotency_conflict/);
});

Deno.test("delivery approval restores one verified offline runtime", () => {
  assertMatch(
    migration,
    /insert into private\.delivery_partner_profiles[\s\S]*?on conflict \(account_id\) do update/i,
  );
  assertMatch(
    migration,
    /insert into private\.delivery_partner_availability[\s\S]*?on conflict \(account_id\) do update/i,
  );
  assertMatch(migration, /set status = 'offline', location = null, service_zone_id = null/i);
});
