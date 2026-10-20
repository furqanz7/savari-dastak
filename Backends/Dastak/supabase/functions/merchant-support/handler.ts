import { corsHeaders } from "../_shared/http.ts";
import { supportDeadline, supportText } from "./limits.ts";

export type SupportDependencies = {
  enabled: boolean;
  authenticate: (bearer: string, signal?: AbortSignal) => Promise<{ accountId: string }>;
  command: (
    actor: string | null,
    input: Record<string, unknown>,
    signal?: AbortSignal,
  ) => Promise<unknown>;
  enter?: () => (() => void) | undefined;
  bodyDeadlineMs?: number;
  operationDeadlineMs?: number;
};
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const categories = ["ACCESS", "ORDERS", "STORE", "EARNINGS", "PRIVACY", "OTHER"];
const statuses = ["OPEN", "WAITING_ON_MERCHANT", "RESOLVED"];
const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
const failure = (code: string, status: number) => response({ error: { code } }, status);

export async function handleMerchantSupport(request: Request, deps: SupportDependencies) {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") return failure("method_not_allowed", 405);
  if (!deps.enabled) return failure("support_unavailable", 503);
  const release = deps.enter?.();
  if (deps.enter && !release) return failure("support_rate_limited", 429);
  try {
    return await handleRequest(request, deps);
  } finally {
    release?.();
  }
}

async function handleRequest(request: Request, deps: SupportDependencies) {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return failure("support_invalid", 400);
  }
  let body: Record<string, unknown>;
  try {
    // Bound actual streamed bytes, not just the spoofable Content-Length header.
    body = await supportDeadline(
      async (signal) => {
        const reader = request.body?.getReader();
        if (!reader) throw Error("support_invalid");
        const cancel = () => {
          void reader.cancel().catch(() => {});
        };
        signal.addEventListener("abort", cancel, { once: true });
        const chunks: Uint8Array[] = [];
        let length = 0;
        try {
          while (true) {
            const next = await reader.read();
            if (next.done) break;
            length += next.value.length;
            if (length > 12_000) {
              cancel();
              throw Error("support_body_too_large");
            }
            chunks.push(next.value);
          }
        } finally {
          signal.removeEventListener("abort", cancel);
          reader.releaseLock();
        }
        const bytes = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) {
          bytes.set(chunk, offset);
          offset += chunk.length;
        }
        const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
        if (!value || typeof value !== "object" || Array.isArray(value)) {
          throw Error("support_invalid");
        }
        return value;
      },
      deps.bodyDeadlineMs ?? 3000,
      request.signal,
    );
  } catch (error) {
    return failure(
      "support_invalid",
      error instanceof Error && error.message === "support_body_too_large" ? 413 : 400,
    );
  }
  const op = body.operation;
  if (
    typeof op !== "string" ||
    !["create", "read", "reply", "adminList", "adminRead", "adminReply"].includes(op)
  ) return failure("support_invalid", 400);
  const input: Record<string, unknown> = { operation: op };
  let actor: string | null = null;
  if (op.startsWith("admin")) {
    const bearer = request.headers.get("authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(bearer)) return failure("authentication_required", 401);
    try {
      actor = (await supportDeadline(
        (signal) => deps.authenticate(bearer, signal),
        deps.operationDeadlineMs ?? 3500,
        request.signal,
      )).accountId;
    } catch (error) {
      if (error instanceof Error && error.message === "support_unavailable") {
        return failure("support_unavailable", 503);
      }
      return failure("authentication_required", 401);
    }
    // Active Admin role is checked in the same DB transaction as every command.
  } else {
    if (typeof body.token !== "string" || !/^[a-f0-9]{64}$/.test(body.token)) {
      return failure("support_not_found", 404);
    }
    input.tokenHash = [
      ...new Uint8Array(
        await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body.token)),
      ),
    ].map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  if (op !== "adminList") {
    if (typeof body.ticketId !== "string" || !uuid.test(body.ticketId)) {
      return failure("support_invalid", 400);
    }
    input.ticketId = body.ticketId.toLowerCase();
  }
  if (["create", "reply", "adminReply"].includes(op)) {
    if (
      !supportText(body.message, 5, 2000) ||
      typeof body.requestId !== "string" || !uuid.test(body.requestId)
    ) return failure("support_invalid", 400);
    input.message = body.message.trim();
    input.requestId = body.requestId.toLowerCase();
  }
  if (op === "create") {
    if (
      body.website || body.consent !== true || !supportText(body.subject, 5, 100) ||
      !categories.includes(String(body.category))
    ) return failure("support_invalid", 400);
    input.subject = body.subject.trim();
    input.category = body.category;
  }
  if (op === "reply" || op === "adminReply") {
    if (!Number.isSafeInteger(body.version) || Number(body.version) < 1) {
      return failure("support_invalid", 400);
    }
    input.version = body.version;
  }
  if (op === "adminReply" || op === "adminList") {
    if (
      (op === "adminReply" || body.status !== undefined) && !statuses.includes(String(body.status))
    ) return failure("support_invalid", 400);
    if (body.status !== undefined) input.status = body.status;
  }
  if (op === "adminList" && (body.cursorAt !== undefined || body.cursorId !== undefined)) {
    if (
      typeof body.cursorId !== "string" || !uuid.test(body.cursorId) ||
      typeof body.cursorAt !== "string" ||
      !/^\d{4}-\d\d-\d\dT/.test(body.cursorAt) || !Number.isFinite(Date.parse(body.cursorAt))
    ) return failure("support_invalid", 400);
    input.cursorAt = body.cursorAt;
    input.cursorId = body.cursorId;
  }
  try {
    return response(
      await supportDeadline(
        (signal) => deps.command(actor, input, signal),
        deps.operationDeadlineMs ?? 6000,
        request.signal,
      ),
      op === "create" ? 201 : 200,
    );
  } catch (error) {
    const code = error instanceof Error ? error.message : "";
    const status: Record<string, number> = {
      support_forbidden: 403,
      support_not_found: 404,
      support_conflict: 409,
      support_stale: 409,
      support_rate_limited: 429,
      support_thread_full: 409,
      support_invalid: 400,
      support_busy: 409,
    };
    return Object.hasOwn(status, code)
      ? failure(code, status[code])
      : failure("support_unavailable", 503);
  }
}
