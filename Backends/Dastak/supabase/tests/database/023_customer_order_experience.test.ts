import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migrationURL = new URL(
  "../../migrations/20260816030558_customer_order_experience.sql",
  import.meta.url,
);

Deno.test("customer order experience is private, ownership-checked, and recoverable", async () => {
  const normalized = (await Deno.readTextFile(migrationURL)).replace(/\s+/g, " ");

  assertMatch(normalized, /create table private\.customer_order_support_cases/i);
  assertMatch(
    normalized,
    /alter table private\.customer_order_support_cases enable row level security/i,
  );
  assertMatch(
    normalized,
    /revoke all on table private\.customer_order_support_cases from public, anon, authenticated/i,
  );
  assertNotMatch(normalized, /grant[^;]*customer_order_support_cases[^;]*authenticated/i);

  for (
    const functionName of [
      "get_customer_order_snapshot",
      "get_parcel_delivery_snapshot",
      "get_customer_orders",
      "get_customer_parcel_deliveries",
      "create_customer_order_support_case",
    ]
  ) {
    assertMatch(normalized, new RegExp(`${functionName}`, "i"));
  }

  assertMatch(normalized, /merchant_order\.customer_account_id = p_account_id/i);
  assertMatch(
    normalized,
    /parcel\.customer_account_id = p_account_id or parcel\.recipient_account_id = p_account_id/i,
  );
  assertMatch(normalized, /'customerActions'/i);
  assertMatch(normalized, /'supportCases'/i);
  assertMatch(normalized, /'cancellationMode'/i);
  assertMatch(normalized, /private\.request_deduplication/i);
  assertMatch(normalized, /customer_order_support_requested/i);
  assertMatch(normalized, /security invoker set search_path = ''/i);

  assertMatch(
    normalized,
    /revoke execute on function public\.create_customer_order_support_case\([^;]*from public, anon, authenticated/i,
  );
  assertMatch(
    normalized,
    /grant execute on function public\.create_customer_order_support_case\([^;]*to service_role/i,
  );
});
