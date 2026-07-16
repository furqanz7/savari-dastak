import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("courier dispatch stays private, nearest-first, and server-timed", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (
      entry.isFile && entry.name.endsWith("_courier_dispatch_assignment.sql")
    ) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one courier dispatch migration");
  const migrationName = migrations[0];
  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");
  const signatures = normalized
    .replace(/\(\s+/g, "(")
    .replace(/\s+\)/g, ")");

  assertMatch(
    normalized,
    /create table private\.delivery_assignment_attempts/i,
  );
  assertMatch(
    signatures,
    /alter table private\.delivery_assignment_attempts enable row level security/i,
  );
  assertMatch(
    normalized,
    /revoke all on table private\.delivery_assignment_attempts from public, anon, authenticated/i,
  );

  for (
    const signature of [
      "get_delivery_partner_dispatch_snapshot(uuid)",
      "accept_delivery_assignment(uuid, uuid, text, text)",
      "decline_delivery_assignment(uuid, uuid, text, text, text)",
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
      new RegExp(
        `grant execute on function public\\.${escaped} to service_role`,
        "i",
      ),
    );
  }

  assertMatch(normalized, /interval '60 seconds'/i);
  assertMatch(normalized, /operator\(extensions\.<->\)/i);
  assertMatch(normalized, /extensions\.st_distance/i);
  assertMatch(normalized, /where status = 'offered'/i);
  assertMatch(normalized, /where status in \('offered', 'accepted'\)/i);
  assertMatch(
    normalized,
    /not exists \( select 1 from private\.delivery_assignment_attempts/i,
  );
  assertMatch(normalized, /create extension if not exists pg_cron/i);
  assertMatch(normalized, /cron\.schedule\(/i);
  assertMatch(normalized, /'10 seconds'/i);
  assertMatch(normalized, /delivery_assignment_offered/i);
  assertMatch(normalized, /delivery_assignment_accepted/i);
  assertMatch(normalized, /delivery_assignment_declined/i);
  assertMatch(normalized, /delivery_assignment_expired/i);
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
  assert(
    !/security definer/i.test(normalized),
    "dispatch must not introduce definer functions",
  );
});

Deno.test("courier dispatch serializes idempotency by account and function", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260716182140_fix_courier_dispatch_idempotency_lock.sql",
      import.meta.url,
    ),
  );
  const normalized = migration.replace(/\s+/g, " ");

  assertMatch(
    normalized,
    /alter function public\.accept_delivery_assignment\(uuid, uuid, text, text\) set schema private/i,
  );
  assertMatch(
    normalized,
    /alter function public\.decline_delivery_assignment\(uuid, uuid, text, text, text\) set schema private/i,
  );
  assertMatch(
    normalized,
    /hashtextextended\(\s*p_account_id::text \|\| ':' \|\| v_function_name, 0\s*\)/i,
  );
  assert(
    !/security definer/i.test(normalized),
    "idempotency wrappers must stay invoker-only",
  );
});

Deno.test("courier lifecycle is partner-owned and server-sequenced", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260716200000_courier_job_lifecycle.sql",
      import.meta.url,
    ),
  );
  const normalized = migration.replace(/\s+/g, " ");

  assertMatch(
    normalized,
    /'assigned'.*'en_route_to_pickup'.*'at_store'.*'picked_up'.*'in_transit'.*'delivered'/i,
  );
  assertMatch(
    normalized,
    /create function public\.advance_delivery_assignment/i,
  );
  assertMatch(
    normalized,
    /grant execute on function public\.advance_delivery_assignment\( uuid, uuid, text, text, text \) to service_role/i,
  );
  for (
    const action of [
      "start_to_store",
      "arrive_at_store",
      "confirm_pickup",
      "start_delivery",
      "complete_delivery",
    ]
  ) assertMatch(normalized, new RegExp(action, "i"));
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
  assert(
    !/security definer/i.test(normalized),
    "courier lifecycle must stay invoker-only",
  );
});
