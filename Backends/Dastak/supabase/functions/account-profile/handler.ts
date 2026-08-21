import { corsPreflight, json } from "../_shared/http.ts";

export type AccountProfile = {
  displayName: string;
  phoneNumber: string;
};

export type AccountProfileDependencies = {
  authenticateBearer: (bearerToken: string) => Promise<{ accountId: string }>;
  snapshotProfile: (accountId: string) => Promise<AccountProfile | null>;
  updateProfile: (accountId: string, profile: AccountProfile) => Promise<AccountProfile | null>;
  deleteAccount: (accountId: string) => Promise<void>;
};

type RequestBody =
  | { operation: "snapshot" }
  | { operation: "update"; displayName: string; phoneNumber: string }
  | { operation: "delete" };

const e164Pattern = /^\+[1-9][0-9]{7,14}$/;

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

  let accountId: string;
  try {
    accountId = (await dependencies.authenticateBearer(authorization)).accountId;
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
        const profile = await dependencies.snapshotProfile(accountId);
        return profile ? json({ profile }) : profileRequired();
      }
      case "update": {
        const profile = normalizeProfile(body.displayName, body.phoneNumber);
        if (profile instanceof Response) return profile;
        const updated = await dependencies.updateProfile(accountId, profile);
        return updated ? json({ profile: updated }) : profileRequired();
      }
      case "delete":
        await dependencies.deleteAccount(accountId);
        return json({ deleted: true });
    }
  } catch {
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
  if (!e164Pattern.test(normalizedPhone)) {
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
    if (value.operation === "snapshot" || value.operation === "delete") {
      return { operation: value.operation };
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
