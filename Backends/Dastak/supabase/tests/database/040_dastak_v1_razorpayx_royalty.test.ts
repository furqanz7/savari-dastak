import { assert } from "jsr:@std/assert";

const migration = await read(
  "../../migrations/20260824050000_dastak_v1_razorpayx_royalty_withdrawals.sql",
);
const config = await read("../../config.toml");
const adapter = await read("../../functions/_shared/razorpayx.ts");
const orchestration = await read("../../functions/earnings/razorpayx.ts");
const earningsIndex = await read("../../functions/earnings/index.ts");
const webhook = await read("../../functions/razorpayx-payout-webhook/handler.ts");
const webhookIndex = await read("../../functions/razorpayx-payout-webhook/index.ts");
const royaltyWeb = await read("../../../../../Web/MarketplaceWeb/src/RoyaltyPanel.tsx");
const adminWeb = await read("../../../../../Web/MarketplaceWeb/src/AdminRoyaltyPayoutPanel.tsx");
const addenda = await read("../../../../../docs/DASTAK_V1_LOCKED_ADDENDA.md");
const executionState = await read("../../../../../DASTAK_EXECUTION_STATE.md");
const workflow = await read("../../../../../.github/workflows/foundation.yml");

Deno.test("newer authority locks RazorpayX as rail while Dastak remains ledger authority", () => {
  assert(addenda.includes("Newest payout-rail authority: RazorpayX"));
  assert(addenda.includes("Dastak's append-only ledger remains the sole balance authority"));
  assert(addenda.includes("Indian bank accounts and UPI VPAs"));
  assert(addenda.includes("no live payout is authorized"));
  assert(executionState.includes("RazorpayX-backed bank/UPI withdrawals"));
});

Deno.test("RazorpayX payout webhook deployment skips JWT only because raw HMAC is mandatory", () => {
  const section = config.slice(
    config.indexOf("[functions.razorpayx-payout-webhook]"),
    config.indexOf("[functions.earnings]"),
  );
  assert(section.includes("enabled = true"));
  assert(section.includes("verify_jwt = false"));
  assert(section.includes('entrypoint = "./functions/razorpayx-payout-webhook/index.ts"'));
  assert(webhook.includes("request.text()"));
  assert(webhook.includes("x-razorpay-signature"));
  assert(webhook.includes("x-razorpay-event-id"));
  assert(webhook.includes("crypto.subtle.sign"));
  assert(webhookIndex.includes('Deno.env.get("RAZORPAYX_WEBHOOK_SECRET")'));
  assert(webhookIndex.includes("provider_configuration_missing"));
});

Deno.test("provider credentials stay server-only and live mode requires fixed-egress allowlisting", () => {
  for (
    const secret of [
      "RAZORPAYX_KEY_ID",
      "RAZORPAYX_KEY_SECRET",
      "RAZORPAYX_ACCOUNT_NUMBER",
      "RAZORPAYX_DESTINATION_FINGERPRINT_SECRET",
      "RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED",
    ]
  ) assert(earningsIndex.includes(secret), `${secret} is not wired server-side`);
  assert(adapter.includes("RazorpayX live egress IP allowlisting must be confirmed"));
  assert(!royaltyWeb.includes("RAZORPAYX_"));
  assert(!royaltyWeb.includes("RazorpayX"));
});

Deno.test("Contact, Fund Account, and Payout stay behind one provider adapter", () => {
  assert(adapter.includes('this.request("/contacts"'));
  assert(adapter.includes('this.request("/fund_accounts"'));
  assert(adapter.includes('this.request("/payouts"'));
  assert(adapter.includes('"X-Payout-Idempotency": input.idempotencyKey'));
  assert(adapter.includes("input.idempotencyKey !== input.withdrawalId"));
  assert(orchestration.includes("dastak_v1_claim_razorpayx_withdrawal"));
  assert(orchestration.includes("dastak_v1_apply_razorpayx_payout_status"));
});

Deno.test("one external payout identity and immutable destination snapshot are structural", () => {
  assert(migration.includes("withdrawal_id uuid primary key"));
  assert(migration.includes("payout_idempotency_key = withdrawal_id::text"));
  assert(migration.includes("royalty_withdrawal_attempts_one_razorpayx_uidx"));
  assert(migration.includes("destination_snapshot ->> 'providerDestinationReference'"));
  assert(migration.includes("rawBankOrVpaStored', false"));
  assert(migration.includes("RazorpayX payout identity cannot change"));
});

Deno.test("provider failure and reversal restore Royalty append-only and exactly once", () => {
  assert(migration.includes("RAZORPAYX_SUBMISSION_RELEASE"));
  assert(migration.includes("RAZORPAYX_REVERSAL:"));
  assert(migration.includes("mark_razorpayx_reconciliation_required"));
  assert(migration.includes("RoyaltyRemainsReserved"));
  assert(migration.includes("originalPaidEntryPreserved', true"));
  assert(migration.includes("on conflict (event_key) do nothing"));
  assert(migration.includes("duplicate can arrive while the first transaction"));
  assert(!migration.includes("wallet_balance"));
});

Deno.test("Merchant/Rider UI remains provider-neutral while Admin receives reconciliation detail", () => {
  assert(royaltyWeb.includes("Indian bank account"));
  assert(royaltyWeb.includes("UPI ID"));
  assert(royaltyWeb.includes("Paid appears only after provider confirmation"));
  assert(adminWeb.includes("Provider reference"));
  assert(adminWeb.includes("Webhook / reconciliation events"));
  assert(adminWeb.includes("destinationSnapshot.displayLabel"));
});

Deno.test("true RazorpayX concurrency coverage remains in the release workflow", () => {
  assert(workflow.includes("scripts/test-v1-razorpayx-payout-concurrency.sh"));
});

async function read(path: string) {
  return await Deno.readTextFile(new URL(path, import.meta.url));
}
