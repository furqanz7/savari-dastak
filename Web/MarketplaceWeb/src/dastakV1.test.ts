import { describe, expect, it } from "vitest";
import {
  DastakV1RequestError, getV1Catalogue, parseV1Catalogue, submitV1Order, updateV1AdminSku,
} from "./dastakV1";

const auth = {
  supabaseUrl: "http://127.0.0.1:54321",
  publishableKey: "publishable",
  accessToken: "customer-token",
};
const categoryId = "11111111-1111-4111-8111-111111111111";
const subcategoryId = "22222222-2222-4222-8222-222222222222";
const skuId = "33333333-3333-4333-8333-333333333333";
const orderId = "44444444-4444-4444-8444-444444444444";
const lineId = "55555555-5555-4555-8555-555555555555";

describe("Dastak V1 web contract", () => {
  it("requests a canonical customer projection without merchant discovery fields", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await getV1Catalogue({ ...auth, query: "rice" }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json(catalogueFixture());
    });

    expect(requestBody).toEqual({
      operation: "customerCatalogue", query: "rice", categoryId: null,
      subcategoryId: null, limit: 250, cursor: null,
    });
    expect(JSON.stringify(requestBody)).not.toMatch(/merchant|store|price/i);
    expect(result.skus[0]).not.toHaveProperty("merchantId");
    expect(result.skus[0]).not.toHaveProperty("storeId");
  });

  it("submits SKU and quantity only, with no client-authored price or merchant", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const result = await submitV1Order({
      ...auth,
      idempotencyKey: "submit-once",
      order: {
        deliveryAddress: {
          line1: "12 Market Road", countryCode: "IN", latitude: 28.61, longitude: 77.2,
        },
        recipient: { name: "A Customer", phoneNumber: "+919876543210" },
        lines: [{ lineType: "RETAIL_SKU", skuId, quantity: 2 }],
      },
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("submit-once");
      return Response.json(orderFixture(), { status: 201 });
    });

    expect(result.status).toBe("MATCHING");
    expect(JSON.stringify(requestBody)).not.toMatch(/merchant|store|sellingPrice|listPrice|totalPaise/);
    expect(requestBody).toMatchObject({ operation: "submit", expectedVersion: 0 });
  });

  it("rejects a customer SKU whose selling price exceeds MRP", () => {
    const fixture = catalogueFixture();
    fixture.skus[0].sellingPricePaise = 11001;
    expect(() => parseV1Catalogue(fixture)).toThrow(DastakV1RequestError);
  });

  it("sends optimistic SKU management commands with explicit idempotency", async () => {
    let requestBody: Record<string, unknown> | undefined;
    await updateV1AdminSku({
      ...auth, skuId, expectedVersion: 7,
      patch: { sellingPricePaise: 9400, status: "ACTIVE" }, idempotencyKey: "admin-update",
    }, async (_url, init) => {
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      expect(new Headers(init?.headers).get("x-idempotency-key")).toBe("admin-update");
      return Response.json({ id: skuId, version: 8 });
    });
    expect(requestBody).toEqual({
      operation: "updateSku", skuId, expectedVersion: 7,
      patch: { sellingPricePaise: 9400, status: "ACTIVE" },
    });
  });
});

function catalogueFixture() {
  return {
    catalogueVersion: "2026-08-22T00:00:00Z",
    categories: [{ id: categoryId, name: "Grocery", slug: "grocery", imageKey: null, sortOrder: 1 }],
    subcategories: [{ id: subcategoryId, categoryId, name: "Staples", slug: "staples", imageKey: null, sortOrder: 1 }],
    skus: [{
      id: skuId, categoryId, subcategoryId, brand: null, name: "Rice", slug: "rice-1kg",
      variant: null, packSize: "1 kg", description: null, imageKey: null, barcode: null,
      listPricePaise: 10000, sellingPricePaise: 9500, currencyCode: "INR",
      logisticsAttributes: { weightGrams: 1000 },
    }],
    nextCursor: null,
  };
}

function orderFixture() {
  return {
    id: orderId, displayOrderNumber: "DV1-0001", orderType: "RETAIL_ONLY", status: "MATCHING",
    version: 1, fulfilmentProgress: { state: "MATCHING" },
    price: {
      snapshotKind: "SUBMISSION", subtotalPaise: 19000, deliveryFeePaise: 0,
      platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 19000, currencyCode: "INR",
    },
    lines: [{
      id: lineId, lineType: "RETAIL_SKU", skuId, name: "Rice", variant: null,
      packSize: "1 kg", quantity: 2, unitPricePaise: 9500, lineTotalPaise: 19000, status: "PENDING_MATCH",
    }],
    submittedAt: "2026-08-22T00:00:00Z", fullySecuredAt: null, paymentExpiresAt: null,
    paidAt: null, deliveredAt: null, createdAt: "2026-08-22T00:00:00Z", updatedAt: "2026-08-22T00:00:00Z",
  };
}
