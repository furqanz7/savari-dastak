import { createClient } from "npm:@supabase/supabase-js@2";

export async function verifyBearerUser(bearerToken: string) {
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

  return { accountId: data.user.id };
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
