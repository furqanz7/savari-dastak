import { assertMatch, assertNotMatch } from "jsr:@std/assert";

Deno.test("Dastak admin order oversight is owner-gated and read-only", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260722070000_dastak_admin_order_oversight.sql", import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");

  assertMatch(normalized, /create function public\.get_owner_merchant_orders/i);
  assertMatch(normalized, /membership\.role = 'owner'/i);
  assertMatch(normalized, /membership\.approved_at is not null/i);
  assertMatch(normalized, /p_limit < 1 or p_limit > 100/i);
  assertMatch(normalized, /order by merchant_order\.created_at desc/i);
  assertMatch(normalized, /grant execute on function public\.get_owner_merchant_orders\(uuid, integer\) to service_role/i);
  assertMatch(normalized, /security invoker/i);
  assertMatch(normalized, /set search_path = ''/i);
  assertNotMatch(normalized, /customer_account_id.*jsonb_build_object/i);
  assertNotMatch(normalized, /security definer/i);
});
