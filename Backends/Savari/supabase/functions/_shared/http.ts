export type ApiErrorCode =
  | "authentication_required"
  | "validation_failed"
  | "invalid_phone_number"
  | "account_already_exists"
  | "idempotency_conflict"
  | "access_denied"
  | "outside_service_area"
  | "maps_unavailable"
  | "quote_invalid"
  | "quote_expired"
  | "active_ride_exists"
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
    headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8" },
  });
