import { createClient } from "npm:@supabase/supabase-js@2";

export async function verifyBearerUser(bearerToken: string) {
  const session = await verifyBearerSession(bearerToken);
  return {
    accountId: session.accountId,
    oauthProviders: session.oauthProviders,
  };
}

export async function verifyBearerSession(bearerToken: string) {
  const token = bearerToken.replace(/^Bearer\s+/i, "");
  const client = createClient(requiredEnv("SUPABASE_URL"), publishableKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  });

  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user?.id) {
    throw new Error("A valid bearer token is required.");
  }

  const oauthProviders = dastakOAuthProviders(data.user);

  const sessionId = sessionID(token);
  if (!sessionId) {
    throw new Error("The bearer token does not identify a session.");
  }

  if (await isRevokedSession(data.user.id, sessionId)) {
    throw new Error("This Dastak session has been revoked.");
  }

  return {
    accountId: data.user.id,
    sessionId,
    accessToken: token,
    oauthProviders,
    oauthAuthenticatedAt: oauthAuthenticationTimestamp(token),
  };
}

export function dastakOAuthProviders(user: {
  is_anonymous?: boolean;
  identities?: Array<{ provider?: string }> | null;
}) {
  if (user.is_anonymous) throw new Error("Anonymous Dastak sessions are forbidden.");
  const providers = [
    ...new Set(
      (user.identities ?? []).map((identity) => identity.provider).filter(
        (provider): provider is string => typeof provider === "string",
      ),
    ),
  ].sort();
  if (
    providers.length < 1 ||
    providers.some((provider) => provider !== "apple" && provider !== "google")
  ) {
    throw new Error("Dastak requires an Apple or Google OAuth identity.");
  }
  return providers as Array<"apple" | "google">;
}

export function oauthAuthenticationTimestamp(token: string) {
  const payload = jwtPayload(token);
  if (!payload || !Array.isArray(payload.amr)) return undefined;
  const timestamps = payload.amr.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return [];
    const record = entry as Record<string, unknown>;
    return record.method === "oauth" && typeof record.timestamp === "number" &&
        Number.isFinite(record.timestamp)
      ? [record.timestamp]
      : [];
  });
  return timestamps.length > 0 ? Math.max(...timestamps) : undefined;
}

function sessionID(token: string) {
  const payload = jwtPayload(token);
  return typeof payload?.session_id === "string" && uuidPattern.test(payload.session_id)
    ? payload.session_id.toLowerCase()
    : null;
}

function jwtPayload(token: string): Record<string, unknown> | null {
  try {
    const encoded = token.split(".")[1];
    if (!encoded) return null;
    const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(Math.ceil(encoded.length / 4) * 4, "=");
    const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function isRevokedSession(accountId: string, sessionId: string) {
  const serviceClient = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );
  const { data, error } = await serviceClient.rpc("is_account_session_revoked", {
    p_account_id: accountId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data === true;
}

function publishableKey() {
  const direct = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  if (direct) {
    return direct;
  }

  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")
    ?.split(",")
    .map((key) => key.trim())
    .filter(Boolean);
  if (keys?.[0]) {
    return keys[0];
  }

  throw new Error("A Supabase publishable key is required.");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
