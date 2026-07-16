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
  | "account_already_exists"
  | "idempotency_conflict"
  | "access_denied"
  | "evidence_url_unavailable"
  | "internal_error";

export type ApiError = { error: { code: ApiErrorCode; message: string } };

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
