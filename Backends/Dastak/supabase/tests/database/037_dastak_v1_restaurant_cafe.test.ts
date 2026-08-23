import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824020000_dastak_v1_restaurant_cafe_runtime.sql",
    import.meta.url,
  ),
);
const customerWeb = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/DastakV1CustomerExperience.tsx", import.meta.url),
);
const merchantWeb = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/MerchantV1CommerceControl.tsx", import.meta.url),
);
const adminWeb = await Deno.readTextFile(
  new URL("../../../../../Web/MarketplaceWeb/src/AdminV1ExecutionPanel.tsx", import.meta.url),
);

function functionBlock(name: string): string {
  const blocks = [...migration.matchAll(
    new RegExp(`create (?:or replace )?function ${name}\\s*\\([\\s\\S]*?\\$\\$;`, "gi"),
  )];
  const block = blocks.at(-1)?.[0];
  assert(block, `missing function ${name}`);
  return block;
}

Deno.test("one mixed parent order uses one selected restaurant and server menu snapshots", () => {
  const submit = functionBlock("dastak_v1_api\\.submit_order");
  assertMatch(submit, /restaurant_branch_id/i);
  assertMatch(submit, /FOOD_MENU_ITEM/i);
  assertMatch(submit, /restaurant_selection_snapshot/i);
  assertMatch(submit, /order_type[^;]*MIXED/i);
  assertNotMatch(submit, /reroute|alternative_restaurant|replacement_restaurant/i);
});

Deno.test("restaurant confirmation is direct, binding, soft-capacity, and pre-payment", () => {
  const respond = functionBlock("dastak_v1_api\\.respond_restaurant_request");
  assertMatch(respond, /restaurant_capacity_commitments/i);
  assertMatch(respond, /soft_threshold_snapshot/i);
  assertMatch(respond, /active_order_count_snapshot/i);
  assertMatch(respond, /RESERVED_PREPAYMENT/i);
  assertMatch(respond, /accepted_above_threshold/i);
  assertMatch(migration, /release_restaurant_commitment_after_fulfilment/i);
  assertMatch(migration, /release_unconfirmed_restaurant_request_after_order/i);
});

Deno.test("food fulfilments join the generic secured, transport, preparation, and custody spine", () => {
  assertMatch(migration, /food_security_snapshot/i);
  assertMatch(migration, /routeDistanceMeters/i);
  assertMatch(migration, /order_transport_snapshot/i);
  assertMatch(migration, /source_restaurant_request_id/i);
  assertMatch(migration, /preparedFoodPhysicallyReturnable', false/i);
  assertMatch(migration, /return_lines_reject_prepared_food/i);
  assertMatch(migration, /PREPARED_FOOD_PHYSICAL_RETURN_FORBIDDEN/i);
});

Deno.test("launch customer and merchant surfaces use V1 Restaurant contracts", () => {
  assertMatch(customerWeb, /getV1Restaurants/);
  assertMatch(customerWeb, /FOOD_MENU_ITEM/);
  assertMatch(customerWeb, /RestaurantMenuSheet/);
  assertMatch(merchantWeb, /upsertV1RestaurantMenuEntity/);
  assertMatch(merchantWeb, /soft threshold/i);
  assertNotMatch(merchantWeb, /MerchantCatalogueView/);
  assertMatch(adminWeb, /Prepared-food issues use investigation\/refund resolution/i);
});
