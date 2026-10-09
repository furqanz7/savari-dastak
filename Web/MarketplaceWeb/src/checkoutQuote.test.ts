import { describe, expect, it, vi } from "vitest";
import { getV1CheckoutQuote } from "./dastakV1";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
const lines = [{ lineType: "RETAIL_SKU" as const, skuId: fixtureId(6), quantity: 1 }];
const input = { accessToken: "test-token", supabaseUrl: "https://example.invalid", publishableKey: "public",
  location: { addressId: fixtureId(70), updatedAt: "2026-10-09T00:00:00Z" }, lines };
const snapshot = (overrides: Record<string, unknown> = {}) => ({ addressId: input.location.addressId,
  addressVersion: input.location.updatedAt, lines: [{ quantity: 1, skuId: fixtureId(6), lineType: "RETAIL_SKU" }],
  restaurantBranchId: null, kind: "ESTIMATE", currencyCode: "INR", pricingVersion: 1,
  checkedAt: "2026-10-09T00:00:00Z", validUntil: "2026-10-09T00:00:45Z", subtotalPaise: 10000,
  deliveryDistanceMeters: 1000, deliveryFeePaise: 1500, platformFeePaise: 230, taxPaise: 0,
  discountPaise: 0, totalPaise: 11730, deliveryAvailable: false, ...overrides });
describe("authoritative checkout quote client", () => {
  it("requests a read-only batched quote without a reservation key, recipient or coordinates", async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json(snapshot()));
    const quote = await getV1CheckoutQuote(input, fetcher);
    expect(quote.totalPaise).toBe(11730); expect(quote.platformFeePaise).toBe(230);
    expect(quote.deliveryAvailable).toBe(false);
    const [url, request] = fetcher.mock.calls[0];
    expect(url).toMatch(/dastak-v1-catalogue$/);
    expect(JSON.parse(request.body)).toEqual({ operation: "customerCheckoutQuote", addressId: input.location.addressId,
      addressVersion: input.location.updatedAt, lines, restaurantBranchId: null });
    expect(request.headers["x-idempotency-key"]).toBeUndefined();
  });
  it.each([0, 1000, 1001, 2000, 2001, 3000, 3001, 6000])("validates the distance band at %i metres", async distance => {
    const delivery = distance <= 1000 ? 1500 : distance <= 2000 ? 2000 : 2000 + 500 * Math.ceil((distance - 2000) / 1000);
    const platform = Math.floor(((10000 + delivery) * 200 + 5000) / 10000);
    const fetcher = vi.fn().mockResolvedValue(Response.json(snapshot({ deliveryDistanceMeters: distance,
      deliveryFeePaise: delivery, platformFeePaise: platform, totalPaise: 10000 + delivery + platform })));
    expect((await getV1CheckoutQuote(input, fetcher)).deliveryFeePaise).toBe(delivery);
  });
  it.each([24, 25, 74, 75])("validates integer half-up rounding for a %i-paise subtotal", async subtotal => {
    const platform = Math.floor(((subtotal + 1500) * 200 + 5000) / 10000);
    const fetcher = vi.fn().mockResolvedValue(Response.json(snapshot({ subtotalPaise: subtotal,
      platformFeePaise: platform, totalPaise: subtotal + 1500 + platform })));
    expect((await getV1CheckoutQuote(input, fetcher)).platformFeePaise).toBe(platform);
  });
  it.each([
    { platformFeePaise: 0 }, { totalPaise: 10000 }, { deliveryFeePaise: 0 }, { subtotalPaise: 1.5 },
    { addressId: fixtureId(71) }, { addressVersion: "2026-10-09T00:00:01Z" }, { restaurantBranchId: fixtureId(72) },
    { lines: [{ ...lines[0], quantity: 2 }] }, { pricingVersion: 0 }, { currencyCode: "USD" },
    { validUntil: "2026-10-09T00:01:00Z" },
  ])("rejects inconsistent pricing or mismatched context %j", async changes => {
    await expect(getV1CheckoutQuote(input, vi.fn().mockResolvedValue(Response.json(snapshot(changes))))).rejects.toThrow();
  });
  it("binds exact Food option selections and the restaurant", async () => {
    const food = [{ lineType: "FOOD_MENU_ITEM" as const, menuItemId: fixtureId(73), optionIds: [fixtureId(74)], quantity: 1 }];
    const branch = fixtureId(72);
    expect((await getV1CheckoutQuote({ ...input, lines: food, restaurantBranchId: branch },
      vi.fn().mockResolvedValue(Response.json(snapshot({ lines: food, restaurantBranchId: branch }))))).totalPaise).toBe(11730);
    await expect(getV1CheckoutQuote({ ...input, lines: food, restaurantBranchId: branch },
      vi.fn().mockResolvedValue(Response.json(snapshot({ lines: [{ ...food[0], optionIds: [] }], restaurantBranchId: branch }))))).rejects.toThrow();
  });
});
