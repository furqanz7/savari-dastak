import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824110330_customer_wishlist_completion.sql",
    import.meta.url,
  ),
);

const functionConfig = await Deno.readTextFile(
  new URL("../../config.toml", import.meta.url),
);

Deno.test("Customer Wishlist remains private and server-authoritative", () => {
  assertMatch(
    migration,
    /alter table dastak_v1\.customer_wishlist_items enable row level security/i,
  );
  assertMatch(migration, /revoke all on table[\s\S]*?from public, anon, authenticated/i);
  assertMatch(
    migration,
    /grant execute on function public\.get_customer_wishlist\(uuid\) to service_role/i,
  );
  assertNotMatch(migration, /grant (select|insert|update|delete)[\s\S]*?to authenticated/i);
});

Deno.test("Wishlist additions validate live canonical items and audit real changes", () => {
  assertMatch(migration, /sku\.status = 'ACTIVE'/i);
  assertMatch(migration, /menu_item\.status = 'ACTIVE'/i);
  assertMatch(migration, /on conflict \(account_id, item_kind, item_id\) do nothing/i);
  assertMatch(migration, /CUSTOMER_WISHLIST_ADDED/);
  assertMatch(migration, /CUSTOMER_WISHLIST_REMOVED/);
});

Deno.test("Customer Wishlist deploys with explicit handler-owned bearer authentication", () => {
  assertMatch(
    functionConfig,
    /\[functions\.customer-wishlist\][\s\S]*?enabled = true[\s\S]*?verify_jwt = false[\s\S]*?entrypoint = "\.\/functions\/customer-wishlist\/index\.ts"/,
  );
});
