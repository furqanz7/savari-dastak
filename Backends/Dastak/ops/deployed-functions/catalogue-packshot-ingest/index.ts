import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "dastak-catalogue";
const MAX_BYTES = 8 * 1024 * 1024;
const MAX_REDIRECTS = 3;
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
  "idhayam.com",
  "www.idhayam.com",
  "daawat.com",
  "www.daawat.com",
  "cdn.daawat.com",
  "aachifoods.com",
  "www.aachifoods.com",
  "cdn.shopify.com",
]);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function allowedUrl(value: string | URL): URL {
  const url = value instanceof URL ? value : new URL(value);
  if (
    url.protocol !== "https:" || url.username || url.password ||
    !ALLOWED_HOSTS.has(url.hostname.toLowerCase())
  ) {
    throw new Error("SOURCE_HOST_NOT_ALLOWED");
  }
  return url;
}

async function fetchAllowed(start: URL): Promise<Response> {
  let current = allowedUrl(start);
  for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
    const response = await fetch(current, {
      redirect: "manual",
      headers: {
        "user-agent": "DastakCatalogueAssetIngest/2.0",
        "accept": "image/avif,image/webp,image/png,image/jpeg,*/*;q=0.1",
      },
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      if (redirects === MAX_REDIRECTS) throw new Error("TOO_MANY_REDIRECTS");
      const location = response.headers.get("location");
      if (!location) throw new Error("INVALID_REDIRECT");
      current = allowedUrl(new URL(location, current));
      continue;
    }
    return response;
  }
  throw new Error("TOO_MANY_REDIRECTS");
}

function adminKey(): string {
  const modern = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modern) {
    const parsed = JSON.parse(modern);
    if (typeof parsed?.default === "string" && parsed.default.length > 0) return parsed.default;
  }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!legacy) throw new Error("SUPABASE_ADMIN_KEY_UNAVAILABLE");
  return legacy;
}

async function sha256Hex(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((v) => v.toString(16).padStart(2, "0")).join("");
}

function expectedMime(path: string): string | null {
  const ext = path.toLowerCase().split(".").pop();
  if (ext === "jpg" || ext === "jpeg") return "image/jpeg";
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  try {
    const auth = req.headers.get("authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "UNAUTHORIZED" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = auth.slice("Bearer ".length);
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "UNAUTHORIZED" }, 401);

    // Database-enforced catalogue-admin authorization gate.
    const { error: permissionError } = await userClient.rpc("dastak_v1_catalogue_quality_summary");
    if (permissionError) return json({ error: "FORBIDDEN" }, 403);

    const payload = await req.json().catch(() => null) as {
      sourceUrl?: string;
      objectPath?: string;
    } | null;
    if (!payload?.sourceUrl || !payload?.objectPath) return json({ error: "INVALID_REQUEST" }, 400);

    let source: URL;
    try {
      source = allowedUrl(payload.sourceUrl);
    } catch {
      return json({ error: "SOURCE_HOST_NOT_ALLOWED" }, 400);
    }

    const objectPath = payload.objectPath.trim();
    if (
      !/^canonical\/[a-z0-9][a-z0-9/_-]{1,420}\.(?:jpg|jpeg|png|webp)$/i.test(objectPath) ||
      objectPath.includes("..")
    ) {
      return json({ error: "INVALID_OBJECT_PATH" }, 400);
    }

    let sourceResponse: Response;
    try {
      sourceResponse = await fetchAllowed(source);
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "SOURCE_FETCH_FAILED" }, 422);
    }
    if (!sourceResponse.ok) {
      return json({ error: "SOURCE_FETCH_FAILED", status: sourceResponse.status }, 422);
    }

    const finalUrl = allowedUrl(sourceResponse.url);
    const mime = (sourceResponse.headers.get("content-type") ?? "").split(";", 1)[0].trim()
      .toLowerCase();
    if (!ALLOWED_MIME.has(mime)) return json({ error: "SOURCE_MIME_NOT_ALLOWED", mime }, 422);
    if (expectedMime(objectPath) !== mime) {
      return json({ error: "OBJECT_EXTENSION_MIME_MISMATCH", mime }, 422);
    }

    const declaredLength = Number(sourceResponse.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > MAX_BYTES) {
      return json({ error: "SOURCE_TOO_LARGE" }, 413);
    }
    const bytes = new Uint8Array(await sourceResponse.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) {
      return json({ error: "SOURCE_TOO_LARGE" }, 413);
    }
    const checksum = await sha256Hex(bytes);

    const admin = createClient(supabaseUrl, adminKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: upload, error: uploadError } = await admin.storage.from(BUCKET).upload(
      objectPath,
      bytes,
      { contentType: mime, cacheControl: "31536000", upsert: false },
    );
    if (uploadError) {
      const message = String(uploadError.message ?? "");
      if (/already exists|duplicate/i.test(message)) {
        return json({ error: "OBJECT_ALREADY_EXISTS" }, 409);
      }
      throw uploadError;
    }

    return json({
      ok: true,
      bucket: BUCKET,
      path: upload.path,
      checksumSha256: checksum,
      bytes: bytes.byteLength,
      mimeType: mime,
      sourceUrl: finalUrl.toString(),
      actorId: userData.user.id,
    });
  } catch (error) {
    console.error(
      "catalogue-packshot-ingest failed",
      error instanceof Error ? error.message : "unknown error",
    );
    return json({ error: "INTERNAL_ERROR" }, 500);
  }
});
