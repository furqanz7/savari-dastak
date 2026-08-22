import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const files = await Promise.all([
  "20260823001500_dastak_v1_launch_failure_financial_completion.sql",
  "20260823001501_dastak_v1_launch_failure_financial_runtime.sql",
  "20260823001502_dastak_v1_launch_failure_projections.sql",
].map((name) => Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url))));
const migration = files.join("\n");

function functionBlock(name: string): string {
  const block = migration.match(
    new RegExp(`create (?:or replace )?function ${name}\\s*\\([\\s\\S]*?\\$\\$;`, "i"),
  )?.[0];
  assert(block, `missing function ${name}`);
  return block;
}

Deno.test("Step 5 preserves recovery, reverse custody, refund, settlement and privacy contracts", () => {
  const normalized = migration.replace(/\s+/g, " ");
  for (
    const required of [
      "EXACT_SKU_RECOVERY_STARTED",
      "RECOVERY_SUCCEEDED",
      "DELIVERY_RECOVERY_STARTED",
      "CUSTOMER_ISSUE_REPORTED",
      "RETURN_PICKUP_VERIFIED",
      "RETURN_RECEIPT_VERIFIED",
      "REFUND_COMPLETED",
      "SETTLEMENT_RECORDED",
      "returns.pickup_photo_required",
      "platform.refunds.process",
      "platform.settlements.manage",
    ]
  ) assert(normalized.includes(required), `missing ${required}`);

  const recovery = functionBlock("dastak_v1_api\\.respond_exact_sku_recovery_offer");
  assertMatch(recovery, /source_recovery_opportunity_id/i);
  assertMatch(recovery, /'RECOVERY', 'PREPARING'/i);
  assertMatch(recovery, /confirmed_quantity[\s\S]*v_line\.quantity/i);
  assertNotMatch(recovery, /selling_price|unit_price_paise\s*=/i);

  const lineTransition = functionBlock("dastak_v1\\.is_valid_order_line_transition");
  assertMatch(lineTransition, /when 'RECOVERY' then p_to in \('FULFILLING'/i);

  const missionGuard = functionBlock("dastak_v1\\.guard_delivery_mission");
  assertMatch(
    missionGuard,
    /old\.status not in \('ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY'\)/i,
  );
  assertMatch(missionGuard, /old\.status not in \('OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY'\)/i);

  const eligibility = functionBlock("dastak_v1_api\\.recovery_branch_eligibility");
  assertMatch(eligibility, /selection\.sku_id = v_line\.sku_id/i);
  assertMatch(eligibility, /'requestedQuantity', v_line\.quantity/i);

  const failedRecovery = functionBlock("dastak_v1_api\\.fail_exact_sku_recovery");
  assertMatch(failedRecovery, /dastak_v1\.recovery_opportunity_status/i);
  assertMatch(failedRecovery, /create_approved_refund/i);

  const returnCommand = functionBlock("dastak_v1_api\\.advance_return_mission");
  assertMatch(returnCommand, /current_custody_owner_type = 'RETURN_RIDER'/i);
  assertMatch(returnCommand, /current_custody_owner_type = 'MERCHANT_RETURN'/i);
  assertMatch(returnCommand, /RETURN_PICKUP_CODE_REJECTED/i);
  assertMatch(returnCommand, /RETURN_RECEIPT_CODE_REJECTED/i);

  const refund = functionBlock("dastak_v1_api\\.record_razorpay_refund_event");
  assertMatch(refund, /provider_event_id/i);
  assertMatch(refund, /pg_advisory_xact_lock[\s\S]*RAZORPAY:REFUND/i);
  assertMatch(refund, /status = 'COMPLETED'/i);

  const settlement = functionBlock("dastak_v1_api\\.settle_entry");
  assertMatch(settlement, /platform\.settlements\.manage/i);
  assertMatch(settlement, /status = 'SETTLED'/i);
  assertMatch(settlement, /settlement_reference/i);
  assertMatch(settlement, /pg_advisory_xact_lock/i);
  assertMatch(settlement, /idempotency_records/i);

  const settlementCalculation = functionBlock(
    "dastak_v1_api\\.finalize_settlement_calculation",
  );
  assertMatch(settlementCalculation, /pg_advisory_xact_lock/i);
  assertMatch(settlementCalculation, /idempotency_records/i);

  const customerProjection = functionBlock("dastak_v1_api\\.order_json");
  assertMatch(customerProjection, /'support'/i);
  assertMatch(customerProjection, /customerMessage/i);
  assertNotMatch(customerProjection, /branch\.display_name|organization_id|branch_id/i);

  for (const block of migration.matchAll(/create (?:or replace )?function[\s\S]*?\$\$;/gi)) {
    if (/security definer/i.test(block[0])) assertMatch(block[0], /set search_path = ''/i);
  }
});
