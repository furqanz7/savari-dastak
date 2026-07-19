import type { AuthChangeEvent, Session } from "@supabase/supabase-js";

export function shouldPreserveAuthenticatedView(
  event: AuthChangeEvent,
  session: Session | null,
  knownUserId?: string,
): session is Session {
  return session !== null
    && session.user.id === knownUserId
    && (event === "SIGNED_IN" || event === "TOKEN_REFRESHED");
}
