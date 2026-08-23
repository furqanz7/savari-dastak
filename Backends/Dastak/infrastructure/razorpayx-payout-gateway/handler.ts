import {
  canonicalPayoutGatewayBody,
  parsePayoutGatewayRequest,
  payoutGatewayPath,
  type PayoutGatewayResult,
  payoutGatewaySignatureHeader,
  sha256Hex,
  verifyPayoutGatewaySignature,
} from "../../supabase/functions/_shared/payout-gateway.ts";
import { RazorpayXApiError } from "../../supabase/functions/_shared/razorpayx.ts";

export type ReplayStore = {
  claim: (digest: string, expiresAt: Date) => Promise<boolean>;
};

export type PayoutGatewayDependencies = {
  secret: string;
  maxClockSkewMilliseconds: number;
  replayStore: ReplayStore;
  executeProviderPayout: (
    request: ReturnType<typeof parsePayoutGatewayRequest>,
  ) => Promise<PayoutGatewayResult>;
  now?: () => Date;
  log?: (entry: Record<string, unknown>) => void;
};

export async function handlePayoutGateway(
  request: Request,
  dependencies: PayoutGatewayDependencies,
) {
  const pathname = new URL(request.url).pathname;
  if (pathname === "/healthz") {
    return request.method === "GET"
      ? json({ status: "ok" }, 200)
      : json({ error: { code: "method_not_allowed", ambiguous: false } }, 405);
  }
  if (pathname !== payoutGatewayPath) {
    return json({ error: { code: "not_found", ambiguous: false } }, 404);
  }
  if (request.method !== "POST") {
    return json({ error: { code: "method_not_allowed", ambiguous: false } }, 405);
  }
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return json({ error: { code: "invalid_content_type", ambiguous: false } }, 415);
  }
  let rawBody: string;
  try {
    rawBody = await readBoundedBody(request, 4_096);
  } catch {
    return json({ error: { code: "invalid_request_size", ambiguous: false } }, 413);
  }
  const signature = request.headers.get(payoutGatewaySignatureHeader) ?? "";
  if (!await verifyPayoutGatewaySignature(dependencies.secret, rawBody, signature)) {
    return json({ error: { code: "invalid_signature", ambiguous: false } }, 401);
  }
  let payoutRequest: ReturnType<typeof parsePayoutGatewayRequest>;
  try {
    payoutRequest = parsePayoutGatewayRequest(JSON.parse(rawBody));
    if (canonicalPayoutGatewayBody(payoutRequest) !== rawBody) {
      throw new Error("non-canonical request");
    }
  } catch {
    return json({ error: { code: "invalid_request", ambiguous: false } }, 400);
  }
  const now = (dependencies.now ?? (() => new Date()))();
  const requestTime = new Date(payoutRequest.timestamp);
  if (
    !Number.isSafeInteger(dependencies.maxClockSkewMilliseconds) ||
    dependencies.maxClockSkewMilliseconds < 1_000 ||
    Math.abs(now.valueOf() - requestTime.valueOf()) > dependencies.maxClockSkewMilliseconds
  ) {
    return json({ error: { code: "expired_request", ambiguous: false } }, 401);
  }
  const replayDigest = await sha256Hex(signature);
  const replayExpiresAt = new Date(
    Math.max(now.valueOf(), requestTime.valueOf()) + dependencies.maxClockSkewMilliseconds,
  );
  let replayClaimed: boolean;
  try {
    replayClaimed = await dependencies.replayStore.claim(replayDigest, replayExpiresAt);
  } catch {
    return json({ error: { code: "replay_store_unavailable", ambiguous: false } }, 503);
  }
  if (!replayClaimed) {
    return json({ error: { code: "replayed_request", ambiguous: true } }, 409);
  }
  const requestFingerprint = (await sha256Hex(payoutRequest.withdrawalId)).slice(0, 16);
  try {
    const result = await dependencies.executeProviderPayout(payoutRequest);
    if (
      result.withdrawalId !== payoutRequest.withdrawalId ||
      result.fundAccountReference !== payoutRequest.fundAccountReference ||
      result.amountPaise !== payoutRequest.amountPaise || result.currency !== "INR"
    ) throw new RazorpayXApiError(409, true, "payout_ownership_mismatch");
    dependencies.log?.({
      event: "payout_gateway_completed",
      requestFingerprint,
      providerStatus: result.status,
    });
    return json({ result }, 200);
  } catch (error) {
    if (error instanceof RazorpayXApiError) {
      dependencies.log?.({
        event: "payout_gateway_provider_error",
        requestFingerprint,
        ambiguous: error.ambiguous,
        code: safeCode(error.providerCode),
      });
      return json({
        error: {
          code: safeCode(error.providerCode),
          ambiguous: error.ambiguous,
        },
      }, error.ambiguous ? 502 : 422);
    }
    dependencies.log?.({
      event: "payout_gateway_internal_error",
      requestFingerprint,
    });
    return json({ error: { code: "gateway_internal_error", ambiguous: true } }, 500);
  }
}

async function readBoundedBody(request: Request, maximumBytes: number) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new Error("request too large");
  }
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximumBytes) {
      await reader.cancel();
      throw new Error("request too large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function safeCode(value: string) {
  return /^[a-z0-9_]{1,120}$/i.test(value) ? value.toLowerCase() : "provider_request_failed";
}

function json(body: unknown, status: number) {
  return Response.json(body, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}
