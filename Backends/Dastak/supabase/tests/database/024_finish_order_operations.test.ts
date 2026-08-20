import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migrationURL = new URL(
  "../../migrations/20260820135959_finish_order_operations.sql",
  import.meta.url,
);

Deno.test("finished order operations are owner-gated, auditable, and recoverable", async () => {
  const normalized = (await Deno.readTextFile(migrationURL)).replace(
    /\s+/g,
    " ",
  );

  assertMatch(
    normalized,
    /'audience', case when v_audience = 'customer' then 'sender' else 'recipient' end/i,
  );
  assertMatch(
    normalized,
    /create(?: or replace)? function public\.get_owner_order_operations/i,
  );
  assertMatch(normalized, /membership\.role = 'owner'/i);
  assertMatch(normalized, /customer_order_support_cases_resolution_check/i);
  assertMatch(
    normalized,
    /create(?: or replace)? function public\.owner_resolve_customer_support_case/i,
  );
  assertMatch(normalized, /customer_order_support_resolved/i);
  assertMatch(
    normalized,
    /create(?: or replace)? function public\.owner_reset_parcel_handoff_code/i,
  );
  assertMatch(normalized, /parcel_handoff_code_reset/i);
  assertMatch(
    normalized,
    /create(?: or replace)? function public\.owner_reconcile_order_lifecycle/i,
  );
  assertMatch(normalized, /private\.reconcile_order_lifecycle\(\)/i);
  assertMatch(
    normalized,
    /create(?: or replace)? function public\.publish_delivery_partner_location/i,
  );
  assertMatch(normalized, /available_until <= pg_catalog\.now\(\)/i);
  assertMatch(
    normalized,
    /set location = v_point, service_zone_id = v_zone_id, last_seen_at = pg_catalog\.now\(\)/i,
  );
  assertNotMatch(
    normalized,
    /publish_delivery_partner_location[\s\S]*set[\s\S]*available_until = pg_catalog\.now\(\) \+ interval '15 minutes'/i,
  );
  assertMatch(
    normalized,
    /revoke execute[^;]*from public, anon, authenticated/i,
  );
  assertMatch(normalized, /grant execute[^;]*to service_role/i);
  assertNotMatch(
    normalized,
    /grant[^;]*(owner_order_operations|customer_order_support_cases)[^;]*authenticated/i,
  );
});
