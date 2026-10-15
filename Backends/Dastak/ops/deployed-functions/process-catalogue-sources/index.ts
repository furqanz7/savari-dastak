import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const MAX_BYTES = 16 * 1024 * 1024, MAX_REDIRECTS = 4;
const ALLOWED_HOSTS = new Set([
  "aachifoods.com",
  "www.aachifoods.com",
  "tatanutrikorner.com",
  "www.tatanutrikorner.com",
  "shop.orklaindia.com",
  "shop.mtrfoods.com",
  "orklaindia.com",
  "www.orklaindia.com",
  "shop.amul.com",
  "amul.com",
  "www.amul.com",
  "idhayam.com",
  "www.idhayam.com",
  "indiagatefoods.com",
  "www.indiagatefoods.com",
  "aashirvaad.com",
  "www.aashirvaad.com",
  "fortunefoods.com",
  "www.fortunefoods.com",
  "daawat.com",
  "www.daawat.com",
  "cdn.daawat.com",
  "hap.in",
  "www.hap.in",
  "world.openfoodfacts.org",
  "farmley.com",
  "www.farmley.com",
  "true-elements.com",
  "www.true-elements.com",
  "yogabars.in",
  "www.yogabars.in",
  "opensecret.in",
  "www.opensecret.in",
  "wingreensworld.com",
  "www.wingreensworld.com",
  "slurrpfarm.com",
  "www.slurrpfarm.com",
  "happilo.com",
  "www.happilo.com",
  "thewholetruthfoods.com",
  "www.thewholetruthfoods.com",
  "consciousfood.com",
  "www.consciousfood.com",
  "snackible.com",
  "www.snackible.com",
  "pintola.in",
  "www.pintola.in",
  "veeba.in",
  "www.veeba.in",
  "sleepyowl.co",
  "www.sleepyowl.co",
  "bluetokaicoffee.com",
  "www.bluetokaicoffee.com",
  "ragecoffee.com",
  "www.ragecoffee.com",
  "countrybean.in",
  "www.countrybean.in",
  "bevzilla.co",
  "www.bevzilla.co",
  "epigamiastore.com",
  "www.epigamiastore.com",
  "organictattva.com",
  "www.organictattva.com",
  "anveshan.farm",
  "www.anveshan.farm",
  "rosierfoods.com",
  "www.rosierfoods.com",
  "twobrothersindiashop.com",
  "www.twobrothersindiashop.com",
  "nourishorganics.in",
  "www.nourishorganics.in",
  "bagrrys.com",
  "www.bagrrys.com",
  "makhana.com",
  "www.makhana.com",
  "4700bc.com",
  "www.4700bc.com",
  "godesi.in",
  "www.godesi.in",
  "healthymaster.in",
  "www.healthymaster.in",
  "nuttygritties.com",
  "www.nuttygritties.com",
  "tagzfoods.com",
  "www.tagzfoods.com",
  "sweetkaramcoffee.in",
  "www.sweetkaramcoffee.in",
  "earlyfoods.com",
  "www.earlyfoods.com",
  "maxprotein.in",
  "www.maxprotein.in",
  "thebutternutcompany.com",
  "www.thebutternutcompany.com",
  "milletamma.com",
  "www.milletamma.com",
  "eatbetterco.com",
  "www.eatbetterco.com",
  "nourishyou.in",
  "www.nourishyou.in",
  "gladful.in",
  "www.gladful.in",
  "jabsons.com",
  "www.jabsons.com",
  "beyondsnack.in",
  "www.beyondsnack.in",
  "letstryfoods.com",
  "www.letstryfoods.com",
  "wonderlandfoods.in",
  "www.wonderlandfoods.in",
  "wickedgud.com",
  "www.wickedgud.com",
  "nutriorg.com",
  "www.nutriorg.com",
  "mrmakhana.com",
  "www.mrmakhana.com",
  "urbanplatter.in",
  "www.urbanplatter.in",
]);
const required = (n: string) => {
  const v = Deno.env.get(n);
  if (!v) throw new Error(`${n} is required`);
  return v;
};
const service = createClient(required("SUPABASE_URL"), required("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  }),
  expectedSecret = required("DASTAK_NOTIFICATION_SECRET"),
  workerId = Deno.env.get("DENO_DEPLOYMENT_ID") ?? `catalogue-sources-${crypto.randomUUID()}`;
const rec = (v: unknown) => {
    if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error("invalid crawl payload");
    return v as Record<string, unknown>;
  },
  txt = (v: unknown) => {
    if (typeof v !== "string" || !v) throw new Error("invalid crawl field");
    return v;
  };
const rpc = async (n: string, p: Record<string, unknown>) => {
  const { data, error } = await service.rpc(n, p);
  if (error) throw error;
  return data;
};
const imageUrl = (v: unknown): string | null => {
  if (typeof v === "string") return v.startsWith("//") ? `https:${v}` : v;
  if (v && typeof v === "object" && !Array.isArray(v)) {
    const s = (v as Record<string, unknown>).src;
    return typeof s === "string" ? (s.startsWith("//") ? `https:${s}` : s) : null;
  }
  return null;
};
const stable = (v: unknown): string =>
    v === null || typeof v !== "object"
      ? JSON.stringify(v)
      : Array.isArray(v)
      ? `[${v.map(stable).join(",")}]`
      : `{${
        Object.keys(v as Record<string, unknown>).sort().map((k) =>
          `${JSON.stringify(k)}:${stable((v as Record<string, unknown>)[k])}`
        ).join(",")
      }}`,
  sha = async (v: unknown) =>
    Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(stable(v)))),
    ).map((x) => x.toString(16).padStart(2, "0")).join("");
function timingSafeEqual(a: string, b: string) {
  const ae = new TextEncoder().encode(a),
    be = new TextEncoder().encode(b),
    n = Math.max(ae.length, be.length);
  let d = ae.length ^ be.length;
  for (let i = 0; i < n; i++) {
    d |= (ae[i % Math.max(ae.length, 1)] ?? 0) ^ (be[i % Math.max(be.length, 1)] ?? 0);
  }
  return d === 0;
}
function approved(u: URL) {
  if (
    u.protocol !== "https:" || u.username || u.password ||
    !ALLOWED_HOSTS.has(u.hostname.toLowerCase())
  ) throw new Error("source host not allowed");
  if (u.port && u.port !== "443") throw new Error("source port not allowed");
}
async function fetchJson(input: string) {
  let u = new URL(input);
  for (let r = 0; r <= MAX_REDIRECTS; r++) {
    approved(u);
    const res = await fetch(u, {
      redirect: "manual",
      headers: {
        "user-agent": "DastakCatalogueSourceWorker/1.9 (catalogue research)",
        accept: "application/json",
      },
      signal: AbortSignal.timeout(20000),
    });
    if ([301, 302, 303, 307, 308].includes(res.status)) {
      const loc = res.headers.get("location");
      if (!loc || r === MAX_REDIRECTS) throw new Error("source redirect rejected");
      u = new URL(loc, u);
      continue;
    }
    if (!res.ok) throw new Error(`source feed rejected (${res.status})`);
    const len = Number(res.headers.get("content-length") ?? "0");
    if (Number.isFinite(len) && len > MAX_BYTES) throw new Error("source feed too large");
    const body = await res.text();
    if (!body.length || body.length > MAX_BYTES) throw new Error("source feed size invalid");
    try {
      return JSON.parse(body);
    } catch {
      throw new Error("source feed is not JSON");
    }
  }
  throw new Error("source redirect limit exceeded");
}
async function parseShopify(payload: unknown, feedUrl: string) {
  const root = rec(payload), products = root.products;
  if (!Array.isArray(products)) throw new Error("Shopify feed missing products array");
  if (products.length > 2000) throw new Error("too many products in feed");
  const items: any[] = [];
  let variants = 0;
  for (const p0 of products) {
    const p = rec(p0),
      vs = Array.isArray(p.variants) ? p.variants : [],
      imgs = Array.isArray(p.images) ? p.images.map(imageUrl).filter(Boolean).slice(0, 12) : [];
    for (const v0 of vs) {
      const v = rec(v0),
        rawPayload = {
          source: "SHOPIFY_OFFICIAL_FEED",
          sourceUrl: feedUrl,
          sourceObservedAt: new Date().toISOString(),
          productId: p.id ?? null,
          productTitle: p.title ?? null,
          handle: p.handle ?? null,
          vendor: p.vendor ?? null,
          productType: p.product_type ?? null,
          tags: p.tags ?? null,
          publishedAt: p.published_at ?? null,
          createdAt: p.created_at ?? null,
          updatedAt: p.updated_at ?? null,
          variantId: v.id ?? null,
          variantTitle: v.title ?? null,
          sku: v.sku ?? null,
          barcode: v.barcode ?? null,
          price: v.price ?? null,
          compareAtPrice: v.compare_at_price ?? null,
          available: v.available ?? null,
          grams: v.grams ?? null,
          option1: v.option1 ?? null,
          option2: v.option2 ?? null,
          option3: v.option3 ?? null,
          featuredImage: imageUrl(v.featured_image),
          productImages: imgs,
          productPage: p.handle
            ? new URL(`/products/${p.handle}`, new URL(feedUrl)).toString()
            : null,
        };
      items.push({
        sourceKey: `shopify:${String(p.id ?? "")}:${String(v.id ?? "")}`,
        sourceFingerprint: await sha(rawPayload),
        rawPayload,
      });
      variants++;
    }
  }
  return { items, counts: { products: products.length, variants, candidates: items.length } };
}
const clean = (v: unknown) =>
    typeof v === "string" && v.trim() ? v.replace(/\s+/g, " ").trim().slice(0, 500) : null,
  nums = (v: unknown) => {
    const s = typeof v === "string" || typeof v === "number" ? String(v).trim() : "";
    return /^\d+$/.test(s) ? s : null;
  },
  arr = (v: unknown) =>
    Array.isArray(v)
      ? v.filter((x): x is string => typeof x === "string" && x.length > 0).slice(0, 100)
      : [],
  num = (v: unknown) =>
    typeof v === "number" && Number.isFinite(v)
      ? v
      : typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))
      ? Number(v)
      : null,
  https = (v: unknown) => {
    if (typeof v !== "string" || !v) return null;
    try {
      const u = new URL(v);
      return u.protocol === "https:" ? u.toString() : null;
    } catch {
      return null;
    }
  };
async function parseOFF(payload: unknown) {
  const root = rec(payload), ps = root.products;
  if (!Array.isArray(ps)) throw new Error("Open Food Facts response missing products array");
  if (ps.length > 1000) throw new Error("too many Open Food Facts products in page");
  const items: any[] = [];
  let discarded = 0;
  for (const p0 of ps) {
    const p = rec(p0), code = nums(p.code), name = clean(p.product_name), brands = clean(p.brands);
    if (!code || code.length < 8 || code.length > 14 || !name || !brands) {
      discarded++;
      continue;
    }
    const rawPayload = {
      source: "OPENFOODFACTS_V2",
      sourceType: "PUBLIC_REFERENCE",
      sourceObservedAt: new Date().toISOString(),
      sourceUrl: `https://world.openfoodfacts.org/product/${code}`,
      dataLicense: "ODbL",
      imageLicense: "CC BY-SA",
      code,
      productName: name,
      brands,
      quantity: clean(p.quantity),
      productQuantity: p.product_quantity ?? null,
      productQuantityUnit: clean(p.product_quantity_unit),
      categoriesTagsEn: arr(p.categories_tags_en),
      labelsTagsEn: arr(p.labels_tags_en),
      countriesTagsEn: arr(p.countries_tags_en),
      stores: clean(p.stores),
      packagingTagsEn: arr(p.packaging_tags_en),
      ingredientsText: clean(p.ingredients_text),
      completeness: num(p.completeness),
      lastModifiedT: num(p.last_modified_t),
      imageFrontUrl: https(p.image_front_url),
      imageFrontSmallUrl: https(p.image_front_small_url),
      imageFrontThumbUrl: https(p.image_front_thumb_url),
    };
    items.push({ sourceKey: `off:${code}`, sourceFingerprint: await sha(rawPayload), rawPayload });
  }
  const total = num(root.count), pageSize = num(root.page_size);
  return {
    items,
    counts: {
      totalResults: total,
      page: num(root.page),
      pageSize,
      returnedPageCount: num(root.page_count),
      totalPages: total !== null && pageSize && pageSize > 0
        ? Math.floor((total - 1) / pageSize) + 1
        : null,
      returnedProducts: ps.length,
      candidates: items.length,
      discarded,
    },
  };
}
const safe = (e: unknown) =>
    e instanceof Error
      ? e.message.slice(0, 1000)
      : String(e ?? "source crawl failed").slice(0, 1000),
  json = (b: unknown, s = 200) =>
    new Response(JSON.stringify(b), {
      status: s,
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    });
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: { code: "method_not_allowed" } }, 405);
  if (!timingSafeEqual(req.headers.get("x-dastak-internal-secret") ?? "", expectedSecret)) {
    return json({ error: { code: "forbidden" } }, 403);
  }
  try {
    const claimed = await rpc("dastak_v1_claim_catalogue_source_crawl_jobs", {
      p_worker_id: workerId,
      p_limit: 3,
    });
    if (!Array.isArray(claimed)) throw new Error("invalid crawl claim response");
    const results: any[] = [];
    for (const j0 of claimed) {
      const j = rec(j0);
      try {
        const parser = txt(j.parserType),
          jobId = txt(j.jobId),
          feed = txt(j.feedUrl),
          batchId = String(
            await rpc("dastak_v1_ensure_catalogue_source_crawl_batch", {
              p_job_id: jobId,
              p_worker_id: workerId,
            }),
          ),
          payload = await fetchJson(feed),
          parsed = parser === "SHOPIFY_PRODUCTS_JSON"
            ? await parseShopify(payload, feed)
            : parser === "OPENFOODFACTS_V2_SEARCH"
            ? await parseOFF(payload)
            : (() => {
              throw new Error("unsupported parser type");
            })(),
          ingest = rec(
            await rpc("dastak_v1_ingest_catalogue_source_raw_items", {
              p_batch_id: batchId,
              p_items: parsed.items,
            }),
          ),
          counts = {
            ...parsed.counts,
            batchTotal: Number(ingest.totalItems ?? parsed.items.length),
            inserted: Number(ingest.insertedItems ?? 0),
            updated: Number(ingest.updatedItems ?? 0),
          };
        await rpc("dastak_v1_complete_catalogue_source_crawl_job", {
          p_job_id: jobId,
          p_worker_id: workerId,
          p_succeeded: true,
          p_batch_id: batchId,
          p_counts: counts,
          p_error: null,
        });
        results.push({ jobId, ok: true, batchId, counts });
      } catch (e) {
        const m = safe(e);
        try {
          await rpc("dastak_v1_complete_catalogue_source_crawl_job", {
            p_job_id: txt(j.jobId),
            p_worker_id: workerId,
            p_succeeded: false,
            p_batch_id: null,
            p_counts: {},
            p_error: m,
          });
        } catch {}
        results.push({ jobId: j.jobId, ok: false, error: m });
      }
    }
    return json({
      workerId,
      claimed: claimed.length,
      completed: results.filter((x) => x.ok).length,
      failed: results.filter((x) => !x.ok).length,
      results,
    });
  } catch (e) {
    return json({ error: { code: "catalogue_source_worker_failed", message: safe(e) } }, 500);
  }
});
