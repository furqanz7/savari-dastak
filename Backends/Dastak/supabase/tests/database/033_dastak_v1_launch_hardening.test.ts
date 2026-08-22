import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260823023000_dastak_v1_launch_hardening.sql",
    import.meta.url,
  ),
);
const config = await Deno.readTextFile(
  new URL("../../config.toml", import.meta.url),
);
const workerIndex = await Deno.readTextFile(
  new URL("../../functions/process-v1-outbox/index.ts", import.meta.url),
);

function functionBlock(name: string): string {
  const block = migration.match(
    new RegExp(
      `create (?:or replace )?function ${name}\\s*\\([\\s\\S]*?\\$\\$;`,
      "i",
    ),
  )?.[0];
  assert(block, `missing function ${name}`);
  return block;
}

Deno.test("Step 6 hardening uses explicit RBAC and durable asynchronous delivery", () => {
  const platformAuthorization = functionBlock(
    "dastak_v1_api\\.actor_has_platform_permission",
  );
  assertNotMatch(platformAuthorization, /is_active_owner/i);
  assertMatch(platformAuthorization, /platform_permission_grants/i);
  assertMatch(platformAuthorization, /permission_bundle_permissions/i);

  const fanout = functionBlock("dastak_v1_api\\.fanout_pending_outbox_events");
  assertMatch(fanout, /for update skip locked/i);
  assertMatch(fanout, /notification_intents/i);
  assertMatch(fanout, /status = 'PUBLISHED'/i);

  const claim = functionBlock("dastak_v1_api\\.claim_notification_deliveries");
  assertMatch(claim, /for update of delivery skip locked/i);
  assertMatch(claim, /stale worker claim recovered/i);

  const complete = functionBlock(
    "dastak_v1_api\\.complete_notification_delivery",
  );
  assertMatch(complete, /delivery retry limit reached/i);
  assertMatch(complete, /disabled_at/i);
  assertNotMatch(complete, /delete from public\.dastak_device_tokens/i);

  const monitor = functionBlock("dastak_v1_api\\.run_invariant_monitors");
  for (
    const invariant of [
      "ORDER_MULTIPLE_ACTIVE_MISSIONS",
      "RIDER_MULTIPLE_ACTIVE_MISSIONS",
      "RETAIL_LINE_MULTIPLE_FINAL_MERCHANTS",
      "RETAIL_HARD_CAPACITY_EXCEEDED",
      "PICKED_UP_FULFILMENT_PACKAGE_MISMATCH",
      "DELIVERED_WITHOUT_FINAL_VERIFICATION",
      "PAID_WITHOUT_SUCCESSFUL_PAYMENT",
      "PAYMENT_EXPIRED_AFTER_PREPARATION",
      "CONTRADICTORY_PACKAGE_CUSTODY",
    ]
  ) assert(monitor.includes(invariant), `missing monitor ${invariant}`);

  assertMatch(migration, /entityType', 'dastakV1Order'/i);
  assertNotMatch(
    functionBlock("dastak_v1_api\\.fanout_pending_outbox_events"),
    /display_name|address_snapshot/i,
  );
  assertNotMatch(migration, /https:\/\/zmtsolkfxlrxepshnjdf\.supabase\.co/i);

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

Deno.test("V1 outbox deployment and schedule share the internal-secret contract", () => {
  const workerConfig = config.match(
    /\[functions\.process-v1-outbox\][\s\S]*?(?=\n\[|$)/,
  )?.[0];
  assert(workerConfig, "missing process-v1-outbox function configuration");
  assertMatch(workerConfig, /\benabled\s*=\s*true\b/);
  assertMatch(workerConfig, /\bverify_jwt\s*=\s*false\b/);
  assertMatch(
    workerConfig,
    /\bimport_map\s*=\s*"\.\/functions\/deno\.json"/,
  );
  assertMatch(
    workerConfig,
    /\bentrypoint\s*=\s*"\.\/functions\/process-v1-outbox\/index\.ts"/,
  );

  assertMatch(
    workerIndex,
    /expectedSecret:\s*requiredEnv\("DASTAK_NOTIFICATION_SECRET"\)/,
  );
  assertMatch(migration, /\/functions\/v1\/process-v1-outbox/i);
  assertMatch(migration, /'x-dastak-internal-secret'/i);
  assertMatch(migration, /secret\.name\s*=\s*'dastak_notification_secret'/i);
});
