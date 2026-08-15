export type AuthCallback = {
  kind: "implicit" | "pkce" | "error";
  message?: string;
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
      message: cleanCallbackMessage(params.get("error_description")),
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
  return callback.message ?? "Sign-in could not be completed. Please try again.";
}

function cleanCallbackMessage(value: string | null): string | undefined {
  const message = value?.replace(/\+/g, " ").trim();
  if (!message || message.length > 180) return undefined;
  return message;
}
