import { assert, assertFalse, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260912195149_admin_c2_2_merchant_governance.sql",
    import.meta.url,
  ),
);
const client = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/dastakV1.ts", import.meta.url),
);
const dashboard = await Deno.readTextFile(
  new URL(
    "../../../../../Web/MarketplaceWeb/src/AdminDashboard.tsx",
    import.meta.url,
  ),
);
const governance = await Deno.readTextFile(
  new URL(
    "../../../../../Web/MarketplaceWeb/src/AdminMerchantGovernancePanel.tsx",
    import.meta.url,
  ),
);
const safety = await Deno.readTextFile(
  new URL(
    "../../../../../Web/MarketplaceWeb/src/AdminOperationalSafetyPanel.tsx",
    import.meta.url,
  ),
);

Deno.test("C2.2 governance stays behind dedicated permission and active Admin assignment", () => {
  assertMatch(
    migration,
    /assert_platform_permission\([\s\S]*?'platform\.merchants\.manage'/,
  );
  assertMatch(migration, /admin_role_for_actor\(p_actor_id\) is null/);
  assertMatch(
    migration,
    /revoke all on function public\.dastak_v1_admin_merchant_governance_page\([\s\S]*?from public, anon/,
  );
  assertFalse(
    /grant execute on function public\.dastak_v1_admin_merchant_governance_page[^;]+to anon/s
      .test(migration),
  );
});

Deno.test("C2.2 commands are versioned, idempotent, audited and preserve operational state", () => {
  for (
    const action of [
      "MERCHANT_ORGANIZATION_SUSPENDED",
      "MERCHANT_ORGANIZATION_REACTIVATED",
      "MERCHANT_BRANCH_SUSPENDED",
      "MERCHANT_BRANCH_REACTIVATED",
      "MERCHANT_BRANCH_DETAILS_CORRECTED",
    ]
  ) assert(migration.includes(action));
  assertMatch(migration, /p_expected_version bigint/g);
  assertMatch(migration, /p_idempotency_key text/g);
  assertMatch(migration, /ACTIVE_FULFILMENTS_REQUIRE_RESOLUTION/);
  assertMatch(migration, /ACTIVE_PICKUP_OR_RETURN_WORK/);
  assertFalse(
    /update dastak_v1\.branch_operational_states[\s\S]*?set/i.test(migration),
  );
  assertFalse(/update private\.merchant_applications/i.test(migration));
});

Deno.test("C2.2 serializes governance with new fulfilment and destination work", () => {
  assertMatch(migration, /guard_new_fulfilment_governance/);
  assertMatch(
    migration,
    /before insert or update of organization_id, branch_id, status[\s\S]*?on dastak_v1\.fulfilments/,
  );
  assertMatch(migration, /serialize_new_branch_route_work/);
  assertMatch(migration, /on dastak_v1\.delivery_stops/);
  assertMatch(migration, /on dastak_v1\.return_stops/);
  assertMatch(migration, /on dastak_v1\.return_packages/);
});

Deno.test("C2.2 Admin client and workspace reuse bounded runtime and privileged-action controls", () => {
  assertMatch(client, /getV1AdminMerchantGovernancePage/);
  assertMatch(client, /setV1AdminMerchantOrganizationStatus/);
  assertMatch(client, /setV1AdminMerchantBranchStatus/);
  assertMatch(client, /correctV1AdminMerchantBranchDetails/);
  assertMatch(dashboard, /<AdminMerchantGovernancePanel auth=\{auth\}/);
  assertMatch(governance, /runAdminPrivilegedMutation/);
  assertMatch(governance, /useAdminWorkspaceRefresh\("merchantGovernance"/);
  assertMatch(governance, /new RefreshQueue\(\)/);
  assertMatch(governance, /new AbortController\(\)/);
});

Deno.test("C2.2 Safety control discovers governed Merchant branches but preserves the existing pause command", () => {
  assertMatch(safety, /getV1AdminMerchantGovernancePage/);
  assertMatch(safety, /aria-label="Merchant branch"/);
  assertMatch(safety, /activeNonTerminalFulfilmentCount/);
  assertMatch(safety, /activePickupReturnWorkCount/);
  assertMatch(safety, /setV1OperationalPause/);
});
