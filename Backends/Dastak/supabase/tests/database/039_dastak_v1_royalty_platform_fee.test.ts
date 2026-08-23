import { assert, assertEquals } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824040000_dastak_v1_royalty_platform_fee.sql",
    import.meta.url,
  ),
);
const addenda = await Deno.readTextFile(
  new URL("../../../../../docs/DASTAK_V1_LOCKED_ADDENDA.md", import.meta.url),
);
const earningsHandler = await Deno.readTextFile(
  new URL("../../functions/earnings/handler.ts", import.meta.url),
);
const merchantWeb = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/MerchantOrdersView.tsx", import.meta.url),
);
const deliveryWeb = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/DeliveryPartnerView.tsx", import.meta.url),
);
const adminWeb = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/AdminV1ExecutionPanel.tsx", import.meta.url),
);

Deno.test("newer financial authority is explicit and does not rewrite history", () => {
  assert(addenda.includes("Newer financial authority: platform fee and Royalty"));
  assert(addenda.includes("2% of the immutable final successfully paid total"));
  assert(addenda.includes("Merchant → assigned Rider custody"));
  assert(addenda.includes("No payout provider is authorized"));
  assert(migration.includes("append-only financial history cannot be changed"));
  assert(migration.includes("historicalEarningsAndWithdrawalsPreserved"));
});

Deno.test("platform fee is paid-snapshot based, exactly once, and compensating", () => {
  assert(migration.includes("PAID_PRICE_SNAPSHOT_MISMATCH"));
  assert(migration.includes("platformFeeBps', 200"));
  assert(migration.includes("rounding', 'HALF_UP_TO_PAISE"));
  assert(migration.includes("checkoutPriceUnchanged', true"));
  assert(migration.includes("on conflict (transaction_key) do nothing"));
  assert(migration.includes("PLATFORM_FEE_REFUND_ADJUSTMENT"));
  assert(migration.includes("payment_provider_events_record_platform_fee"));
});

Deno.test("merchant commission is zero and verified pickup credits all merchant kinds", () => {
  assert(migration.includes("Locked V1 Merchant commission must be exactly 0 bps"));
  assert(migration.includes("fulfilments_credit_merchant_royalty"));
  assert(migration.includes("MERCHANT_TO_RIDER"));
  assert(migration.includes("COMPLETE_RIDER_CUSTODY_REQUIRED_FOR_MERCHANT_ROYALTY"));
  assert(!migration.includes("fulfilment_type = 'RETAIL'"));
});

Deno.test("Rider Royalty requires normal verified delivery rather than pickup", () => {
  const deliveryFunction = migration.slice(
    migration.indexOf("create or replace function dastak_v1.mark_settlements_after_delivery"),
    migration.indexOf("create function dastak_v1.seed_rider_fault_adjustment"),
  );
  assert(deliveryFunction.includes("RIDER_TO_CUSTOMER"));
  assert(deliveryFunction.includes("handoff.status = 'CONSUMED'"));
  assert(deliveryFunction.includes("delivery_evidence"));
  assert(deliveryFunction.includes("package.status <> 'DELIVERED'"));
  assert(deliveryFunction.includes("RIDER_ROYALTY_CREDITED"));
  assert(!deliveryFunction.includes("OVERRIDDEN'"));
});

Deno.test("legacy settlement eligibility cannot bypass immutable custody milestones", () => {
  const milestoneFunction = migration.slice(
    migration.indexOf("create function dastak_v1_api.royalty_earning_milestone_proven"),
    migration.indexOf("create or replace function dastak_v1_api.mark_order_settlements_eligible"),
  );
  const eligibilityFunction = migration.slice(
    migration.indexOf("create or replace function dastak_v1_api.mark_order_settlements_eligible"),
    migration.indexOf("create or replace function dastak_v1.mark_refund_adjustment_eligible"),
  );
  const refundFunction = migration.slice(
    migration.indexOf("create or replace function dastak_v1.mark_refund_adjustment_eligible"),
    migration.indexOf("create function dastak_v1_api.post_royalty_from_settlement_entry"),
  );
  assert(milestoneFunction.includes("package_custody_events"));
  assert(milestoneFunction.includes("fulfilment_evidence"));
  assert(milestoneFunction.includes("delivery_evidence_packages"));
  assert(milestoneFunction.includes("handoff.status = 'CONSUMED'"));
  assert(eligibilityFunction.includes("royalty_earning_milestone_proven(entry.id)"));
  assert(refundFunction.includes("entry.refund_id = new.id"));
  assert(refundFunction.includes("entry.entry_type <> 'EARNING'"));
  assert(migration.includes("ROYALTY_EARNING_MILESTONE_NOT_PROVEN"));
});

Deno.test("negative Royalty and refunds remain causally linked and independent", () => {
  assert(migration.includes("ROYALTY_FAULT_ADJUSTMENT"));
  assert(migration.includes("RIDER_CAUSED_APPROVED_REFUND"));
  assert(migration.includes("resolve_merchant_refund_fulfilment"));
  assert(migration.includes("resolve_rider_refund_mission"));
  assert(migration.includes("MERCHANT_ROYALTY_LIABILITY_ATTRIBUTION_REQUIRED"));
  assert(migration.includes("RIDER_ROYALTY_LIABILITY_ATTRIBUTION_REQUIRED"));
  assert(migration.includes("responsibleFulfilmentId"));
  assert(migration.includes("responsibleRiderId"));
  assert(migration.includes("customerRefundIndependent', true"));
  assert(migration.includes("refund_id"));
  assert(migration.includes("'subjectId', v_entry.subject_id"));
  assert(migration.includes("create_royalty_adjustment"));
});

Deno.test("withdrawal lifecycle reserves, releases, snapshots, and deduplicates", () => {
  for (
    const contract of [
      "REQUESTED",
      "PROCESSING",
      "PAID",
      "FAILED_RETRYABLE",
      "WITHDRAWAL_RESERVATION",
      "WITHDRAWAL_RELEASE",
      "WITHDRAWAL_PAID",
      "destination_snapshot",
      "provider_request_key",
      "provider_event_id",
      "pg_advisory_xact_lock",
      "WITHDRAWAL_EXCEEDS_AVAILABLE_ROYALTY",
      "PAYOUT_ATTEMPT_ALREADY_FINAL",
    ]
  ) assert(migration.includes(contract), contract + " is missing");
  assert(migration.includes("ROYALTY_WITHDRAWAL_REQUIRED"));
  assert(migration.includes("providerIndependent', true"));
});

Deno.test("Royalty APIs are service mediated and launch Web surfaces use Royalty", () => {
  assert(earningsHandler.includes('"merchantRoyaltySnapshot"'));
  assert(earningsHandler.includes('"deliveryRoyaltySnapshot"'));
  assert(earningsHandler.includes('"requestRoyaltyWithdrawal"'));
  assert(earningsHandler.includes("p_account_id: actor.accountId"));
  assert(merchantWeb.includes('<RoyaltyPanel auth={auth} kind="MERCHANT" />'));
  assert(deliveryWeb.includes('<RoyaltyPanel auth={auth} kind="RIDER" />'));
  assert(adminWeb.includes("state.platformFees.map"));
  assert(adminWeb.includes("state.royaltyLedger.map"));
  assert(adminWeb.includes("state.withdrawals.map"));
  assert(!adminWeb.includes("Mark settled"));
});

Deno.test("journal account postings remain structurally two-sided", () => {
  assert(migration.includes("line_number smallint not null check (line_number in (1, 2))"));
  assert(migration.includes("UNBALANCED_FINANCIAL_TRANSACTION"));
  assert(migration.includes("transaction.metadata = p_metadata"));
  assert(migration.includes("line.account_code = p_debit_account"));
  assert(migration.includes("line.account_code = p_credit_account"));
  assertEquals(
    (migration.match(/create constraint trigger financial_/g) ?? []).length,
    2,
  );
});

Deno.test("withdraw availability is actor-specific rather than balance-only", () => {
  const snapshot = migration.slice(
    migration.indexOf("create function dastak_v1_api.royalty_subject_snapshot"),
    migration.indexOf("create function dastak_v1_api.get_royalty_snapshot"),
  );
  assert(snapshot.includes("p_actor_id uuid"));
  assert(snapshot.includes("actor_can_manage_royalty_subject"));
  assert(snapshot.includes("p_actor_id, p_subject_type, p_subject_id, true"));
});
