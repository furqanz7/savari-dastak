import { describe, expect, it } from "vitest";
import {
  browseCatalogue,
  catalogueImageUrl,
  formatPrice,
  groupCatalogue,
  parseCatalogueSnapshot,
} from "./catalogue";

const storeId = "33333333-3333-4333-8333-333333333333";
const categoryId = "44444444-4444-4444-8444-444444444444";

const snapshot = {
  serviceZoneId: "66666666-6666-4666-8666-666666666666",
  stores: [{
    storeId,
    name: "Corner Store",
    address: "12 Main Road",
    location: { latitude: 12.6819, longitude: 78.6201 },
    serviceZoneId: "66666666-6666-4666-8666-666666666666",
    isPublished: true,
    acceptingOrders: true,
  }],
  categories: [{
    categoryId,
    storeId,
    name: "Snacks",
    displayOrder: 1,
    isActive: true,
  }],
  products: [{
    productId: "55555555-5555-4555-8555-555555555555",
    storeId,
    categoryId,
    name: "Lime Soda",
    description: null,
    unitLabel: "750 ml",
    price: { paise: 12500 },
    imageObjectPath: "merchant/account/lime soda.jpg",
    availability: "in_stock",
    catalogueKind: "general",
    restrictedApprovalState: "not_applicable",
    isActive: true,
  }],
};

describe("catalogue data", () => {
  it("validates and groups stores, categories, and products", () => {
    const grouped = groupCatalogue(parseCatalogueSnapshot(snapshot));

    expect(grouped).toHaveLength(1);
    expect(grouped[0].categories[0].products[0].name).toBe("Lime Soda");
  });

  it("rejects malformed server-owned prices", () => {
    expect(() => parseCatalogueSnapshot({
      ...snapshot,
      products: [{ ...snapshot.products[0], price: { paise: -1 } }],
    })).toThrow("invalid catalogue response");
  });

  it("drops orphaned categories and products", () => {
    const parsed = parseCatalogueSnapshot({
      ...snapshot,
      categories: [...snapshot.categories, {
        ...snapshot.categories[0],
        categoryId: "77777777-7777-4777-8777-777777777777",
        storeId: "88888888-8888-4888-8888-888888888888",
      }],
      products: [...snapshot.products, {
        ...snapshot.products[0],
        productId: "99999999-9999-4999-8999-999999999999",
        categoryId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      }],
    });

    expect(groupCatalogue(parsed)[0].categories).toHaveLength(1);
  });

  it("formats paise as Indian rupees", () => {
    expect(formatPrice(12500)).toBe("\u20b9125");
    expect(formatPrice(12550)).toBe("\u20b9125.50");
  });

  it("encodes public catalogue image paths", () => {
    expect(catalogueImageUrl("https://example.supabase.co", "merchant/account/lime soda.jpg"))
      .toBe("https://example.supabase.co/storage/v1/object/public/dastak-catalogue/merchant/account/lime%20soda.jpg");
    expect(catalogueImageUrl("https://example.supabase.co", null)).toBeNull();
  });

  it("preserves safe backend error codes for the UI", async () => {
    const fetcher = () => Promise.resolve(new Response(JSON.stringify({
      error: { code: "outside_service_area", message: "Dastak is not available at this location." },
    }), { status: 422, headers: { "content-type": "application/json" } }));

    await expect(browseCatalogue({
      supabaseUrl: "https://example.supabase.co",
      publishableKey: "publishable-key",
      accessToken: "access-token",
      location: { latitude: 12.6819, longitude: 78.6201 },
    }, fetcher)).rejects.toMatchObject({ code: "outside_service_area", status: 422 });
  });
});
