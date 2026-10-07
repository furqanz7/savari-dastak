import { expect, it, vi } from "vitest";
import { getV1RestaurantPage } from "./dastakV1";
const auth = { accessToken: "test", supabaseUrl: "https://example.invalid", publishableKey: "public" };
it("uses the authenticated paginated operation and preserves exact cursor names", async () => {
  const cursor = { name: " exact name ", branchId: "11111111-1111-4111-8111-111111111111" };
  const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify({ restaurants: [], nextCursor: cursor }), { status: 200 }));
  const page = await getV1RestaurantPage({ ...auth, query: " dish ", cursor }, fetcher);
  expect(page.nextCursor).toEqual(cursor);
  expect(JSON.parse(fetcher.mock.calls[0][1].body)).toMatchObject({ operation: "customerRestaurantPage", query: "dish", cursor });
  expect(fetcher.mock.calls[0][1].headers.authorization).toBe("Bearer test");
});
it("does not treat an old capped response or malformed cursor as a complete catalogue", async () => {
  for (const payload of [{ restaurants: [] }, { restaurants: [], nextCursor: { name: "x", branchId: "invalid" } }, { restaurants: [], nextCursor: { name: "", branchId: "11111111-1111-4111-8111-111111111111" } }]) {
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify(payload), { status: 200 }));
    await expect(getV1RestaurantPage(auth, fetcher)).rejects.toThrow();
  }
});
