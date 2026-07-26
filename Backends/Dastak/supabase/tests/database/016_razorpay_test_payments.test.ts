import { assert, assertEquals } from "jsr:@std/assert";

Deno.test("Razorpay migration keeps provider authority server-only", async () => {
  const migrations = [];
  for await (const entry of Deno.readDir("supabase/migrations")) {
    if (entry.isFile && entry.name.endsWith("_razorpay_test_payments.sql")) {
      migrations.push(entry.name);
    }
  }
  assertEquals(migrations.length, 1);
  const sql = await Deno.readTextFile(`supabase/migrations/${migrations[0]}`);

  for (
    const functionName of [
      "prepare_merchant_order_razorpay_checkout",
      "attach_merchant_order_razorpay_order",
      "prepare_merchant_order_razorpay_refund",
      "attach_merchant_order_razorpay_refund",
      "record_razorpay_merchant_order_event",
    ]
  ) {
    assert(sql.includes(`function public.${functionName}`));
  }
  assert(sql.includes("from public, anon, authenticated"));
  assert(sql.includes("to service_role"));
  assert(sql.includes("provider_order_reference"));
  assert(sql.includes("provider_refund_reference"));
});
