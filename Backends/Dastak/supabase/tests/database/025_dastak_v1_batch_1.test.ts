import { assert, assertEquals, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migrationsDirectory = new URL("../../migrations/", import.meta.url);

async function readMigration(suffix: string): Promise<string> {
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith(suffix)) {
      return await Deno.readTextFile(
        new URL(`../../migrations/${entry.name}`, import.meta.url),
      );
    }
  }
  throw new Error(`Missing migration ending in ${suffix}`);
}

Deno.test("Dastak V1 Batch 1 is additive, private, and command-scoped", async () => {
  const [kernel, commands, config] = await Promise.all([
    readMigration("_dastak_v1_batch_1a_kernel.sql"),
    readMigration("_dastak_v1_batch_1b_commands.sql"),
    Deno.readTextFile(new URL("../../config.toml", import.meta.url)),
  ]);
  const combined = `${kernel}\n${commands}`;
  const normalized = combined.replace(/\s+/g, " ");

  assertMatch(normalized, /create schema dastak_v1;/i);
  assertMatch(normalized, /create schema dastak_v1_api;/i);
  assertNotMatch(
    config,
    /schemas\s*=\s*\[[^\]]*(dastak_v1|dastak_v1_api)/i,
  );

  const publicOperations = [...commands.matchAll(
    /create function public\.(dastak_v1_[a-z0-9_]+)\s*\(/gi,
  )].map((match) => match[1]).sort();
  assertEquals(publicOperations, [
    "dastak_v1_cancel_prepayment_order",
    "dastak_v1_get_order",
    "dastak_v1_list_customer_orders",
    "dastak_v1_submit_order",
  ]);

  for (const operation of publicOperations) {
    const block = commands.match(
      new RegExp(
        `create function public\\.${operation}\\s*\\([\\s\\S]*?\\$\\$;`,
        "i",
      ),
    )?.[0];
    assert(block, `missing public operation block for ${operation}`);
    assertMatch(block, /security invoker/i);
    assertMatch(block, /set search_path = ''/i);
    assertNotMatch(block, /security definer/i);
  }

  for (const block of combined.matchAll(/create function[\s\S]*?\$\$;/gi)) {
    if (/security definer/i.test(block[0])) {
      assertMatch(block[0], /set search_path = ''/i);
    }
  }

  assertMatch(
    normalized,
    /alter table dastak_v1\.%I enable row level security/i,
  );
  assertMatch(
    normalized,
    /revoke all on all tables in schema dastak_v1 from public, anon, authenticated, service_role/i,
  );
  assertNotMatch(
    normalized,
    /grant\s+(?:select|insert|update|delete|all)[^;]*on\s+(?:all\s+tables\s+in\s+schema\s+)?dastak_v1[^;]*to\s+authenticated/i,
  );

  const customerSerializer = commands.match(
    /create function dastak_v1_api\.order_json[\s\S]*?\$\$;/i,
  )?.[0];
  assert(customerSerializer, "missing customer-safe order serializer");
  assertNotMatch(
    customerSerializer,
    /merchant_branch_id|branchId|merchantId|storeId/i,
  );

  assertMatch(normalized, /pg_advisory_xact_lock/i);
  assertMatch(normalized, /p_expected_version is distinct from 0/i);
  assertMatch(
    normalized,
    /v_order\.version is distinct from p_expected_version/i,
  );
  assertMatch(
    normalized,
    /primary key \(actor_id, command_name, idempotency_key\)/i,
  );
  assertMatch(normalized, /event_type, aggregate_version\)/i);
  assertMatch(normalized, /order_context_snapshots_immutable/i);
  assertMatch(normalized, /order_price_snapshots_immutable/i);
  assertMatch(normalized, /order_state_journal_immutable/i);
  assertMatch(
    normalized,
    /organization\.merchant_type = 'RESTAURANT_CAFE'/i,
  );
  assertMatch(
    normalized,
    /bundle\.scope = 'MERCHANT' and bundle\.active/i,
  );
  assertMatch(
    normalized,
    /customer cancellation is not allowed after payment/i,
  );
  assertMatch(
    normalized,
    /when 'PAID' then p_to in \('PREPARING', 'DASTAK_FULFILMENT_FAILURE'\)/i,
  );
  assertNotMatch(normalized, /when 'PAID' then[^;]*CANCELLED_PREPAYMENT/i);

  assertMatch(normalized, /'commerce\.allow_cod'.*?'false'/i);
  assertMatch(normalized, /'commerce\.allow_substitutions'.*?'false'/i);
  assertMatch(normalized, /'commerce\.allow_scheduled_orders'.*?'false'/i);
  assertMatch(normalized, /'matching\.wave1_timeout_seconds'.*?'180'/i);
  assertMatch(normalized, /'matching\.wave2_max_retail_merchants'.*?'3'/i);

  const legacyMutation =
    /\b(?:insert\s+into|update|delete\s+from|alter\s+table|drop\s+table)\s+(?:private\.)?(?:merchant_orders|merchant_order_items|parcel_deliveries|courier_jobs|merchant_stores)\b/i;
  assertNotMatch(combined, legacyMutation);
});
