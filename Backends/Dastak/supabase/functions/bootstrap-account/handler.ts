import { corsPreflight, json } from "../_shared/http.ts";

export type AuthenticateBearer = (
  bearerToken: string,
) => Promise<{
  accountId: string;
  oauthProviders?: Array<"apple" | "google">;
}>;

export type BootstrapAccountInput = {
  accountId: string;
  displayName: string;
  phoneNumber: string;
  idempotencyKey: string;
  requestDigest: string;
};

export type BootstrapAccount = (
  input: BootstrapAccountInput,
) => Promise<{
  responseBody: unknown;
  responseStatus: number;
}>;

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  bootstrapAccount: BootstrapAccount;
};

type NormalizedBootstrapBody = {
  displayName: string;
  phoneNumber: string;
};

const e164Pattern = /^\+[1-9][0-9]{7,14}$/;

export async function handleBootstrapAccount(
  request: Request,
  dependencies: Dependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.match(/^Bearer\s+\S+$/)) {
    return json(
      {
        error: {
          code: "authentication_required",
          message: "A valid bearer token is required.",
        },
      },
      401,
    );
  }

  let user: {
    accountId: string;
    oauthProviders?: Array<"apple" | "google">;
  };
  try {
    user = await dependencies.authenticateBearer(authorization);
  } catch {
    return json(
      {
        error: {
          code: "authentication_required",
          message: "A valid bearer token is required.",
        },
      },
      401,
    );
  }

  if (!user.oauthProviders?.length) {
    return json(
      {
        error: {
          code: "oauth_identity_required",
          message: "Continue with Apple or Google before completing your profile.",
        },
      },
      403,
    );
  }

  const idempotencyKey = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  if (!idempotencyKey) {
    return validationError("X-Idempotency-Key is required.");
  }

  const body = await parseBody(request);
  if (!body.ok) {
    return validationError("A JSON body with displayName and phoneNumber is required.");
  }

  const normalized = normalizeBody(body.value);
  if (!normalized.ok) {
    return normalized.response;
  }

  try {
    const result = await dependencies.bootstrapAccount({
      accountId: user.accountId,
      displayName: normalized.value.displayName,
      phoneNumber: normalized.value.phoneNumber,
      idempotencyKey,
      requestDigest: await canonicalBootstrapDigest(normalized.value),
    });

    return json(result.responseBody, result.responseStatus);
  } catch (_error) {
    return json(
      {
        error: {
          code: "internal_error",
          message: "The account could not be bootstrapped.",
        },
      },
      500,
    );
  }
}

export async function canonicalBootstrapDigest(
  body: NormalizedBootstrapBody,
) {
  const bytes = new TextEncoder().encode(
    JSON.stringify({
      displayName: body.displayName,
      phoneNumber: body.phoneNumber,
    }),
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function parseBody(request: Request) {
  try {
    const value = await request.json();
    return { ok: true as const, value };
  } catch {
    return { ok: false as const };
  }
}

function normalizeBody(value: unknown):
  | { ok: true; value: NormalizedBootstrapBody }
  | { ok: false; response: Response } {
  if (!value || typeof value !== "object") {
    return { ok: false, response: validationError("Request body is required.") };
  }

  const displayName = "displayName" in value ? value.displayName : undefined;
  const phoneNumber = "phoneNumber" in value ? value.phoneNumber : undefined;

  if (typeof displayName !== "string") {
    return { ok: false, response: validationError("displayName is required.") };
  }

  if (typeof phoneNumber !== "string") {
    return { ok: false, response: invalidPhoneNumber() };
  }

  const normalizedName = displayName.trim().replace(/\s+/g, " ");
  if (normalizedName.length < 1 || normalizedName.length > 80) {
    return { ok: false, response: validationError("displayName is required.") };
  }

  const normalizedPhone = phoneNumber.trim();
  if (!e164Pattern.test(normalizedPhone)) {
    return { ok: false, response: invalidPhoneNumber() };
  }

  return {
    ok: true,
    value: {
      displayName: normalizedName,
      phoneNumber: normalizedPhone,
    },
  };
}

function validationError(message: string) {
  return json({ error: { code: "validation_failed", message } }, 400);
}

function invalidPhoneNumber() {
  return json(
    {
      error: {
        code: "invalid_phone_number",
        message: "phoneNumber must be a valid E.164 number.",
      },
    },
    400,
  );
}
