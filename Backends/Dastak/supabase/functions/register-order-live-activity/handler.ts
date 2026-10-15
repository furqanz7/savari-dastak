import { corsPreflight, json } from "../_shared/http.ts";

export type Registration = {
  orderId: string;
  activityId: string;
  token: string;
  environment: "sandbox" | "production";
};
export async function handleRegistration(request: Request, dependencies: {
  authenticate: (bearer: string) => Promise<{ accountId: string; sessionId: string }>;
  register: (
    actor: { accountId: string; sessionId: string },
    registration: Registration,
  ) => Promise<void>;
}) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return json({ error: { code: "method_not_allowed" } }, 405);
  const bearer = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(bearer)) {
    return json({ error: { code: "authentication_required" } }, 401);
  }
  let actor;
  try {
    actor = await dependencies.authenticate(bearer);
  } catch {
    return json({ error: { code: "authentication_required" } }, 401);
  }
  const input = await request.json().catch(() => null);
  if (
    !input || typeof input.orderId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.orderId) ||
    typeof input.activityId !== "string" || input.activityId.length < 1 ||
    input.activityId.length > 200 ||
    typeof input.token !== "string" || !/^[0-9a-f]{32,512}$/.test(input.token) ||
    !["sandbox", "production"].includes(input.environment)
  ) {
    return json({ error: { code: "invalid_live_activity" } }, 400);
  }
  try {
    await dependencies.register(actor, input);
    return json({ registered: true });
  } catch {
    return json({ error: { code: "live_activity_registration_rejected" } }, 403);
  }
}
