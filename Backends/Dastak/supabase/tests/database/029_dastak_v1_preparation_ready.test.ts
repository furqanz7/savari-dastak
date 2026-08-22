import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migrationsDirectory = new URL("../../migrations/", import.meta.url);

async function migration(): Promise<string> {
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_dastak_v1_preparation_ready_packages.sql")) {
      return await Deno.readTextFile(new URL(`../../migrations/${entry.name}`, import.meta.url));
    }
  }
  throw new Error("Missing Step 3 migration");
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

Deno.test("Dastak V1 Step 3 preserves preparation, Ready, package, and evidence invariants", async () => {
  const sql = await migration();
  const normalized = sql.replace(/\s+/g, " ");
  for (const table of ["packages", "fulfilment_evidence", "fulfilment_problem_reports"]) {
    assertMatch(normalized, new RegExp(`create table dastak_v1\\.${table} \\(`, "i"));
    assertMatch(
      normalized,
      new RegExp(`alter table dastak_v1\\.${table} enable row level security`, "i"),
    );
  }
  assertMatch(normalized, /estimated_ready_at timestamptz/i);
  assertMatch(normalized, /actual_ready_at timestamptz/i);
  assertMatch(normalized, /package_count integer/i);
  assertMatch(normalized, /ready_at is not distinct from actual_ready_at/i);
  assertMatch(normalized, /merchant-ready/i);
  assertNotMatch(normalized, /for update to authenticated[\s\S]{0,300}merchant-ready/i);
  assertNotMatch(normalized, /for delete to authenticated[\s\S]{0,300}merchant-ready/i);

  const payment = functionBlock(sql, "dastak_v1\\.start_preparation_after_payment_event");
  assertMatch(payment, /new\.outcome <> 'SUCCEEDED'/i);
  assertMatch(payment, /status = 'PREPARING'/i);
  assertMatch(payment, /prep_started_at = v_now/i);
  assertMatch(payment, /estimated_ready_at = v_now \+ pg_catalog\.make_interval/i);
  assertMatch(payment, /and fulfilment\.status = 'RESERVED_PREPAYMENT'/i);
  assertMatch(payment, /'PREPARATION_STARTED'/i);

  const guard = functionBlock(sql, "dastak_v1\\.guard_fulfilment");
  assertMatch(guard, /preparation start cannot be reset/i);
  assertMatch(guard, /promised preparation time cannot be extended after payment/i);
  assertMatch(guard, /actual Ready timestamp cannot change/i);
  assertMatch(guard, /old\.status = 'PREPARING' and new\.status = 'READY'/i);
  assertNotMatch(guard, /old\.status = 'READY' and new\.status = 'PREPARING'/i);

  const ready = functionBlock(sql, "dastak_v1_api\\.mark_fulfilment_ready");
  assertMatch(ready, /actor_has_wave1_merchant_permission/i);
  assertMatch(ready, /stale fulfilment version/i);
  assertMatch(ready, /payment\.status = 'SUCCEEDED'/i);
  assertMatch(ready, /declare package count before marking Ready/i);
  assertMatch(ready, /MERCHANT_READY_PHOTO/i);
  assertMatch(ready, /set status = 'READY'/i);
  assertMatch(ready, /actual_ready_at = v_now/i);
  assertMatch(ready, /release_reason = 'FULFILMENT_READY'/i);
  assertMatch(ready, /v_released_capacity <> 1/i);
  assertMatch(ready, /FULFILMENT_READY/i);

  const eligibility = functionBlock(sql, "dastak_v1_api\\.order_rider_match_eligibility");
  assertMatch(eligibility, /bool_and\(required\.satisfied\)/i);
  assertMatch(eligibility, /thresholdSeconds', 300/i);
  assertMatch(
    normalized,
    /p_estimated_ready_at <= p_evaluated_at \+ pg_catalog\.make_interval\(secs => 300\)/i,
  );

  for (const block of sql.matchAll(/create (?:or replace )?function[\s\S]*?\$\$;/gi)) {
    if (/security definer/i.test(block[0])) assertMatch(block[0], /set search_path = ''/i);
  }
  for (
    const name of [
      "dastak_v1_merchant_fulfilments",
      "dastak_v1_declare_fulfilment_packages",
      "dastak_v1_add_fulfilment_ready_evidence",
      "dastak_v1_mark_fulfilment_ready",
      "dastak_v1_report_fulfilment_problem",
    ]
  ) {
    const wrapper = functionBlock(sql, `public\\.${name}`);
    assertMatch(wrapper, /security invoker/i);
    assertNotMatch(wrapper, /security definer/i);
  }
  assertNotMatch(normalized, /create function public\.[^(]*(?:extend|update)_prep/i);
});
