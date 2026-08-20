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

Deno.test("Dastak V1 Wave 1 implements the locked matching contract", async () => {
  const migration = await readMigration("_dastak_v1_wave_1.sql");
  const normalized = migration.replace(/\s+/g, " ");

  for (
    const table of [
      "branch_operational_states",
      "matching_attempts",
      "matching_candidate_evaluations",
      "merchant_opportunities",
      "merchant_opportunity_lines",
      "fulfilments",
      "fulfilment_lines",
      "inventory_holds",
      "retail_capacity_slots",
    ]
  ) {
    assertMatch(
      normalized,
      new RegExp(`create table dastak_v1\\.${table} \\(`, "i"),
    );
  }

  assertMatch(normalized, /matching\.wave1_timeout_seconds/i);
  assertMatch(normalized, /v_timeout_seconds is distinct from 180/i);
  assertMatch(normalized, /matching\.retail_radius_meters/i);
  assertMatch(normalized, /retail\.prep_time_options_minutes/i);
  assertMatch(normalized, /requires_explicit_value[\s\S]*?true/i);

  const configuration = functionBlock(
    migration,
    "dastak_v1_api\\.wave1_branch_configuration",
  );
  assertMatch(configuration, /SYSTEM_CONFIGURATION_ERROR/i);
  assertMatch(configuration, /matching\.retail_radius_meters/i);
  assertMatch(configuration, /retail\.prep_time_options_minutes/i);
  assertMatch(configuration, /validate_setting_value/i);
  assertMatch(configuration, /is_valid_positive_integer_options/i);

  const merchantAuthorization = functionBlock(
    migration,
    "dastak_v1_api\\.actor_has_merchant_permission",
  );
  assertNotMatch(merchantAuthorization, /is_active_owner/i);
  assertMatch(merchantAuthorization, /dastak_v1\.merchant_users/i);
  assertMatch(merchantAuthorization, /dastak_v1\.merchant_permission_grants/i);
  assertMatch(merchantAuthorization, /dastak_v1\.merchant_branches/i);
  assertMatch(merchantAuthorization, /bundle_permission\.permission_key/i);

  const evaluator = functionBlock(
    migration,
    "dastak_v1_api\\.evaluate_wave1_candidate",
  );
  for (
    const rule of [
      "ORGANIZATION_NOT_ACTIVE",
      "BRANCH_NOT_ACTIVE",
      "BRANCH_CLOSED",
      "NOT_ACCEPTING_ORDERS",
      "SERVICE_ZONE_UNAVAILABLE",
      "OUTSIDE_RETAIL_RADIUS",
      "AT_CAPACITY",
      "INCOMPLETE_CATALOGUE_COVERAGE",
    ]
  ) {
    assertMatch(evaluator, new RegExp(rule));
  }
  assertMatch(evaluator, /selection\.state = 'SELECTED'/i);
  assertNotMatch(
    evaluator,
    /stock_on_hand|available_quantity|inventory_count/i,
  );

  const starter = functionBlock(migration, "dastak_v1_api\\.start_wave1");
  assertMatch(starter, /insert into dastak_v1\.matching_attempts/i);
  assertMatch(starter, /insert into dastak_v1\.merchant_opportunities/i);
  assertMatch(starter, /insert into dastak_v1\.merchant_opportunity_lines/i);
  assertMatch(starter, /MERCHANT_OPPORTUNITY_OFFERED/i);
  assertMatch(starter, /domain_events_outbox/i);
  assertNotMatch(starter, /http|fetch|net\.|webhook/i);
  assert(
    starter.indexOf("wave1_branch_configuration") <
      starter.indexOf("insert into dastak_v1.matching_attempts"),
    "required Wave 1 configuration must be validated before opening an attempt",
  );

  const accept = functionBlock(
    migration,
    "dastak_v1_api\\.accept_wave1_opportunity",
  );
  assertMatch(accept, /v_command constant text := 'acceptWave1Opportunity'/i);
  assertMatch(accept, /from dastak_v1\.orders[\s\S]*?for update/i);
  assertMatch(accept, /from dastak_v1\.matching_attempts[\s\S]*?for update/i);
  assertMatch(
    accept,
    /from dastak_v1\.merchant_opportunities[\s\S]*?for update/i,
  );
  assertMatch(accept, /from dastak_v1\.merchant_branches[\s\S]*?for update/i);
  assertMatch(accept, /status = 'SELECTED'/i);
  assertMatch(accept, /status = 'LOST'/i);
  assertMatch(accept, /physicalStockConfirmed', true/i);
  assertMatch(accept, /insert into dastak_v1\.inventory_holds/i);
  assertMatch(accept, /insert into dastak_v1\.retail_capacity_slots/i);
  assertMatch(accept, /insert into dastak_v1\.retail_line_allocations/i);
  assertMatch(accept, /'RESERVED_PREPAYMENT'/i);
  assertNotMatch(
    accept,
    /update dastak_v1\.orders|insert into dastak_v1\.(?:payment_intents|payment_attempts)|set\s+(?:status\s*=\s*'(?:FULLY_SECURED|AWAITING_PAYMENT)'|payment_expires_at\s*=)/i,
  );

  const cancel = functionBlock(
    migration,
    "dastak_v1_api\\.cancel_prepayment_order",
  );
  assertMatch(cancel, /release_order_prepayment_resources/i);
  assertMatch(cancel, /CUSTOMER_CANCELLED_PREPAYMENT/i);
  assertMatch(cancel, /status = 'CANCELLED_PREPAYMENT'/i);

  const release = functionBlock(
    migration,
    "dastak_v1_api\\.release_order_prepayment_resources",
  );
  assertMatch(release, /inventory_holds[\s\S]*?status = 'RELEASED'/i);
  assertMatch(release, /retail_capacity_slots[\s\S]*?status = 'RELEASED'/i);
  assertMatch(release, /retail_line_allocations[\s\S]*?status = 'RELEASED'/i);
  assertMatch(release, /fulfilments[\s\S]*?status = 'RELEASED'/i);

  const expiry = functionBlock(
    migration,
    "dastak_v1_api\\.expire_wave1_attempt",
  );
  assertMatch(expiry, /v_attempt\.status <> 'OPEN'/i);
  assertMatch(expiry, /v_now < v_attempt\.expires_at/i);
  assertMatch(expiry, /'WAVE_2',[\s\S]*?'OPEN'/i);
  assertMatch(expiry, /WAVE_1_EXPIRED/i);
  assertMatch(expiry, /WAVE_2_STARTED/i);

  const customerSerializer = functionBlock(
    migration,
    "dastak_v1_api\\.order_json",
  );
  assertNotMatch(
    customerSerializer,
    /organizationId|branchId|merchantId|merchantName|Wave 1|Wave 2/i,
  );
  assertMatch(customerSerializer, /FINDING_ITEMS/i);
  assertNotMatch(customerSerializer, /ITEMS_RESERVED/i);

  assertNotMatch(migration, /REACHABILITY_NOT_CONFIGURED/i);
  assertNotMatch(migration, /PREP_OPTIONS_NOT_CONFIGURED/i);
  assertNotMatch(migration, /is_active_owner/i);

  assertNotMatch(
    migration,
    /create table[^;]*(?:stock_on_hand|inventory_count|merchant_inventory)/i,
  );
  assertNotMatch(migration, /\b(?:fetch|http_post|net\.http_post)\s*\(/i);

  const publicOperations = [...migration.matchAll(
    /create function public\.(dastak_v1_[a-z0-9_]+)\s*\(/gi,
  )].map((match) => match[1]).sort();
  assertEquals(publicOperations, [
    "dastak_v1_accept_wave1_opportunity",
    "dastak_v1_decline_opportunity",
    "dastak_v1_get_merchant_opportunity",
    "dastak_v1_list_merchant_opportunities",
    "dastak_v1_set_branch_operational_state",
  ]);

  for (const operation of publicOperations) {
    const block = functionBlock(migration, `public\\.${operation}`);
    assertMatch(block, /security invoker/i);
    assertMatch(block, /set search_path = ''/i);
    assertNotMatch(block, /security definer/i);
  }

  for (
    const block of migration.matchAll(
      /create (?:or replace )?function[\s\S]*?\$\$;/gi,
    )
  ) {
    if (/security definer/i.test(block[0])) {
      assertMatch(block[0], /set search_path = ''/i);
    }
  }
});
