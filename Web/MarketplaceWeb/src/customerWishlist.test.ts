import { describe, expect, it, vi } from "vitest";
import {
  CustomerWishlistRequestError,
  getCustomerWishlist,
  setCustomerWishlistItem,
} from "./customerWishlist";

const auth = {
  accessToken: "customer-token",
  publishableKey: "publishable-key",
  supabaseUrl: "https://example.supabase.co",
};
const itemId = "11111111-1111-4111-8111-111111111111";

describe("customer Wishlist", () => {
  it("loads an authenticated, validated snapshot", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.headers).toMatchObject({ authorization: "Bearer customer-token" });
      return Response.json({ items: [{ kind: "RETAIL_SKU", itemId, createdAt: "2026-08-24T10:00:00Z" }] });
    });
    await expect(getCustomerWishlist(auth, fetcher)).resolves.toMatchObject({
      items: [{ kind: "RETAIL_SKU", itemId }],
    });
  });

  it("sends desired-state changes with an idempotency key", async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.headers).toMatchObject({ "x-idempotency-key": "request-id" });
      expect(JSON.parse(String(init?.body))).toEqual({
        operation: "set", itemKind: "MENU_ITEM", itemId, wished: false,
      });
      return Response.json({ items: [] });
    });
    await expect(setCustomerWishlistItem({
      ...auth, itemKind: "MENU_ITEM", itemId, wished: false, idempotencyKey: "request-id",
    }, fetcher)).resolves.toEqual({ items: [] });
  });

  it("rejects malformed and failed responses", async () => {
    await expect(getCustomerWishlist(auth, async () => Response.json({ items: [{}] })))
      .rejects.toBeInstanceOf(CustomerWishlistRequestError);
    await expect(getCustomerWishlist(auth, async () => Response.json({
      error: { code: "authentication_required", message: "Sign in again." },
    }, { status: 401 }))).rejects.toMatchObject({ code: "authentication_required", status: 401 });
  });
});
