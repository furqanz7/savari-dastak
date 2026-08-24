import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824080000_recover_orphaned_customer_oauth_identity.sql",
    import.meta.url,
  ),
);

Deno.test("orphaned OAuth recovery preserves history without unsafe account merging", () => {
  assertMatch(
    migration,
    /where revoked_at is null/i,
  );
  assertMatch(
    migration,
    /reconcile_orphaned_customer_oauth_identity/i,
  );
  assertMatch(
    migration,
    /not in \('apple', 'google'\)/i,
  );
  assertMatch(
    migration,
    /automaticAccountMerge', false/i,
  );
  assertMatch(
    migration,
    /CUSTOMER_AUTH_ORPHAN_RECONCILED/i,
  );
  assertMatch(
    migration,
    /concurrent token issuance[\s\S]*registered\.provider_subject_digest = v_identity\.subject_digest/i,
  );
  assertNotMatch(
    migration,
    /on delete cascade|delete from\s+(?:public\.accounts|dastak_v1\.orders|dastak_v1\.audit_events)/i,
  );
  assertNotMatch(
    migration.match(
      /create or replace function public\.dastak_custom_access_token[\s\S]*?\$\$;/i,
    )?.[0] ?? "",
    /identity_data[^;]*(?:email|phone)|phone_number|display_name/i,
  );
});
