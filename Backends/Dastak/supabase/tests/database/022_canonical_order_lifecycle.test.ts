import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migrationURL = new URL(
  "../../migrations/20260816020228_canonical_order_lifecycle_realtime.sql",
  import.meta.url,
);

Deno.test("canonical order lifecycle is server-owned and recovery-safe", async () => {
  const sql = await Deno.readTextFile(migrationURL);
  const normalized = sql.replace(/\s+/g, " ");

  for (
    const validator of [
      "is_valid_merchant_order_transition",
      "is_valid_merchant_payment_transition",
      "is_valid_parcel_transition",
      "is_valid_parcel_payment_transition",
      "is_valid_parcel_refund_transition",
      "is_valid_merchant_assignment_transition",
      "is_valid_parcel_assignment_transition",
    ]
  ) {
    assertMatch(
      normalized,
      new RegExp(`create or replace function private\\.${validator}`, "i"),
    );
  }

  assertMatch(normalized, /\('assigned', 'ready'\)/i);
  assertMatch(normalized, /\('assigned', 'paid'\)/i);
  assertMatch(normalized, /merchant_order_canonical_transition/i);
  assertMatch(normalized, /parcel_canonical_transition/i);
  assertMatch(normalized, /merchant_order_state_version_sequence/i);
  assertMatch(normalized, /parcel_state_version_sequence/i);
  assertMatch(normalized, /order_state_transitions_immutable/i);
  assertMatch(
    normalized,
    /revoke all on table private\.order_state_transitions from public, anon, authenticated/i,
  );
  assertMatch(
    normalized,
    /grant select on table private\.order_state_transitions to service_role/i,
  );
  assertNotMatch(
    normalized,
    /grant[^;]*insert[^;]*private\.order_state_transitions/i,
  );

  assertMatch(
    normalized,
    /create policy "dastak_account_order_events" on realtime\.messages for select to authenticated/i,
  );
  assertMatch(
    normalized,
    /realtime\.topic\(\)\) = 'order-account:' \|\| \(select auth\.uid\(\)\)::text/i,
  );
  assertMatch(
    normalized,
    /jsonb_build_object\( 'entityKind', p_entity_kind, 'entityId', p_entity_id, 'stateVersion', p_state_version \)/i,
  );
  assertNotMatch(
    normalized,
    /jsonb_build_object\([^;]*(phone|address|amount|payment_state)/i,
  );
  assertMatch(normalized, /v_entity_kind := 'merchant_order'/i);
  assertMatch(normalized, /v_entity_kind := 'parcel'/i);

  assertMatch(
    normalized,
    /set status = 'ready', assigned_at = null, state_version = merchant_order\.state_version \+ 1/i,
  );
  assertMatch(
    normalized,
    /set status = 'paid', assigned_at = null, state_version = parcel\.state_version \+ 1/i,
  );
  const reconcileBody = normalized.match(
    /create or replace function private\.reconcile_order_lifecycle\(\).*?\$\$;(.*?revoke execute on function private\.is_valid_merchant_order_transition)/i,
  )?.[0] ?? "";
  assert(reconcileBody, "reconciliation function must exist");
  assertNotMatch(reconcileBody, /set payment_state\s*=/i);
  assertNotMatch(reconcileBody, /set payment_status\s*=/i);
  assertNotMatch(reconcileBody, /set refund_status\s*=/i);
  assertMatch(normalized, /dastak-order-lifecycle-reconciliation/i);
  assertMatch(normalized, /'\* \* \* \* \*'/i);
  assertMatch(
    normalized,
    /revoke execute on function private\.reconcile_order_lifecycle\(\) from public, anon, authenticated/i,
  );
  assertMatch(
    normalized,
    /grant execute on function private\.reconcile_order_lifecycle\(\) to service_role/i,
  );
});
