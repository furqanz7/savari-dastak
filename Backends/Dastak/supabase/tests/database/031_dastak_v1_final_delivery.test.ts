import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822175812_dastak_v1_final_delivery.sql",
    import.meta.url,
  ),
);

function functionBlock(name: string): string {
  const block = migration.match(
    new RegExp(`create (?:or replace )?function ${name}\\s*\\([\\s\\S]*?\\$\\$;`, "i"),
  )?.[0];
  assert(block, `missing function ${name}`);
  return block;
}

Deno.test("Step 4B preserves final-delivery verification, custody, override and privacy contracts", () => {
  const normalized = migration.replace(/\s+/g, " ");
  for (
    const required of [
      "delivery_evidence_immutable",
      "delivery_evidence_packages_immutable",
      "exceptional_handoff_authorizations_immutable",
      "delivery.rider_pre_delivery_photo_required",
      "platform.delivery.handoff_override",
      "START_FINAL_DELIVERY",
      "ARRIVE_CUSTOMER",
      "ADD_DELIVERY_EVIDENCE",
      "VERIFY_DELIVERY",
      "OUT_FOR_DELIVERY",
      "OVERRIDDEN",
      "current_custody_owner_type = 'CUSTOMER'",
      "DELIVERY_HANDOFF_OVERRIDDEN",
    ]
  ) assert(normalized.includes(required), `missing ${required}`);

  const command = functionBlock("public\\.dastak_v1_advance_final_delivery");
  assertMatch(command, /assigned_rider_id is distinct from p_account_id/i);
  assertMatch(command, /final_delivery_incomplete_custody/i);
  assertMatch(command, /delivery_evidence_required/i);
  assertMatch(command, /delivery_code_blocked/i);
  assertMatch(command, /delivery_code_invalid/i);
  assertMatch(command, /delivery_verification_attempt_limit/i);
  assertMatch(command, /complete_final_delivery_locked/i);

  const completion = functionBlock("dastak_v1_api\\.complete_final_delivery_locked");
  assertMatch(completion, /status = 'DELIVERED'/i);
  assertMatch(completion, /current_custody_owner_type = 'CUSTOMER'/i);
  assertMatch(completion, /package_custody_events/i);
  assertMatch(completion, /DELIVERY_HANDOFF_VERIFIED|DELIVERY_HANDOFF_OVERRIDDEN/i);

  const override = functionBlock("dastak_v1_api\\.authorize_exceptional_delivery_handoff");
  assertMatch(override, /assert_authenticated_actor/i);
  assertMatch(override, /platform\.delivery\.handoff_override/i);
  assertMatch(override, /status = 'OVERRIDDEN'/i);
  assertMatch(override, /normalVerificationOccurred', false/i);

  assertMatch(normalized, /customerState}', '"ON_THE_WAY"'/i);
  assertMatch(normalized, /handoff\.status = 'ACTIVE'[\s\S]*deliveryCode/i);
  assertNotMatch(normalized, /customerState[^;]+branch\.display_name/i);

  for (const block of migration.matchAll(/create (?:or replace )?function[\s\S]*?\$\$;/gi)) {
    if (/security definer/i.test(block[0])) assertMatch(block[0], /set search_path = ''/i);
  }
});
