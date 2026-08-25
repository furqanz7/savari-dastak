import type { User } from "@supabase/supabase-js";

function normalizedEmail(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const candidate = value.trim();
  return candidate.includes("@") ? candidate : undefined;
}

/** Resolve contact email only from the authenticated Supabase identity. */
export function resolveAuthenticatedEmail(user: Pick<User, "email" | "user_metadata" | "identities">): string | undefined {
  const direct = normalizedEmail(user.email);
  if (direct) return direct;

  const metadata = normalizedEmail(user.user_metadata?.email);
  if (metadata) return metadata;

  for (const identity of user.identities ?? []) {
    const identityEmail = normalizedEmail(identity.identity_data?.email);
    if (identityEmail) return identityEmail;
  }
  return undefined;
}
