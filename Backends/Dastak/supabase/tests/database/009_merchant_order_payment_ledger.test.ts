import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("merchant-order payments use a private balanced immutable ledger", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_merchant_order_payment_ledger.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one merchant-order payment-ledger migration");
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");
  const signatures = normalized
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")");

  for (
    const table of [
      "merchant_order_payment_records",
      "merchant_order_provider_events",
      "merchant_order_ledger_transactions",
      "merchant_order_ledger_entries",
    ]
  ) {
    assertMatch(normalized, new RegExp(`create table private\\.${table}`, "i"));
    assertMatch(
      signatures,
      new RegExp(`alter table private\\.${table} enable row level security`, "i"),
    );
    assertMatch(
      normalized,
      new RegExp(`revoke all on table private\\.${table} from public, anon, authenticated`, "i"),
    );
  }

  for (
    const signature of [
      "upsert_merchant_order_financial_rate_card(uuid, uuid, integer, integer, integer, boolean, text, text)",
      "get_owner_merchant_order_financial_snapshot(uuid, uuid)",
      "record_merchant_order_payment_event(uuid, text, text, text, text, text, bigint, timestamp with time zone, text)",
    ]
  ) {
    const escaped = signature.replace(/[()]/g, "\\$&");
    assertMatch(
      signatures,
      new RegExp(
        `revoke execute on function public\\.${escaped} from public, anon, authenticated`,
        "i",
      ),
    );
    assertMatch(
      signatures,
      new RegExp(`grant execute on function public\\.${escaped} to service_role`, "i"),
    );
  }

  assertMatch(normalized, /merchant_commission_bps/i);
  assertMatch(normalized, /courier_payout_paise/i);
  assertMatch(normalized, /platform_delivery_margin_paise/i);
  assertMatch(normalized, /payment_capture/i);
  assertMatch(normalized, /refund_reserve/i);
  assertMatch(normalized, /refund_complete/i);
  assertMatch(normalized, /order_settlement/i);
  assertMatch(normalized, /provider_clearing/i);
  assertMatch(normalized, /customer_funds_held/i);
  assertMatch(normalized, /merchant_payable/i);
  assertMatch(normalized, /courier_payable/i);
  assertMatch(normalized, /merchant_order_ledger_immutable/i);
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
  assert(
    !/security definer/i.test(normalized),
    "payment foundation must not introduce definer functions",
  );
});
