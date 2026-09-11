import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import {
  BadgeCheck,
  Barcode,
  Boxes,
  CalendarClock,
  Check,
  ChevronDown,
  ChevronRight,
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
  X,
} from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import {
  getV1AdminCatalogue, getV1AdminCataloguePage, importV1AdminCatalogue, updateV1AdminSku,
  type DastakV1Auth, type V1AdminCataloguePageSku, type V1AdminSnapshot,
} from "./dastakV1";
import { catalogueImageUrl } from "./catalogue";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

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
  const [pageLoaded, setPageLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [editingSku, setEditingSku] = useState<V1AdminCataloguePageSku>();
  const [reconciliationBlocked, setReconciliationBlocked] = useState(false);
  const [intent, setIntent] = useState<{
    dialog: AdminPrivilegedActionIntent;
    identity: string;
    mutate: (idempotencyKey: string) => Promise<unknown>;
    success: string;
    closeEditor?: boolean;
  }>();
  const headingRef = useRef<HTMLElement>(null);
  const pageGeneration = useRef(0);
  const pageController = useRef<AbortController | undefined>(undefined);
  const refreshQueue = useRef(new RefreshQueue());
  const { reportRequestError } = useAdminRuntime();
  useEffect(() => {
    if (categoryTypeId) headingRef.current?.scrollIntoView({ block: "start" });
  }, [categoryTypeId]);

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

  const artworkKeys = useMemo(() => {
    const categories = new Map<string, string>();
    const subcategories = new Map<string, string>();
    for (const sku of [...(snapshot?.skus ?? []), ...skus]) {
      const imageKey = sku.imageKey;
      if (!imageKey) continue;
      if (!categories.has(sku.categoryId)) categories.set(sku.categoryId, imageKey);
      if (!subcategories.has(sku.subcategoryId)) subcategories.set(sku.subcategoryId, imageKey);
    }
    return { categories, subcategories };
  }, [skus, snapshot]);

  const loadMetadata = useCallback(async (signal?: AbortSignal) => setSnapshot(await getV1AdminCatalogue({ ...auth, signal })), [auth]);
  const loadPage = useCallback(async (append: boolean, signal?: AbortSignal) => {
    const generation = ++pageGeneration.current;
    if (append) setLoadingMore(true);
    else setLoading(true);
    try {
      const page = await getV1AdminCataloguePage({ ...auth, ...filters, limit: 50, cursor: append ? cursor : undefined, signal });
      if (signal?.aborted || generation !== pageGeneration.current) return;
      setSkus((current) => append ? [...current, ...page.skus] : page.skus);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore);
      setPageLoaded(true);
      setError(undefined);
    } catch (loadError) {
      if (signal?.aborted || generation !== pageGeneration.current) return;
      reportRequestError(loadError);
      setError(message(loadError));
      throw loadError;
    } finally {
      if (generation === pageGeneration.current) {
        setLoading(false);
        setLoadingMore(false);
      }
    }
  }, [auth, cursor, filters, reportRequestError]);

  useEffect(() => {
    const controller = new AbortController();
    void loadMetadata(controller.signal).catch((loadError) => {
      if (!controller.signal.aborted) { reportRequestError(loadError); setError(message(loadError)); }
    });
    return () => controller.abort();
  }, [loadMetadata, reportRequestError]);
  useEffect(() => {
    pageController.current?.abort();
    const controller = new AbortController();
    pageController.current = controller;
    setPageLoaded(false);
    const timer = window.setTimeout(() => void loadPage(false, controller.signal).catch(() => undefined), 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
    // Cursor changes only while appending and must not restart page one.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, filters]);

  const reconcileCatalogue = useCallback(async () => {
    pageController.current?.abort();
    const controller = new AbortController();
    pageController.current = controller;
    const generation = ++pageGeneration.current;
    const [metadata, page] = await Promise.all([
      getV1AdminCatalogue({ ...auth, signal: controller.signal }),
      getV1AdminCataloguePage({ ...auth, ...filters, limit: 50, signal: controller.signal }),
    ]);
    if (controller.signal.aborted || generation !== pageGeneration.current) return;
    setSnapshot(metadata); setSkus(page.skus); setCursor(page.nextCursor); setHasMore(page.hasMore); setPageLoaded(true);
  }, [auth, filters]);

  const refresh = useCallback(() => refreshQueue.current.request(false, async () => {
    try { await reconcileCatalogue(); setError(undefined); }
    catch (refreshError) { reportRequestError(refreshError); setError(message(refreshError)); throw refreshError; }
  }), [reconcileCatalogue, reportRequestError]);
  useAdminWorkspaceRefresh("catalogue", refresh);
  const loadMore = useCallback(async () => {
    pageController.current?.abort();
    const controller = new AbortController();
    pageController.current = controller;
    await loadPage(true, controller.signal);
  }, [loadPage]);

  const chooseCategoryType = (value: string) => {
    const children = value ? snapshot?.categories.filter((item) => item.categoryTypeId === value) ?? [] : [];
    setCategoryTypeId(value);
    setCategoryId((children.find((item) => item.status === "ACTIVE") ?? children[0])?.id ?? "");
    setSubcategoryId("");
  };
  const chooseCategory = (value: string) => {
    setCategoryId(value);
    if (value) setCategoryTypeId(snapshot?.categories.find((item) => item.id === value)?.categoryTypeId ?? "");
    setSubcategoryId("");
  };

  const runImport = (event: FormEvent) => {
    event.preventDefault();
    let catalogue: unknown;
    try { catalogue = JSON.parse(source); } catch { setError("Import must be valid JSON."); return; }
    if (!catalogue || typeof catalogue !== "object" || Array.isArray(catalogue)) { setError("Import must be one catalogue object."); return; }
    const fingerprint = source.trim();
    const payload = catalogue as Record<string, unknown>;
    const counts = ["categories", "subcategories", "brands", "skus"].map((key) =>
      `${Array.isArray(payload[key]) ? (payload[key] as unknown[]).length : 0} ${key}`).join(" · ");
    setIntent({
      identity: `catalogue-import:${fingerprint}`,
      success: "Catalogue import committed atomically and recorded in audit history.",
      dialog: {
        title: "Import this catalogue payload?", entityLabel: "Draft catalogue changes", entityValue: counts,
        currentState: "Existing authoritative catalogue", resultingState: "Validated records imported as Draft",
        consequence: "This atomic operation can create or update many shared catalogue records. Imported products remain Draft and are not customer-visible until their separate readiness gates pass.",
        confirmLabel: "Import as Draft", tone: "danger",
      },
      mutate: (idempotencyKey) => importV1AdminCatalogue({ ...auth, catalogue: payload, idempotencyKey }),
    });
  };

  const updateSku = async (sku: V1AdminCataloguePageSku, patch: Record<string, unknown>) => {
    const nextStatus = typeof patch.status === "string" ? patch.status : sku.status;
    const nextPrice = typeof patch.sellingPricePaise === "number" ? patch.sellingPricePaise : sku.sellingPricePaise;
    setIntent({
      identity: `catalogue-sku:${sku.id}:${sku.version}:${JSON.stringify(patch)}`,
      success: `${sku.name} was updated with version protection.`, closeEditor: true,
      dialog: {
        title: `Save changes to ${sku.name}?`, entityLabel: "Canonical SKU", entityValue: `${sku.name} · ${sku.id}`,
        currentState: `${label(sku.status)} · ${formatPaise(sku.sellingPricePaise)} · version ${sku.version}`,
        resultingState: `${label(nextStatus)} · ${formatPaise(nextPrice)}`,
        consequence: "This updates the shared authoritative product record, including customer pricing and visibility where changed. Existing order snapshots remain immutable.",
        confirmLabel: "Save authoritative SKU", tone: nextStatus === "INACTIVE" ? "danger" : "primary",
      },
      mutate: (idempotencyKey) => updateV1AdminSku({ ...auth, skuId: sku.id, expectedVersion: sku.version, patch, idempotencyKey }),
    });
  };

  const confirmMutation = async () => {
    if (!intent || busy) return;
    setBusy(true); setError(undefined); setNotice(undefined); setReconciliationBlocked(false);
    const result = await runAdminPrivilegedMutation({ operationIdentity: intent.identity, mutate: intent.mutate, reconcile: reconcileCatalogue });
    setBusy(false);
    if (result.kind === "completed") {
      setNotice(intent.success);
      if (intent.closeEditor) setEditingSku(undefined);
      setIntent(undefined);
    } else if (result.kind === "reconciled" || result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      if (result.kind === "reconciled") setIntent(undefined);
    } else if (result.kind === "uncertain_blocked") {
      setReconciliationBlocked(true); setError(result.message);
    } else { reportRequestError(result.error); setError(message(result.error)); }
  };

  const showProducts = Boolean(query.trim() || categoryTypeId || categoryId || subcategoryId || status || qaStatus);
  const selectedType = snapshot?.categoryTypes.find((type) => type.id === categoryTypeId);
  const navigationGroups = adminNavigationGroups(snapshot?.categoryTypes ?? []);

  return <section className="admin-section v1-admin-catalogue" role="tabpanel">
    <header ref={headingRef} className="admin-section-heading admin-catalogue-heading"><div><p className="eyebrow">MASTER CATALOGUE</p><h2>{selectedType?.name ?? "Everything, beautifully organised"}</h2><p>{categoryTypeId ? "Open any product to manage its exact record, visibility and readiness." : "The same image-led catalogue customers and merchants browse."}</p></div>{categoryTypeId ? <button type="button" className="admin-directory-back" onClick={() => chooseCategoryType("")}>All categories</button> : null}</header>
    {error ? <p className="order-error" role="alert"><CircleAlert size={16} /> {error}</p> : null}
    {notice ? <p className="v1-admin-notice" role="status"><Check size={17} /> {notice}</p> : null}
    <div className="admin-catalogue-toolbar">
      <label className="admin-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search SKU, brand, alias or category" aria-label="Search catalogue" /></label>
      <Select label="Department" value={categoryTypeId} onChange={chooseCategoryType}><option value="">All departments</option>{snapshot?.categoryTypes.map((type) => <option value={type.id} key={type.id}>{type.name}</option>)}</Select>
      <Select label="Category" value={categoryId} onChange={chooseCategory}><option value="">All categories</option>{visibleCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}</Select>
      <Select label="Subcategory" value={subcategoryId} onChange={setSubcategoryId}><option value="">All subcategories</option>{visibleSubcategories.map((subcategory) => <option value={subcategory.id} key={subcategory.id}>{subcategory.name}</option>)}</Select>
      <Select label="Visibility" value={status} onChange={setStatus}><option value="">Any status</option><option value="ACTIVE">Active</option><option value="DRAFT">Draft</option><option value="INACTIVE">Inactive</option></Select>
      <Select label="QA" value={qaStatus} onChange={setQaStatus}><option value="">Any QA state</option><option value="VERIFIED">Verified</option><option value="NEEDS_REVIEW">Needs review</option><option value="PENDING">Pending</option><option value="REJECTED">Rejected</option></Select>
    </div>
    {snapshot && !showProducts ? <div className="admin-catalogue-directory">{navigationGroups.map((group) => <section key={group.key}>
      <header><div><small>MASTER CATALOGUE</small><h3>{group.name}</h3></div></header>
      <div>{group.types.map((type) => <button type="button" key={type.id} onClick={() => chooseCategoryType(type.id)}>
        <AdminCategoryArtwork item={type} supabaseUrl={auth.supabaseUrl} />
        <strong>{type.name}</strong>{type.status !== "ACTIVE" ? <small>Coming soon</small> : null}
      </button>)}</div>
    </section>)}</div> : null}
    {snapshot && showProducts ? <section className="v1-admin-skus">
      <header><Tags size={20} /><div><h3>Customer-ready products</h3><p>Open a product to manage its exact record.</p></div></header>
      <div className={`admin-catalogue-browser ${categoryTypeId && visibleCategories.length ? "with-rail" : ""}`}>
        {categoryTypeId && visibleCategories.length ? <div className="admin-subcategory-rail" role="group" aria-label="Subcategories">{visibleCategories.map((category) => <button type="button" className={categoryId === category.id ? "selected" : ""} aria-pressed={categoryId === category.id} key={category.id} onClick={() => chooseCategory(category.id)}><AdminCategoryArtwork item={{ ...category, imageKey: category.imageKey ?? artworkKeys.categories.get(category.id) }} supabaseUrl={auth.supabaseUrl} /><strong>{category.name}</strong></button>)}</div> : null}
        <div className="admin-catalogue-products" key={categoryId}>{loading ? <div className="catalogue-loading" role="status"><span /> Loading exact SKUs</div> : skus.length === 0 && pageLoaded ? <div className="admin-empty-state"><Database size={28} /><h3>No SKUs match these filters</h3><p>Clear a filter or search for another exact product.</p></div> : skus.length > 0 ? <div className="v1-admin-sku-grid">{skus.map((sku) => <button type="button" key={`${sku.id}:${sku.version}`} onClick={() => setEditingSku(sku)}><AdminSkuTile sku={sku} supabaseUrl={auth.supabaseUrl} /><ChevronRight size={18} /></button>)}</div> : null}</div>
      </div>
      {hasMore ? <button type="button" className="admin-load-more wide" onClick={() => void loadMore().catch(() => undefined)} disabled={loadingMore}>{loadingMore ? "Loading more…" : "Load next 50 products"}</button> : null}
    </section> : null}
    {snapshot ? <details className="admin-catalogue-operations"><summary><Settings2 size={18} /><span><strong>Catalogue operations</strong><small>Counts, hierarchy and launch configuration</small></span><ChevronDown size={17} /></summary><div className="admin-catalogue-operations-body"><div className="v1-admin-summary"><Summary label="Departments" value={snapshot.categoryTypes.length} /><Summary label="Categories" value={snapshot.categories.length} /><Summary label="Subcategories" value={snapshot.subcategories.length} /><Summary label="Canonical SKUs" value={snapshot.skuCount} /><Summary label="Retail branches" value={snapshot.branches.length} /></div><section className="v1-admin-config"><header><Settings2 size={20} /><div><h3>Launch configuration</h3><p>Effective settings and validation state for the customer catalogue.</p></div></header><div>{snapshot.configuration.map((setting) => <article key={setting.key} className={!setting.valid || (setting.required && !setting.explicit) ? "attention" : ""}><code>{setting.key}</code><strong>{displayValue(setting.value)}</strong><span>{setting.explicit ? "Explicit" : "Default"} · {setting.valid ? "Valid" : "Invalid"}</span></article>)}</div></section></div></details> : null}
    <details className="v1-admin-import"><summary><Upload size={18} /><span><strong>Advanced atomic import</strong><small>Imports enter Draft and require taxonomy, QA, price and cleared imagery before activation</small></span><ChevronDown size={17} /></summary><form onSubmit={runImport}><label htmlFor="v1-catalogue-import">Catalogue JSON</label><textarea id="v1-catalogue-import" value={source} onChange={(event) => setSource(event.target.value)} rows={16} spellCheck={false} disabled={busy} /><p className="field-help">Use approved taxonomy slugs. A successful import does not make a product customer-visible.</p><button className="primary-button" type="submit" disabled={busy}>{busy ? "Importing…" : "Validate and import as Draft"}</button></form></details>
    {editingSku ? <div className="v1-overlay admin-sku-overlay" role="presentation"><section className="v1-sheet admin-sku-sheet" role="dialog" aria-modal="true" aria-label={`Edit ${editingSku.name}`}><header><div><p>EXACT SKU</p><h2>{editingSku.name}</h2></div><button type="button" onClick={() => setEditingSku(undefined)} aria-label="Close product editor"><X size={19} /></button></header><SkuEditor sku={editingSku} taxonomy={snapshot} supabaseUrl={auth.supabaseUrl} disabled={busy} onSave={updateSku} /></section></div> : null}
    {intent ? <AdminPrivilegedActionDialog intent={intent.dialog} busy={busy} error={error} notice={notice}
      reconciliationBlocked={reconciliationBlocked} onConfirm={() => confirmMutation()}
      onDismiss={() => { setIntent(undefined); setError(undefined); }}
      onReconcile={async () => {
        setBusy(true);
        try { await reconcileCatalogue(); setReconciliationBlocked(false); setNotice("Authoritative catalogue state was reloaded. Review the current record before acting again."); setIntent(undefined); }
        catch (cause) { setError(message(cause)); } finally { setBusy(false); }
      }} /> : null}
  </section>;
}

function AdminCategoryArtwork({ item, supabaseUrl }: { item: { imageKey?: string; previewImageKeys?: string[]; name: string; slug?: string }; supabaseUrl: string }) {
  const keys = [item.imageKey, ...(item.previewImageKeys ?? [])]
    .filter((value, index, values): value is string => Boolean(value) && values.indexOf(value) === index)
    .slice(0, 2);
  const slug = item.slug ?? "";
  return <span className={`admin-category-art count-${keys.length}`} aria-hidden="true">{keys.length
    ? keys.map((key) => <AdminArtworkImage key={key} source={catalogueImageUrl(supabaseUrl, key)} />)
    : slug.includes("paan") || slug.includes("produce") ? <Leaf size={27} />
      : slug.includes("pharmacy") || slug.includes("medicine") || slug.includes("health") ? <BadgeCheck size={27} />
        : <Boxes size={25} />}</span>;
}

function AdminArtworkImage({ source }: { source: string | null }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [source]);
  return source && !failed
    ? <img src={source} alt="" loading="lazy" decoding="async" onError={() => setFailed(true)} />
    : <Boxes size={21} />;
}

function adminNavigationGroups(categoryTypes: V1AdminSnapshot["categoryTypes"]) {
  const groups = new Map<string, {
    key: string;
    name: string;
    sortOrder: number;
    types: V1AdminSnapshot["categoryTypes"];
  }>();
  for (const type of categoryTypes) {
    const section = type.navigationSection ?? { key: "more", name: "More to explore", sortOrder: 999 };
    const group = groups.get(section.key) ?? { ...section, types: [] };
    group.types.push(type);
    groups.set(section.key, group);
  }
  return [...groups.values()]
    .map((group) => ({ ...group, types: [...group.types].sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name)) }))
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

function AdminSkuTile({ sku, supabaseUrl }: { sku: V1AdminCataloguePageSku; supabaseUrl: string }) {
  return <span className="admin-sku-tile">
    <SkuArtwork sku={sku} supabaseUrl={supabaseUrl} />
    <span className="admin-sku-tile-copy">
      <small>{sku.brandName?.toUpperCase() ?? sku.categoryName.toUpperCase()}</small>
      <strong>{sku.name}</strong>
      <span>{[sku.variant, sku.packSize].filter(Boolean).join(" · ")}</span>
      <b>{formatPaise(sku.sellingPricePaise)}</b>
      <em className={sku.activationReady ? "ready" : "attention"}>{sku.activationReady ? "Verified" : label(sku.qaStatus)}</em>
    </span>
  </span>;
}

function SkuEditor({ sku, taxonomy, supabaseUrl, disabled, onSave }: { sku: V1AdminCataloguePageSku; taxonomy?: V1AdminSnapshot; supabaseUrl: string; disabled: boolean; onSave: (sku: V1AdminCataloguePageSku, patch: Record<string, unknown>) => Promise<void> }) {
  const [name, setName] = useState(sku.name);
  const [variant, setVariant] = useState(sku.variant ?? "");
  const [packSize, setPackSize] = useState(sku.packSize);
  const [description, setDescription] = useState(sku.description ?? "");
  const [subcategoryId, setSubcategoryId] = useState(sku.subcategoryId);
  const [brandId, setBrandId] = useState(sku.brandId ?? "");
  const [barcode, setBarcode] = useState(sku.barcode ?? "");
  const quantityValue = sku.quantityValue?.toString() ?? "";
  const quantityUnit = sku.quantityUnit ?? "";
  const packCount = sku.packCount?.toString() ?? "";
  const [manufacturerName, setManufacturerName] = useState(sku.manufacturerName ?? "");
  const [countryOfOriginCode, setCountryOfOriginCode] = useState(sku.countryOfOriginCode ?? "");
  const [hsnCode, setHsnCode] = useState(sku.hsnCode ?? "");
  const [dietType, setDietType] = useState(sku.dietType);
  const [shelfLifeDays, setShelfLifeDays] = useState(sku.shelfLifeDays?.toString() ?? "");
  const [taxPercent, setTaxPercent] = useState((sku.taxRateBps / 100).toString());
  const [qaStatus, setQaStatus] = useState(sku.qaStatus);
  const [listPrice, setListPrice] = useState(sku.listPricePaise === undefined ? "" : (sku.listPricePaise / 100).toFixed(2));
  const [sellingPrice, setSellingPrice] = useState(sku.sellingPricePaise === undefined ? "" : (sku.sellingPricePaise / 100).toFixed(2));
  const [status, setStatus] = useState(sku.status);
  const listPricePaise = priceInPaise(listPrice);
  const sellingPricePaise = priceInPaise(sellingPrice);
  const numericQuantity = optionalPositiveNumber(quantityValue);
  const numericPackCount = optionalPositiveInteger(packCount);
  const numericShelfLife = optionalPositiveInteger(shelfLifeDays);
  const taxRateBps = priceInPaise(taxPercent);
  const changed = listPricePaise !== sku.listPricePaise || sellingPricePaise !== sku.sellingPricePaise || status !== sku.status ||
    name.trim() !== sku.name || variant.trim() !== (sku.variant ?? "") || packSize.trim() !== sku.packSize ||
    description.trim() !== (sku.description ?? "") || subcategoryId !== sku.subcategoryId || brandId !== (sku.brandId ?? "") ||
    barcode.trim() !== (sku.barcode ?? "") || numericQuantity !== (sku.quantityValue ?? null) || quantityUnit !== (sku.quantityUnit ?? "") ||
    numericPackCount !== (sku.packCount ?? null) || manufacturerName.trim() !== (sku.manufacturerName ?? "") ||
    countryOfOriginCode.trim().toUpperCase() !== (sku.countryOfOriginCode ?? "") || hsnCode.trim() !== (sku.hsnCode ?? "") ||
    dietType !== sku.dietType || numericShelfLife !== (sku.shelfLifeDays ?? null) || taxRateBps !== sku.taxRateBps || qaStatus !== sku.qaStatus;
  const valid = Boolean(name.trim() && packSize.trim() && subcategoryId) && listPricePaise !== undefined &&
    sellingPricePaise !== undefined && sellingPricePaise <= listPricePaise && taxRateBps !== undefined && taxRateBps <= 10000 &&
    !Number.isNaN(numericQuantity) && !Number.isNaN(numericPackCount) && !Number.isNaN(numericShelfLife);
  const activatingWithoutEvidence = status === "ACTIVE" && sku.status !== "ACTIVE" && !sku.activationReady;
  const canSave = valid && changed && !activatingWithoutEvidence;
  const patch = { name: name.trim(), variant: variant.trim() || null, packSize: packSize.trim(), description: description.trim() || null,
    subcategoryId, brandId: brandId || null, barcode: barcode.trim() || null, quantityValue: numericQuantity,
    quantityUnit: quantityUnit || null, packCount: numericPackCount, manufacturerName: manufacturerName.trim() || null,
    countryOfOriginCode: countryOfOriginCode.trim().toUpperCase() || null, hsnCode: hsnCode.trim() || null,
    dietType, shelfLifeDays: numericShelfLife, taxRateBps, qaStatus, listPricePaise, sellingPricePaise, status };
  return <form className="admin-sku-card" onSubmit={(event) => { event.preventDefault(); if (canSave) void onSave(sku, patch); }}>
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
      <section className="admin-sku-master-fields" aria-label="Authoritative SKU controls">
        <header><Package size={18} /><div><strong>Identity &amp; compliance</strong><small>These values become the shared customer, merchant and Admin product record.</small></div></header>
        <label><span>Product name</span><input value={name} maxLength={160} onChange={(event) => setName(event.target.value)} /></label>
        <label><span>Variant</span><input value={variant} maxLength={160} onChange={(event) => setVariant(event.target.value)} /></label>
        <label className="wide"><span>Description</span><textarea value={description} maxLength={1000} rows={3} onChange={(event) => setDescription(event.target.value)} /></label>
        <label><span>Subcategory</span><select value={subcategoryId} onChange={(event) => setSubcategoryId(event.target.value)}>{taxonomy?.subcategories.map((item) => <option key={item.id} value={item.id}>{taxonomy.categories.find((category) => category.id === item.categoryId)?.name ?? "Category"} · {item.name}</option>)}</select></label>
        <label><span>Brand</span><select value={brandId} onChange={(event) => setBrandId(event.target.value)}><option value="">No brand</option>{taxonomy?.brands.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
        <label><span>Display pack</span><input value={packSize} maxLength={80} onChange={(event) => setPackSize(event.target.value)} placeholder="1 kg" /></label>
        <label><span>Manufacturer</span><input value={manufacturerName} maxLength={200} onChange={(event) => setManufacturerName(event.target.value)} /></label>
        <label><span>Barcode</span><input value={barcode} maxLength={64} onChange={(event) => setBarcode(event.target.value)} /></label>
        <label><span>HSN</span><input inputMode="numeric" value={hsnCode} maxLength={8} onChange={(event) => setHsnCode(event.target.value)} /></label>
        <label><span>Country code</span><input value={countryOfOriginCode} maxLength={2} onChange={(event) => setCountryOfOriginCode(event.target.value)} placeholder="IN" /></label>
        <label><span>Diet</span><select value={dietType} onChange={(event) => setDietType(event.target.value)}><option value="NA">Not applicable</option><option value="VEG">Vegetarian</option><option value="NON_VEG">Non-vegetarian</option><option value="EGG">Contains egg</option></select></label>
        <label><span>Shelf life (days)</span><input inputMode="numeric" value={shelfLifeDays} onChange={(event) => setShelfLifeDays(event.target.value)} /></label>
        <label><span>Tax (%)</span><input inputMode="decimal" value={taxPercent} onChange={(event) => setTaxPercent(event.target.value)} /></label>
        <label><span>QA state</span><select value={qaStatus} onChange={(event) => setQaStatus(event.target.value as V1AdminCataloguePageSku["qaStatus"])}><option value="PENDING">Pending</option><option value="NEEDS_REVIEW">Needs review</option><option value="VERIFIED">Verified</option><option value="REJECTED">Rejected</option></select></label>
      </section>
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
function optionalPositiveNumber(value: string): number | null {
  if (!value.trim()) return null;
  const result = Number(value);
  return Number.isFinite(result) && result > 0 ? result : Number.NaN;
}
function optionalPositiveInteger(value: string): number | null {
  const result = optionalPositiveNumber(value);
  return result === null || Number.isInteger(result) ? result : Number.NaN;
}
function message(error: unknown) { return userFacingError(error, "The catalogue operation could not be completed."); }
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
