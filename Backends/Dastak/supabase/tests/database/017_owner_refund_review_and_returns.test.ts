import { assertMatch, assertNotMatch } from "jsr:@std/assert";

Deno.test("owner refund review enforces stage rules and merchant return", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260722080000_owner_refund_review_and_returns.sql",
      import.meta.url,
    ),
  );
  const sql = migration.replace(/\s+/g, " ");

  assertMatch(
    sql,
    /create function public\.owner_review_merchant_order_refund/i,
  );
  assertMatch(sql, /membership\.role = 'owner'/i);
  assertMatch(sql, /approve_items_only.*approve_full.*deny/i);
  assertMatch(sql, /delivery_fee_retained_unless_fault/i);
  assertMatch(sql, /v_fault_source not in \('merchant', 'dastak'\)/i);
  assertMatch(
    sql,
    /status = case when v_post_pickup then 'returning_to_merchant' else 'cancelled'/i,
  );
  assertMatch(
    sql,
    /create function public\.merchant_confirm_customer_cancellation_return/i,
  );
  assertMatch(sql, /response_reason = 'customer_cancellation_returned'/i);
  assertMatch(sql, /decision_status <> 'eligible'/i);
  assertMatch(sql, /from public, anon, authenticated/i);
  assertMatch(sql, /to service_role/i);
  assertMatch(sql, /security invoker/i);
  assertNotMatch(sql, /security definer/i);

  const lockMigration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260722081000_allow_refund_review_row_lock.sql",
      import.meta.url,
    ),
  );
  assertMatch(
    lockMigration.replace(/\s+/g, " "),
    /grant update \(id\) on table private\.merchant_order_refund_decisions to service_role/i,
  );
});
