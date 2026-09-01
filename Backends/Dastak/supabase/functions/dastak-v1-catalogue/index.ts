import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { verifyBearerSession } from "../_shared/auth.ts";
import { callAuthenticatedRPC } from "../_shared/v1-rpc.ts";
import { handleV1Catalogue } from "./handler.ts";

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
