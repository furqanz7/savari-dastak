import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyBearerUser } from "../_shared/auth.ts";
import {
  handleCatalogue,
  type UpsertCategoryInput,
  type UpsertProductInput,
  type UpsertStoreInput,
} from "./handler.ts";

const serviceClient = createClient(
  requiredEnv("SUPABASE_URL"),
  requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

Deno.serve((request) =>
  handleCatalogue(request, {
    authenticateBearer: verifyBearerUser,
    upsertStore,
    upsertCategory,
    upsertProduct,
    getMerchantCatalogue,
    browseCatalogue,
  })
);

async function upsertStore(input: UpsertStoreInput) {
  const { data, error } = await serviceClient.rpc("upsert_merchant_store", {
    p_account_id: input.accountId,
    p_name: input.name,
    p_address: input.address,
    p_latitude: input.latitude,
    p_longitude: input.longitude,
    p_is_published: input.isPublished,
    p_accepting_orders: input.acceptingOrders,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "upsert_merchant_store");
}

async function upsertCategory(input: UpsertCategoryInput) {
  const { data, error } = await serviceClient.rpc("upsert_catalogue_category", {
    p_account_id: input.accountId,
    p_category_id: input.categoryId,
    p_name: input.name,
    p_display_order: input.displayOrder,
    p_is_active: input.isActive,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "upsert_catalogue_category");
}

async function upsertProduct(input: UpsertProductInput) {
  const { data, error } = await serviceClient.rpc("upsert_catalogue_product", {
    p_account_id: input.accountId,
    p_product_id: input.productId,
    p_category_id: input.categoryId,
    p_name: input.name,
    p_description: input.description,
    p_unit_label: input.unitLabel,
    p_price_paise: input.pricePaise,
    p_image_object_path: input.imageObjectPath,
    p_availability: input.availability,
    p_catalogue_kind: input.catalogueKind,
    p_is_active: input.isActive,
    p_idempotency_key: input.idempotencyKey,
    p_request_digest: input.requestDigest,
  });
  if (error) throw error;
  return rpcResponse(data, "upsert_catalogue_product");
}

async function getMerchantCatalogue(accountId: string) {
  const { data, error } = await serviceClient.rpc("get_merchant_catalogue", {
    p_account_id: accountId,
  });
  if (error) throw error;
  return rpcResponse(data, "get_merchant_catalogue");
}

async function browseCatalogue(input: {
  accountId: string;
  latitude: number;
  longitude: number;
}) {
  const { data, error } = await serviceClient.rpc("browse_catalogue", {
    p_account_id: input.accountId,
    p_latitude: input.latitude,
    p_longitude: input.longitude,
  });
  if (error) throw error;
  return rpcResponse(data, "browse_catalogue");
}

function rpcResponse(data: unknown, functionName: string) {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row || !("response_body" in row) || typeof row.response_status !== "number") {
    throw new Error(`${functionName} returned an invalid response`);
  }
  return {
    responseBody: row.response_body,
    responseStatus: row.response_status,
  };
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
