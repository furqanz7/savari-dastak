import { assert, assertEquals } from "jsr:@std/assert";
import {
  type CatalogueDependencies,
  type CatalogueSnapshot,
  handleCatalogue,
  type UpsertCategoryInput,
  type UpsertProductInput,
  type UpsertStoreInput,
} from "../../catalogue/handler.ts";

Deno.test("catalogue accepts browser CORS preflight without authenticating", async () => {
  let authenticationAttempts = 0;
  const response = await handleCatalogue(
    new Request("http://localhost/functions/v1/catalogue", { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
  assert(response.headers.get("access-control-allow-headers")?.includes("authorization"));
});

Deno.test("catalogue rejects missing authorization", async () => {
  let authenticationAttempts = 0;
  const response = await handleCatalogue(
    request({ operation: "merchantSnapshot" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("catalogue authenticates before validating the operation", async () => {
  const response = await handleCatalogue(
    request({ operation: "unsupported" }, "Bearer invalid-token"),
    dependencies({
      authenticateBearer: () => Promise.reject(new Error("invalid bearer")),
    }),
  );

  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("store upsert forwards normalized authenticated merchant input", async () => {
  let recorded: UpsertStoreInput | undefined;
  const response = await handleCatalogue(
    request(
      {
        operation: "upsertStore",
        accountId: otherAccountId,
        name: "  Corner   Store  ",
        address: "  12   Main Road  ",
        location: { latitude: 12.6819, longitude: 78.6201 },
        isPublished: true,
        acceptingOrders: true,
      },
      "Bearer session-token",
      "store-key-1",
    ),
    dependencies({
      upsertStore: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: store, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.name, "Corner Store");
  assertEquals(recorded?.address, "12 Main Road");
  assertEquals(recorded?.latitude, 12.6819);
  assertEquals(recorded?.longitude, 78.6201);
  assertEquals(recorded?.isPublished, true);
  assertEquals(recorded?.acceptingOrders, true);
  assertEquals(recorded?.idempotencyKey, "store-key-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
});

Deno.test("store upsert rejects invalid coordinates and unpublished ordering", async () => {
  let calls = 0;
  const invalidLocation = await handleCatalogue(
    request(
      {
        operation: "upsertStore",
        name: "Corner Store",
        address: "12 Main Road",
        location: { latitude: 91, longitude: 78.6201 },
        isPublished: false,
        acceptingOrders: false,
      },
      "Bearer session-token",
      "store-key-2",
    ),
    dependencies({
      upsertStore: () => {
        calls += 1;
        return Promise.resolve({ responseBody: {}, responseStatus: 200 });
      },
    }),
  );
  const unpublishedOrdering = await handleCatalogue(
    request(
      {
        operation: "upsertStore",
        name: "Corner Store",
        address: "12 Main Road",
        location: { latitude: 12.6819, longitude: 78.6201 },
        isPublished: false,
        acceptingOrders: true,
      },
      "Bearer session-token",
      "store-key-3",
    ),
    dependencies({
      upsertStore: () => {
        calls += 1;
        return Promise.resolve({ responseBody: {}, responseStatus: 200 });
      },
    }),
  );

  assertEquals(calls, 0);
  assertEquals(invalidLocation.status, 400);
  assertEquals(unpublishedOrdering.status, 400);
});

Deno.test("category upsert normalizes input without trusting a store ID", async () => {
  let recorded: UpsertCategoryInput | undefined;
  const response = await handleCatalogue(
    request(
      {
        operation: "upsertCategory",
        storeId,
        categoryId,
        name: "  Snacks   and Drinks  ",
        displayOrder: 4,
        isActive: true,
      },
      "Bearer session-token",
      "category-key-1",
    ),
    dependencies({
      upsertCategory: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: category, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.categoryId, categoryId);
  assertEquals(recorded?.name, "Snacks and Drinks");
  assertEquals(recorded?.displayOrder, 4);
  assertEquals(recorded?.isActive, true);
  assertEquals(recorded?.idempotencyKey, "category-key-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
  assertEquals("storeId" in (recorded ?? {}), false);
});

Deno.test("product upsert forwards integer price and server-owned restriction state", async () => {
  let recorded: UpsertProductInput | undefined;
  const response = await handleCatalogue(
    request(
      {
        operation: "upsertProduct",
        accountId: otherAccountId,
        storeId,
        productId,
        categoryId,
        name: "  Lime   Soda  ",
        description: "  Freshly   bottled  ",
        unitLabel: "  750   ml  ",
        price: { paise: 12500 },
        imageObjectPath: `merchant/${accountId}/lime-soda.jpg`,
        availability: "in_stock",
        catalogueKind: "general",
        restrictedApprovalState: "approved",
        isActive: true,
      },
      "Bearer session-token",
      "product-key-1",
    ),
    dependencies({
      upsertProduct: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: product, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.productId, productId);
  assertEquals(recorded?.categoryId, categoryId);
  assertEquals(recorded?.name, "Lime Soda");
  assertEquals(recorded?.description, "Freshly bottled");
  assertEquals(recorded?.unitLabel, "750 ml");
  assertEquals(recorded?.pricePaise, 12500);
  assertEquals(recorded?.imageObjectPath, `merchant/${accountId}/lime-soda.jpg`);
  assertEquals(recorded?.availability, "in_stock");
  assertEquals(recorded?.catalogueKind, "general");
  assertEquals(recorded?.isActive, true);
  assertEquals(recorded?.idempotencyKey, "product-key-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
  assertEquals("restrictedApprovalState" in (recorded ?? {}), false);
  assertEquals("storeId" in (recorded ?? {}), false);
});

Deno.test("product upsert rejects another merchant image path", async () => {
  let calls = 0;
  const response = await handleCatalogue(
    request(
      {
        operation: "upsertProduct",
        categoryId,
        name: "Lime Soda",
        description: null,
        unitLabel: "750 ml",
        price: { paise: 12500 },
        imageObjectPath: `merchant/${otherAccountId}/lime-soda.jpg`,
        availability: "in_stock",
        catalogueKind: "general",
        isActive: true,
      },
      "Bearer session-token",
      "product-key-2",
    ),
    dependencies({
      upsertProduct: () => {
        calls += 1;
        return Promise.resolve({ responseBody: {}, responseStatus: 200 });
      },
    }),
  );

  assertEquals(calls, 0);
  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "validation_failed");
});

Deno.test("merchant snapshot uses only the authenticated merchant", async () => {
  let requestedAccountId: string | undefined;
  const response = await handleCatalogue(
    request(
      { operation: "merchantSnapshot", accountId: otherAccountId },
      "Bearer session-token",
    ),
    dependencies({
      getMerchantCatalogue: (id) => {
        requestedAccountId = id;
        return Promise.resolve({ responseBody: snapshot, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(requestedAccountId, accountId);
  assertEquals(await jsonBody(response), snapshot);
});

Deno.test("customer browse forwards authenticated customer and valid location", async () => {
  let recorded: { accountId: string; latitude: number; longitude: number } | undefined;
  const response = await handleCatalogue(
    request(
      {
        operation: "browse",
        accountId: otherAccountId,
        location: { latitude: 12.6819, longitude: 78.6201 },
      },
      "Bearer session-token",
    ),
    dependencies({
      browseCatalogue: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: snapshot, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accountId,
    latitude: 12.6819,
    longitude: 78.6201,
  });
});

Deno.test("catalogue dependency failures do not leak details", async () => {
  const response = await handleCatalogue(
    request({ operation: "merchantSnapshot" }, "Bearer session-token"),
    dependencies({
      getMerchantCatalogue: () => Promise.reject(new Error("private schema unavailable")),
    }),
  );

  assertEquals(response.status, 500);
  assertEquals(await jsonBody(response), {
    error: {
      code: "internal_error",
      message: "The catalogue request could not be processed.",
    },
  });
});

const accountId = "22222222-2222-4222-8222-222222222222";
const otherAccountId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const storeId = "33333333-3333-4333-8333-333333333333";
const categoryId = "44444444-4444-4444-8444-444444444444";
const productId = "55555555-5555-4555-8555-555555555555";
const serviceZoneId = "66666666-6666-4666-8666-666666666666";

const store = {
  storeId,
  name: "Corner Store",
  address: "12 Main Road",
  location: { latitude: 12.6819, longitude: 78.6201 },
  serviceZoneId,
  isPublished: true,
  acceptingOrders: true,
};
const category = {
  categoryId,
  storeId,
  name: "Snacks and Drinks",
  displayOrder: 4,
  isActive: true,
};
const product = {
  productId,
  storeId,
  categoryId,
  name: "Lime Soda",
  description: "Freshly bottled",
  unitLabel: "750 ml",
  price: { paise: 12500 },
  imageObjectPath: `merchant/${accountId}/lime-soda.jpg`,
  availability: "in_stock" as const,
  catalogueKind: "general" as const,
  restrictedApprovalState: "not_applicable" as const,
  isActive: true,
};
const snapshot: CatalogueSnapshot = {
  serviceZoneId,
  stores: [store],
  categories: [category],
  products: [product],
};

function dependencies(
  overrides: Partial<CatalogueDependencies> = {},
): CatalogueDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId })),
    upsertStore: overrides.upsertStore ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
    upsertCategory: overrides.upsertCategory ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
    upsertProduct: overrides.upsertProduct ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
    getMerchantCatalogue: overrides.getMerchantCatalogue ??
      (() => Promise.resolve({ responseBody: snapshot, responseStatus: 200 })),
    browseCatalogue: overrides.browseCatalogue ??
      (() => Promise.resolve({ responseBody: snapshot, responseStatus: 200 })),
  };
}

function request(
  body: unknown,
  authorization?: string,
  idempotencyKey?: string,
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request("http://localhost/functions/v1/catalogue", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function jsonBody(response: Response) {
  return await response.json();
}
