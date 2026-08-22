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
    adminSnapshot: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_admin_catalogue_snapshot", {
        p_sku_limit: input.skuLimit,
      }),
    importCatalogue: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_import_catalogue", {
        p_idempotency_key: input.idempotencyKey,
        p_catalogue: input.catalogue,
      }),
    updateSku: (input) =>
      callAuthenticatedRPC(input.accessToken, "dastak_v1_update_catalogue_sku", {
        p_sku_id: input.skuId,
        p_idempotency_key: input.idempotencyKey,
        p_expected_version: input.expectedVersion,
        p_patch: input.patch,
      }),
  })
);
