import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerSession } from "../_shared/auth.ts";
import { callAuthenticatedRPC, safeRPCError, V1RequestError } from "../_shared/v1-rpc.ts";
import { handleV1Catalogue } from "./handler.ts";

const catalogueBucket = "dastak-catalogue";
const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

async function callServiceRPC(functionName: string, parameters: Record<string, unknown>) {
  const { data, error } = await serviceClient.rpc(functionName, parameters);
  if (error) throw safeRPCError(error);
  return data;
}

Deno.serve((request) =>
  handleV1Catalogue(request, {
    authenticateBearer: verifyBearerSession,
    customerCatalogue: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_customer_catalogue", {
        p_query: input.query,
        p_category_id: input.categoryId,
        p_subcategory_id: input.subcategoryId,
        p_limit: input.limit,
        p_after_name: input.afterName,
        p_after_sku_id: input.afterSkuId,
      }),
    customerRestaurants: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_customer_restaurants",
        {
          p_query: input.query,
          p_limit: input.limit,
        },
      ),
    adminSnapshot: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_admin_catalogue_snapshot",
        {
          p_sku_limit: input.skuLimit,
        },
      ),
    adminTaxonomy: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_catalogue_taxonomy_snapshot",
        {},
      ),
    adminPage: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_admin_catalogue_page",
        {
          p_query: input.query,
          p_category_type_id: input.categoryTypeId,
          p_category_id: input.categoryId,
          p_subcategory_id: input.subcategoryId,
          p_status: input.status,
          p_qa_status: input.qaStatus,
          p_limit: input.limit,
          p_after_name: input.afterName,
          p_after_sku_id: input.afterSkuId,
        },
      ),
    adminCatalogueAssets: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_admin_catalogue_sku_assets",
        { p_sku_id: input.skuId },
      ),
    prepareAdminCatalogueAsset: (input) =>
      callServiceRPC("dastak_v1_admin_prepare_catalogue_asset", {
        p_actor_id: input.actorId,
        p_sku_id: input.skuId,
        p_expected_asset_version: input.expectedAssetVersion,
        p_mime_type: input.mimeType,
        p_byte_size: input.byteSize,
        p_source_type: input.sourceType,
        p_source_reference: input.sourceReference,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
      }),
    finalizeAdminCatalogueAsset: (input) =>
      callServiceRPC("dastak_v1_admin_finalize_catalogue_asset", {
        p_actor_id: input.actorId,
        p_sku_id: input.skuId,
        p_asset_id: input.assetId,
        p_expected_asset_version: input.expectedAssetVersion,
        p_checksum_sha256: input.checksumSha256,
        p_mime_type: input.mimeType,
        p_byte_size: input.byteSize,
        p_width_pixels: input.widthPixels,
        p_height_pixels: input.heightPixels,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
      }),
    promoteAdminCataloguePrimary: (input) =>
      callServiceRPC("dastak_v1_admin_promote_catalogue_primary_asset", {
        p_actor_id: input.actorId,
        p_sku_id: input.skuId,
        p_asset_id: input.assetId,
        p_expected_primary_asset_id: input.expectedPrimaryAssetId,
        p_expected_asset_version: input.expectedAssetVersion,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
      }),
    removeAdminCatalogueAsset: (input) =>
      callServiceRPC("dastak_v1_admin_remove_catalogue_asset", {
        p_actor_id: input.actorId,
        p_sku_id: input.skuId,
        p_asset_id: input.assetId,
        p_expected_asset_version: input.expectedAssetVersion,
        p_reason: input.reason,
        p_idempotency_key: input.idempotencyKey,
      }),
    storeAdminCatalogueAsset: async (input) => {
      const storage = serviceClient.storage.from(catalogueBucket);
      const uploaded = await storage.upload(input.objectPath, input.bytes, {
        cacheControl: "31536000",
        contentType: input.mimeType,
        upsert: false,
      });
      if (uploaded.error && !/already exists|duplicate/i.test(uploaded.error.message)) {
        throw new V1RequestError(
          503,
          "storage_unavailable",
          "The catalogue image could not be stored safely.",
        );
      }
      const downloaded = await storage.download(input.objectPath);
      if (downloaded.error || !downloaded.data) {
        throw new V1RequestError(
          503,
          "storage_unavailable",
          "The stored catalogue image could not be verified.",
        );
      }
      const checksum = await sha256(new Uint8Array(await downloaded.data.arrayBuffer()));
      if (checksum !== input.checksumSha256) {
        throw new V1RequestError(
          409,
          "asset_storage_conflict",
          "A different object already occupies this governed asset path.",
        );
      }
    },
    deleteAdminCatalogueAsset: async (input) => {
      const { error } = await serviceClient.storage.from(catalogueBucket).remove([
        input.objectPath,
      ]);
      if (error) {
        throw new V1RequestError(
          503,
          "storage_unavailable",
          "The unused catalogue image could not be removed from storage.",
        );
      }
    },
    merchantSnapshot: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_merchant_canonical_catalogue_snapshot",
        {
          p_branch_id: input.branchId,
          p_limit: input.limit,
        },
      ),
    merchantRestaurantMenu: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_merchant_restaurant_menu",
        {
          p_branch_id: input.branchId,
        },
      ),
    importCatalogue: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_import_catalogue", {
        p_idempotency_key: input.idempotencyKey,
        p_catalogue: input.catalogue,
      }),
    updateSku: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_update_catalogue_sku",
        {
          p_sku_id: input.skuId,
          p_idempotency_key: input.idempotencyKey,
          p_expected_version: input.expectedVersion,
          p_patch: input.patch,
        },
      ),
    updateMerchantSelection: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_update_merchant_sku_selection",
        {
          p_branch_id: input.branchId,
          p_sku_id: input.skuId,
          p_selected: input.selected,
          p_expected_version: input.expectedVersion,
          p_idempotency_key: input.idempotencyKey,
        },
      ),
    updateMerchantSelections: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_update_merchant_sku_selections",
        {
          p_branch_id: input.branchId,
          p_selections: input.selections,
          p_idempotency_key: input.idempotencyKey,
        },
      ),
    updateBranchOperationalState: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_set_branch_operational_state",
        {
          p_branch_id: input.branchId,
          p_idempotency_key: input.idempotencyKey,
          p_expected_version: input.expectedVersion,
          p_is_open: input.isOpen,
          p_accepting_orders: input.acceptingOrders,
        },
      ),
    upsertRestaurantMenuEntity: (input) =>
      callAuthenticatedRPC(
        input.accessToken,
        "dastak_v1_upsert_restaurant_menu_entity",
        {
          p_branch_id: input.branchId,
          p_entity_type: input.entityType,
          p_entity_id: input.entityId,
          p_expected_version: input.expectedVersion,
          p_payload: input.payload,
          p_idempotency_key: input.idempotencyKey,
        },
      ),
  })
);

async function sha256(bytes: Uint8Array) {
  const input = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  const hash = await crypto.subtle.digest("SHA-256", input);
  return [...new Uint8Array(hash)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
