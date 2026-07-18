import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("parcel delivery is server-authoritative and private", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrations = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_parcel_delivery_foundation.sql")) {
      migrations.push(entry.name);
    }
  }

  assert(migrations.length === 1, "expected one parcel-delivery migration");
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
      "parcel_rate_cards",
      "parcel_quotes",
      "parcel_deliveries",
      "parcel_assignment_attempts",
      "parcel_payment_events",
      "parcel_partner_reliability_reviews",
      "parcel_handoff_code_keys",
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
      "upsert_parcel_rate_card(uuid, uuid, text, integer, integer, integer, boolean, text, text)",
      "quote_parcel_delivery(uuid, text, double precision, double precision, text, double precision, double precision, text, integer, integer, text, text)",
      "create_parcel_delivery(uuid, uuid, text, text, text, integer, text, text)",
      "record_parcel_payment_event(text, text, uuid, text, integer, timestamp with time zone, text)",
      "get_parcel_delivery_snapshot(uuid, uuid)",
      "get_parcel_partner_snapshot(uuid)",
      "acknowledge_parcel_assignment(uuid, uuid, text, text)",
      "decline_parcel_assignment(uuid, uuid, text, text, text)",
      "advance_parcel_delivery(uuid, uuid, text, text, text, text)",
      "cancel_parcel_delivery(uuid, uuid, text, text, text)",
      "report_parcel_safety_incident(uuid, uuid, text, text, text, text)",
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

  assertMatch(normalized, /interval '60 seconds'/i);
  assertMatch(normalized, /interval '90 seconds'/i);
  assertMatch(normalized, /interval '15 minutes'/i);
  assertMatch(normalized, /interval '24 hours'/i);
  assertMatch(normalized, /interval '30 minutes'/i);
  assertMatch(normalized, /interval '7 days'/i);
  assertMatch(normalized, /% 1000000/i);
  assertMatch(normalized, /ceil\s*\(.*route_distance_meters.*1000/im);
  assertMatch(normalized, /delivery_assignment_attempts/i);
  assertMatch(normalized, /parcel_assignment_attempts/i);
  assertMatch(normalized, /dastak-parcel-dispatch/i);
  assertMatch(normalized, /security invoker/gi);
  assertMatch(normalized, /set search_path = ''/gi);
  assert(
    !/security definer/i.test(normalized),
    "parcel foundation must not introduce definer functions",
  );
  assert(
    !/\bpickup_code\s+text\b/i.test(normalized),
    "raw pickup codes must never be stored",
  );
  assert(
    !/\bdelivery_code\s+text\b/i.test(normalized),
    "raw delivery codes must never be stored",
  );
});
