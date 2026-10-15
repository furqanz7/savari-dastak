import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "dastak-catalogue";
const MAX_BYTES = 8 * 1024 * 1024;
const MAX_REDIRECTS = 5;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const ALLOWED_HOSTS = new Set([
  "indiagatefoods.com",
  "www.indiagatefoods.com",
  "aashirvaad.com",
  "www.aashirvaad.com",
  "s7ap1.scene7.com",
  "fortunefoods.com",
  "www.fortunefoods.com",
  "amul.com",
  "www.amul.com",
  "old.amul.com",
  "uat.amul.com",
  "assets.amul.com",
  "shop.amul.com",
  "shop.mtrfoods.com",
  "shop.orklaindia.com",
  "www.orklaindia.com",
  "orklaindia.com",
  "idhayam.com",
  "www.idhayam.com",
  "daawat.com",
  "www.daawat.com",
  "cdn.daawat.com",
  "aachifoods.com",
  "www.aachifoods.com",
  "cdn.shopify.com",
  "tatanutrikorner.com",
  "www.tatanutrikorner.com",
  "hap.in",
  "www.hap.in",
]);

const supabaseUrl = requiredEnv("SUPABASE_URL");
const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
const expectedSecret = requiredEnv("DASTAK_NOTIFICATION_SECRET");
const service = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const workerId = Deno.env.get("DENO_DEPLOYMENT_ID") ?? `catalogue-assets-${crypto.randomUUID()}`;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: { code: "method_not_allowed" } }, 405);
  const supplied = req.headers.get("x-dastak-internal-secret") ?? "";
  if (!timingSafeEqual(supplied, expectedSecret)) {
    return json({ error: { code: "forbidden" } }, 403);
  }
  try {
    const jobs = array(
      await rpc("dastak_v1_claim_catalogue_asset_jobs", { p_worker_id: workerId, p_limit: 20 }),
    );
    const results = [];
    for (const raw of jobs) {
      const job = record(raw);
      try {
        const sourceUrl = text(job.sourceUrl);
        const logicalObjectPath = text(job.objectPath);
        const fetched = await fetchApprovedImage(sourceUrl);
        const objectPath = storagePathForMime(logicalObjectPath, fetched.mimeType);
        const checksum = await sha256Hex(fetched.bytes);
        await uploadOrConfirm(objectPath, fetched.bytes, fetched.mimeType, checksum);
        await rpc("dastak_v1_complete_catalogue_asset_job", {
          p_job_id: text(job.jobId),
          p_worker_id: workerId,
          p_succeeded: true,
          p_image_key: objectPath,
          p_checksum_sha256: checksum,
          p_mime_type: fetched.mimeType,
          p_byte_size: fetched.bytes.byteLength,
          p_source_reference: fetched.finalUrl,
          p_error: null,
        });
        results.push({ jobId: job.jobId, ok: true, path: objectPath });
      } catch (error) {
        const message = safeError(error);
        try {
          await rpc("dastak_v1_complete_catalogue_asset_job", {
            p_job_id: text(job.jobId),
            p_worker_id: workerId,
            p_succeeded: false,
            p_image_key: null,
            p_checksum_sha256: null,
            p_mime_type: null,
            p_byte_size: null,
            p_source_reference: null,
            p_error: message,
          });
        } catch (completionError) {
          console.error("catalogue asset failure completion failed", safeError(completionError));
        }
        results.push({ jobId: job.jobId, ok: false, error: message });
      }
    }
    return json({
      workerId,
      claimed: jobs.length,
      completed: results.filter((r) => r.ok).length,
      failed: results.filter((r) => !r.ok).length,
      results,
    });
  } catch (error) {
    console.error("catalogue asset worker failed", safeError(error));
    return json({ error: { code: "catalogue_asset_worker_failed" } }, 500);
  }
});

async function fetchApprovedImage(input: string) {
  let url = new URL(input);
  for (let redirect = 0; redirect <= MAX_REDIRECTS; redirect++) {
    assertApprovedUrl(url);
    const response = await fetch(url, {
      redirect: "manual",
      headers: {
        "user-agent": "DastakCatalogueAssetWorker/1.2",
        accept: "image/webp,image/png,image/jpeg,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(15000),
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location || redirect === MAX_REDIRECTS) throw new Error("source redirect rejected");
      url = new URL(location, url);
      continue;
    }
    if (!response.ok) throw new Error(`source fetch rejected (${response.status})`);
    const mimeType = (response.headers.get("content-type") ?? "").split(";", 1)[0].trim()
      .toLowerCase();
    if (!ALLOWED_MIME.has(mimeType)) {
      throw new Error(`source MIME not allowed (${mimeType || "missing"})`);
    }
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (Number.isFinite(declared) && declared > MAX_BYTES) {
      throw new Error("source image too large");
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) {
      throw new Error("source image size invalid");
    }
    return { bytes, mimeType, finalUrl: url.toString() };
  }
  throw new Error("source redirect limit exceeded");
}

function storagePathForMime(path: string, mimeType: string) {
  if (!/^canonical\/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$/i.test(path) || path.includes("..")) {
    throw new Error("invalid object path");
  }
  const extension = mimeType === "image/jpeg"
    ? "jpg"
    : mimeType === "image/png"
    ? "png"
    : mimeType === "image/webp"
    ? "webp"
    : null;
  if (!extension) throw new Error("source MIME not allowed");
  return path.replace(/\.(jpg|jpeg|png|webp)$/i, `.${extension}`);
}

async function uploadOrConfirm(
  path: string,
  bytes: Uint8Array,
  mimeType: string,
  checksum: string,
) {
  assertPathMime(path, mimeType);
  const { error } = await service.storage.from(BUCKET).upload(path, bytes, {
    contentType: mimeType,
    cacheControl: "31536000",
    upsert: false,
  });
  if (!error) return;
  if (!/already exists|duplicate/i.test(String(error.message ?? ""))) throw error;
  const existing = await service.storage.from(BUCKET).download(path);
  if (existing.error || !existing.data) throw new Error("existing object could not be verified");
  const existingBytes = new Uint8Array(await existing.data.arrayBuffer());
  const existingChecksum = await sha256Hex(existingBytes);
  if (existingChecksum !== checksum) {
    throw new Error("object path collision with different content");
  }
}
function assertApprovedUrl(url: URL) {
  if (
    url.protocol !== "https:" || url.username || url.password ||
    !ALLOWED_HOSTS.has(url.hostname.toLowerCase())
  ) throw new Error("source host not allowed");
  if (url.port && url.port !== "443") throw new Error("source port not allowed");
}
function assertPathMime(path: string, mime: string) {
  if (!/^canonical\/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$/i.test(path) || path.includes("..")) {
    throw new Error("invalid object path");
  }
  const ext = path.split(".").pop()!.toLowerCase();
  if (
    (mime === "image/jpeg" && !["jpg", "jpeg"].includes(ext)) ||
    (mime === "image/png" && ext !== "png") || (mime === "image/webp" && ext !== "webp")
  ) throw new Error("object extension does not match MIME");
}
async function rpc(name: string, params: Record<string, unknown>) {
  const { data, error } = await service.rpc(name, params);
  if (error) throw error;
  return data;
}
async function sha256Hex(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((v) => v.toString(16).padStart(2, "0")).join("");
}
function timingSafeEqual(a: string, b: string) {
  const ae = new TextEncoder().encode(a), be = new TextEncoder().encode(b);
  const n = Math.max(ae.length, be.length);
  let diff = ae.length ^ be.length;
  for (let i = 0; i < n; i++) {
    diff |= (ae[i % Math.max(ae.length, 1)] ?? 0) ^ (be[i % Math.max(be.length, 1)] ?? 0);
  }
  return diff === 0;
}
function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}
function array(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new Error("invalid asset claim response");
  return value;
}
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid asset job");
  }
  return value as Record<string, unknown>;
}
function text(value: unknown): string {
  if (typeof value !== "string" || !value) throw new Error("invalid asset job field");
  return value;
}
function safeError(error: unknown) {
  if (error instanceof Error) return error.message.slice(0, 1000);
  if (error && typeof error === "object") {
    const source = error as Record<string, unknown>;
    const message = typeof source.message === "string" ? source.message : JSON.stringify(source);
    return message.slice(0, 1000);
  }
  return String(error).slice(0, 1000);
}
