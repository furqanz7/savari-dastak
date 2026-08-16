import { createClient } from "npm:@supabase/supabase-js@2";

export async function verifyBearerUser(bearerToken: string) {
  const session = await verifyBearerSession(bearerToken);
  return { accountId: session.accountId };
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

  const sessionId = sessionID(token);
  if (!sessionId) {
    throw new Error("The bearer token does not identify a session.");
  }

  return { accountId: data.user.id, sessionId, accessToken: token };
}

function sessionID(token: string) {
  try {
    const encoded = token.split(".")[1];
    if (!encoded) return null;
    const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(Math.ceil(encoded.length / 4) * 4, "=");
    const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
    const payload = JSON.parse(new TextDecoder().decode(bytes)) as Record<string, unknown>;
    return typeof payload.session_id === "string" && uuidPattern.test(payload.session_id)
      ? payload.session_id.toLowerCase()
      : null;
  } catch {
    return null;
  }
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
