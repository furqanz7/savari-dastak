import { corsPreflight, json } from "../_shared/http.ts";

type Actor = { accountId: string; sessionId: string; accessToken: string };
type RpcResult = { responseBody: unknown; responseStatus: number };
type DeviceMetadata = {
  deviceName: string;
  platform: "ios" | "web";
  appName: string;
  userAgent?: string;
};

type Dependencies = {
  authenticateBearer: (authorization: string) => Promise<Actor>;
  touch: (actor: Actor, metadata: DeviceMetadata) => Promise<RpcResult>;
  snapshot: (actor: Actor) => Promise<RpcResult>;
  revokeOthers: (accessToken: string) => Promise<void>;
  endOthers: (actor: Actor) => Promise<RpcResult>;
  endCurrent: (actor: Actor) => Promise<RpcResult>;
};

export async function handleAccountSessions(request: Request, dependencies: Dependencies) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();

  let actor: Actor;
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  if (!body) return validationError();

  if (body.operation === "endCurrent") {
    return runRpc(() => dependencies.endCurrent(actor), "This session could not be closed.");
  }

  const metadata = normalizeMetadata(body);
  if (!metadata) return validationError();

  try {
    const touched = await dependencies.touch(actor, metadata);
    if (touched.responseStatus >= 400) return rpcResponse(touched);

    if (body.operation === "snapshot") {
      return rpcResponse(await dependencies.snapshot(actor));
    }
    if (body.operation === "signOutOthers") {
      await dependencies.revokeOthers(actor.accessToken);
      const ended = await dependencies.endOthers(actor);
      if (ended.responseStatus >= 400) return rpcResponse(ended);
      return rpcResponse(await dependencies.snapshot(actor));
    }
    return validationError();
  } catch {
    return json({
      error: { code: "internal_error", message: "Account sessions could not be updated." },
    }, 500);
  }
}

function normalizeMetadata(body: Record<string, unknown>): DeviceMetadata | null {
  const deviceName = clean(body.deviceName, 80);
  const appName = clean(body.appName, 40);
  const platform = body.platform;
  const userAgent = body.userAgent === undefined || body.userAgent === null || body.userAgent === ""
    ? undefined
    : clean(body.userAgent, 500);
  if (
    !deviceName || !appName || (platform !== "ios" && platform !== "web") ||
    (body.userAgent !== undefined && body.userAgent !== null && body.userAgent !== "" && !userAgent)
  ) return null;
  return { deviceName, appName, platform, userAgent: userAgent ?? undefined };
}

function clean(value: unknown, maximum: number) {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length >= 1 && normalized.length <= maximum ? normalized : null;
}

async function runRpc(operation: () => Promise<RpcResult>, fallback: string) {
  try {
    return rpcResponse(await operation());
  } catch {
    return json({ error: { code: "internal_error", message: fallback } }, 500);
  }
}

function rpcResponse(result: RpcResult) {
  return json(result.responseBody, result.responseStatus);
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "Valid device details are required." },
  }, 400);
}
