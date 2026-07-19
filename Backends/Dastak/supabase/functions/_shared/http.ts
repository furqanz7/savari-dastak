export type ApiErrorCode =
  | "authentication_required"
  | "invalid_application"
  | "validation_failed"
  | "invalid_phone_number"
  | "profile_required"
  | "evidence_not_found"
  | "merchant_access_exists"
  | "merchant_application_pending"
  | "merchant_application_not_found"
  | "merchant_application_reviewed"
  | "delivery_partner_access_exists"
  | "delivery_partner_application_pending"
  | "delivery_partner_application_not_found"
  | "delivery_partner_application_reviewed"
  | "outside_service_area"
  | "store_required"
  | "catalogue_name_conflict"
  | "catalogue_category_not_found"
  | "catalogue_product_not_found"
  | "catalogue_image_not_found"
  | "pricing_unavailable"
  | "store_unavailable"
  | "catalogue_changed"
  | "quote_unavailable"
  | "order_not_found"
  | "invalid_order_transition"
  | "payment_amount_mismatch"
  | "account_already_exists"
  | "idempotency_conflict"
  | "access_denied"
  | "evidence_url_unavailable"
  | "internal_error";

export type ApiError = { error: { code: ApiErrorCode; message: string } };

export const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type, x-idempotency-key",
};

export const corsPreflight = (request: Request) =>
  request.method === "OPTIONS"
    ? new Response(null, { status: 204, headers: corsHeaders })
    : undefined;

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
