import { assert, assertMatch } from "jsr:@std/assert";

Deno.test("Admin C2.3 governance migration preserves the locked global assignment architecture", async () => {
  const migration = await Deno.readTextFile(new URL(
    "../../migrations/20260912210626_admin_c2_3_delivery_partner_governance.sql",
    import.meta.url,
  ));
  const normalized = migration.replace(/\s+/g, " ");
  assertMatch(normalized, /platform\.delivery_partners\.manage/i);
  assertMatch(normalized, /lock_delivery_partner_active_work\(p_rider_id\)/i);
  assertMatch(normalized, /delivery_partner_active_work\(p_rider_id\)/i);
  assertMatch(normalized, /RIDER_ACTIVE_WORK_REQUIRES_RELEASE/i);
  assertMatch(normalized, /RIDER_GOVERNANCE_SUSPENDED/i);
  assertMatch(normalized, /DELIVERY_PARTNER_SUSPENDED/i);
  assertMatch(normalized, /DELIVERY_PARTNER_REACTIVATED/i);
  assert(!/identity_evidence_object_path['"]?\s*[,)]/i.test(
    normalized.match(/jsonb_build_object\([\s\S]*?'deliveryPartners'[\s\S]*?return pg_catalog\.jsonb_build_object/i)?.[0] ?? "",
  ), "raw identity evidence paths must not enter the Admin projection");
});
