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
  if (!token || token.length > 512 || !platform) {
    return json({ error: { code: "invalid_device_token" } }, 400);
  }

  try {
    await dependencies.upsertToken(actor.accountId, token, platform);
    return json({ registered: true }, 200);
  } catch {
    return json({ error: { code: "device_token_registration_failed" } }, 500);
  }
}
