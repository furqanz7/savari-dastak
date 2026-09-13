import { assert, assertFalse, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(new URL(
  "../../migrations/20260913222542_governed_taxonomy_restaurant_media.sql",
  import.meta.url,
));
const sql = migration.replace(/\s+/g, " ");

Deno.test("governed media is exact-entity, serialized, and service-bound", () => {
  assertMatch(sql, /unique index governed_entity_media_active_uidx.*entity_type,entity_id.*status='ACTIVE'/i);
  assertMatch(sql, /pg_advisory_xact_lock.*dastak:governed-media:/i);
  assertMatch(sql, /entity_type=p_type and entity_id=p_id and status='PENDING_UPLOAD'/i);
  assertMatch(sql, /canonical\/.*p_id.*v_asset/i);
  assertMatch(sql, /actor_has_wave1_merchant_permission.*merchant\.restaurant\.menu\.manage/i);
  assertMatch(sql, /platform\.catalogue\.assets\.manage/i);
  assertMatch(sql, /revoke all on function.*authenticated.*grant execute on function.*service_role/i);
});

Deno.test("governed media atomically replaces only presentation fields", () => {
  assertMatch(sql, /set status='REPLACED'.*set status='ACTIVE'/i);
  assertMatch(sql, /GOVERNED_MEDIA_REPLACED/i);
  assertMatch(sql, /banner_image_key=v_media\.image_key/i);
  assertMatch(sql, /restaurant_menu_items set image_key=v_media\.image_key/i);
  assertFalse(/set\s+(canonical_name|pack_size|variant_name|selling_price_paise|list_price_paise|base_price_paise|tax_rate_bps)\s*=/i.test(sql));
});

Deno.test("restaurant banner no longer comes from mutable address JSON", () => {
  const projection = migration.slice(migration.indexOf("create or replace function dastak_v1_api.restaurant_menu_json"));
  assert(projection.includes("'imageKey',b.banner_image_key"));
  assertFalse(projection.includes("address_snapshot->>'imageKey'"));
});
