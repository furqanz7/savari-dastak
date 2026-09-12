import { assert, assertFalse, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260912185758_admin_c2_1_permissions_audit_history.sql",
    import.meta.url,
  ),
);
const adminClient = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/dastakV1.ts", import.meta.url),
);
const auditPanel = await Deno.readTextFile(
  new URL(
    "../../../../../Web/MarketplaceWeb/src/AdminAuditHistoryPanel.tsx",
    import.meta.url,
  ),
);

Deno.test("C2.1 permissions remain narrowly assigned", () => {
  for (
    const permission of [
      "platform.merchants.manage",
      "platform.delivery_partners.manage",
      "platform.accounts.recover",
      "platform.audit.read",
      "platform.catalogue.assets.manage",
    ]
  ) assert(migration.includes(`'${permission}'`));
  assertMatch(
    migration,
    /bundle\.bundle_key in \('platform_super_admin', 'executive_admin'\)/,
  );
  assertMatch(migration, /bundle\.bundle_key = 'catalogue_admin'/);
});

Deno.test("Audit History is caller-bound and projects reviewed fields only", () => {
  assertMatch(
    migration,
    /assert_platform_permission\(p_actor_id, 'platform\.audit\.read'\)/,
  );
  assertMatch(migration, /admin_role_for_actor\(p_actor_id\) is null/);
  assertMatch(migration, /security definer[\s\S]*?set search_path = ''/i);
  assertMatch(
    migration,
    /revoke all on function public\.dastak_v1_admin_audit_history_page\([\s\S]*?from public, anon/i,
  );
  assertFalse(/'metadata',\s*event\.metadata/.test(migration));
  assertFalse(/'beforeState'|'afterState'|'rawMetadata'/.test(migration));
});

Deno.test("Audit History frontend uses shared runtime and opaque pagination", () => {
  assertMatch(adminClient, /getV1AdminAuditHistory/);
  assertMatch(
    adminClient,
    /nextCursor\?: \{ occurredAt: string; eventId: string \}/,
  );
  assertMatch(auditPanel, /useAdminWorkspaceRefresh\("auditHistory"/);
  assertMatch(auditPanel, /new RefreshQueue\(\)/);
  assertMatch(auditPanel, /adminFeedFailed/);
  assertMatch(auditPanel, /Load older events/);
});
