import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import {
  BadgeCheck,
  Barcode,
  Boxes,
  CalendarClock,
  Check,
  ChevronDown,
  CircleAlert,
  Database,
  Factory,
  Image as ImageIcon,
  Leaf,
  Package,
  Percent,
  Search,
  Settings2,
  Tags,
  Upload,
} from "lucide-react";
import {
  getV1AdminCatalogue, getV1AdminCataloguePage, importV1AdminCatalogue, updateV1AdminSku,
  type DastakV1Auth, type V1AdminCataloguePageSku, type V1AdminSnapshot,
} from "./dastakV1";
import { catalogueImageUrl } from "./catalogue";
import { useAdminWorkspaceRefresh } from "./adminRefresh";

const importTemplate = `{
  "categories": [],
  "subcategories": [],
  "brands": [{ "slug": "example-brand", "name": "Example Brand", "status": "DRAFT" }],
  "skus": [{
    "categorySlug": "rice", "subcategorySlug": "ponni-rice", "brandSlug": "example-brand",
    "slug": "example-rice-1kg", "canonicalName": "Example Rice", "packSize": "1 kg",
    "listPricePaise": 10000, "sellingPricePaise": 9500, "currencyCode": "INR",
    "taxRateBps": 0, "status": "DRAFT", "logisticsAttributes": { "weightGrams": 1000 }
  }]
}`;

export function AdminCataloguePanel({ auth }: { auth: DastakV1Auth }) {
  const [snapshot, setSnapshot] = useState<V1AdminSnapshot>();
  const [skus, setSkus] = useState<V1AdminCataloguePageSku[]>([]);
  const [cursor, setCursor] = useState<{ name: string; skuId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [query, setQuery] = useState("");
  const [categoryTypeId, setCategoryTypeId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [subcategoryId, setSubcategoryId] = useState("");
  const [status, setStatus] = useState("");
  const [qaStatus, setQaStatus] = useState("");
  const [source, setSource] = useState(importTemplate);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const importKeys = useRef(new Map<string, string>());

  const filters = useMemo(() => ({
    query: query.trim(),
    categoryTypeId: categoryTypeId || undefined,
    categoryId: categoryId || undefined,
    subcategoryId: subcategoryId || undefined,
    status: status ? status as V1AdminCataloguePageSku["status"] : undefined,
    qaStatus: qaStatus ? qaStatus as V1AdminCataloguePageSku["qaStatus"] : undefined,
  }), [categoryId, categoryTypeId, qaStatus, query, status, subcategoryId]);

  const visibleCategories = useMemo(() => snapshot?.categories.filter((category) =>
    !categoryTypeId || category.categoryTypeId === categoryTypeId) ?? [], [categoryTypeId, snapshot]);
  const visibleSubcategories = useMemo(() => snapshot?.subcategories.filter((subcategory) =>
    (!categoryId || subcategory.categoryId === categoryId) &&
    (!categoryTypeId || visibleCategories.some((category) => category.id === subcategory.categoryId))) ?? [],
  [categoryId, categoryTypeId, snapshot, visibleCategories]);

  const loadMetadata = useCallback(async () => setSnapshot(await getV1AdminCatalogue(auth)), [auth]);
  const loadPage = useCallback(async (append: boolean, signal?: AbortSignal) => {
    if (append) setLoadingMore(true);
    else setLoading(true);
    try {
      const page = await getV1AdminCataloguePage({ ...auth, ...filters, limit: 50, cursor: append ? cursor : undefined, signal });
      setSkus((current) => append ? [...current, ...page.skus] : page.skus);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore);
      setError(undefined);
    } catch (loadError) {
      if (loadError instanceof DOMException && loadError.name === "AbortError") return;
      setError(message(loadError));
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [auth, cursor, filters]);

  useEffect(() => { void loadMetadata().catch((loadError) => setError(message(loadError))); }, [loadMetadata]);
  useEffect(() => {
    const controller = new AbortController();
    const timer = window.setTimeout(() => void loadPage(false, controller.signal), 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
    // Cursor changes only while appending and must not restart page one.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, filters]);

  const refresh = useCallback(async () => {
    setBusy(true);
    try { await Promise.all([loadMetadata(), loadPage(false)]); setError(undefined); }
    catch (refreshError) { setError(message(refreshError)); }
    finally { setBusy(false); }
  }, [loadMetadata, loadPage]);
  useAdminWorkspaceRefresh(refresh);

  const chooseCategoryType = (value: string) => {
    setCategoryTypeId(value);
    setCategoryId("");
    setSubcategoryId("");
  };
  const chooseCategory = (value: string) => {
    setCategoryId(value);
    setSubcategoryId("");
  };

  const runImport = async (event: FormEvent) => {
    event.preventDefault();
    let catalogue: unknown;
    try { catalogue = JSON.parse(source); } catch { setError("Import must be valid JSON."); return; }
    if (!catalogue || typeof catalogue !== "object" || Array.isArray(catalogue)) { setError("Import must be one catalogue object."); return; }
    const fingerprint = source.trim();
    const idempotencyKey = importKeys.current.get(fingerprint) ?? crypto.randomUUID();
    importKeys.current.set(fingerprint, idempotencyKey);
    setBusy(true); setError(undefined);
    try {
      await importV1AdminCatalogue({ ...auth, catalogue: catalogue as Record<string, unknown>, idempotencyKey });
      importKeys.current.delete(fingerprint);
      setNotice("Catalogue import committed atomically and recorded in audit history.");
      await refresh();
    } catch (importError) { setError(message(importError)); }
    finally { setBusy(false); }
  };

  const updateSku = async (sku: V1AdminCataloguePageSku, patch: Record<string, unknown>) => {
    setBusy(true); setError(undefined);
    try {
      await updateV1AdminSku({ ...auth, skuId: sku.id, expectedVersion: sku.version, patch, idempotencyKey: crypto.randomUUID() });
      setNotice(`${sku.name} was updated with version protection.`);
      await loadPage(false);
    } catch (updateError) { setError(message(updateError)); }
    finally { setBusy(false); }
  };

  return <section className="admin-section v1-admin-catalogue" role="tabpanel">
    <header className="admin-section-heading"><div><p className="eyebrow">MASTER CATALOGUE</p><h2>Every product, exactly represented</h2><p>Browse the same visual product truth customers see, with governed taxonomy, evidence, QA, pricing and visibility in one record.</p></div></header>
    {error ? <p className="order-error" role="alert"><CircleAlert size={16} /> {error}</p> : null}
    {notice ? <p className="v1-admin-notice" role="status"><Check size={17} /> {notice}</p> : null}
    {snapshot ? <>
      <div className="v1-admin-summary"><Summary label="Departments" value={snapshot.categoryTypes.length} /><Summary label="Categories" value={snapshot.categories.length} /><Summary label="Subcategories" value={snapshot.subcategories.length} /><Summary label="Canonical SKUs" value={snapshot.skuCount} /><Summary label="Retail branches" value={snapshot.branches.length} /></div>
      <section className="v1-admin-taxonomy"><header><Boxes size={20} /><div><h3>Catalogue hierarchy</h3><p>Department → category → subcategory → exact SKU</p></div></header><div>{snapshot.categoryTypes.map((type) => {
        const categories = snapshot.categories.filter((category) => category.categoryTypeId === type.id);
        const subcategoryCount = snapshot.subcategories.filter((subcategory) => categories.some((category) => category.id === subcategory.categoryId)).length;
        return <article key={type.id}><span><strong>{type.name}</strong><small>{categories.length} categories · {subcategoryCount} subcategories</small></span><em>{type.status}</em><p>{categories.slice(0, 5).map((category) => category.name).join(" · ") || "Classification pending"}</p></article>;
      })}</div></section>
      <section className="v1-admin-config"><header><Settings2 size={20} /><div><h3>Launch configuration</h3><p>Effective settings and validation state for the customer catalogue.</p></div></header><div>{snapshot.configuration.map((setting) => <article key={setting.key} className={!setting.valid || (setting.required && !setting.explicit) ? "attention" : ""}><code>{setting.key}</code><strong>{displayValue(setting.value)}</strong><span>{setting.explicit ? "Explicit" : "Default"} · {setting.valid ? "Valid" : "Invalid"}</span></article>)}</div></section>
    </> : null}
    <section className="v1-admin-skus">
      <header><Tags size={20} /><div><h3>SKU library</h3><p>Only QA-ready exact products with valid pricing and imagery can be activated.</p></div></header>
      <div className="admin-catalogue-toolbar">
        <label className="admin-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search SKU, brand, alias or category" aria-label="Search catalogue" /></label>
        <Select label="Department" value={categoryTypeId} onChange={chooseCategoryType}><option value="">All departments</option>{snapshot?.categoryTypes.map((type) => <option value={type.id} key={type.id}>{type.name}</option>)}</Select>
        <Select label="Category" value={categoryId} onChange={chooseCategory}><option value="">All categories</option>{visibleCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}</Select>
        <Select label="Subcategory" value={subcategoryId} onChange={setSubcategoryId}><option value="">All subcategories</option>{visibleSubcategories.map((subcategory) => <option value={subcategory.id} key={subcategory.id}>{subcategory.name}</option>)}</Select>
        <Select label="Visibility" value={status} onChange={setStatus}><option value="">Any status</option><option value="ACTIVE">Active</option><option value="DRAFT">Draft</option><option value="INACTIVE">Inactive</option></Select>
        <Select label="QA" value={qaStatus} onChange={setQaStatus}><option value="">Any QA state</option><option value="VERIFIED">Verified</option><option value="NEEDS_REVIEW">Needs review</option><option value="PENDING">Pending</option><option value="REJECTED">Rejected</option></Select>
      </div>
      {loading ? <div className="catalogue-loading" role="status"><span /> Loading exact SKUs</div> : skus.length === 0 ? <div className="admin-empty-state"><Database size={28} /><h3>No SKUs match these filters</h3><p>Clear a filter or search for another exact product.</p></div> : <div className="v1-admin-sku-list">{skus.map((sku) => <SkuEditor key={`${sku.id}:${sku.version}`} sku={sku} supabaseUrl={auth.supabaseUrl} disabled={busy} onSave={updateSku} />)}</div>}
      {hasMore ? <button type="button" className="admin-load-more wide" onClick={() => void loadPage(true)} disabled={loadingMore}>{loadingMore ? "Loading more…" : "Load next 50 SKUs"}</button> : null}
    </section>
    <details className="v1-admin-import"><summary><Upload size={18} /><span><strong>Advanced atomic import</strong><small>Imports enter Draft and require taxonomy, QA, price and cleared imagery before activation</small></span><ChevronDown size={17} /></summary><form onSubmit={runImport}><label htmlFor="v1-catalogue-import">Catalogue JSON</label><textarea id="v1-catalogue-import" value={source} onChange={(event) => setSource(event.target.value)} rows={16} spellCheck={false} disabled={busy} /><p className="field-help">Use approved taxonomy slugs. A successful import does not make a product customer-visible.</p><button className="primary-button" type="submit" disabled={busy}>{busy ? "Importing…" : "Validate and import as Draft"}</button></form></details>
  </section>;
}

function SkuEditor({ sku, supabaseUrl, disabled, onSave }: { sku: V1AdminCataloguePageSku; supabaseUrl: string; disabled: boolean; onSave: (sku: V1AdminCataloguePageSku, patch: Record<string, unknown>) => Promise<void> }) {
  const [listPrice, setListPrice] = useState(sku.listPricePaise === undefined ? "" : (sku.listPricePaise / 100).toFixed(2));
  const [sellingPrice, setSellingPrice] = useState(sku.sellingPricePaise === undefined ? "" : (sku.sellingPricePaise / 100).toFixed(2));
  const [status, setStatus] = useState(sku.status);
  const listPricePaise = priceInPaise(listPrice);
  const sellingPricePaise = priceInPaise(sellingPrice);
  const changed = listPricePaise !== sku.listPricePaise || sellingPricePaise !== sku.sellingPricePaise || status !== sku.status;
  const valid = listPricePaise !== undefined && sellingPricePaise !== undefined && sellingPricePaise <= listPricePaise;
  const activatingWithoutEvidence = status === "ACTIVE" && sku.status !== "ACTIVE" && !sku.activationReady;
  const canSave = valid && changed && !activatingWithoutEvidence;
  return <form className="admin-sku-card" onSubmit={(event) => { event.preventDefault(); if (canSave) void onSave(sku, { listPricePaise, sellingPricePaise, status }); }}>
    <div className="admin-sku-customer-preview">
      <SkuArtwork sku={sku} supabaseUrl={supabaseUrl} />
      <div className="admin-sku-copy">
        <p className="admin-sku-breadcrumb"><span>{sku.categoryTypeName ?? "Unclassified department"}</span><i>›</i><span>{sku.categoryName}</span><i>›</i><span>{sku.subcategoryName}</span></p>
        <h4>{sku.name}</h4>
        <p className="admin-sku-byline">{[sku.brandName, sku.variant, sku.packSize].filter(Boolean).join(" · ")}</p>
        <p className="admin-sku-description">{sku.description ?? "Customer-facing product description has not been added yet."}</p>
        <div className="admin-sku-chips"><span>{sku.dietType === "NONE" ? "General" : label(sku.dietType)}</span><span>{sku.currencyCode}</span><span>v{sku.version}</span><span className={sku.status === "ACTIVE" ? "positive" : ""}>{label(sku.status)}</span></div>
      </div>
    </div>

    <section className="admin-sku-commercial" aria-label={`${sku.name} commercial controls`}>
      <div className="admin-sku-price-summary"><small>Customer price</small><strong>{formatPaise(sku.sellingPricePaise)}</strong>{sku.listPricePaise !== sku.sellingPricePaise ? <s>{formatPaise(sku.listPricePaise)}</s> : null}</div>
      <label><span>MRP (₹)</span><input inputMode="decimal" value={listPrice} onChange={(event) => setListPrice(event.target.value)} placeholder="Not set" aria-label={`${sku.name} MRP`} /></label>
      <label><span>Selling (₹)</span><input inputMode="decimal" value={sellingPrice} onChange={(event) => setSellingPrice(event.target.value)} placeholder="Not set" aria-label={`${sku.name} selling price`} /></label>
      <label><span>Visibility</span><select value={status} onChange={(event) => setStatus(event.target.value as V1AdminCataloguePageSku["status"])} aria-label={`${sku.name} visibility`}><option value="DRAFT">Draft</option><option value="ACTIVE" disabled={!sku.activationReady && sku.status !== "ACTIVE"}>Active</option><option value="INACTIVE">Inactive</option></select></label>
      <span className={`v1-admin-status ${sku.activationReady ? "active" : "inactive"}`}><BadgeCheck size={15} /><span><b>{label(sku.qaStatus)}</b><small>{sku.activationReady ? "Ready to activate" : blockerSummary(sku.activationBlockers)}</small></span></span>
      <button className="secondary-button" type="submit" disabled={disabled || !canSave}>{changed ? "Save changes" : "Up to date"}</button>
    </section>

    <details className="admin-sku-record">
      <summary><span><strong>Full product record</strong><small>Identity, classification, evidence, compliance and operations</small></span><ChevronDown size={17} /></summary>
      <div className="admin-sku-facts">
        <SkuFact icon={<Tags />} label="Department" value={sku.categoryTypeName ?? "Not classified"} />
        <SkuFact icon={<Tags />} label="Category" value={sku.categoryName} />
        <SkuFact icon={<Tags />} label="Subcategory" value={sku.subcategoryName} />
        <SkuFact icon={<Package />} label="Canonical pack" value={formatQuantity(sku)} />
        <SkuFact icon={<Factory />} label="Manufacturer" value={sku.manufacturerName ?? "Not recorded"} />
        <SkuFact icon={<Leaf />} label="Diet type" value={label(sku.dietType)} />
        <SkuFact icon={<CalendarClock />} label="Shelf life" value={sku.shelfLifeDays ? `${sku.shelfLifeDays} days` : "Not recorded"} />
        <SkuFact icon={<Barcode />} label="Barcode / HSN" value={[sku.barcode, sku.hsnCode].filter(Boolean).join(" · ") || "Not recorded"} />
        <SkuFact icon={<Percent />} label="Tax" value={`${(sku.taxRateBps / 100).toFixed(2)}%`} />
        <SkuFact icon={<Boxes />} label="Merchant selections" value={sku.selectionCount.toLocaleString("en-IN")} />
        <SkuFact icon={<ImageIcon />} label="Image evidence" value={`${sku.imageCount} images · ${sku.primaryImage?.rightsStatus ?? "No primary rights state"}`} />
        <SkuFact icon={<Search />} label="Discovery data" value={`${sku.identifierCount} identifiers · ${sku.aliasCount} aliases`} />
      </div>
      <div className="admin-sku-technical"><span><strong>Country of origin</strong>{sku.countryOfOriginCode ?? "Not recorded"}</span><span><strong>SKU</strong>{sku.id}</span><span><strong>Slug</strong>{sku.slug}</span><span><strong>Updated</strong>{formatDate(sku.updatedAt)}</span><span className="wide"><strong>Logistics</strong>{readableObject(sku.logisticsAttributes)}</span><span className="wide"><strong>Attributes</strong>{readableObject(sku.attributes)}</span></div>
    </details>
  </form>;
}

function SkuArtwork({ sku, supabaseUrl }: { sku: V1AdminCataloguePageSku; supabaseUrl: string }) {
  const imageKey = sku.primaryImage?.imageKey ?? sku.imageKey;
  const [failed, setFailed] = useState(false);
  const source = imageKey ? catalogueImageUrl(supabaseUrl, imageKey) : undefined;
  return <span className={`admin-sku-artwork ${source && !failed ? "ready" : "missing"}`}>
    {source && !failed ? <img src={source} alt={`${sku.name}, ${sku.packSize}`} loading="lazy" decoding="async" onError={() => setFailed(true)} /> : <><ImageIcon size={28} /><small>Image pending</small></>}
  </span>;
}

function SkuFact({ icon, label: factLabel, value }: { icon: ReactNode; label: string; value: string }) {
  return <div><span>{icon}</span><p><small>{factLabel}</small><strong>{value}</strong></p></div>;
}

function Select({ label, value, onChange, children }: { label: string; value: string; onChange: (value: string) => void; children: ReactNode }) { return <label><span>{label}</span><select value={value} onChange={(event) => onChange(event.target.value)}>{children}</select><ChevronDown size={14} /></label>; }
function Summary({ label, value }: { label: string; value: number }) { return <div><strong>{value.toLocaleString("en-IN")}</strong><span>{label}</span></div>; }
function displayValue(value: unknown) { if (value === null) return "Not set"; if (typeof value === "object") return JSON.stringify(value); return String(value); }
function priceInPaise(value: string) {
  const normalized = value.trim();
  if (!normalized) return undefined;
  const amount = Number(normalized);
  return Number.isFinite(amount) && amount >= 0 ? Math.round(amount * 100) : undefined;
}
function message(error: unknown) { return error instanceof Error ? error.message : "The catalogue operation could not be completed."; }
function label(value: string) { return value.replaceAll("_", " ").toLowerCase().replace(/\b\w/g, (character) => character.toUpperCase()); }
function formatPaise(value?: number) { return value === undefined ? "Not set" : new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(value / 100); }
function formatDate(value: string) { return new Date(value).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }); }
function formatQuantity(sku: V1AdminCataloguePageSku) {
  const quantity = sku.quantityValue === undefined ? sku.packSize : `${sku.quantityValue} ${sku.quantityUnit ?? ""}`.trim();
  return sku.packCount && sku.packCount > 1 ? `${sku.packCount} × ${quantity}` : quantity;
}
function readableObject(value: Record<string, unknown>) {
  const entries = Object.entries(value);
  return entries.length === 0 ? "Not recorded" : entries.map(([key, entry]) => `${label(key)}: ${String(entry)}`).join(" · ");
}
function blockerSummary(blockers: string[]) {
  if (blockers.length === 0) return "Complete required catalogue evidence";
  const labels: Record<string, string> = {
    QA_VERIFIED_REQUIRED: "Complete QA verification",
    DASTAK_PRICING_REQUIRED: "Set Dastak pricing",
    CATEGORY_TYPE_ACTIVE_REQUIRED: "Assign an active department",
    CATEGORY_ACTIVE_REQUIRED: "Activate its category",
    SUBCATEGORY_ACTIVE_REQUIRED: "Activate its subcategory",
    BRAND_ACTIVE_REQUIRED: "Activate its brand",
    SOURCE_PROVENANCE_REQUIRED: "Add source provenance",
    PRIMARY_IMAGE_REQUIRED: "Add a primary image",
    PRIMARY_IMAGE_VERIFICATION_REQUIRED: "Verify its primary image",
    IMAGE_RIGHTS_CLEARANCE_REQUIRED: "Clear image usage rights",
  };
  return blockers.map((blocker) => labels[blocker] ?? blocker.replaceAll("_", " ").toLowerCase()).join(" · ");
}
