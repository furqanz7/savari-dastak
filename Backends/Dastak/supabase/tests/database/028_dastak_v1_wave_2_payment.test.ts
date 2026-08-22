import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

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

function functionBlock(sql: string, name: string): string {
  const block = sql.match(
    new RegExp(
      `create (?:or replace )?function ${name}\\s*\\([\\s\\S]*?\\$\\$;`,
      "i",
    ),
  )?.[0];
  assert(block, `missing function ${name}`);
  return block;
}

Deno.test("Dastak V1 Step 2 preserves matching, security, and payment contracts", async () => {
  const [types, runtime] = await Promise.all([
    readMigration("_dastak_v1_wave_2_fully_secured_payment.sql"),
    readMigration("_dastak_v1_wave_2_runtime_and_payments.sql"),
  ]);
  const combined = `${types}\n${runtime}`;
  const normalized = combined.replace(/\s+/g, " ");

  for (
    const table of [
      "wave2_provisional_holds",
      "fulfilment_plans",
      "fulfilment_plan_merchants",
      "fulfilment_plan_lines",
      "payments",
      "payment_attempts",
      "payment_provider_events",
      "payment_reconciliation_cases",
    ]
  ) {
    assertMatch(normalized, new RegExp(`create table dastak_v1\\.${table} \\(`, "i"));
  }

  assertMatch(
    normalized,
    /merchant_count integer not null check \(merchant_count between 1 and 3\)/i,
  );
  assertMatch(normalized, /matching\.wave2_timeout_seconds/i);
  assertMatch(normalized, /matching\.wave2_hold_seconds/i);
  assertMatch(normalized, /payment\.reservation_seconds/i);
  assertMatch(normalized, /matching\.wave2_max_pickup_route_meters/i);
  assertMatch(normalized, /delivery\.transport_load_profiles/i);

  const configuration = functionBlock(
    runtime,
    "dastak_v1_api\\.wave2_global_configuration",
  );
  assertMatch(configuration, /SYSTEM_CONFIGURATION_ERROR/i);
  assertMatch(normalized, /requires_explicit_value/i);
  assertNotMatch(configuration, /UNAVAILABLE|PRODUCT_UNAVAILABLE/i);

  const starter = functionBlock(runtime, "dastak_v1_api\\.start_wave2");
  assertMatch(starter, /v_wave1\.status <> 'EXPIRED'/i);
  assertMatch(starter, /evaluate_wave2_candidate/i);
  assertMatch(starter, /merchant_opportunity_lines/i);
  assertMatch(starter, /selection\.state = 'SELECTED'/i);
  assertMatch(starter, /requested_quantity/i);

  const accept = functionBlock(runtime, "dastak_v1_api\\.accept_wave2_opportunity");
  assertMatch(accept, /from dastak_v1\.orders[\s\S]*?for update/i);
  assertMatch(accept, /from dastak_v1\.matching_attempts[\s\S]*?for update/i);
  assertMatch(accept, /from dastak_v1\.merchant_opportunities[\s\S]*?for update/i);
  assertMatch(accept, /from dastak_v1\.merchant_branches[\s\S]*?for update/i);
  assertMatch(accept, /status = 'PROVISIONALLY_ACCEPTED'/i);
  assertMatch(accept, /insert into dastak_v1\.wave2_provisional_holds/i);
  assertMatch(accept, /opportunity_line\.requested_quantity/i);
  assertMatch(accept, /'capacityConsumed', false/i);
  assertNotMatch(accept, /insert into dastak_v1\.retail_capacity_slots/i);

  const plans = functionBlock(runtime, "dastak_v1_api\\.record_wave2_candidate_plans");
  assertMatch(plans, /combination\.merchant_count < 3/i);
  assertMatch(plans, /plan_line\.allocated_quantity|order_line\.quantity/i);
  assertMatch(plans, /'advertisingInfluence', false/i);
  assertNotMatch(plans, /sponsor|promotion/i);

  const finalLock = functionBlock(runtime, "dastak_v1_api\\.lock_best_wave2_plan");
  assertMatch(
    finalLock,
    /order by\s+plan\.merchant_count,\s+plan\.route_distance_meters,\s+plan\.reliability_score_bps desc/i,
  );
  assertMatch(finalLock, /BRANCH_CAPACITY_LOST/i);
  assertMatch(finalLock, /TRANSPORT_LOAD_INFEASIBLE/i);
  assertMatch(finalLock, /PICKUP_ROUTE_INFEASIBLE/i);
  assertMatch(finalLock, /insert into dastak_v1\.retail_capacity_slots/i);
  assertMatch(finalLock, /status = 'SELECTED'/i);
  assertMatch(finalLock, /status = 'RELEASED'/i);
  assertMatch(finalLock, /coordinate_fully_secured/i);

  const coordinator = functionBlock(
    runtime,
    "dastak_v1_api\\.coordinate_fully_secured",
  );
  assertMatch(coordinator, /retail_security_snapshot/i);
  assertMatch(coordinator, /food_security_snapshot/i);
  assertMatch(coordinator, /'FULLY_SECURED'/i);
  assertMatch(coordinator, /insert into dastak_v1\.payments/i);
  assertMatch(coordinator, /'AWAITING_PAYMENT'/i);
  assertMatch(coordinator, /paymentReservationSeconds/i);

  const expiry = functionBlock(
    runtime,
    "dastak_v1_api\\.expire_payment_reservation",
  );
  assertMatch(expiry, /from dastak_v1\.orders[\s\S]*?for update/i);
  assertMatch(expiry, /from dastak_v1\.payments[\s\S]*?for update/i);
  assertMatch(expiry, /release_order_prepayment_resources/i);
  assertMatch(expiry, /'PAYMENT_EXPIRED'/i);

  const webhook = functionBlock(
    runtime,
    "dastak_v1_api\\.record_razorpay_payment_event",
  );
  assertMatch(webhook, /dastak-v1-razorpay-event:/i);
  assertMatch(webhook, /pg_advisory_xact_lock/i);
  assertMatch(webhook, /v_now >= v_payment\.expires_at/i);
  assertMatch(webhook, /payment_reconciliation_cases/i);
  assertMatch(webhook, /LATE_SUCCESS_AFTER_PAYMENT_EXPIRED/i);
  assertMatch(webhook, /status = 'PAID'/i);

  const customer = functionBlock(runtime, "dastak_v1_api\\.order_json");
  assertMatch(customer, /'FINDING_ITEMS'/i);
  assertMatch(customer, /'PAYMENT_READY'/i);
  assertMatch(customer, /'ORDER_SECURED'/i);
  assertNotMatch(customer, /organizationId|branchId|merchantName|Wave 1|Wave 2/i);

  for (const block of combined.matchAll(/create (?:or replace )?function[\s\S]*?\$\$;/gi)) {
    if (/security definer/i.test(block[0])) {
      assertMatch(block[0], /set search_path = ''/i);
    }
  }

  for (
    const operation of [
      "dastak_v1_accept_wave2_opportunity",
      "dastak_v1_prepare_razorpay_checkout",
      "dastak_v1_record_razorpay_event",
    ]
  ) {
    const block = functionBlock(runtime, `public\\.${operation}`);
    assertMatch(block, /security invoker/i);
    assertMatch(block, /set search_path = ''/i);
    assertNotMatch(block, /security definer/i);
  }
});
