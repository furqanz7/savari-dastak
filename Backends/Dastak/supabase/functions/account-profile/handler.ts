import { corsPreflight, json } from "../_shared/http.ts";
import { isValidDastakPhoneNumber } from "../_shared/phone.ts";

export type AccountProfile = {
  displayName: string;
  phoneNumber: string;
};

export type AccountProfileDependencies = {
  authenticateBearer: (bearerToken: string) => Promise<{
    accountId: string;
    accessToken: string;
    oauthAuthenticatedAt?: number;
    verifiedPhoneNumber?: string;
  }>;
  snapshotProfile: (accountId: string) => Promise<AccountProfile | null>;
  updateProfile: (
    accountId: string,
    profile: AccountProfile,
    verifiedPhoneNumber?: string,
  ) => Promise<AccountProfile | null>;
  snapshotIdentities: (accessToken: string) => Promise<unknown>;
  beginIdentityLink: (input: {
    accessToken: string;
    provider: "apple" | "google";
    idempotencyKey: string;
  }) => Promise<unknown>;
  exportAccount: (accountId: string) => Promise<unknown>;
  deleteAccount: (input: {
    accountId: string;
    accessToken: string;
    idempotencyKey: string;
    persona: DastakPersona;
  }) => Promise<{ alreadyDeleted?: boolean; identityRecoveryEligible?: boolean }>;
  now?: () => number;
};

type RequestBody =
  | { operation: "snapshot" }
  | { operation: "update"; displayName: string; phoneNumber: string }
  | { operation: "identitySnapshot" }
  | { operation: "beginIdentityLink"; provider: "apple" | "google" }
  | { operation: "export" }
  | { operation: "delete"; persona: DastakPersona };

export type DastakPersona = "CUSTOMER" | "MERCHANT" | "DELIVERY";

const deletionRecentAuthenticationSeconds = 10 * 60;

export async function handleAccountProfile(
  request: Request,
  dependencies: AccountProfileDependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  if (request.method !== "POST") {
    return json({ error: { code: "validation_failed", message: "POST is required." } }, 405);
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.match(/^Bearer\s+\S+$/)) {
    return authenticationRequired();
  }

  let actor: {
    accountId: string;
    accessToken: string;
    oauthAuthenticatedAt?: number;
    verifiedPhoneNumber?: string;
  };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await readBody(request);
  if (!body) {
    return json(
      { error: { code: "validation_failed", message: "A valid operation is required." } },
      400,
    );
  }

  try {
    switch (body.operation) {
      case "snapshot": {
        const profile = await dependencies.snapshotProfile(actor.accountId);
        return profile ? json({ profile }) : profileRequired();
      }
      case "update": {
        const profile = normalizeProfile(body.displayName, body.phoneNumber);
        if (profile instanceof Response) return profile;
        if (actor.verifiedPhoneNumber !== profile.phoneNumber) {
          return json({
            error: {
              code: "phone_verification_required",
              message: "Verify the new phone number before saving it.",
            },
          }, 409);
        }
        const updated = await dependencies.updateProfile(
          actor.accountId,
          profile,
          actor.verifiedPhoneNumber,
        );
        return updated ? json({ profile: updated }) : profileRequired();
      }
      case "identitySnapshot":
        return json(await dependencies.snapshotIdentities(actor.accessToken));
      case "beginIdentityLink": {
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!idempotencyKey) return validationError("X-Idempotency-Key is required.");
        return json(
          await dependencies.beginIdentityLink({
            accessToken: actor.accessToken,
            provider: body.provider,
            idempotencyKey,
          }),
        );
      }
      case "export": {
        const exported = await dependencies.exportAccount(actor.accountId);
        return json({
          export: exported,
          filename: `dastak-account-${actor.accountId}.json`,
        });
      }
      case "delete": {
        const idempotencyKey = requiredIdempotencyKey(request);
        if (!idempotencyKey) return validationError("X-Idempotency-Key is required.");
        if (
          !recentOAuthAuthentication(actor.oauthAuthenticatedAt, dependencies.now?.() ?? Date.now())
        ) {
          return json({
            error: {
              code: "reauthentication_required",
              message: "Verify with Apple or Google again before deleting your account.",
            },
          }, 428);
        }
        const result = await dependencies.deleteAccount({
          accountId: actor.accountId,
          accessToken: actor.accessToken,
          idempotencyKey,
          persona: body.persona,
        });
        return json({
          deleted: true,
          persona: body.persona,
          alreadyDeleted: result.alreadyDeleted === true,
        });
      }
    }
  } catch (error) {
    const message = safeOperationConflict(error);
    if (message) {
      return json({ error: { code: "persona_deletion_blocked", message } }, 409);
    }
    return json(
      { error: { code: "internal_error", message: "The account request could not be completed." } },
      500,
    );
  }
}

function normalizeProfile(displayName: string, phoneNumber: string): AccountProfile | Response {
  const normalizedName = displayName.trim().replace(/\s+/g, " ");
  if (normalizedName.length < 1 || normalizedName.length > 80) {
    return json({ error: { code: "validation_failed", message: "Enter a valid full name." } }, 400);
  }

  const normalizedPhone = phoneNumber.trim();
  if (!isValidDastakPhoneNumber(normalizedPhone)) {
    return json(
      {
        error: { code: "invalid_phone_number", message: "Enter a phone number with country code." },
      },
      400,
    );
  }
  return { displayName: normalizedName, phoneNumber: normalizedPhone };
}

async function readBody(request: Request): Promise<RequestBody | null> {
  try {
    const value = await request.json() as Record<string, unknown>;
    if (
      value.operation === "snapshot" || value.operation === "identitySnapshot" ||
      value.operation === "export"
    ) {
      return { operation: value.operation };
    }
    if (
      value.operation === "delete" &&
      (value.persona === "CUSTOMER" || value.persona === "MERCHANT" ||
        value.persona === "DELIVERY")
    ) {
      return { operation: value.operation, persona: value.persona };
    }
    if (
      value.operation === "beginIdentityLink" &&
      (value.provider === "apple" || value.provider === "google")
    ) {
      return { operation: value.operation, provider: value.provider };
    }
    if (
      value.operation === "update" &&
      typeof value.displayName === "string" &&
      typeof value.phoneNumber === "string"
    ) {
      return {
        operation: "update",
        displayName: value.displayName,
        phoneNumber: value.phoneNumber,
      };
    }
  } catch {
    // The typed validation response below covers malformed JSON.
  }
  return null;
}

function safeOperationConflict(error: unknown) {
  const message = error && typeof error === "object" && "message" in error &&
      typeof error.message === "string"
    ? error.message
    : "";
  return [
      "Complete or cancel active customer orders before deleting Customer.",
      "Complete active merchant fulfilments before deleting Merchant.",
      "Complete or release the active delivery before deleting Delivery Partner.",
    ].includes(message)
    ? message
    : undefined;
}

function recentOAuthAuthentication(timestamp: number | undefined, nowMilliseconds: number) {
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) return false;
  const age = nowMilliseconds / 1_000 - timestamp;
  return age >= 0 && age <= deletionRecentAuthenticationSeconds;
}

function requiredIdempotencyKey(request: Request) {
  const value = request.headers.get("X-Idempotency-Key")?.trim() ?? "";
  return value.length >= 1 && value.length <= 200 ? value : undefined;
}

function validationError(message: string) {
  return json({ error: { code: "validation_failed", message } }, 400);
}

function authenticationRequired() {
  return json(
    { error: { code: "authentication_required", message: "Sign in again to continue." } },
    401,
  );
}

function profileRequired() {
  return json(
    { error: { code: "profile_required", message: "Complete your profile to continue." } },
    409,
  );
}
