import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type RegisterDeviceTokenDependencies = {
  authenticateBearer: AuthenticateBearer;
  upsertToken: (accountId: string, token: string, platform: "ios" | "web") => Promise<void>;
};

export async function handleRegisterDeviceToken(
  request: Request,
  dependencies: RegisterDeviceTokenDependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") {
    return json({ error: { code: "method_not_allowed" } }, 405);
  }
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) {
    return json({ error: { code: "authentication_required" } }, 401);
  }

  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return json({ error: { code: "authentication_required" } }, 401);
  }

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const token = typeof body?.token === "string" ? body.token.trim() : "";
  const platform = body?.platform === "ios" || body?.platform === "web" ? body.platform : null;
  if (
    !token || !platform ||
    (platform === "ios" && token.length > 512) ||
    (platform === "web" && (token.length > 4096 || !validWebSubscription(token)))
  ) {
    return json({ error: { code: "invalid_device_token" } }, 400);
  }

  try {
    await dependencies.upsertToken(actor.accountId, token, platform);
    return json({ registered: true }, 200);
  } catch {
    return json({ error: { code: "device_token_registration_failed" } }, 500);
  }
}

function validWebSubscription(value: string) {
  try {
    const subscription = JSON.parse(value) as Record<string, unknown>;
    const keys = subscription.keys && typeof subscription.keys === "object"
      ? subscription.keys as Record<string, unknown>
      : undefined;
    return typeof subscription.endpoint === "string" &&
      /^https:\/\/\S+$/.test(subscription.endpoint) &&
      typeof keys?.auth === "string" && keys.auth.length > 0 && keys.auth.length <= 512 &&
      typeof keys.p256dh === "string" && keys.p256dh.length > 0 && keys.p256dh.length <= 512;
  } catch {
    return false;
  }
}
