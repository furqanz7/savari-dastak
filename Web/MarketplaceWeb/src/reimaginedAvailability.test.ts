import { describe, expect, it, vi } from "vitest";
import { getV1AreaAvailability, type V1AreaAvailability } from "./dastakV1";
import { areaCheckoutIssue, localGroceryEligibility } from "./reimaginedAvailability";
import { fixtureId, groceryFixture } from "./reimaginedCatalogue.testFixtures";
const location = { addressId: fixtureId(70), updatedAt: "2026-10-08T00:00:00Z" };
export const areaFixture: V1AreaAvailability = { addressId: location.addressId, addressVersion: location.updatedAt,
  checkedAt: location.updatedAt, groceryServiceable: true, foodServiceable: true, deliveryAvailable: true,
  stock: { [fixtureId(6)]: 3 }, restaurants: { [fixtureId(30)]: true, [fixtureId(31)]: false } };
const auth = { accessToken: "test", supabaseUrl: "https://example.invalid", publishableKey: "public" };
describe("local availability contract", () => {
  it("requires positive exact-pack stock but does not require a partner to edit the cart", () => {
    const noRider = { ...areaFixture, deliveryAvailable: false };
    expect(localGroceryEligibility(fixtureId(6), noRider, true, true, true)).toMatchObject({ canAdd: true, maximumQuantity: 3 });
    expect(areaCheckoutIssue(noRider, true)).toContain("No delivery partners");
    expect(localGroceryEligibility(fixtureId(7), noRider, true, true, true)).toMatchObject({ canAdd: false, maximumQuantity: 0, reason: "Out of stock", canRemove: true });
  });
  it("fails closed without an address, current data or cart ownership", () => {
    expect(localGroceryEligibility(fixtureId(6), undefined, true, true, false).canAdd).toBe(false);
    expect(localGroceryEligibility(fixtureId(6), undefined, true, true, true).canAdd).toBe(false);
    expect(localGroceryEligibility(fixtureId(6), areaFixture, false, true, true).canAdd).toBe(false);
    expect(localGroceryEligibility(fixtureId(6), areaFixture, true, false, true).canAdd).toBe(false);
  });
  it("blocks unsupported Grocery and saved quantities that exceed local stock without removing them", () => {
    expect(localGroceryEligibility(fixtureId(6), { ...areaFixture, groceryServiceable: false }, true, true, true).reason).toBe("This area is not serviceable yet.");
    const cart = { [fixtureId(6)]: 4 };
    expect(areaCheckoutIssue(areaFixture, true, cart)).toContain("out of stock"); expect(cart[fixtureId(6)]).toBe(4);
    expect(areaCheckoutIssue(areaFixture, true, { [fixtureId(6)]: 3 })).toBeUndefined();
  });
  it("makes one authenticated, address-version-bound batched request, without coordinates", async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json(areaFixture));
    expect(await getV1AreaAvailability({ ...auth, location }, fetcher)).toEqual(areaFixture);
    expect(JSON.parse(fetcher.mock.calls[0][1].body)).toEqual({ operation: "customerAreaAvailability", addressId: location.addressId, addressVersion: location.updatedAt });
    expect(fetcher.mock.calls[0][1].headers.authorization).toBe("Bearer test");
  });
  it("decodes server ranking in order, distinguishes empty history, and rejects duplicate packs", async () => {
    const trendingSkus = groceryFixture.catalogue.skus.slice(0, 2).reverse();
    const load = (payload: unknown) => getV1AreaAvailability({ ...auth, location }, async () => Response.json(payload));
    expect((await load({ ...areaFixture, trendingSkus })).trendingSkus?.map(sku => sku.id)).toEqual(trendingSkus.map(sku => sku.id));
    expect((await load({ ...areaFixture, trendingSkus: [] })).trendingSkus).toEqual([]);
    expect((await load(areaFixture)).trendingSkus).toBeUndefined();
    await expect(load({ ...areaFixture, trendingSkus: [trendingSkus[0], trendingSkus[0]] })).rejects.toThrow();
    await expect(load({ ...areaFixture, trendingSkus: "invalid" })).rejects.toThrow();
  });
  it.each([
    { ...areaFixture, addressId: fixtureId(71) }, { ...areaFixture, addressVersion: "2026-10-09T00:00:00Z" },
    { ...areaFixture, deliveryAvailable: "true" }, { ...areaFixture, stock: { [fixtureId(6)]: null } },
    { ...areaFixture, stock: { [fixtureId(6)]: 0 } }, { ...areaFixture, stock: { [fixtureId(6)]: -1 } },
    { ...areaFixture, stock: { [fixtureId(6)]: 1.2 } }, { ...areaFixture, restaurants: { [fixtureId(30)]: "true" } },
  ])("rejects malformed or mismatched snapshots", async payload => {
    await expect(getV1AreaAvailability({ ...auth, location }, async () => Response.json(payload))).rejects.toThrow();
  });
});
