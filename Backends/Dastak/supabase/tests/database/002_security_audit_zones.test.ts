import { assert, assertStringIncludes } from "jsr:@std/assert";

Deno.test("Dastak security migration keeps evidence and client business data constrained", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715140344_security_audit_zones.sql",
      import.meta.url,
    ),
  );
  const config = await Deno.readTextFile(new URL("../../config.toml", import.meta.url));
  const grantHardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260715202448_harden_service_zone_grants.sql",
      import.meta.url,
    ),
  );
  const behavioralTest = await Deno.readTextFile(
    new URL("./002_security_audit_zones.pgtap.sql", import.meta.url),
  );

  for (
    const contract of [
      "create extension if not exists postgis with schema extensions",
      "create table audit.events",
      "create table private.safety_cases",
      "create table public.service_zones",
      "alter table audit.events enable row level security",
      "alter table private.safety_cases enable row level security",
      "alter table public.service_zones enable row level security",
      "revoke all on audit.events from anon, authenticated",
      "revoke all on private.safety_cases from anon, authenticated",
      "create policy service_zones_select_active",
      "active = true",
      "create trigger audit_events_immutable",
      "audit.events is append-only",
      "insert into storage.buckets (id, name, public)",
      "'dastak-evidence', 'dastak-evidence', false",
      "'dastak-catalogue', 'dastak-catalogue', true",
      "create policy dastak_evidence_select_own",
      "create policy dastak_evidence_insert_own",
      "create policy dastak_evidence_update_own",
      "bucket_id = 'dastak-evidence'",
      "dastak-partner",
    ]
  ) assertStringIncludes(migration, contract);

  assert(!migration.includes("alter table storage.objects enable row level security"));
  assertStringIncludes(config, "[functions.issue-evidence-url]");
  assertStringIncludes(config, "verify_jwt = true");
  for (
    const contract of [
      "revoke all privileges on table public.service_zones from public, anon, authenticated",
      "grant select on table public.service_zones to authenticated",
    ]
  ) assertStringIncludes(grantHardening, contract);
  for (
    const behavior of [
      "create extension if not exists pgtap with schema extensions",
      "anon has no service zone table privileges",
      "authenticated has only SELECT on service zones",
      "storage.objects keeps managed RLS enabled",
      "authenticated selects only its own exact evidence path",
      "authenticated inserts its own exact evidence path",
      "authenticated cannot insert a foreign evidence path",
      "authenticated cannot insert a nested evidence path",
      "authenticated cannot insert an empty evidence filename",
      "authenticated cannot overwrite its own identity evidence",
      "authenticated cannot update a foreign evidence object",
      "authenticated cannot delete evidence objects",
    ]
  ) assertStringIncludes(behavioralTest, behavior);
});
