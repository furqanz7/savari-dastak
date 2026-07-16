import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("merchant checkout stays private, server-priced, and transition-owned", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_merchant_order_checkout.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one merchant_order_checkout migration");
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
      "merchant_order_rate_cards",
      "merchant_order_quotes",
      "merchant_order_quote_lines",
      "merchant_orders",
      "merchant_order_lines",
      "merchant_order_refund_decisions",
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
      "upsert_merchant_order_rate_card(uuid, uuid, integer, boolean, text, text)",
      "quote_merchant_order(uuid, uuid, jsonb, double precision, double precision, text, text)",
      "create_merchant_order(uuid, uuid, text, text)",
      "confirm_merchant_order_payment(uuid, text, bigint, text, text)",
      "merchant_accept_order(uuid, uuid, text, text)",
      "merchant_reject_order(uuid, uuid, text, text, text)",
      "merchant_mark_order_ready(uuid, uuid, text, text)",
      "customer_cancel_order(uuid, uuid, text, text, text)",
      "get_customer_orders(uuid)",
      "get_merchant_orders(uuid)",
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

  assertMatch(normalized, /item_subtotal_paise bigint not null/i);
  assertMatch(normalized, /delivery_fee_paise integer not null/i);
  assertMatch(normalized, /total_paise bigint not null/i);
  assertMatch(normalized, /expires_at timestamptz not null/i);
  assertMatch(normalized, /interval '5 minutes'/i);
  assertMatch(normalized, /product\.catalogue_kind = 'general'/i);
  assertMatch(normalized, /product\.availability = 'in_stock'/i);
  assertMatch(normalized, /payment_amount_mismatch/i);
  assertMatch(normalized, /owner_review_required/i);
  assertMatch(normalized, /merchant_fault_full_refund/i);
  assertMatch(normalized, /merchant_order_created/i);
  assertMatch(normalized, /merchant_order_payment_confirmed/i);
  assertMatch(normalized, /merchant_order_ready/i);
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
});
