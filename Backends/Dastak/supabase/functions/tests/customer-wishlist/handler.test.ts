import { assertEquals } from "jsr:@std/assert@1";
import { handleCustomerWishlist } from "../../customer-wishlist/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const itemId = "22222222-2222-4222-8222-222222222222";
type Dependencies = Parameters<typeof handleCustomerWishlist>[1];

Deno.test("Wishlist snapshot is scoped to the authenticated account", async () => {
  let received = "";
  const response = await handleCustomerWishlist(
    request({ operation: "snapshot" }),
    dependencies({
      snapshot: async (value) => {
        received = value;
        return { responseBody: { items: [] }, responseStatus: 200 };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(received, accountId);
});

Deno.test("Wishlist set ignores forged account identity and forwards desired state", async () => {
  let received: Record<string, unknown> = {};
  const response = await handleCustomerWishlist(
    request({
      operation: "set",
      accountId: "99999999-9999-4999-8999-999999999999",
      itemKind: "RETAIL_SKU",
      itemId,
      wished: true,
    }),
    dependencies({
      setItem: async (input) => {
        received = input;
        return { responseBody: { items: [] }, responseStatus: 200 };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(received, { accountId, itemKind: "RETAIL_SKU", itemId, wished: true });
});

Deno.test("Wishlist rejects missing auth and invalid item kinds", async () => {
  const missingAuth = await handleCustomerWishlist(
    new Request("https://example.test/customer-wishlist", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ operation: "snapshot" }),
    }),
    dependencies(),
  );
  const invalid = await handleCustomerWishlist(
    request({ operation: "set", itemKind: "STORE", itemId, wished: true }),
    dependencies(),
  );
  assertEquals(missingAuth.status, 401);
  assertEquals(invalid.status, 400);
});

Deno.test("Wishlist removal is an idempotent desired-state command", async () => {
  let calls = 0;
  const response = await handleCustomerWishlist(
    request({ operation: "set", itemKind: "MENU_ITEM", itemId, wished: false }),
    dependencies({
      setItem: async (input) => {
        calls += 1;
        assertEquals(input.wished, false);
        return { responseBody: { items: [] }, responseStatus: 200 };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, 1);
});

function request(body: unknown) {
  return new Request("https://example.test/customer-wishlist", {
    method: "POST",
    headers: { authorization: "Bearer token", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function dependencies(overrides: Partial<Dependencies> = {}): Dependencies {
  return {
    authenticateBearer: async () => ({ accountId }),
    snapshot: async () => ({ responseBody: { items: [] }, responseStatus: 200 }),
    setItem: async () => ({ responseBody: { items: [] }, responseStatus: 200 }),
    ...overrides,
  };
}
