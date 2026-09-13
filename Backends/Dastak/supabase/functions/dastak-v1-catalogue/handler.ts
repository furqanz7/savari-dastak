import { corsPreflight, json } from "../_shared/http.ts";
import { V1RequestError } from "../_shared/v1-rpc.ts";

export type V1Actor = { accountId: string; accessToken: string };
export type V1CatalogueDependencies = {
  authenticateBearer: (authorization: string) => Promise<V1Actor>;
  customerCatalogue: (input: {
    accessToken: string;
    query: string | null;
    categoryId: string | null;
    subcategoryId: string | null;
    limit: number;
    afterName: string | null;
    afterSkuId: string | null;
  }) => Promise<unknown>;
  customerRestaurants: (input: {
    accessToken: string;
    query: string | null;
    limit: number;
  }) => Promise<unknown>;
  adminSnapshot: (
    input: { accessToken: string; skuLimit: number },
  ) => Promise<unknown>;
  adminTaxonomy: (
    input: { accessToken: string },
  ) => Promise<unknown>;
  adminPage: (input: {
    accessToken: string;
    query: string | null;
    categoryTypeId: string | null;
    categoryId: string | null;
    subcategoryId: string | null;
    status: string | null;
    qaStatus: string | null;
    limit: number;
    afterName: string | null;
    afterSkuId: string | null;
  }) => Promise<unknown>;
  adminCatalogueAssets: (input: {
    accessToken: string;
    skuId: string;
  }) => Promise<unknown>;
  prepareAdminCatalogueAsset: (input: {
    actorId: string;
    skuId: string;
    expectedAssetVersion: number;
    mimeType: string;
    byteSize: number;
    sourceType: string;
    sourceReference: string;
    reason: string;
    idempotencyKey: string;
  }) => Promise<unknown>;
  finalizeAdminCatalogueAsset: (input: {
    actorId: string;
    skuId: string;
    assetId: string;
    expectedAssetVersion: number;
    checksumSha256: string;
    mimeType: string;
    byteSize: number;
    widthPixels: number;
    heightPixels: number;
    reason: string;
    idempotencyKey: string;
  }) => Promise<unknown>;
  promoteAdminCataloguePrimary: (input: {
    actorId: string;
    skuId: string;
    assetId: string;
    expectedPrimaryAssetId: string | null;
    expectedAssetVersion: number;
    reason: string;
    idempotencyKey: string;
  }) => Promise<unknown>;
  removeAdminCatalogueAsset: (input: {
    actorId: string;
    skuId: string;
    assetId: string;
    expectedAssetVersion: number;
    reason: string;
    idempotencyKey: string;
  }) => Promise<unknown>;
  storeAdminCatalogueAsset: (input: {
    objectPath: string;
    bytes: Uint8Array;
    mimeType: string;
    checksumSha256: string;
  }) => Promise<void>;
  deleteAdminCatalogueAsset: (input: { objectPath: string }) => Promise<void>;
  prepareGovernedMedia: (input: {
    actorId: string; entityType: string; entityId: string; expectedMediaVersion: number;
    mimeType: string; byteSize: number; sourceReference: string; reason: string; idempotencyKey: string;
  }) => Promise<unknown>;
  finalizeGovernedMedia: (input: {
    actorId: string; entityType: string; entityId: string; assetId: string; expectedMediaVersion: number;
    checksumSha256: string; mimeType: string; byteSize: number; widthPixels: number; heightPixels: number;
    reason: string; idempotencyKey: string;
  }) => Promise<unknown>;
  merchantSnapshot: (input: {
    accessToken: string;
    branchId: string | null;
    limit: number;
  }) => Promise<unknown>;
  merchantRestaurantMenu: (input: {
    accessToken: string;
    branchId: string | null;
  }) => Promise<unknown>;
  importCatalogue: (input: {
    accessToken: string;
    idempotencyKey: string;
    catalogue: Record<string, unknown>;
  }) => Promise<unknown>;
  updateSku: (input: {
    accessToken: string;
    skuId: string;
    idempotencyKey: string;
    expectedVersion: number;
    patch: Record<string, unknown>;
  }) => Promise<unknown>;
  updateMerchantSelection: (input: {
    accessToken: string;
    branchId: string;
    skuId: string;
    selected: boolean;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  updateMerchantSelections: (input: {
    accessToken: string;
    branchId: string;
    selections: Array<{
      skuId: string;
      selected: boolean;
      expectedVersion: number;
      stockQuantity?: number;
    }>;
    idempotencyKey: string;
  }) => Promise<unknown>;
  updateBranchOperationalState: (input: {
    accessToken: string;
    branchId: string;
    isOpen: boolean;
    acceptingOrders: boolean;
    expectedVersion: number;
    idempotencyKey: string;
  }) => Promise<unknown>;
  upsertRestaurantMenuEntity: (input: {
    accessToken: string;
    branchId: string;
    entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION";
    entityId: string | null;
    expectedVersion: number;
    payload: Record<string, unknown>;
    idempotencyKey: string;
  }) => Promise<unknown>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleV1Catalogue(
  request: Request,
  dependencies: V1CatalogueDependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();

  let actor: V1Actor;
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  if (request.headers.get("content-type")?.toLowerCase().includes("multipart/form-data")) {
    try {
      const copy = request.clone();
      const form = await copy.formData();
      return form.get("operation") === "uploadGovernedMedia"
        ? await uploadGovernedMedia(request, actor, dependencies)
        : await uploadAdminCatalogueAsset(request, actor, dependencies);
    } catch (error) {
      return requestFailure(error);
    }
  }

  const body = await parseBody(request);
  if (!body || typeof body.operation !== "string") return validationError();

  try {
    switch (body.operation) {
      case "customerCatalogue":
        return await customerCatalogue(body, actor, dependencies);
      case "customerRestaurants": {
        const query = optionalText(body.query, 80);
        const parsedLimit = optionalInteger(body.limit, 1, 100);
        if (
          query === undefined ||
          (body.limit !== null && body.limit !== undefined &&
            parsedLimit === undefined)
        ) {
          return validationError();
        }
        return json(
          await dependencies.customerRestaurants({
            accessToken: actor.accessToken,
            query,
            limit: parsedLimit ?? 50,
          }),
        );
      }
      case "adminSnapshot": {
        const parsedLimit = optionalInteger(body.skuLimit, 1, 1000);
        if (
          body.skuLimit !== null && body.skuLimit !== undefined &&
          parsedLimit === undefined
        ) {
          return validationError();
        }
        const skuLimit = parsedLimit ?? 1000;
        const [snapshot, taxonomy] = await Promise.all([
          dependencies.adminSnapshot({
            accessToken: actor.accessToken,
            skuLimit,
          }),
          dependencies.adminTaxonomy({ accessToken: actor.accessToken }),
        ]);
        const snapshotRecord = record(snapshot);
        const taxonomyRecord = record(taxonomy);
        if (!snapshotRecord || !taxonomyRecord) {
          throw new Error("invalid Admin catalogue projection");
        }
        return json({ ...snapshotRecord, ...taxonomyRecord });
      }
      case "adminMetadata": {
        // The paginated SKU browser is authoritative. Fetch one bounded row so
        // the existing summary projection can provide counts/config/branches,
        // then deliberately omit SKU data from the metadata response.
        const [snapshot, taxonomy] = await Promise.all([
          dependencies.adminSnapshot({ accessToken: actor.accessToken, skuLimit: 1 }),
          dependencies.adminTaxonomy({ accessToken: actor.accessToken }),
        ]);
        const snapshotRecord = record(snapshot);
        const taxonomyRecord = record(taxonomy);
        if (!snapshotRecord || !taxonomyRecord) {
          throw new Error("invalid Admin catalogue metadata projection");
        }
        return json({ ...snapshotRecord, ...taxonomyRecord, skus: [] });
      }
      case "adminCataloguePage":
        return await adminCataloguePage(body, actor, dependencies);
      case "adminCatalogueAssets": {
        const skuId = requiredUUID(body.skuId);
        if (!skuId) return validationError();
        return json(
          await dependencies.adminCatalogueAssets({
            accessToken: actor.accessToken,
            skuId,
          }),
        );
      }
      case "promoteAdminCataloguePrimary":
        return await promoteAdminCataloguePrimary(request, body, actor, dependencies);
      case "removeAdminCatalogueAsset":
        return await removeAdminCatalogueAsset(request, body, actor, dependencies);
      case "merchantSnapshot": {
        const branchId = optionalUUID(body.branchId);
        const parsedLimit = optionalInteger(body.limit, 1, 5000);
        if (
          branchId === undefined ||
          (body.limit !== null && body.limit !== undefined &&
            parsedLimit === undefined)
        ) {
          return validationError();
        }
        return json(
          await dependencies.merchantSnapshot({
            accessToken: actor.accessToken,
            branchId,
            limit: parsedLimit ?? 5000,
          }),
        );
      }
      case "merchantRestaurantMenu": {
        const branchId = optionalUUID(body.branchId);
        if (branchId === undefined) return validationError();
        return json(
          await dependencies.merchantRestaurantMenu({
            accessToken: actor.accessToken,
            branchId,
          }),
        );
      }
      case "importCatalogue": {
        const idempotencyKey = requiredIdempotencyKey(request);
        const catalogue = record(body.catalogue);
        if (!idempotencyKey || !catalogue) return validationError();
        const result = await dependencies.importCatalogue({
          accessToken: actor.accessToken,
          idempotencyKey,
          catalogue,
        });
        return json(result);
      }
      case "updateSku":
        return await updateSku(request, body, actor, dependencies);
      case "updateMerchantSelection":
        return await updateMerchantSelection(
          request,
          body,
          actor,
          dependencies,
        );
      case "updateMerchantSelections":
        return await updateMerchantSelections(
          request,
          body,
          actor,
          dependencies,
        );
      case "updateBranchOperationalState":
        return await updateBranchOperationalState(
          request,
          body,
          actor,
          dependencies,
        );
      case "upsertRestaurantMenuEntity":
        return await upsertRestaurantMenuEntity(
          request,
          body,
          actor,
          dependencies,
        );
      default:
        return validationError();
    }
  } catch (error) {
    return requestFailure(error);
  }
}

async function uploadGovernedMedia(request: Request, actor: V1Actor, dependencies: V1CatalogueDependencies) {
  const idempotencyKey = requiredIdempotencyKey(request);
  let form: FormData;
  try { form = await request.formData(); } catch { return validationError(); }
  const entityType = requiredChoice(form.get("entityType"), ["CATEGORY_TYPE", "CATEGORY", "SUBCATEGORY", "RESTAURANT_BRANCH_BANNER", "RESTAURANT_MENU_ITEM"]);
  const entityId = requiredUUID(form.get("entityId"));
  const expectedMediaVersion = formInteger(form.get("expectedMediaVersion"), 1);
  const sourceReference = requiredFormText(form.get("sourceReference"), 3, 500);
  const reason = requiredFormText(form.get("reason"), 3, 500);
  const file = form.get("file");
  if (!idempotencyKey || !entityType || !entityId || expectedMediaVersion === undefined || !sourceReference || !reason || !(file instanceof File) || file.size < 1 || file.size > 5 * 1024 * 1024) return validationError();
  const bytes = new Uint8Array(await file.arrayBuffer());
  const inspected = inspectImage(bytes);
  if (!inspected || inspected.mimeType !== file.type) return validationError();
  const checksumSha256 = await sha256(bytes);
  const prepared = record(await dependencies.prepareGovernedMedia({ actorId: actor.accountId, entityType, entityId, expectedMediaVersion, mimeType: inspected.mimeType, byteSize: bytes.byteLength, sourceReference, reason, idempotencyKey: `${idempotencyKey}:prepare` }));
  const assetId = requiredUUID(prepared?.assetId);
  const imageKey = typeof prepared?.imageKey === "string" ? prepared.imageKey : undefined;
  const preparedVersion = optionalInteger(prepared?.mediaVersion, 1, Number.MAX_SAFE_INTEGER);
  const scope = entityType.startsWith("RESTAURANT_") ? "restaurant" : "taxonomy";
  const expectedPrefix = `canonical/${scope}/${entityType.toLowerCase()}/${entityId}/`;
  if (!assetId || !imageKey?.startsWith(expectedPrefix) || preparedVersion === undefined || !/^canonical\/(taxonomy|restaurant)\/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$/.test(imageKey)) throw new V1RequestError(500, "invalid_asset_contract", "The governed media preparation result was invalid.");
  await dependencies.storeAdminCatalogueAsset({ objectPath: imageKey, bytes, mimeType: inspected.mimeType, checksumSha256 });
  return json(await dependencies.finalizeGovernedMedia({ actorId: actor.accountId, entityType, entityId, assetId, expectedMediaVersion: preparedVersion, checksumSha256, mimeType: inspected.mimeType, byteSize: bytes.byteLength, widthPixels: inspected.width, heightPixels: inspected.height, reason, idempotencyKey: `${idempotencyKey}:finalize` }));
}

async function uploadAdminCatalogueAsset(
  request: Request,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return validationError();
  }
  if (form.get("operation") !== "uploadAdminCatalogueAsset") return validationError();
  const skuId = requiredUUID(form.get("skuId"));
  const expectedAssetVersion = formInteger(form.get("expectedAssetVersion"), 1);
  const sourceType = requiredChoice(form.get("sourceType"), [
    "MANUFACTURER",
    "BRAND",
    "AUTHORIZED_RETAILER",
    "DISTRIBUTOR",
    "OWNER_CAPTURE",
    "COMMODITY_STOCK",
    "OTHER",
  ]);
  const sourceReference = requiredFormText(form.get("sourceReference"), 3, 500);
  const reason = requiredFormText(form.get("reason"), 3, 500);
  const file = form.get("file");
  if (
    !idempotencyKey || !skuId || expectedAssetVersion === undefined || !sourceType ||
    !sourceReference || !reason || !(file instanceof File) || file.size < 1 ||
    file.size > 5 * 1024 * 1024
  ) return validationError();

  const bytes = new Uint8Array(await file.arrayBuffer());
  const inspected = inspectImage(bytes);
  if (!inspected || inspected.mimeType !== file.type) return validationError();
  const checksumSha256 = await sha256(bytes);
  const prepared = record(
    await dependencies.prepareAdminCatalogueAsset({
      actorId: actor.accountId,
      skuId,
      expectedAssetVersion,
      mimeType: inspected.mimeType,
      byteSize: bytes.byteLength,
      sourceType,
      sourceReference,
      reason,
      idempotencyKey: `${idempotencyKey}:prepare`,
    }),
  );
  const assetId = requiredUUID(prepared?.assetId);
  const imageKey = typeof prepared?.imageKey === "string" ? prepared.imageKey : undefined;
  const preparedVersion = optionalInteger(prepared?.assetVersion, 1, Number.MAX_SAFE_INTEGER);
  const extension = inspected.mimeType === "image/png"
    ? "png"
    : inspected.mimeType === "image/webp"
    ? "webp"
    : "jpg";
  const expectedPath = assetId ? `canonical/admin/${skuId}/${assetId}.${extension}` : "";
  if (!assetId || !imageKey || imageKey !== expectedPath || preparedVersion === undefined) {
    throw new V1RequestError(
      500,
      "invalid_asset_contract",
      "The catalogue asset preparation result was invalid.",
    );
  }
  await dependencies.storeAdminCatalogueAsset({
    objectPath: imageKey,
    bytes,
    mimeType: inspected.mimeType,
    checksumSha256,
  });
  return json(
    await dependencies.finalizeAdminCatalogueAsset({
      actorId: actor.accountId,
      skuId,
      assetId,
      expectedAssetVersion: preparedVersion,
      checksumSha256,
      mimeType: inspected.mimeType,
      byteSize: bytes.byteLength,
      widthPixels: inspected.width,
      heightPixels: inspected.height,
      reason,
      idempotencyKey: `${idempotencyKey}:finalize`,
    }),
  );
}

async function promoteAdminCataloguePrimary(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const skuId = requiredUUID(body.skuId);
  const assetId = requiredUUID(body.assetId);
  const expectedPrimaryAssetId = optionalUUID(body.expectedPrimaryAssetId);
  const expectedAssetVersion = optionalInteger(
    body.expectedAssetVersion,
    1,
    Number.MAX_SAFE_INTEGER,
  );
  const reason = requiredText(body.reason, 3, 500);
  if (
    !idempotencyKey || !skuId || !assetId || expectedPrimaryAssetId === undefined ||
    expectedAssetVersion === undefined || !reason
  ) return validationError();
  return json(
    await dependencies.promoteAdminCataloguePrimary({
      actorId: actor.accountId,
      skuId,
      assetId,
      expectedPrimaryAssetId,
      expectedAssetVersion,
      reason,
      idempotencyKey,
    }),
  );
}

async function removeAdminCatalogueAsset(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const skuId = requiredUUID(body.skuId);
  const assetId = requiredUUID(body.assetId);
  const expectedAssetVersion = optionalInteger(
    body.expectedAssetVersion,
    1,
    Number.MAX_SAFE_INTEGER,
  );
  const reason = requiredText(body.reason, 3, 500);
  if (!idempotencyKey || !skuId || !assetId || expectedAssetVersion === undefined || !reason) {
    return validationError();
  }
  const result = record(
    await dependencies.removeAdminCatalogueAsset({
      actorId: actor.accountId,
      skuId,
      assetId,
      expectedAssetVersion,
      reason,
      idempotencyKey,
    }),
  );
  const objectPath = typeof result?.storageObjectPath === "string"
    ? result.storageObjectPath
    : undefined;
  if (
    !objectPath ||
    !/^canonical\/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$/.test(objectPath)
  ) {
    throw new V1RequestError(
      500,
      "invalid_asset_contract",
      "The catalogue asset removal result was invalid.",
    );
  }
  await dependencies.deleteAdminCatalogueAsset({ objectPath });
  const safeResult = { ...(result ?? {}) };
  delete safeResult.storageObjectPath;
  return json(safeResult);
}

async function adminCataloguePage(
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const query = optionalText(body.query, 80);
  const categoryTypeId = optionalUUID(body.categoryTypeId);
  const categoryId = optionalUUID(body.categoryId);
  const subcategoryId = optionalUUID(body.subcategoryId);
  const status = optionalChoice(body.status, ["DRAFT", "ACTIVE", "INACTIVE"]);
  const qaStatus = optionalChoice(body.qaStatus, [
    "PENDING",
    "NEEDS_REVIEW",
    "VERIFIED",
    "REJECTED",
  ]);
  const parsedLimit = optionalInteger(body.limit, 1, 250);
  const cursor = record(body.cursor);
  const afterName = cursor ? optionalText(cursor.name, 160) : null;
  const afterSkuId = cursor ? optionalUUID(cursor.skuId) : null;
  if (
    query === undefined || categoryTypeId === undefined ||
    categoryId === undefined ||
    subcategoryId === undefined || status === undefined ||
    qaStatus === undefined ||
    (body.limit !== null && body.limit !== undefined &&
      parsedLimit === undefined) ||
    (body.cursor !== null && body.cursor !== undefined &&
      cursor === undefined) ||
    (cursor !== undefined && (!afterName || !afterSkuId))
  ) return validationError();
  return json(
    await dependencies.adminPage({
      accessToken: actor.accessToken,
      query,
      categoryTypeId,
      categoryId,
      subcategoryId,
      status,
      qaStatus,
      limit: parsedLimit ?? 100,
      afterName: afterName ?? null,
      afterSkuId: afterSkuId ?? null,
    }),
  );
}

async function upsertRestaurantMenuEntity(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  const entityId = optionalUUID(body.entityId);
  const expectedVersion = optionalInteger(
    body.expectedVersion,
    0,
    Number.MAX_SAFE_INTEGER,
  );
  const payload = record(body.payload);
  const entityType = body.entityType;
  if (
    !idempotencyKey || !branchId || entityId === undefined ||
    expectedVersion === undefined || !payload ||
    !["CATEGORY", "ITEM", "OPTION_GROUP", "OPTION"].includes(String(entityType))
  ) {
    return validationError();
  }
  return json(
    await dependencies.upsertRestaurantMenuEntity({
      accessToken: actor.accessToken,
      branchId,
      entityType: entityType as "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION",
      entityId,
      expectedVersion,
      payload,
      idempotencyKey,
    }),
  );
}

async function updateMerchantSelection(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  const skuId = requiredUUID(body.skuId);
  const expectedVersion = optionalInteger(
    body.expectedVersion,
    0,
    Number.MAX_SAFE_INTEGER,
  );
  if (
    !idempotencyKey || !branchId || !skuId || expectedVersion === undefined ||
    typeof body.selected !== "boolean"
  ) return validationError();
  return json(
    await dependencies.updateMerchantSelection({
      accessToken: actor.accessToken,
      branchId,
      skuId,
      selected: body.selected,
      expectedVersion,
      idempotencyKey,
    }),
  );
}

async function updateMerchantSelections(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  if (
    !idempotencyKey || idempotencyKey.length > 120 || !branchId ||
    !Array.isArray(body.selections) || body.selections.length < 1 ||
    body.selections.length > 1000
  ) return validationError();

  const selections = body.selections.map((value) => {
    const item = record(value);
    if (!item) return undefined;
    const skuId = requiredUUID(item.skuId);
    const expectedVersion = optionalInteger(
      item.expectedVersion,
      0,
      Number.MAX_SAFE_INTEGER,
    );
    if (!skuId || expectedVersion === undefined || typeof item.selected !== "boolean") {
      return undefined;
    }
    const stockQuantity = item.stockQuantity === undefined
      ? undefined
      : optionalInteger(item.stockQuantity, 0, 1_000_000);
    if (
      item.stockQuantity !== undefined &&
      (stockQuantity === undefined || (stockQuantity === 0 && item.selected))
    ) return undefined;
    return {
      skuId,
      selected: item.selected,
      expectedVersion,
      ...(stockQuantity === undefined ? {} : { stockQuantity }),
    };
  });
  if (
    selections.some((item) => item === undefined) ||
    new Set(selections.map((item) => item?.skuId)).size !== selections.length
  ) return validationError();

  return json(
    await dependencies.updateMerchantSelections({
      accessToken: actor.accessToken,
      branchId,
      selections: selections as Array<{
        skuId: string;
        selected: boolean;
        expectedVersion: number;
      }>,
      idempotencyKey,
    }),
  );
}

async function updateBranchOperationalState(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const branchId = requiredUUID(body.branchId);
  const expectedVersion = optionalInteger(
    body.expectedVersion,
    0,
    Number.MAX_SAFE_INTEGER,
  );
  if (
    !idempotencyKey || !branchId || expectedVersion === undefined ||
    typeof body.isOpen !== "boolean" ||
    typeof body.acceptingOrders !== "boolean"
  ) {
    return validationError();
  }
  return json(
    await dependencies.updateBranchOperationalState({
      accessToken: actor.accessToken,
      branchId,
      isOpen: body.isOpen,
      acceptingOrders: body.acceptingOrders,
      expectedVersion,
      idempotencyKey,
    }),
  );
}

async function customerCatalogue(
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const query = optionalText(body.query, 80);
  const categoryId = optionalUUID(body.categoryId);
  const subcategoryId = optionalUUID(body.subcategoryId);
  const parsedLimit = optionalInteger(body.limit, 1, 250);
  const limit = parsedLimit ?? 100;
  const cursor = record(body.cursor);
  const afterName = cursor ? optionalText(cursor.name, 160) : null;
  const afterSkuId = cursor ? optionalUUID(cursor.skuId) : null;
  if (
    query === undefined || categoryId === undefined ||
    subcategoryId === undefined ||
    (body.limit !== null && body.limit !== undefined &&
      parsedLimit === undefined) ||
    (body.cursor !== null && body.cursor !== undefined &&
      cursor === undefined) ||
    (cursor !== undefined && (!afterName || !afterSkuId))
  ) {
    return validationError();
  }
  const result = await dependencies.customerCatalogue({
    accessToken: actor.accessToken,
    query,
    categoryId,
    subcategoryId,
    limit,
    afterName: afterName ?? null,
    afterSkuId: afterSkuId ?? null,
  });
  return json(result);
}

async function updateSku(
  request: Request,
  body: Record<string, unknown>,
  actor: V1Actor,
  dependencies: V1CatalogueDependencies,
) {
  const idempotencyKey = requiredIdempotencyKey(request);
  const skuId = requiredUUID(body.skuId);
  const expectedVersion = optionalInteger(
    body.expectedVersion,
    1,
    Number.MAX_SAFE_INTEGER,
  );
  const patch = record(body.patch);
  if (
    !idempotencyKey || !skuId || !expectedVersion || !patch ||
    Object.keys(patch).length === 0
  ) {
    return validationError();
  }
  const result = await dependencies.updateSku({
    accessToken: actor.accessToken,
    skuId,
    idempotencyKey,
    expectedVersion,
    patch,
  });
  return json(result);
}

async function parseBody(
  request: Request,
): Promise<Record<string, unknown> | undefined> {
  try {
    const source = await request.text();
    if (source.length === 0 || source.length > 2_000_000) return undefined;
    return record(JSON.parse(source));
  } catch {
    return undefined;
  }
}

function optionalText(
  value: unknown,
  maximum: number,
): string | null | undefined {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : undefined;
}

function requiredText(value: unknown, minimum: number, maximum: number) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= minimum && normalized.length <= maximum ? normalized : undefined;
}

function requiredFormText(value: FormDataEntryValue | null, minimum: number, maximum: number) {
  return requiredText(typeof value === "string" ? value : undefined, minimum, maximum);
}

function requiredChoice(value: FormDataEntryValue | null, choices: readonly string[]) {
  const normalized = typeof value === "string" ? value.trim().toUpperCase() : "";
  return choices.includes(normalized) ? normalized : undefined;
}

function formInteger(value: FormDataEntryValue | null, minimum: number) {
  if (typeof value !== "string" || !/^\d+$/.test(value)) return undefined;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= minimum ? parsed : undefined;
}

type InspectedImage = {
  mimeType: "image/jpeg" | "image/png" | "image/webp";
  width: number;
  height: number;
};

export function inspectImage(bytes: Uint8Array): InspectedImage | undefined {
  if (
    bytes.length >= 24 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
    bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    const width = readU32BE(bytes, 16);
    const height = readU32BE(bytes, 20);
    return validDimensions(width, height) ? { mimeType: "image/png", width, height } : undefined;
  }
  if (bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP") {
    const dimensions = webpDimensions(bytes);
    return dimensions ? { mimeType: "image/webp", ...dimensions } : undefined;
  }
  if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    const dimensions = jpegDimensions(bytes);
    return dimensions ? { mimeType: "image/jpeg", ...dimensions } : undefined;
  }
  return undefined;
}

function jpegDimensions(bytes: Uint8Array) {
  let offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = bytes[offset + 1];
    if (marker === 0xd8 || marker === 0xd9) {
      offset += 2;
      continue;
    }
    const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2 || offset + 2 + length > bytes.length) return undefined;
    if (
      [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(
        marker,
      )
    ) {
      const height = (bytes[offset + 5] << 8) | bytes[offset + 6];
      const width = (bytes[offset + 7] << 8) | bytes[offset + 8];
      return validDimensions(width, height) ? { width, height } : undefined;
    }
    offset += 2 + length;
  }
  return undefined;
}

function webpDimensions(bytes: Uint8Array) {
  const chunk = ascii(bytes, 12, 4);
  if (chunk === "VP8X" && bytes.length >= 30) {
    const width = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
    const height = 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16);
    return validDimensions(width, height) ? { width, height } : undefined;
  }
  if (chunk === "VP8L" && bytes.length >= 25 && bytes[20] === 0x2f) {
    const bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    const width = (bits & 0x3fff) + 1;
    const height = ((bits >> 14) & 0x3fff) + 1;
    return validDimensions(width, height) ? { width, height } : undefined;
  }
  if (
    chunk === "VP8 " && bytes.length >= 30 && bytes[23] === 0x9d && bytes[24] === 0x01 &&
    bytes[25] === 0x2a
  ) {
    const width = ((bytes[27] << 8) | bytes[26]) & 0x3fff;
    const height = ((bytes[29] << 8) | bytes[28]) & 0x3fff;
    return validDimensions(width, height) ? { width, height } : undefined;
  }
  return undefined;
}

function validDimensions(width: number, height: number) {
  return width >= 1 && width <= 20000 && height >= 1 && height <= 20000;
}

function readU32BE(bytes: Uint8Array, offset: number) {
  return ((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) |
    bytes[offset + 3]) >>> 0;
}

function ascii(bytes: Uint8Array, offset: number, length: number) {
  return String.fromCharCode(...bytes.slice(offset, offset + length));
}

async function sha256(bytes: Uint8Array) {
  const input = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  const hash = await crypto.subtle.digest("SHA-256", input);
  return [...new Uint8Array(hash)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

function optionalChoice(
  value: unknown,
  choices: readonly string[],
): string | null | undefined {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toUpperCase();
  return choices.includes(normalized) ? normalized : undefined;
}

function requiredUUID(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function optionalUUID(value: unknown): string | null | undefined {
  if (value === null || value === undefined) return null;
  return requiredUUID(value);
}

function optionalInteger(value: unknown, minimum: number, maximum: number) {
  if (value === null || value === undefined) return undefined;
  return typeof value === "number" && Number.isSafeInteger(value) &&
      value >= minimum &&
      value <= maximum
    ? value
    : undefined;
}

function requiredIdempotencyKey(request: Request) {
  const key = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  return key.length >= 1 && key.length <= 200 ? key : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function authenticationRequired() {
  return json({
    error: {
      code: "authentication_required",
      message: "A valid bearer token is required.",
    },
  }, 401);
}

function validationError() {
  return json({
    error: {
      code: "validation_failed",
      message: "The catalogue request is invalid.",
    },
  }, 400);
}

function requestFailure(error: unknown) {
  if (error instanceof V1RequestError) {
    return json(
      { error: { code: error.code, message: error.message } },
      error.status,
    );
  }
  return json({
    error: {
      code: "internal_error",
      message: "The catalogue request could not be processed.",
    },
  }, 500);
}
