import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824214134_dastak_v1_custom_checkout_completion.sql",
    import.meta.url,
  ),
);

Deno.test("Custom Checkout completion remains service-only and append-only", () => {
  assertMatch(migration, /payment_client_completions_immutable/i);
  assertMatch(migration, /enable row level security/i);
  assertMatch(
    migration,
    /grant execute[\s\S]*?record_custom_checkout_completion[\s\S]*?to service_role/i,
  );
  assertNotMatch(
    migration,
    /grant execute[\s\S]*?record_custom_checkout_completion[\s\S]*?to authenticated/i,
  );
});

Deno.test("verified client return explicitly preserves captured-webhook authority", () => {
  assertMatch(migration, /paidAuthority', 'payment\.captured'/i);
  assertMatch(migration, /AWAITING_PROVIDER_CONFIRMATION/i);
  assertNotMatch(
    migration,
    /update dastak_v1\.payments[\s\S]*?set status = 'SUCCEEDED'/i,
  );
  assertNotMatch(
    migration,
    /update dastak_v1\.orders[\s\S]*?set status = 'PAID'/i,
  );
});
