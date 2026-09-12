import { assert, assertFalse, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260913120000_admin_c2_5_catalogue_asset_governance.sql",
    import.meta.url,
  ),
);
const normalized = migration.replace(/\s+/g, " ");

Deno.test("Admin C2.5 remains exact-SKU, permission-scoped and service-bound", () => {
  assertMatch(normalized, /platform\.catalogue\.assets\.manage/i);
  assertMatch(
    normalized,
    /pg_advisory_xact_lock.*dastak:catalogue-asset-sku:/i,
  );
  assertMatch(
    normalized,
    /where asset\.id = p_asset_id and asset\.sku_id = p_sku_id/i,
  );
  assertMatch(normalized, /canonical\/admin\/.*p_sku_id.*v_asset\.id/i);
  assertMatch(
    normalized,
    /revoke all on function public\.dastak_v1_admin_prepare_catalogue_asset.*authenticated/i,
  );
  assertMatch(
    normalized,
    /grant execute on function public\.dastak_v1_admin_prepare_catalogue_asset.*service_role/i,
  );
  assertFalse(
    /update dastak_v1\.skus[\s\S]*?(canonical_name|pack_size|variant_name|list_price|selling_price|subcategory_id|brand_id)\s*=/i
      .test(normalized),
  );
});

Deno.test("Admin C2.5 protects and atomically replaces the primary image", () => {
  assertMatch(normalized, /CATALOGUE_PRIMARY_ASSET_REQUIRES_REPLACEMENT/i);
  assertMatch(
    normalized,
    /set_config\( 'dastak\.catalogue_asset_primary_swap_sku'/i,
  );
  assertMatch(normalized, /set role = 'GALLERY'[\s\S]*?set role = 'PRIMARY'/i);
  assertMatch(normalized, /v_primary_count <> 1/i);
});

Deno.test("Admin C2.5 audit contains governed identifiers without storage paths", () => {
  for (
    const action of [
      "CATALOGUE_ASSET_UPLOAD_PREPARED",
      "CATALOGUE_ASSET_ADDED",
      "CATALOGUE_PRIMARY_IMAGE_PROMOTED",
      "CATALOGUE_PRIMARY_IMAGE_REPLACED",
      "CATALOGUE_ASSET_REMOVED",
    ]
  ) assert(migration.includes(action));
  const auditBlocks = [
    ...migration.matchAll(/insert into dastak_v1\.audit_events[\s\S]*?\);/gi),
  ]
    .map((match) => match[0]).join("\n");
  assertFalse(
    /imageKey|storageObjectPath|sourceReference|checksumSha256/i.test(
      auditBlocks,
    ),
  );
});
