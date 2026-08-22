import { assertEquals } from "jsr:@std/assert";
import { V1RequestError } from "../../_shared/v1-rpc.ts";
import {
  handleV1Catalogue,
  type V1CatalogueDependencies,
} from "../../dastak-v1-catalogue/handler.ts";

Deno.test("V1 catalogue serves CORS preflight before authentication", async () => {
  let authCalls = 0;
  const response = await handleV1Catalogue(
    new Request(url, { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authCalls += 1;
        return Promise.resolve(actor);
      },
    }),
  );
  assertEquals(response.status, 204);
  assertEquals(authCalls, 0);
});

Deno.test("V1 catalogue authenticates before request validation", async () => {
  const response = await handleV1Catalogue(
    request({ operation: "unknown" }, "Bearer invalid"),
    dependencies({ authenticateBearer: () => Promise.reject(new Error("invalid")) }),
  );
  assertEquals(response.status, 401);
  assertEquals((await body(response)).error.code, "authentication_required");
});

Deno.test("V1 customer catalogue forwards only validated customer filters", async () => {
  let recorded: unknown;
  const response = await handleV1Catalogue(
    request({
      operation: "customerCatalogue",
      query: "  whole   milk ",
      categoryId,
      subcategoryId,
      limit: 75,
      cursor: { name: "Whole Milk", skuId },
      accountId: otherAccountId,
    }),
    dependencies({
      customerCatalogue: (input) => {
        recorded = input;
        return Promise.resolve(snapshot);
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    query: "whole milk",
    categoryId,
    subcategoryId,
    limit: 75,
    afterName: "Whole Milk",
    afterSkuId: skuId,
  });
  assertEquals(await body(response), snapshot);
});

Deno.test("V1 customer catalogue rejects incomplete cursors and invalid limits", async () => {
  let calls = 0;
  const deps = dependencies({
    customerCatalogue: () => {
      calls += 1;
      return Promise.resolve(snapshot);
    },
  });
  const cursor = await handleV1Catalogue(
    request({ operation: "customerCatalogue", cursor: { name: "Milk" } }),
    deps,
  );
  const limit = await handleV1Catalogue(
    request({ operation: "customerCatalogue", limit: 251 }),
    deps,
  );
  assertEquals(cursor.status, 400);
  assertEquals(limit.status, 400);
  assertEquals(calls, 0);
});

Deno.test("V1 catalogue import requires idempotency and forwards opaque catalogue data", async () => {
  let recorded: unknown;
  const catalogue = { categories: [{ slug: "groceries" }], skus: [] };
  const missingKey = await handleV1Catalogue(
    request({ operation: "importCatalogue", catalogue }, undefined),
    dependencies(),
  );
  const response = await handleV1Catalogue(
    request({ operation: "importCatalogue", catalogue }, "import-1"),
    dependencies({
      importCatalogue: (input) => {
        recorded = input;
        return Promise.resolve({ importId: skuId });
      },
    }),
  );
  assertEquals(missingKey.status, 400);
  assertEquals(response.status, 200);
  assertEquals(recorded, { accessToken: actor.accessToken, idempotencyKey: "import-1", catalogue });
});

Deno.test("V1 SKU update validates optimistic version and idempotency", async () => {
  let recorded: unknown;
  const response = await handleV1Catalogue(
    request({
      operation: "updateSku",
      skuId,
      expectedVersion: 4,
      patch: { sellingPricePaise: 6900, status: "ACTIVE" },
    }, "sku-update-1"),
    dependencies({
      updateSku: (input) => {
        recorded = input;
        return Promise.resolve({ id: skuId, version: 5 });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    skuId,
    idempotencyKey: "sku-update-1",
    expectedVersion: 4,
    patch: { sellingPricePaise: 6900, status: "ACTIVE" },
  });
});

Deno.test("V1 catalogue exposes safe database conflict errors", async () => {
  const response = await handleV1Catalogue(
    request({ operation: "adminSnapshot" }),
    dependencies({
      adminSnapshot: () =>
        Promise.reject(
          new V1RequestError(403, "access_denied", "This account cannot perform that action."),
        ),
    }),
  );
  assertEquals(response.status, 403);
  assertEquals(await body(response), {
    error: { code: "access_denied", message: "This account cannot perform that action." },
  });
});

Deno.test("V1 catalogue hides unexpected dependency details", async () => {
  const response = await handleV1Catalogue(
    request({ operation: "adminSnapshot" }),
    dependencies({ adminSnapshot: () => Promise.reject(new Error("private table leaked")) }),
  );
  assertEquals(response.status, 500);
  assertEquals(
    (await body(response)).error.message,
    "The catalogue request could not be processed.",
  );
});

const url = "http://localhost/functions/v1/dastak-v1-catalogue";
const categoryId = "11111111-1111-4111-8111-111111111111";
const subcategoryId = "22222222-2222-4222-8222-222222222222";
const skuId = "33333333-3333-4333-8333-333333333333";
const otherAccountId = "44444444-4444-4444-8444-444444444444";
const actor = {
  accountId: "55555555-5555-4555-8555-555555555555",
  accessToken: "verified-access-token",
};
const snapshot = { categories: [], subcategories: [], skus: [], nextCursor: null };

function dependencies(
  overrides: Partial<V1CatalogueDependencies> = {},
): V1CatalogueDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ?? (() => Promise.resolve(actor)),
    customerCatalogue: overrides.customerCatalogue ?? (() => Promise.resolve(snapshot)),
    adminSnapshot: overrides.adminSnapshot ?? (() => Promise.resolve(snapshot)),
    importCatalogue: overrides.importCatalogue ?? (() => Promise.resolve({})),
    updateSku: overrides.updateSku ?? (() => Promise.resolve({})),
  };
}

function request(payload: unknown, idempotencyKey?: string, authorization = "Bearer session") {
  const headers = new Headers({ "content-type": "application/json", authorization });
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request(url, { method: "POST", headers, body: JSON.stringify(payload) });
}

async function body(response: Response) {
  return await response.json();
}
