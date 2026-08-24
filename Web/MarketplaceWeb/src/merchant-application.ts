import type { SupabaseClient } from "@supabase/supabase-js";

type AuthenticatedInput = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
type EvidenceFile = { type: string; size: number };

export type MerchantApplicationResult = {
  applicationId: string;
  status: "pending";
};

export type MerchantApplicationSnapshot = {
  onboardingState: "not_applied" | "pending" | "approved" | "rejected";
  applicationId: string | null;
  businessName: string | null;
  businessAddress: string | null;
  evidenceObjectPath: string | null;
  reviewReason: string | null;
};

export type MerchantAccountState = MerchantApplicationSnapshot["onboardingState"] | "unavailable";

export class MerchantApplicationRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "MerchantApplicationRequestError";
  }
}

const maximumEvidenceBytes = 10 * 1024 * 1024;
const evidenceExtensions = new Map([
  ["application/pdf", "pdf"],
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isAcceptedEvidenceFile(file: EvidenceFile) {
  return evidenceExtensions.has(file.type) && file.size > 0 && file.size <= maximumEvidenceBytes;
}

export function evidenceObjectPath(accountId: string, contentType: string, uniqueId: string) {
  const extension = evidenceExtensions.get(contentType);
  if (!uuidPattern.test(accountId) || !uuidPattern.test(uniqueId) || !extension) {
    throw validationError();
  }
  return `merchant/${accountId.toLowerCase()}/${uniqueId.toLowerCase()}.${extension}`;
}

export async function uploadMerchantEvidence(
  client: SupabaseClient,
  accountId: string,
  file: File,
) {
  if (!isAcceptedEvidenceFile(file)) throw validationError("Choose a PDF, JPG or PNG file up to 10 MB.");
  const objectPath = evidenceObjectPath(accountId, file.type, crypto.randomUUID());
  const { error } = await client.storage.from("dastak-evidence").upload(objectPath, file, {
    cacheControl: "3600",
    contentType: file.type,
    upsert: false,
  });
  if (error) {
    throw new MerchantApplicationRequestError(
      "evidence_upload_failed",
      "The business document could not be uploaded. Try again.",
      0,
    );
  }
  return objectPath;
}

export async function getMerchantApplicationSnapshot(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
): Promise<MerchantApplicationSnapshot> {
  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/merchant-applications`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ operation: "selfSnapshot" }),
    });
  } catch {
    throw new MerchantApplicationRequestError(
      "network_error",
      "Dastak could not reach the merchant application service.",
      0,
    );
  }

  const payload = await response.json().catch(() => undefined);
  if (!response.ok) throw responseError(response.status, payload, "The merchant application could not be loaded.");
  const result = record(payload);
  const onboardingState = result?.onboardingState;
  if (!result || !["not_applied", "pending", "approved", "rejected"].includes(String(onboardingState))) {
    throw new MerchantApplicationRequestError("invalid_response", "Dastak received an invalid merchant application response.", 502);
  }
  return {
    onboardingState: onboardingState as MerchantApplicationSnapshot["onboardingState"],
    applicationId: nullableUUID(result.applicationId),
    businessName: nullableText(result.businessName, 120),
    businessAddress: nullableText(result.businessAddress, 300),
    evidenceObjectPath: nullableText(result.evidenceObjectPath, 500),
    reviewReason: nullableText(result.reviewReason, 500),
  };
}

export async function getMerchantAccountState(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
): Promise<MerchantAccountState> {
  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/resolve-app-access`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ application: "merchant" }),
    });
  } catch {
    throw new MerchantApplicationRequestError(
      "network_error",
      "Dastak could not verify Merchant access.",
      0,
    );
  }

  const payload = await response.json().catch(() => undefined);
  if (!response.ok) throw responseError(response.status, payload, "Merchant access could not be verified.");
  const route = record(payload)?.route;
  if (route === "active" || route === "suspended") return "approved";
  if (route === "pending_approval") return "pending";
  if (route === "access_denied") {
    const snapshot = await getMerchantApplicationSnapshot(input, fetcher);
    return snapshot.onboardingState === "approved" ? "unavailable" : snapshot.onboardingState;
  }
  if (route === "needs_profile" || route === "signed_out") return "unavailable";
  throw new MerchantApplicationRequestError("invalid_response", "Dastak received an invalid Merchant access response.", 502);
}

export async function submitMerchantApplication(
  input: AuthenticatedInput & {
    businessName: string;
    businessAddress: string;
    evidenceObjectPath: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
): Promise<MerchantApplicationResult> {
  const businessName = normalize(input.businessName);
  const businessAddress = normalize(input.businessAddress);
  if (
    businessName.length < 1 || businessName.length > 120 ||
    businessAddress.length < 1 || businessAddress.length > 300 ||
    !input.evidenceObjectPath
  ) {
    throw validationError();
  }

  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/merchant-applications`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
        "X-Idempotency-Key": input.idempotencyKey,
      },
      body: JSON.stringify({
        operation: "submit",
        businessName,
        businessAddress,
        evidenceObjectPath: input.evidenceObjectPath,
      }),
    });
  } catch {
    throw new MerchantApplicationRequestError(
      "network_error",
      "Dastak could not reach the merchant application service.",
      0,
    );
  }

  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    throw responseError(response.status, payload, "The merchant application could not be submitted.");
  }

  const result = record(payload);
  if (!result || !uuidPattern.test(String(result.applicationId)) || result.status !== "pending") {
    throw new MerchantApplicationRequestError(
      "invalid_response",
      "Dastak received an invalid merchant application response.",
      502,
    );
  }
  return { applicationId: String(result.applicationId).toLowerCase(), status: "pending" };
}

function normalize(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function text(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}

function nullableText(value: unknown, maximum: number) {
  return value === null || value === undefined ? null : text(value, maximum) ?? invalidSnapshot();
}

function nullableUUID(value: unknown) {
  if (value === null || value === undefined) return null;
  if (!uuidPattern.test(String(value))) return invalidSnapshot();
  return String(value).toLowerCase();
}

function invalidSnapshot(): never {
  throw new MerchantApplicationRequestError(
    "invalid_response",
    "Dastak received an invalid merchant application response.",
    502,
  );
}

function responseError(status: number, payload: unknown, fallback: string) {
  const error = record(record(payload)?.error);
  return new MerchantApplicationRequestError(
    text(error?.code, 80) ?? "application_unavailable",
    text(error?.message, 300) ?? fallback,
    status,
  );
}

function validationError(message = "Enter valid business details and choose a business document.") {
  return new MerchantApplicationRequestError("validation_failed", message, 400);
}
