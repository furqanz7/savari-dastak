import type { SupabaseClient } from "@supabase/supabase-js";

// A feature endpoint denying access is not proof that the login is invalid.
// Never revoke the account-session registry from an automatic error handler.
export async function recoverCustomerSession(client: SupabaseClient, failedToken: string): Promise<void> {
  try {
    const before = await client.auth.getSession();
    if (before.error || before.data.session?.access_token !== failedToken) return;
    const verified = await client.auth.getUser(failedToken);
    if (!verified.error || ![401, 403].includes(verified.error.status ?? 0)) return;
    const current = await client.auth.getSession();
    // An older request must not sign out a refreshed or switched account.
    if (!current.error && current.data.session?.access_token === failedToken) {
      await client.auth.signOut({ scope: "local" });
    }
  } catch {
    // Network/server failures remain retryable; they do not invalidate a login.
  }
}
