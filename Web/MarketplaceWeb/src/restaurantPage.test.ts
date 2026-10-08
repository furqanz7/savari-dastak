import { expect, it, vi } from "vitest";
import { getV1RestaurantPage } from "./dastakV1";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
const auth = { accessToken: "test", supabaseUrl: "https://example.invalid", publishableKey: "public" };
it("uses the authenticated paginated operation and preserves exact cursor names", async () => {
  const cursor = { name: " exact name ", branchId: "11111111-1111-4111-8111-111111111111" };
  const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify({ restaurants: [], nextCursor: cursor }), { status: 200 }));
  const page = await getV1RestaurantPage({ ...auth, query: " dish ", cursor }, fetcher);
  expect(page.nextCursor).toEqual(cursor);
  expect(JSON.parse(fetcher.mock.calls[0][1].body)).toMatchObject({ operation: "customerRestaurantPage", query: "dish", cursor });
  expect(fetcher.mock.calls[0][1].headers.authorization).toBe("Bearer test");
});
it("uses nearest server pages and retains the distance/address cursor including unknown locations", async () => {
  const location = { addressId: "22222222-2222-4222-8222-222222222222", updatedAt: "2026-10-08T00:00:00Z" };
  const menu = foodMenuFixture(); menu.restaurant.distanceMeters = 1250;
  const cursor = { name: "x", branchId: menu.restaurant.branchId, distanceMeters: null, addressId: location.addressId, addressVersion: location.updatedAt };
  const response = { restaurants: [menu], nextCursor: cursor, ordering: "NEAREST", addressId: location.addressId, addressVersion: location.updatedAt };
  const fetcher = vi.fn().mockResolvedValue(Response.json(response));
  const page = await getV1RestaurantPage({ ...auth, location }, fetcher);
  expect(page.ordering).toBe("NEAREST"); expect(page.restaurants[0].restaurant.distanceMeters).toBe(1250); expect(page.nextCursor).toEqual(cursor);
  expect(JSON.parse(fetcher.mock.calls[0][1].body)).toMatchObject({ operation: "customerRestaurantNearestPage", addressId: location.addressId, addressVersion: location.updatedAt });
});
it("rejects mismatched distance context/cursors instead of pretending an alphabetical page is nearest", async () => {
  const location = { addressId: "22222222-2222-4222-8222-222222222222", updatedAt: "2026-10-08T00:00:00Z" };
  const response = { restaurants: [], nextCursor: null, ordering: "NEAREST", addressId: location.addressId, addressVersion: location.updatedAt };
  for (const payload of [{ ...response, ordering: undefined }, { ...response, addressId: "different" }, { ...response, addressVersion: "2026-10-09T00:00:00Z" },
    { ...response, nextCursor: { name: "x", branchId: location.addressId } },
    { ...response, nextCursor: { name: "x", branchId: location.addressId, distanceMeters: -1, addressId: location.addressId, addressVersion: location.updatedAt } }]) {
    await expect(getV1RestaurantPage({ ...auth, location }, async () => Response.json(payload))).rejects.toThrow();
  }
  const fetcher = vi.fn();
  await expect(getV1RestaurantPage({ ...auth, location, cursor: { name: "x", branchId: location.addressId } }, fetcher)).rejects.toThrow();
  expect(fetcher).not.toHaveBeenCalled();
});
it("rejects missing or impossible distances in nearest responses, but accepts an explicitly unknown location", async () => {
  const location = { addressId: "22222222-2222-4222-8222-222222222222", updatedAt: "2026-10-08T00:00:00Z" };
  const menu = foodMenuFixture();
  const response = { restaurants: [menu], nextCursor: null, ordering: "NEAREST", addressId: location.addressId, addressVersion: location.updatedAt };
  await expect(getV1RestaurantPage({ ...auth, location }, async () => Response.json(response))).rejects.toThrow();
  menu.restaurant.distanceMeters = 41000001;
  await expect(getV1RestaurantPage({ ...auth, location }, async () => Response.json(response))).rejects.toThrow();
  const unknown = { ...response, restaurants: [{ ...menu, restaurant: { ...menu.restaurant, distanceMeters: null } }] };
  expect((await getV1RestaurantPage({ ...auth, location }, async () => Response.json(unknown))).restaurants[0].restaurant.distanceMeters).toBeUndefined();
});
it("does not treat an old capped response or malformed cursor as a complete catalogue", async () => {
  for (const payload of [{ restaurants: [] }, { restaurants: [], nextCursor: { name: "x", branchId: "invalid" } }, { restaurants: [], nextCursor: { name: "", branchId: "11111111-1111-4111-8111-111111111111" } }]) {
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify(payload), { status: 200 }));
    await expect(getV1RestaurantPage(auth, fetcher)).rejects.toThrow();
  }
});
