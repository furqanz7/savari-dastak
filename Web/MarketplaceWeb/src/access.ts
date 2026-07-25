import type { Session, SupabaseClient } from "@supabase/supabase-js";
import type { AppConfig } from "./config";

export type AccessState = "signed_out" | "needs_profile" | "active" | "pending" | "suspended" | "denied";

export type AccountProfile = {
  displayName: string;
  phoneNumber: string;
};

export type AccessResult = {
  state: AccessState;
  profile?: AccountProfile;
  message?: string;
};

type SavariProfile = {
  name: string | null;
  phone: string | null;
  role: string | null;
  has_user_profile: boolean | null;
  has_driver_profile: boolean | null;
};

type DeliverySnapshot = {
  onboardingState?: unknown;
};

export async function resolveAccess(
  client: SupabaseClient,
  session: Session,
  config: AppConfig,
): Promise<AccessResult> {
  return config.product === "savari"
    ? resolveSavariAccess(client, session.user.id, config.role)
    : resolveDastakAccess(client, session, config);
}

export async function completeProfile(
  client: SupabaseClient,
  session: Session,
  config: AppConfig,
  profile: AccountProfile,
) {
  if (!isValidProfile(profile)) throw new Error("Enter a valid name and phone number with country code.");

  if (config.product === "savari") {
    const { error } = await client.from("profiles").upsert({
      id: session.user.id,
      name: normalizeName(profile.displayName),
      phone: profile.phoneNumber.trim(),
      role: "Passenger",
      has_user_profile: true,
      has_driver_profile: false,
    });
    if (error) throw error;
    return;
  }

  const response = await callFunction(session, config, "bootstrap-account", {
    displayName: normalizeName(profile.displayName),
    phoneNumber: profile.phoneNumber.trim(),
  }, { "X-Idempotency-Key": crypto.randomUUID() });
  if (!response.ok) throw new Error(readErrorMessage(response.body, "Profile could not be saved."));
}

export function isValidProfile(profile: AccountProfile) {
  const name = normalizeName(profile.displayName);
  return name.length >= 2 && name.length <= 100 && /^\+[1-9]\d{7,14}$/.test(profile.phoneNumber.trim());
}

export function mapSavariAccess(
  profile: SavariProfile | null,
  role: AppConfig["role"],
  driverVerified = false,
): AccessResult {
  if (!profile) return { state: "needs_profile" };
  const account = {
    displayName: profile.name?.trim() || "Savari member",
    phoneNumber: profile.phone?.trim() || "",
  };
  if (role === "passenger") {
    return profile.has_user_profile || profile.role?.toLowerCase() === "passenger"
      ? { state: "active", profile: account }
      : { state: "denied", profile: account, message: "Passenger access is not active for this account." };
  }
  const isDriver = profile.has_driver_profile || profile.role?.toLowerCase() === "driver";
  return isDriver && driverVerified
    ? { state: "active", profile: account }
    : { state: "denied", profile: account, message: "Rider access has not been approved." };
}

export function mapDastakRoute(route: unknown): AccessResult {
  switch (route) {
    case "needs_profile": return { state: "needs_profile" };
    case "active": return { state: "active" };
    case "pending_approval": return { state: "pending", message: "Approval is pending." };
    case "suspended": return { state: "suspended", message: "This account is temporarily suspended." };
    default: return { state: "denied", message: "This account is not approved for this app." };
  }
}

export function mapDeliverySnapshot(snapshot: DeliverySnapshot): AccessResult {
  switch (snapshot.onboardingState) {
    case "approved": return { state: "active" };
    case "pending": return { state: "pending", message: "Your delivery partner application is under review." };
    case "rejected": return { state: "denied", message: "Your delivery partner application was not approved." };
    case "not_applied": return { state: "denied", message: "A delivery partner profile is required." };
    default: return { state: "denied", message: "Delivery partner access could not be verified." };
  }
}

export function isAuthenticationRequiredResponse(status: number) {
  return status === 401;
}

async function resolveSavariAccess(
  client: SupabaseClient,
  userId: string,
  role: AppConfig["role"],
) {
  const { data, error } = await client
    .from("profiles")
    .select("name,phone,role,has_user_profile,has_driver_profile")
    .eq("id", userId)
    .maybeSingle<SavariProfile>();
  if (error) throw error;

  let driverVerified = false;
  if (data && role === "rider") {
    const result = await client
      .from("driver_onboarding")
      .select("verified")
      .eq("profile_id", userId)
      .maybeSingle<{ verified: boolean | null }>();
    if (result.error) throw result.error;
    driverVerified = result.data?.verified === true;
  }
  return mapSavariAccess(data, role, driverVerified);
}

async function resolveDastakAccess(
  client: SupabaseClient,
  session: Session,
  config: AppConfig,
) {
  const { role } = config;
  if (role === "delivery") {
    const response = await callFunction(session, config, "delivery-partners", { operation: "selfSnapshot" });
    if (isAuthenticationRequiredResponse(response.status)) {
      return { state: "signed_out" } satisfies AccessResult;
    }
    if (response.status === 409) return { state: "needs_profile" } satisfies AccessResult;
    if (!response.ok) throw new Error(readErrorMessage(response.body, "Delivery access could not be verified."));
    const result = mapDeliverySnapshot(response.body as DeliverySnapshot);
    if (result.state === "active") {
      const { data } = await client.from("accounts").select("display_name,phone_number").eq("id", session.user.id).maybeSingle<{
        display_name: string;
        phone_number: string;
      }>();
      if (data) result.profile = { displayName: data.display_name, phoneNumber: data.phone_number };
    }
    return result;
  }

  const application = role === "merchant" ? "merchant" : role === "admin" ? "admin" : "customer";
  const response = await callFunction(session, config, "resolve-app-access", { application });
  if (isAuthenticationRequiredResponse(response.status)) {
    return { state: "signed_out" } satisfies AccessResult;
  }
  if (!response.ok) throw new Error(readErrorMessage(response.body, "Account access could not be verified."));
  const result = mapDastakRoute((response.body as { route?: unknown }).route);
  if (result.state === "active") {
    const { data } = await client.from("accounts").select("display_name,phone_number").eq("id", session.user.id).maybeSingle<{
      display_name: string;
      phone_number: string;
    }>();
    if (data) result.profile = { displayName: data.display_name, phoneNumber: data.phone_number };
  }
  return result;
}

async function callFunction(
  session: Session,
  config: AppConfig,
  name: string,
  body: unknown,
  extraHeaders: Record<string, string> = {},
) {
  const url = `${config.supabaseUrl}/functions/v1/${name}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      apikey: config.supabasePublishableKey,
      authorization: `Bearer ${session.access_token}`,
      "content-type": "application/json",
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });
  const responseBody = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, body: responseBody };
}

function readErrorMessage(body: unknown, fallback: string) {
  const record = body && typeof body === "object" ? body as Record<string, unknown> : undefined;
  const error = record?.error && typeof record.error === "object" ? record.error as Record<string, unknown> : undefined;
  return typeof error?.message === "string" ? error.message : fallback;
}

function normalizeName(value: string) {
  return value.trim().replace(/\s+/g, " ");
}
