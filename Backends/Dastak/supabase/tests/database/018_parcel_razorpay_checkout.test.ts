import { assertMatch, assertNotMatch } from "jsr:@std/assert";

Deno.test("parcel checkout is server-authoritative and customer-readable through functions", async () => {
  const migration = await Deno.readTextFile(
    new URL("../../migrations/20260722110000_parcel_razorpay_checkout.sql", import.meta.url),
  );
  const sql = migration.replace(/\s+/g, " ");

  for (
    const functionName of [
      "get_customer_parcel_deliveries",
      "prepare_parcel_razorpay_checkout",
      "attach_parcel_razorpay_order",
      "prepare_parcel_razorpay_refund",
      "attach_parcel_razorpay_refund",
      "record_razorpay_parcel_event",
    ]
  ) assertMatch(sql, new RegExp(`function public\\.${functionName}`, "i"));

  assertMatch(sql, /create table private\.parcel_payment_records/i);
  assertMatch(sql, /parcel\.recipient_account_id = p_account_id/i);
  assertMatch(sql, /'audience', selected\.public_audience/i);
  assertMatch(sql, /from public, anon, authenticated/i);
  assertMatch(sql, /to service_role/i);
  assertMatch(sql, /security invoker/i);
  assertNotMatch(sql, /security definer/i);
});
