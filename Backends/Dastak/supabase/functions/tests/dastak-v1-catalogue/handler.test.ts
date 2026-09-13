import { assertEquals } from "jsr:@std/assert";
import { V1RequestError } from "../../_shared/v1-rpc.ts";
import {
  handleV1Catalogue,
  inspectImage,
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
    dependencies({
      authenticateBearer: () => Promise.reject(new Error("invalid")),
    }),
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

Deno.test("V1 Restaurant discovery and merchant menu commands preserve authenticated scope", async () => {
  let discovery: unknown;
  let menuUpdate: unknown;
  const restaurants = await handleV1Catalogue(
    request({ operation: "customerRestaurants", query: "  Cafe  ", limit: 20 }),
    dependencies({
      customerRestaurants: (input) => {
        discovery = input;
        return Promise.resolve({ restaurants: [] });
      },
    }),
  );
  const updated = await handleV1Catalogue(
    request({
      operation: "upsertRestaurantMenuEntity",
      branchId: categoryId,
      entityType: "ITEM",
      entityId: skuId,
      expectedVersion: 3,
      payload: {
        categoryId: subcategoryId,
        name: "Masala Dosa",
        basePricePaise: 8000,
      },
    }, "restaurant-menu-1"),
    dependencies({
      upsertRestaurantMenuEntity: (input) => {
        menuUpdate = input;
        return Promise.resolve({ entityId: skuId });
      },
    }),
  );
  assertEquals(restaurants.status, 200);
  assertEquals(discovery, {
    accessToken: actor.accessToken,
    query: "Cafe",
    limit: 20,
  });
  assertEquals(updated.status, 200);
  assertEquals(menuUpdate, {
    accessToken: actor.accessToken,
    branchId: categoryId,
    entityType: "ITEM",
    entityId: skuId,
    expectedVersion: 3,
    payload: {
      categoryId: subcategoryId,
      name: "Masala Dosa",
      basePricePaise: 8000,
    },
    idempotencyKey: "restaurant-menu-1",
  });
});

Deno.test("V1 Restaurant menu mutation rejects unsupported entities without calling RPC", async () => {
  let calls = 0;
  const response = await handleV1Catalogue(
    request({
      operation: "upsertRestaurantMenuEntity",
      branchId: categoryId,
      entityType: "STORE_PRODUCT",
      expectedVersion: 0,
      payload: { name: "Legacy" },
    }, "restaurant-menu-invalid"),
    dependencies({
      upsertRestaurantMenuEntity: () => {
        calls += 1;
        return Promise.resolve({});
      },
    }),
  );
  assertEquals(response.status, 400);
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
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    idempotencyKey: "import-1",
    catalogue,
  });
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

Deno.test("V1 Admin catalogue page preserves safe filters and a complete cursor", async () => {
  let recorded: unknown;
  const response = await handleV1Catalogue(
    request({
      operation: "adminCataloguePage",
      query: "  Aashirvaad   Atta  ",
      categoryTypeId,
      categoryId,
      subcategoryId,
      status: "active",
      qaStatus: "needs_review",
      limit: 80,
      cursor: { name: "Whole Wheat Flour", skuId },
      sourcePayload: { private: true },
    }),
    dependencies({
      adminPage: (input) => {
        recorded = input;
        return Promise.resolve({ skus: [], hasMore: false, nextCursor: null });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    query: "Aashirvaad Atta",
    categoryTypeId,
    categoryId,
    subcategoryId,
    status: "ACTIVE",
    qaStatus: "NEEDS_REVIEW",
    limit: 80,
    afterName: "Whole Wheat Flour",
    afterSkuId: skuId,
  });
});

Deno.test("V1 Admin catalogue page rejects malformed filters before database access", async () => {
  let calls = 0;
  const deps = dependencies({
    adminPage: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const status = await handleV1Catalogue(
    request({ operation: "adminCataloguePage", status: "DELETED" }),
    deps,
  );
  const qa = await handleV1Catalogue(
    request({ operation: "adminCataloguePage", qaStatus: "SKIPPED" }),
    deps,
  );
  const cursor = await handleV1Catalogue(
    request({ operation: "adminCataloguePage", cursor: { name: "Milk" } }),
    deps,
  );
  const limit = await handleV1Catalogue(
    request({ operation: "adminCataloguePage", limit: 251 }),
    deps,
  );
  assertEquals([status.status, qa.status, cursor.status, limit.status, calls], [
    400,
    400,
    400,
    400,
    0,
  ]);
});

Deno.test("V1 merchant stock rejects invalid counts before database access", async () => {
  let calls = 0;
  const deps = dependencies({
    updateMerchantSelections: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  for (const stockQuantity of [-1, 1.5, 1_000_001, 0]) {
    const response = await handleV1Catalogue(
      request({
        operation: "updateMerchantSelections",
        branchId: categoryId,
        selections: [{ skuId, selected: true, expectedVersion: 0, stockQuantity }],
      }, "invalid-stock"),
      deps,
    );
    assertEquals(response.status, 400);
  }
  assertEquals(calls, 0);
});

Deno.test("V1 merchant catalogue exposes canonical selection and branch controls", async () => {
  let selection: unknown;
  let selections: unknown;
  let operation: unknown;
  const merchantSnapshot = await handleV1Catalogue(
    request({
      operation: "merchantSnapshot",
      branchId: categoryId,
      limit: 500,
    }),
    dependencies({
      merchantSnapshot: (input) => Promise.resolve({ recorded: input }),
    }),
  );
  assertEquals((await body(merchantSnapshot)).recorded, {
    accessToken: actor.accessToken,
    branchId: categoryId,
    limit: 500,
  });

  const completeMerchantSnapshot = await handleV1Catalogue(
    request({
      operation: "merchantSnapshot",
      branchId: categoryId,
    }),
    dependencies({
      merchantSnapshot: (input) => Promise.resolve({ recorded: input }),
    }),
  );
  assertEquals((await body(completeMerchantSnapshot)).recorded, {
    accessToken: actor.accessToken,
    branchId: categoryId,
    limit: 5000,
  });

  let invalidSnapshotCalls = 0;
  const invalidMerchantSnapshot = await handleV1Catalogue(
    request({
      operation: "merchantSnapshot",
      branchId: categoryId,
      limit: 5001,
    }),
    dependencies({
      merchantSnapshot: () => {
        invalidSnapshotCalls += 1;
        return Promise.resolve({});
      },
    }),
  );
  assertEquals(invalidMerchantSnapshot.status, 400);
  assertEquals(invalidSnapshotCalls, 0);

  const selectionResponse = await handleV1Catalogue(
    request({
      operation: "updateMerchantSelection",
      branchId: categoryId,
      skuId,
      selected: true,
      expectedVersion: 0,
    }, "selection-key"),
    dependencies({
      updateMerchantSelection: (input) => {
        selection = input;
        return Promise.resolve({ selected: true });
      },
    }),
  );
  assertEquals(selectionResponse.status, 200);
  assertEquals(selection, {
    accessToken: actor.accessToken,
    branchId: categoryId,
    skuId,
    selected: true,
    expectedVersion: 0,
    idempotencyKey: "selection-key",
  });

  const selectionsResponse = await handleV1Catalogue(
    request({
      operation: "updateMerchantSelections",
      branchId: categoryId,
      selections: [
        { skuId, selected: true, expectedVersion: 0, stockQuantity: 12 },
        { skuId: categoryId, selected: false, expectedVersion: 4, stockQuantity: 0 },
      ],
    }, "selections-key"),
    dependencies({
      updateMerchantSelections: (input) => {
        selections = input;
        return Promise.resolve({ updatedCount: 2 });
      },
    }),
  );
  assertEquals(selectionsResponse.status, 200);
  assertEquals(selections, {
    accessToken: actor.accessToken,
    branchId: categoryId,
    selections: [
      { skuId, selected: true, expectedVersion: 0, stockQuantity: 12 },
      { skuId: categoryId, selected: false, expectedVersion: 4, stockQuantity: 0 },
    ],
    idempotencyKey: "selections-key",
  });

  const operationResponse = await handleV1Catalogue(
    request({
      operation: "updateBranchOperationalState",
      branchId: categoryId,
      isOpen: true,
      acceptingOrders: true,
      expectedVersion: 0,
    }, "operation-key"),
    dependencies({
      updateBranchOperationalState: (input) => {
        operation = input;
        return Promise.resolve({ acceptingOrders: true });
      },
    }),
  );
  assertEquals(operationResponse.status, 200);
  assertEquals(operation, {
    accessToken: actor.accessToken,
    branchId: categoryId,
    isOpen: true,
    acceptingOrders: true,
    expectedVersion: 0,
    idempotencyKey: "operation-key",
  });
});

Deno.test("V1 catalogue exposes safe database conflict errors", async () => {
  const response = await handleV1Catalogue(
    request({ operation: "adminSnapshot" }),
    dependencies({
      adminSnapshot: () =>
        Promise.reject(
          new V1RequestError(
            403,
            "access_denied",
            "This account cannot perform that action.",
          ),
        ),
    }),
  );
  assertEquals(response.status, 403);
  assertEquals(await body(response), {
    error: {
      code: "access_denied",
      message: "This account cannot perform that action.",
    },
  });
});

Deno.test("V1 Admin snapshot composes canonical taxonomy without exposing another write path", async () => {
  let taxonomyInput: unknown;
  const response = await handleV1Catalogue(
    request({ operation: "adminSnapshot", skuLimit: 250 }),
    dependencies({
      adminSnapshot: () =>
        Promise.resolve({
          skus: [],
          skuCount: 0,
          truncated: false,
          configuration: [],
          branches: [],
        }),
      adminTaxonomy: (input) => {
        taxonomyInput = input;
        return Promise.resolve({
          categoryTypes: [{ id: categoryTypeId, name: "Groceries" }],
          categories: [{ id: categoryId, categoryTypeId }],
          subcategories: [{ id: subcategoryId, categoryId }],
          brands: [],
        });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(taxonomyInput, { accessToken: actor.accessToken });
  assertEquals((await body(response)).categoryTypes, [
    { id: categoryTypeId, name: "Groceries" },
  ]);
});

Deno.test("V1 Admin metadata avoids bulk SKU loading while retaining taxonomy", async () => {
  let snapshotInput: unknown;
  const response = await handleV1Catalogue(
    request({ operation: "adminMetadata" }),
    dependencies({
      adminSnapshot: (input) => {
        snapshotInput = input;
        return Promise.resolve({
          skus: [{ id: skuId }],
          skuCount: 4_200,
          truncated: true,
          configuration: [],
          branches: [],
        });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(snapshotInput, { accessToken: actor.accessToken, skuLimit: 1 });
  const payload = await body(response);
  assertEquals(payload.skus, []);
  assertEquals(payload.skuCount, 4_200);
});

Deno.test("V1 catalogue hides unexpected dependency details", async () => {
  const response = await handleV1Catalogue(
    request({ operation: "adminSnapshot" }),
    dependencies({
      adminSnapshot: () => Promise.reject(new Error("private table leaked")),
    }),
  );
  assertEquals(response.status, 500);
  assertEquals(
    (await body(response)).error.message,
    "The catalogue request could not be processed.",
  );
});

Deno.test("Admin catalogue assets remain caller-bound and exact-SKU scoped", async () => {
  let recorded: unknown;
  const response = await handleV1Catalogue(
    request({ operation: "adminCatalogueAssets", skuId }),
    dependencies({
      adminCatalogueAssets: (input) => {
        recorded = input;
        return Promise.resolve({ sku: { id: skuId }, assets: [] });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, { accessToken: actor.accessToken, skuId });
});

Deno.test("Admin catalogue upload verifies bytes and preserves one logical operation", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const png = minimalPng(320, 240);
  const form = new FormData();
  form.set("operation", "uploadAdminCatalogueAsset");
  form.set("skuId", skuId);
  form.set("expectedAssetVersion", "7");
  form.set("sourceType", "MANUFACTURER");
  form.set("sourceReference", "Manufacturer product page reviewed by catalogue team");
  form.set("reason", "Correct exact-SKU product imagery");
  form.set("file", new File([png], "sku.png", { type: "image/png" }));
  const assetId = "66666666-6666-4666-8666-666666666666";
  const response = await handleV1Catalogue(
    multipartRequest(form, "asset-upload-key"),
    dependencies({
      prepareAdminCatalogueAsset: (input) => {
        calls.push({ step: "prepare", ...input });
        return Promise.resolve({
          assetId,
          imageKey: `canonical/admin/${skuId}/${assetId}.png`,
          assetVersion: 8,
        });
      },
      storeAdminCatalogueAsset: (input) => {
        calls.push({ step: "store", objectPath: input.objectPath, mimeType: input.mimeType });
        return Promise.resolve();
      },
      finalizeAdminCatalogueAsset: (input) => {
        calls.push({ step: "finalize", ...input });
        return Promise.resolve({ assetVersion: 9, asset: { id: assetId } });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(calls[0].actorId, actor.accountId);
  assertEquals(calls[0].idempotencyKey, "asset-upload-key:prepare");
  assertEquals(calls[1], {
    step: "store",
    objectPath: `canonical/admin/${skuId}/${assetId}.png`,
    mimeType: "image/png",
  });
  assertEquals(calls[2].expectedAssetVersion, 8);
  assertEquals(calls[2].widthPixels, 320);
  assertEquals(calls[2].heightPixels, 240);
  assertEquals(calls[2].idempotencyKey, "asset-upload-key:finalize");
});

Deno.test("Admin catalogue upload rejects MIME spoofing before privileged work", async () => {
  let calls = 0;
  const form = new FormData();
  form.set("operation", "uploadAdminCatalogueAsset");
  form.set("skuId", skuId);
  form.set("expectedAssetVersion", "1");
  form.set("sourceType", "BRAND");
  form.set("sourceReference", "Reviewed brand asset library");
  form.set("reason", "Launch readiness");
  form.set("file", new File(["not an image"], "fake.png", { type: "image/png" }));
  const response = await handleV1Catalogue(
    multipartRequest(form, "asset-spoof"),
    dependencies({
      prepareAdminCatalogueAsset: () => {
        calls += 1;
        return Promise.resolve({});
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(calls, 0);
});

Deno.test("governed media upload verifies bytes and preserves exact entity scope", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const png = minimalPng(1440, 720);
  const form = new FormData();
  form.set("operation", "uploadGovernedMedia");
  form.set("entityType", "RESTAURANT_BRANCH_BANNER");
  form.set("entityId", categoryId);
  form.set("expectedMediaVersion", "3");
  form.set("sourceReference", "Merchant-owned restaurant banner capture");
  form.set("reason", "Publish reviewed restaurant presentation media");
  form.set("file", new File([png], "banner.png", { type: "image/png" }));
  const assetId = "66666666-6666-4666-8666-666666666666";
  const response = await handleV1Catalogue(multipartRequest(form, "restaurant-banner-once"), dependencies({
    prepareGovernedMedia: (input) => {
      calls.push({ step: "prepare", ...input });
      return Promise.resolve({ assetId, imageKey: `canonical/restaurant/restaurant_branch_banner/${categoryId}/${assetId}.png`, mediaVersion: 3 });
    },
    storeAdminCatalogueAsset: (input) => { calls.push({ step: "store", objectPath: input.objectPath }); return Promise.resolve(); },
    finalizeGovernedMedia: (input) => { calls.push({ step: "finalize", ...input }); return Promise.resolve({ assetId, mediaVersion: 4 }); },
  }));
  assertEquals(response.status, 200);
  assertEquals(calls[0].entityType, "RESTAURANT_BRANCH_BANNER");
  assertEquals(calls[0].entityId, categoryId);
  assertEquals(calls[0].idempotencyKey, "restaurant-banner-once:prepare");
  assertEquals(calls[1].objectPath, `canonical/restaurant/restaurant_branch_banner/${categoryId}/${assetId}.png`);
  assertEquals(calls[2].widthPixels, 1440);
  assertEquals(calls[2].heightPixels, 720);
  assertEquals(calls[2].idempotencyKey, "restaurant-banner-once:finalize");
});

Deno.test("governed media refuses a server path outside its exact entity", async () => {
  const form = new FormData();
  form.set("operation", "uploadGovernedMedia");
  form.set("entityType", "CATEGORY");
  form.set("entityId", categoryId);
  form.set("expectedMediaVersion", "1");
  form.set("sourceReference", "Reviewed taxonomy artwork");
  form.set("reason", "Set one-time category art");
  form.set("file", new File([minimalPng(400, 400)], "category.png", { type: "image/png" }));
  const response = await handleV1Catalogue(multipartRequest(form, "taxonomy-path-check"), dependencies({
    prepareGovernedMedia: () => Promise.resolve({ assetId: skuId, imageKey: `canonical/taxonomy/category/${otherAccountId}/${skuId}.png`, mediaVersion: 1 }),
  }));
  assertEquals(response.status, 500);
  assertEquals((await body(response)).error.code, "invalid_asset_contract");
});

Deno.test("Admin primary promotion and removal forward actor scope and hide storage paths", async () => {
  let promoted: unknown;
  let removedPath = "";
  const assetId = "66666666-6666-4666-8666-666666666666";
  const promote = await handleV1Catalogue(
    request({
      operation: "promoteAdminCataloguePrimary",
      skuId,
      assetId,
      expectedPrimaryAssetId: null,
      expectedAssetVersion: 4,
      reason: "Correct primary image",
    }, "promote-key"),
    dependencies({
      promoteAdminCataloguePrimary: (input) => {
        promoted = input;
        return Promise.resolve({ primaryAssetId: assetId });
      },
    }),
  );
  const remove = await handleV1Catalogue(
    request({
      operation: "removeAdminCatalogueAsset",
      skuId,
      assetId,
      expectedAssetVersion: 5,
      reason: "Remove unused image",
    }, "remove-key"),
    dependencies({
      removeAdminCatalogueAsset: () =>
        Promise.resolve({ assetId, storageObjectPath: "canonical/imported/legacy-gallery.jpg" }),
      deleteAdminCatalogueAsset: ({ objectPath }) => {
        removedPath = objectPath;
        return Promise.resolve();
      },
    }),
  );
  assertEquals(promote.status, 200);
  assertEquals((promoted as { actorId: string }).actorId, actor.accountId);
  assertEquals(remove.status, 200);
  assertEquals(removedPath, "canonical/imported/legacy-gallery.jpg");
  assertEquals((await body(remove)).storageObjectPath, undefined);
});

Deno.test("Admin catalogue removal refuses a non-catalogue storage path", async () => {
  let deletionCalls = 0;
  const assetId = "66666666-6666-4666-8666-666666666666";
  const response = await handleV1Catalogue(
    request({
      operation: "removeAdminCatalogueAsset",
      skuId,
      assetId,
      expectedAssetVersion: 5,
      reason: "Remove unused image",
    }, "remove-private-key"),
    dependencies({
      removeAdminCatalogueAsset: () =>
        Promise.resolve({ assetId, storageObjectPath: "private/customer/avatar.jpg" }),
      deleteAdminCatalogueAsset: () => {
        deletionCalls += 1;
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 500);
  assertEquals(deletionCalls, 0);
});

Deno.test("Image inspection accepts supported headers and rejects unrelated bytes", () => {
  assertEquals(inspectImage(minimalPng(16, 9)), { mimeType: "image/png", width: 16, height: 9 });
  assertEquals(inspectImage(new TextEncoder().encode("not an image")), undefined);
});

const url = "http://localhost/functions/v1/dastak-v1-catalogue";
const categoryTypeId = "00000000-0000-4000-8000-000000000001";
const categoryId = "11111111-1111-4111-8111-111111111111";
const subcategoryId = "22222222-2222-4222-8222-222222222222";
const skuId = "33333333-3333-4333-8333-333333333333";
const otherAccountId = "44444444-4444-4444-8444-444444444444";
const actor = {
  accountId: "55555555-5555-4555-8555-555555555555",
  accessToken: "verified-access-token",
};
const snapshot = {
  categories: [],
  subcategories: [],
  skus: [],
  nextCursor: null,
};

function dependencies(
  overrides: Partial<V1CatalogueDependencies> = {},
): V1CatalogueDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve(actor)),
    customerCatalogue: overrides.customerCatalogue ??
      (() => Promise.resolve(snapshot)),
    customerRestaurants: overrides.customerRestaurants ??
      (() => Promise.resolve({ restaurants: [] })),
    adminSnapshot: overrides.adminSnapshot ?? (() => Promise.resolve(snapshot)),
    adminTaxonomy: overrides.adminTaxonomy ??
      (() =>
        Promise.resolve({
          categoryTypes: [],
          categories: [],
          subcategories: [],
          brands: [],
        })),
    adminPage: overrides.adminPage ??
      (() => Promise.resolve({ skus: [], hasMore: false })),
    adminCatalogueAssets: overrides.adminCatalogueAssets ?? (() => Promise.resolve({})),
    prepareAdminCatalogueAsset: overrides.prepareAdminCatalogueAsset ?? (() => Promise.resolve({})),
    finalizeAdminCatalogueAsset: overrides.finalizeAdminCatalogueAsset ??
      (() => Promise.resolve({})),
    promoteAdminCataloguePrimary: overrides.promoteAdminCataloguePrimary ??
      (() => Promise.resolve({})),
    removeAdminCatalogueAsset: overrides.removeAdminCatalogueAsset ?? (() => Promise.resolve({})),
    storeAdminCatalogueAsset: overrides.storeAdminCatalogueAsset ?? (() => Promise.resolve()),
    deleteAdminCatalogueAsset: overrides.deleteAdminCatalogueAsset ?? (() => Promise.resolve()),
    prepareGovernedMedia: overrides.prepareGovernedMedia ?? (() => Promise.resolve({})),
    finalizeGovernedMedia: overrides.finalizeGovernedMedia ?? (() => Promise.resolve({})),
    merchantSnapshot: overrides.merchantSnapshot ??
      (() => Promise.resolve(snapshot)),
    merchantRestaurantMenu: overrides.merchantRestaurantMenu ??
      (() => Promise.resolve({})),
    importCatalogue: overrides.importCatalogue ?? (() => Promise.resolve({})),
    updateSku: overrides.updateSku ?? (() => Promise.resolve({})),
    updateMerchantSelection: overrides.updateMerchantSelection ??
      (() => Promise.resolve({})),
    updateMerchantSelections: overrides.updateMerchantSelections ??
      (() => Promise.resolve({})),
    updateBranchOperationalState: overrides.updateBranchOperationalState ??
      (() => Promise.resolve({})),
    upsertRestaurantMenuEntity: overrides.upsertRestaurantMenuEntity ??
      (() => Promise.resolve({})),
  };
}

function multipartRequest(form: FormData, idempotencyKey: string) {
  return new Request(url, {
    method: "POST",
    headers: { authorization: "Bearer session", "X-Idempotency-Key": idempotencyKey },
    body: form,
  });
}

function minimalPng(width: number, height: number) {
  const bytes = new Uint8Array(24);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const view = new DataView(bytes.buffer);
  view.setUint32(16, width);
  view.setUint32(20, height);
  return bytes;
}

function request(
  payload: unknown,
  idempotencyKey?: string,
  authorization = "Bearer session",
) {
  const headers = new Headers({
    "content-type": "application/json",
    authorization,
  });
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request(url, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });
}

async function body(response: Response) {
  return await response.json();
}
