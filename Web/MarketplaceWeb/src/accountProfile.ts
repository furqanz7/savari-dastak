export type AccountProfile = {
  displayName: string;
  phoneNumber: string;
};

export type CustomerOAuthProvider = "apple" | "google";
export type CustomerIdentity = {
  provider: CustomerOAuthProvider;
  linkKind: "ORIGIN" | "EXPLICIT";
  linkedAt: string;
};

type AuthenticatedInput = {
  accessToken: string;
  supabaseUrl: string;
  publishableKey: string;
};

export class AccountProfileRequestError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string) {
    super(message);
    this.name = "AccountProfileRequestError";
  }
}

export async function snapshotAccountProfile(
  input: AuthenticatedInput,
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(input, { operation: "snapshot" }, fetcher);
  const profile = (body as { profile?: unknown }).profile;
  if (!isAccountProfile(profile)) throw new Error("Dastak returned an invalid account profile.");
  return profile;
}

export async function updateAccountProfile(
  input: AuthenticatedInput & AccountProfile,
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(input, {
    operation: "update",
    displayName: input.displayName,
    phoneNumber: input.phoneNumber,
  }, fetcher);
  const profile = (body as { profile?: unknown }).profile;
  if (!isAccountProfile(profile)) throw new Error("Dastak returned an invalid account profile.");
  return profile;
}

export async function deleteAccount(
  input: AuthenticatedInput,
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(input, { operation: "delete" }, fetcher);
  if ((body as { deleted?: unknown }).deleted !== true) {
    throw new Error("Dastak could not confirm account deletion.");
  }
}

export async function snapshotCustomerIdentities(
  input: AuthenticatedInput,
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(input, { operation: "identitySnapshot" }, fetcher);
  const providers = (body as { providers?: unknown }).providers;
  if (!Array.isArray(providers) || !providers.every(isCustomerIdentity)) {
    throw new Error("Dastak returned an invalid identity snapshot.");
  }
  return providers;
}

export async function beginCustomerIdentityLink(
  input: AuthenticatedInput & { provider: CustomerOAuthProvider },
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(input, {
    operation: "beginIdentityLink",
    provider: input.provider,
  }, fetcher);
  const provider = (body as { provider?: unknown }).provider;
  if (provider !== input.provider) throw new Error("Dastak could not confirm identity linking.");
  return body;
}

export function isValidAccountProfile(profile: AccountProfile) {
  const name = profile.displayName.trim().replace(/\s+/g, " ");
  return name.length >= 1 && name.length <= 80 && /^\+[1-9]\d{7,14}$/.test(profile.phoneNumber.trim());
}

async function callAccountProfile(
  input: AuthenticatedInput,
  operation: unknown,
  fetcher: typeof fetch,
) {
  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/account-profile`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
        "X-Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify(operation),
    });
  } catch {
    throw new Error("Dastak could not reach your account. Check your connection and try again.");
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const { code, message } = readError(body, "The account request could not be completed.");
    throw new AccountProfileRequestError(message, response.status, code);
  }
  return body;
}

function isAccountProfile(value: unknown): value is AccountProfile {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return typeof record.displayName === "string" && typeof record.phoneNumber === "string";
}

function isCustomerIdentity(value: unknown): value is CustomerIdentity {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return (record.provider === "apple" || record.provider === "google") &&
    (record.linkKind === "ORIGIN" || record.linkKind === "EXPLICIT") &&
    typeof record.linkedAt === "string";
}

function readError(body: unknown, fallback: string) {
  const record = body && typeof body === "object" ? body as Record<string, unknown> : undefined;
  const error = record?.error && typeof record.error === "object" ? record.error as Record<string, unknown> : undefined;
  return {
    code: typeof error?.code === "string" ? error.code : undefined,
    message: typeof error?.message === "string" ? error.message : fallback,
  };
}
