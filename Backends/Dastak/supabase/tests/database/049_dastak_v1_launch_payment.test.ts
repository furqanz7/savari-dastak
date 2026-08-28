import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260828115505_dastak_v1_pay_on_delivery_launch.sql",
    import.meta.url,
  ),
);

const commitment = migration.slice(
  migration.indexOf("create function dastak_v1_api.commit_launch_payment"),
  migration.indexOf("create function dastak_v1_api.record_launch_payment_collection"),
);
const collection = migration.slice(
  migration.indexOf("create function dastak_v1_api.record_launch_payment_collection"),
  migration.indexOf("alter function dastak_v1_api.complete_final_delivery_locked"),
);

Deno.test("launch payment authority is immutable, projected and command-bound", () => {
  assertMatch(migration, /launch_payment_commitments_immutable/i);
  assertMatch(migration, /launch_payment_collection_attempts_immutable/i);
  assertMatch(migration, /enable row level security/gi);
  assertMatch(migration, /base\.snapshot\s*-\s*'payment'/i);
  assertMatch(migration, /dastak_v1_commit_launch_payment\([\s\S]*?auth\.uid\(\)/i);
  assertMatch(
    migration,
    /dastak_v1_record_launch_payment_collection[\s\S]*?to service_role/i,
  );
  assertNotMatch(
    migration,
    /grant execute[\s\S]*?dastak_v1_record_launch_payment_collection[\s\S]*?to authenticated/i,
  );
});

Deno.test("customer commitment starts the full secured basket without provider execution", () => {
  assertMatch(commitment, /assert_customer_actor/i);
  assertMatch(commitment, /AWAITING_PAYMENT/i);
  assertMatch(commitment, /RESERVED_PREPAYMENT/i);
  assertMatch(commitment, /status = 'CANCELLED'/i);
  assertMatch(commitment, /status = 'PREPARING'/i);
  assertMatch(commitment, /status = 'FULFILLING'/i);
  assertMatch(commitment, /prep_started_at = v_now/i);
  assertMatch(commitment, /domain_events_outbox/i);
  assertMatch(commitment, /audit_events/i);
  assertNotMatch(commitment, /razorpay|payment_provider_events|provider_order/i);
});

Deno.test("doorstep collection owns amount, retry and exactly-once finance", () => {
  assertNotMatch(collection, /p_amount_paise/i);
  assertMatch(collection, /p_outcome not in \('COLLECTED', 'FAILED'\)/i);
  assertMatch(collection, /p_method not in \('CASH', 'UPI'\)/i);
  assertMatch(collection, /assigned_rider_id is distinct from p_actor_id/i);
  assertMatch(collection, /complete rider custody at the final-delivery stage is required/i);
  assertMatch(collection, /snapshot_kind = 'FULLY_SECURED'/i);
  assertMatch(collection, /snapshot_kind[\s\S]*?'PAID'/i);
  assertMatch(collection, /calculate_platform_fee/i);
  assertMatch(collection, /post_balanced_financial_transaction/i);
  assertNotMatch(collection, /razorpay|payment_provider_events/i);
  assertNotMatch(collection, /set status = 'SUCCEEDED'/i);
});

Deno.test("delivery guard accepts collected launch orders or historical provider-paid orders", () => {
  assertMatch(
    migration,
    /complete_final_delivery_locked[\s\S]*?launch_payment_collection_attempts[\s\S]*?outcome = 'COLLECTED'/i,
  );
  assertMatch(
    migration,
    /payment\.order_id = v_order_id and payment\.status = 'SUCCEEDED'/i,
  );
  assertMatch(migration, /LAUNCH_PAYMENT_COLLECTION_REQUIRED/i);
});

Deno.test("launch override preserves dormant provider and RazorpayX domains", () => {
  assertNotMatch(migration, /drop (table|function|type)[\s\S]*?(payment|razorpay)/i);
  assertNotMatch(migration, /razorpayx/i);
  assertMatch(migration, /payment\.launch_option_code/i);
  assertMatch(migration, /PAY_VIA_UPI_OR_CASH_ON_DELIVERY/i);
});
