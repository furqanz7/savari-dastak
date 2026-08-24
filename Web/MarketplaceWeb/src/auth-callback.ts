export type AuthCallback = {
  kind: "implicit" | "pkce" | "error";
  errorCode?: string;
};

const authKeys = new Set([
  "access_token",
  "code",
  "error",
  "error_code",
  "error_description",
  "expires_at",
  "expires_in",
  "provider_refresh_token",
  "provider_token",
  "refresh_token",
  "token_type",
  "type",
]);

export function readAuthCallback(href: string): AuthCallback | null {
  const url = new URL(href);
  const hash = new URLSearchParams(url.hash.startsWith("#") ? url.hash.slice(1) : url.hash);
  const params = hash.has("access_token") || hash.has("error") ? hash : url.searchParams;

  if (params.has("error") || params.has("error_description") || params.has("error_code")) {
    return {
      kind: "error",
      errorCode: cleanCallbackCode(params.get("error_code") ?? params.get("error")),
    };
  }
  if (hash.has("access_token")) return { kind: "implicit" };
  if (url.searchParams.has("code")) return { kind: "pkce" };
  return null;
}

export function sanitizedAuthCallbackUrl(href: string): string {
  const url = new URL(href);
  const hash = new URLSearchParams(url.hash.startsWith("#") ? url.hash.slice(1) : url.hash);

  if ([...hash.keys()].some((key) => authKeys.has(key))) url.hash = "";
  for (const key of authKeys) url.searchParams.delete(key);
  return url.toString();
}

export function callbackFailureMessage(callback: AuthCallback): string {
  switch (callback.errorCode) {
    case "access_denied":
    case "user_cancelled":
    case "user_canceled":
      return "Sign-in was cancelled. No account changes were made.";
    case "bad_oauth_state":
    case "oauth_state_expired":
      return "The secure sign-in session expired. Please start again.";
    case "provider_disabled":
      return "That sign-in method is temporarily unavailable. Please use Apple or Google.";
    default:
      return "Sign-in could not be completed. Please try again.";
  }
}

function cleanCallbackCode(value: string | null): string | undefined {
  const code = value?.trim().toLowerCase();
  return code && /^[a-z0-9_-]{1,80}$/.test(code) ? code : undefined;
}
