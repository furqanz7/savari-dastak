import { assertEquals, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260911060701_delivery_group_a_assignment_return_integrity.sql",
    import.meta.url,
  ),
);

Deno.test("Group A uses one locked predicate instead of a global assignment registry", () => {
  assertMatch(
    migration,
    /create function private\.delivery_partner_active_work\(/i,
  );
  assertMatch(
    migration,
    /create function private\.lock_delivery_partner_active_work\(/i,
  );
  assertMatch(
    migration,
    /pg_advisory_xact_lock\([\s\S]*?dastak:delivery-partner-active-work:/i,
  );
  assertNotMatch(
    migration,
    /create table[^;]*(active_work|assignment_registry)/i,
  );
  assertMatch(migration, /message = 'EXISTING_RIDER_ACTIVE_WORK_CONFLICT'/i);
  assertMatch(
    migration,
    /mission\.status = 'DELIVERY_RECOVERY'[\s\S]*?mission\.id is not distinct from p_related_delivery_mission_id/i,
  );

  const guards = migration.match(
    /for each row execute function private\.enforce_delivery_partner_active_work\(\)/gi,
  ) ?? [];
  assertEquals(guards.length, 4);
  for (
    const acquisition of [
      "dastak_v1_accept_delivery_offer",
      "assign_return_rider",
      "accept_delivery_assignment_impl",
      "acknowledge_parcel_assignment",
    ]
  ) {
    assertMatch(
      migration,
      new RegExp(
        `create function (?:dastak_v1_api|private|public)\\.${acquisition}[\\s\\S]*?lock_delivery_partner_active_work`,
        "i",
      ),
    );
  }
});

Deno.test("Group A makes bypass implementations owner-only", () => {
  assertMatch(
    migration,
    /create function dastak_v1_api\.assign_return_rider\([\s\S]*?assert_authenticated_actor\(p_actor_id\)[\s\S]*?assert_platform_permission\(/i,
  );
  for (
    const implementation of [
      "dastak_v1_accept_delivery_offer_pre_group_a",
      "assign_return_rider_pre_group_a",
      "accept_delivery_assignment_impl_pre_group_a",
      "acknowledge_parcel_assignment_pre_group_a",
    ]
  ) {
    assertMatch(
      migration,
      new RegExp(
        `revoke all on function[\\s\\S]*?${implementation}[\\s\\S]*?from public, anon, authenticated, service_role`,
        "i",
      ),
    );
  }
});

Deno.test("return arrival is server-gated by fresh accurate 50 metre tracking", () => {
  assertMatch(
    migration,
    /create function dastak_v1_api\.return_arrival_eligibility\(/i,
  );
  assertMatch(migration, /interval '30 seconds'/i);
  assertMatch(migration, /tracking_accuracy_meters > 35/i);
  assertMatch(migration, /distance_meters > 50/i);
  assertMatch(migration, /message = 'RETURN_ARRIVAL_LOCATION_REQUIRED'/i);
  assertEquals(
    (migration.match(
      /execute function dastak_v1\.enforce_return_arrival\(\)/gi,
    ) ?? [])
      .length,
    2,
  );
});

Deno.test("return projection adds only rider-scoped routes and capabilities", () => {
  assertMatch(migration, /tracking_return_mission_id uuid/i);
  assertMatch(migration, /assigned_rider_id = p_rider_id/i);
  assertMatch(migration, /'customerArrival', customer_arrival/i);
  assertMatch(migration, /'canArriveCustomer'/i);
  assertMatch(
    migration,
    /'location'[\s\S]*?st_y\(branch\.location\)[\s\S]*?st_x\(branch\.location\)/i,
  );
  assertMatch(
    migration,
    /revoke all on function[\s\S]*?return_arrival_eligibility\(uuid, uuid\)[\s\S]*?from public, anon, authenticated, service_role/i,
  );
});
