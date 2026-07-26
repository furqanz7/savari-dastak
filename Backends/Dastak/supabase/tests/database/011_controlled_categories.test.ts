import { assert, assertExists, assertMatch } from "jsr:@std/assert";

Deno.test("controlled categories fail closed behind private server contracts", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  let migrationName: string | undefined;
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_controlled_category_enforcement.sql")) {
      migrationName = entry.name;
    }
  }

  assertExists(migrationName);
  const migration = await Deno.readTextFile(
    new URL(`../../migrations/${migrationName}`, import.meta.url),
  );
  const normalized = migration.replace(/\s+/g, " ");
  const signatures = normalized.replace(/\(\s+/g, "(").replace(/\s+\)/g, ")");

  for (
    const table of [
      "controlled_category_policies",
      "controlled_store_compliance",
      "adult_attestations",
      "restricted_exclusion_zones",
      "prescription_evidence",
      "restricted_handoff_events",
      "restricted_return_confirmations",
    ]
  ) {
    assertMatch(normalized, new RegExp(`create table private\\.${table}`, "i"));
    assertMatch(
      normalized,
      new RegExp(`alter table private\\.${table} enable row level security`, "i"),
    );
    assertMatch(
      normalized,
      new RegExp(`revoke all on table private\\.${table} from public, anon, authenticated`, "i"),
    );
  }

  for (
    const signature of [
      "upsert_controlled_category_policy(uuid, text, jsonb, boolean, text, text)",
      "record_adult_attestation(uuid, text, boolean, boolean, text, text)",
      "submit_controlled_store_compliance(uuid, text, text, text, text)",
      "review_controlled_store_compliance(uuid, uuid, text, timestamp with time zone, text, text, text)",
      "submit_controlled_product(uuid, uuid, text, text, text)",
      "review_controlled_product(uuid, uuid, text, text, text, text)",
      "upsert_restricted_exclusion_zone(uuid, uuid, text, text, double precision, double precision, integer, boolean, text, text)",
      "browse_controlled_catalogue(uuid, text, double precision, double precision)",
      "quote_controlled_merchant_order(uuid, text, uuid, jsonb, double precision, double precision, text, text, text)",
      "create_controlled_merchant_order(uuid, uuid, text, text)",
      "get_controlled_order_snapshot(uuid, uuid)",
      "get_order_prescription_evidence_path(uuid, uuid)",
      "get_delivery_assignment_controlled_scope(uuid, uuid)",
      "verify_restricted_handoff(uuid, uuid, text, text, text, text, text)",
      "confirm_restricted_return(uuid, uuid, text, text, text)",
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

  assertMatch(normalized, /requires_prescription boolean not null default false/i);
  assertMatch(normalized, /restricted_tobacco_kind text/i);
  assertMatch(normalized, /adult_attestation_required/i);
  assertMatch(normalized, /prescription_required/i);
  assertMatch(normalized, /restricted_location_prohibited/i);
  assertMatch(normalized, /restricted_product_unavailable/i);
  assertMatch(normalized, /returning_to_merchant/i);
  assertMatch(normalized, /restricted_handoff_required/i);
  assert(!/security definer/i.test(normalized), "controlled-category functions must be invokers");
});
