export type AccountProfile = {
  displayName: string;
  phoneNumber: string;
};

export type CustomerOAuthProvider = "apple" | "google";
export type DastakPersona = "CUSTOMER" | "MERCHANT" | "DELIVERY";
export type CustomerIdentity = {
  provider: CustomerOAuthProvider;
  linkKind: "ORIGIN" | "EXPLICIT";
  linkedAt: string;
};

const identityLinkStorageName = "dastak.identityLink.pendingProvider.v1";
const deletionReauthenticationStorageName = "dastak.accountDeletion.reauthentication.v1";

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
  input: AuthenticatedInput & { persona: DastakPersona; idempotencyKey?: string },
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(
    input,
    { operation: "delete", persona: input.persona },
    fetcher,
    input.idempotencyKey,
  );
  if ((body as { deleted?: unknown }).deleted !== true) {
    throw new Error("Dastak could not confirm account deletion.");
  }
}

export async function exportAccountData(
  input: AuthenticatedInput,
  fetcher: typeof fetch = fetch,
) {
  const body = await callAccountProfile(input, { operation: "export" }, fetcher);
  const record = body && typeof body === "object" ? body as Record<string, unknown> : undefined;
  if (!record?.export || typeof record.filename !== "string" || !record.filename.endsWith(".json")) {
    throw new Error("Dastak returned an invalid account export.");
  }
  return { filename: record.filename, data: record.export };
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
  const errors = accountProfileValidation(profile);
  return !errors.displayName && !errors.phoneNumber;
}

export function accountProfileValidation(profile: AccountProfile) {
  const name = profile.displayName.trim().replace(/\s+/g, " ");
  return {
    displayName: name.length < 1
      ? "Enter your full name."
      : name.length > 80 ? "Use 80 characters or fewer." : undefined,
    phoneNumber: isValidDastakPhoneNumber(profile.phoneNumber)
      ? undefined
      : "Enter a valid phone number with country code.",
  };
}

async function callAccountProfile(
  input: AuthenticatedInput,
  operation: unknown,
  fetcher: typeof fetch,
  idempotencyKey: string = crypto.randomUUID(),
) {
  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/account-profile`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
        "X-Idempotency-Key": idempotencyKey,
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

const deletionKeyStorageName = "dastak.accountDeletion.idempotencyKey.v1";

export function accountDeletionIdempotencyKey(
  persona: DastakPersona = "CUSTOMER",
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
) {
  const created = crypto.randomUUID();
  try {
    const key = `${deletionKeyStorageName}.${persona}`;
    const existing = storage.getItem(key)?.trim();
    if (existing) return existing;
    storage.setItem(key, created);
  } catch {
    // A stable in-memory caller key still protects private-browsing sessions.
  }
  return created;
}

export function clearAccountDeletionIdempotencyKey(
  persona: DastakPersona = "CUSTOMER",
  storage: Pick<Storage, "removeItem"> = localStorage,
) {
  try {
    storage.removeItem(`${deletionKeyStorageName}.${persona}`);
  } catch {
    // Storage can be unavailable in private browsing.
  }
}

export function rememberPendingIdentityLink(
  provider: CustomerOAuthProvider,
  storage: Pick<Storage, "setItem"> = sessionStorage,
) {
  try {
    storage.setItem(identityLinkStorageName, provider);
  } catch {
    // The provider snapshot still confirms the result when storage is unavailable.
  }
}

export function pendingIdentityLink(
  storage: Pick<Storage, "getItem"> = sessionStorage,
): CustomerOAuthProvider | undefined {
  try {
    const value = storage.getItem(identityLinkStorageName);
    return value === "apple" || value === "google" ? value : undefined;
  } catch {
    return undefined;
  }
}

export function clearPendingIdentityLink(
  storage: Pick<Storage, "removeItem"> = sessionStorage,
) {
  try {
    storage.removeItem(identityLinkStorageName);
  } catch {
    // Storage can be unavailable in private browsing.
  }
}

export type PendingDeletionReauthentication = {
  accountId: string;
  provider: CustomerOAuthProvider;
};

export function rememberPendingDeletionReauthentication(
  value: PendingDeletionReauthentication,
  storage: Pick<Storage, "setItem"> = sessionStorage,
) {
  try {
    storage.setItem(deletionReauthenticationStorageName, JSON.stringify(value));
  } catch {
    // The server still requires a recent OAuth authentication before deletion.
  }
}

export function pendingDeletionReauthentication(
  storage: Pick<Storage, "getItem"> = sessionStorage,
): PendingDeletionReauthentication | undefined {
  try {
    const value: unknown = JSON.parse(storage.getItem(deletionReauthenticationStorageName) ?? "null");
    if (!value || typeof value !== "object") return undefined;
    const record = value as Record<string, unknown>;
    return typeof record.accountId === "string" &&
        (record.provider === "apple" || record.provider === "google")
      ? { accountId: record.accountId, provider: record.provider }
      : undefined;
  } catch {
    return undefined;
  }
}

export function clearPendingDeletionReauthentication(
  storage: Pick<Storage, "removeItem"> = sessionStorage,
) {
  try {
    storage.removeItem(deletionReauthenticationStorageName);
  } catch {
    // Storage can be unavailable in private browsing.
  }
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
import { isValidDastakPhoneNumber } from "./phoneNumber";
