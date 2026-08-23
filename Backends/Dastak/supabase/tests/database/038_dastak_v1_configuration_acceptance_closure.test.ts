import { assert, assertEquals } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824030000_dastak_v1_configuration_acceptance_closure.sql",
    import.meta.url,
  ),
);
const courier = await Deno.readTextFile(
  new URL(
    "../../functions/courier-dispatch/handler.ts",
    import.meta.url,
  ),
);

Deno.test("acceptance closure has no invented business defaults", () => {
  for (
    const key of [
      "merchant.reachability_stale_seconds",
      "delivery.customer_unreachable_policy",
      "observability.alert_thresholds",
      "settlement.payout_cadence",
    ]
  ) assert(migration.includes(`'${key}'`), `${key} is missing`);
  assert(migration.includes("requires_explicit_value = true"));
  assert(migration.includes("message = 'SYSTEM_CONFIGURATION_ERROR'"));
});

Deno.test("merchant reachability gates discovery and final merchant decisions", () => {
  assert(migration.includes("aa_merchant_opportunities_reachability"));
  assert(migration.includes("aa_restaurant_requests_reachability"));
  assert(migration.includes("branch_operational_state_records_heartbeat"));
  assert(migration.includes("dastak_v1_api.branch_is_reachable"));
});

Deno.test("customer unreachable is structured and configuration-backed", () => {
  assert(courier.includes('case "v1ReportCustomerUnreachable"'));
  assert(courier.includes('"REPORT_CUSTOMER_UNREACHABLE"'));
  assert(migration.includes("CUSTOMER_UNREACHABLE"));
  assert(migration.includes("operational_policy_snapshot"));
  assert(migration.includes("next_action_at"));
  assert(migration.includes("CUSTOMER_UNREACHABLE_NOT_ALLOWED"));
  assertEquals(
    (migration.match(/delivery_problem_(?:code|policy)', '', true/g) ?? []).length,
    2,
    "each mission action must clear transaction-local customer-unreachable context",
  );
});

Deno.test("settlement and observability preserve configured operational truth", () => {
  assert(migration.includes("payout_cadence_snapshot"));
  assert(migration.includes("dastak_v1_api.payout_cadence_policy()"));
  assert(migration.includes("operationalAlerts"));
  assertEquals((migration.match(/outboxPendingCount/g) ?? []).length >= 3, true);
});
