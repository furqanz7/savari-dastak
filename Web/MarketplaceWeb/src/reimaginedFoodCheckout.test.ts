import { describe, expect, it } from "vitest";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
import { prepareFoodCheckout } from "./reimaginedFoodCheckoutPreparation";

function input(): Parameters<typeof prepareFoodCheckout>[0] {
  const menu = foodMenuFixture(); const item = menu.categories[0].items[0];
  return { menus: [menu], food: [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [item.optionGroups[0].options[0].id], quantity: 2 }], online: true, canEdit: true, addressesReady: true,
    recipient: { name: " Customer ", phoneNumber: "+919876543210" },
    address: { addressId: "home", label: "Home", address: "Test address", building: "1", floor: "2", details: "", displayAddress: "Test address", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-09-30" } };
}
describe("Food-only local checkout preparation", () => {
  it("prepares exact Food lines and estimates without sending prices or mutating input", () => {
    const source = input(); const before = JSON.stringify(source); const result = prepareFoodCheckout(source);
    expect(result.issues).toEqual([]); expect(result.estimatedSubtotalPaise).toBe(36000);
    expect(result.submission?.restaurantBranchId).toBe(source.food[0].branchId);
    expect(result.submission?.lines).toEqual([{ lineType: "FOOD_MENU_ITEM", menuItemId: source.food[0].itemId, optionIds: source.food[0].optionIds, quantity: 2 }]);
    expect(result.submission?.recipient.name).toBe("Customer"); expect(result.submission?.deliveryAddress.line2).toBe("1, 2");
    expect(result.submission).not.toHaveProperty("price"); expect(result.submission).not.toHaveProperty("idempotencyKey");
    expect(JSON.stringify(source)).toBe(before);
  });
  it.each([0, -1, 100, 1.5, NaN])("blocks invalid quantity %s without inventing an estimate", quantity => {
    const source = input(); source.food[0].quantity = quantity;
    const result = prepareFoodCheckout(source); expect(result.submission).toBeUndefined(); expect(result.estimatedSubtotalPaise).toBeUndefined();
  });
  it("retains unresolved selections, rejects duplicate lines and multiple branches", () => {
    for (const mutation of [(source: ReturnType<typeof input>) => { source.food[0].itemId = fixtureId(90); }, (source: ReturnType<typeof input>) => { source.food[0].optionIds = []; }, (source: ReturnType<typeof input>) => { source.food.push({ ...source.food[0] }); }, (source: ReturnType<typeof input>) => { source.food.push({ ...source.food[0], branchId: fixtureId(91) }); }]) {
      const source = input(); mutation(source); const before = JSON.stringify(source);
      const result = prepareFoodCheckout(source); expect(result.issues.length).toBeGreaterThan(0); expect(result.submission).toBeUndefined(); expect(result.estimatedSubtotalPaise).toBeUndefined(); expect(JSON.stringify(source)).toBe(before);
    }
  });
  it("blocks unavailable, inactive, closed or paused menus", () => {
    for (const mutation of [(source: ReturnType<typeof input>) => { source.menus = undefined; }, (source: ReturnType<typeof input>) => { source.menus![0].restaurant.isOpen = false; }, (source: ReturnType<typeof input>) => { source.menus![0].restaurant.acceptingOrders = false; }, (source: ReturnType<typeof input>) => { source.menus![0].categories[0].items[0].status = "INACTIVE"; }]) {
      const source = input(); mutation(source); expect(prepareFoodCheckout(source).submission).toBeUndefined();
    }
  });
  it("blocks offline, read-only, missing recipient and unconfirmed or invalid address", () => {
    for (const patch of [{ online: false }, { canEdit: false }, { addressesReady: false }, { address: undefined }, { recipient: { name: "", phoneNumber: "+919876543210" } }, { recipient: { name: "Customer", phoneNumber: "not a phone" } }]) {
      expect(prepareFoodCheckout({ ...input(), ...patch }).submission).toBeUndefined();
    }
    const source = input(); source.address!.location.latitude = 91;
    expect(prepareFoodCheckout(source).submission).toBeUndefined();
  });
  it("rejects ambiguous menus and unsafe prices without generating requests", () => {
    const source = input(); source.menus!.push(source.menus![0]); expect(prepareFoodCheckout(source).submission).toBeUndefined();
    const invalid = input(); invalid.menus![0].categories[0].items[0].basePricePaise = Number.MAX_SAFE_INTEGER;
    expect(prepareFoodCheckout(invalid).submission).toBeUndefined();
  });
});
