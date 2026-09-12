import { assert, assertFalse, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL("../../migrations/20260912113357_admin_operational_scale_pagination.sql", import.meta.url),
);
const adminClient = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/dastakV1.ts", import.meta.url),
);
const legacyClient = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/admin.ts", import.meta.url),
);

Deno.test("Admin scale projections are keyset-paginated and keep service-only legacy reads behind Edge", () => {
  for (const functionName of [
    "dastak_v1_admin_execution_orders_page",
    "get_owner_merchant_orders_page",
    "get_owner_order_exceptions_page",
    "dastak_v1_razorpayx_admin_page",
  ]) assert(migration.includes(functionName));
  assertMatch(migration, /limit p_limit \+ 1/g);
  assertMatch(migration, /'hasMore'/g);
  assertMatch(migration, /'nextCursor'/g);
  assertMatch(migration, /revoke all on function public\.get_owner_merchant_orders_page[\s\S]*?from public, anon, authenticated/);
  assertMatch(migration, /revoke all on function public\.get_owner_order_exceptions_page[\s\S]*?from public, anon, authenticated/);
  assertFalse(/grant execute on function public\.get_owner_(merchant_orders|order_exceptions)_page[^;]+to authenticated/s.test(migration));
});

Deno.test("Admin clients expose explicit live/history, exact search and opaque continuation contracts", () => {
  assertMatch(adminClient, /scope\?: "ACTIVE" \| "HISTORY"/);
  assertMatch(adminClient, /query\?: string/);
  assertMatch(adminClient, /nextCursor\?: \{ updatedAt: string; orderId: string \}/);
  assertMatch(legacyClient, /operation: "ownerHistoryPage"/);
  assertMatch(legacyClient, /operation: "ownerExceptionsPage"/);
  assertMatch(legacyClient, /hasMore: boolean/);
});
