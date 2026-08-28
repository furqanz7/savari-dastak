import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260828143000_fix_razorpay_mode_service_role_boundary.sql",
    import.meta.url,
  ),
);

const providerWrappers = [
  "dastak_v1_prepare_razorpay_checkout_mode",
  "dastak_v1_attach_razorpay_order_mode",
  "dastak_v1_custom_checkout_completion_context_mode",
  "dastak_v1_record_custom_checkout_completion_mode",
  "dastak_v1_prepare_razorpay_refund_mode",
  "dastak_v1_attach_razorpay_refund_mode",
  "dastak_v1_record_razorpay_event_mode",
];

Deno.test("mode-isolated provider wrappers execute through the service boundary", () => {
  for (const wrapper of providerWrappers) {
    assertMatch(
      migration,
      new RegExp(`alter function public\\.${wrapper}\\([\\s\\S]*?security definer`, "i"),
    );
  }
});

Deno.test("service boundary migration does not grant direct provider-table access", () => {
  assertNotMatch(migration, /grant\s+(select|insert|update|delete|all)[\s\S]*?service_role/i);
  assertNotMatch(migration, /alter\s+table/i);
});
