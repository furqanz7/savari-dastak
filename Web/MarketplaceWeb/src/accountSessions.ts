import { isAbortError, requestDeadline } from "./requestDeadline";

export type AccountSession = {
  sessionId: string;
  deviceName: string;
  platform: "ios" | "web";
  appName: string;
  createdAt: string;
  lastSeenAt: string;
  isCurrent: boolean;
};

export type AccountSessionCollection = { sessions: AccountSession[] };
export type AccountSessionMetadata = {
  deviceName: string;
  platform: "web";
  appName: string;
  userAgent?: string;
};

type AuthenticatedInput = { supabaseUrl: string; publishableKey: string; accessToken: string; signal?: AbortSignal };
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class AccountSessionRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "AccountSessionRequestError";
  }
}

export function webSessionMetadata(appName: string): AccountSessionMetadata {
  const userAgent = navigator.userAgent.slice(0, 500);
  const browser = /Edg\//.test(userAgent) ? "Edge" : /CriOS|Chrome\//.test(userAgent) ? "Chrome" :
    /Firefox\//.test(userAgent) ? "Firefox" : /Safari\//.test(userAgent) ? "Safari" : "Browser";
  const system = /iPhone|iPad/.test(userAgent) ? "iPhone or iPad" : /Mac/.test(userAgent) ? "Mac" :
    /Windows/.test(userAgent) ? "Windows PC" : /Android/.test(userAgent) ? "Android device" : "device";
  return { deviceName: `${browser} on ${system}`, platform: "web", appName, userAgent };
}

export function getAccountSessions(
  input: AuthenticatedInput & AccountSessionMetadata,
  fetcher: Fetcher = fetch,
) {
  return sessionOperation(input, "snapshot", fetcher);
}

export async function registerAccountSessionWithRetry(
  input: AuthenticatedInput & AccountSessionMetadata,
  fetcher: Fetcher = fetch,
  options: {
    maximumAttempts?: number;
    retryDelaysMs?: number[];
    wait?: (milliseconds: number, signal?: AbortSignal) => Promise<void>;
  } = {},
) {
  const maximumAttempts = Math.max(1, Math.min(options.maximumAttempts ?? 3, 5));
  const retryDelaysMs = options.retryDelaysMs ?? [750, 2_000, 5_000];
  const wait = options.wait ?? waitForRetry;
  let latestError: unknown;

  for (let attempt = 0; attempt < maximumAttempts; attempt += 1) {
    try {
      return await getAccountSessions(input, fetcher);
    } catch (error) {
      latestError = error;
      if (input.signal?.aborted || !retryableRegistrationError(error) || attempt + 1 >= maximumAttempts) throw error;
      await wait(retryDelaysMs[Math.min(attempt, retryDelaysMs.length - 1)] ?? 5_000, input.signal);
    }
  }
  throw latestError;
}

export function signOutOtherSessions(
  input: AuthenticatedInput & AccountSessionMetadata,
  fetcher: Fetcher = fetch,
) {
  return sessionOperation(input, "signOutOthers", fetcher);
}

export async function revokeAccountSession(
  input: AuthenticatedInput & { sessionId: string },
  fetcher: Fetcher = fetch,
) {
  return parseCollection(await call(input, {
    operation: "revoke",
    sessionId: input.sessionId,
  }, fetcher));
}

export async function endCurrentAccountSession(
  input: AuthenticatedInput,
  fetcher: Fetcher = fetch,
) {
  await call(input, { operation: "endCurrent" }, fetcher);
}

async function sessionOperation(
  input: AuthenticatedInput & AccountSessionMetadata,
  operation: "snapshot" | "signOutOthers",
  fetcher: Fetcher,
) {
  return parseCollection(await call(input, {
    operation,
    deviceName: input.deviceName,
    platform: input.platform,
    appName: input.appName,
    userAgent: input.userAgent,
  }, fetcher));
}

async function call(auth: AuthenticatedInput, body: unknown, fetcher: Fetcher) {
  const deadline = requestDeadline(auth.signal);
  let response: Response;
  let payload: unknown;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/account-sessions`, {
      method: "POST",
      headers: {
        apikey: auth.publishableKey,
        authorization: `Bearer ${auth.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: deadline.signal,
    });
    payload = await response.json().catch((error: unknown) => {
      if (deadline.timedOut()) throw error;
      return undefined;
    });
  } catch (error) {
    if (deadline.timedOut()) throw new AccountSessionRequestError("request_timeout", "Account sessions took too long to respond.", 0);
    if (isAbortError(error) || auth.signal?.aborted) throw error;
    throw new AccountSessionRequestError("network_error", "Dastak could not reach account sessions.", 0);
  } finally {
    deadline.dispose();
  }
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new AccountSessionRequestError(
      text(error?.code, 80) ?? "sessions_unavailable",
      text(error?.message, 300) ?? "Account sessions are unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function retryableRegistrationError(error: unknown) {
  return error instanceof AccountSessionRequestError &&
    (error.status === 0 || error.status === 429 || error.status >= 500);
}

function waitForRetry(milliseconds: number, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(signal?.reason ?? new DOMException("The request was aborted.", "AbortError"));
      return;
    }
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal?.reason ?? new DOMException("The request was aborted.", "AbortError"));
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, milliseconds);
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

function parseCollection(value: unknown): AccountSessionCollection {
  const source = record(value);
  if (!source || !Array.isArray(source.sessions)) invalid();
  return { sessions: source.sessions.map(parseSession) };
}

function parseSession(value: unknown): AccountSession {
  const source = record(value);
  if (!source || (source.platform !== "ios" && source.platform !== "web") || typeof source.isCurrent !== "boolean") invalid();
  const createdAt = requiredText(source.createdAt, 50);
  const lastSeenAt = requiredText(source.lastSeenAt, 50);
  if (Number.isNaN(Date.parse(createdAt)) || Number.isNaN(Date.parse(lastSeenAt))) invalid();
  return {
    sessionId: uuid(source.sessionId),
    deviceName: requiredText(source.deviceName, 80),
    platform: source.platform,
    appName: requiredText(source.appName, 40),
    createdAt,
    lastSeenAt,
    isCurrent: source.isCurrent,
  };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
function text(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}
function requiredText(value: unknown, maximum: number) { return text(value, maximum) ?? invalid(); }
function uuid(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}
function invalid(): never {
  throw new AccountSessionRequestError("invalid_response", "Dastak received an invalid session response.", 502);
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
