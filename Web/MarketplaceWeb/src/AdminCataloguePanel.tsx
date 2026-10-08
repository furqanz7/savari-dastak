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
} from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { AdminCatalogueAssets } from "./AdminCatalogueAssets";
import { AdminRecordDialog } from "./AdminRecordDialog";
import { catalogueProductType, validProductType, withCatalogueProductType, PRODUCT_TYPE_MAX_LENGTH } from "./catalogueProductType";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import {
  getV1AdminCatalogue, getV1AdminCataloguePage, importV1AdminCatalogue, updateV1AdminSku, deleteV1AdminSku,
  getV1CatalogueBrowseMap,
  mutateV1AdminCatalogueTaxonomy,
  type DastakV1Auth, type V1AdminCataloguePageSku, type V1AdminSnapshot, type V1CatalogueBrowseMap,
} from "./dastakV1";
import { catalogueImageUrl } from "./catalogue";
import { catalogueDepartmentName, catalogueHomeTiles, catalogueNavigationGroups, curatedCatalogueRails, resolveCatalogueRail, riceRailExcludedSubcategoryIds } from "./cataloguePresentation";
import { browseChildren, browseSkuIds, validateBrowseMap } from "./catalogueBrowse";
import { referenceBrowseArtworkKey } from "./referenceBrowseArtwork";
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
  const [browseMap, setBrowseMap] = useState<V1CatalogueBrowseMap | null>();
  const [skus, setSkus] = useState<V1AdminCataloguePageSku[]>([]);
  const [cursor, setCursor] = useState<{ name: string; skuId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [query, setQuery] = useState("");
  const [categoryTypeId, setCategoryTypeId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [subcategoryId, setSubcategoryId] = useState("");
  const [selectedRailLabel, setSelectedRailLabel] = useState("");
  const [selectedHomeTile, setSelectedHomeTile] = useState<{ label: string; categoryId?: string }>();
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
  const [selectedSkuIds, setSelectedSkuIds] = useState<Set<string>>(new Set());
  const [reconciliationBlocked, setReconciliationBlocked] = useState(false);
  const [taxonomyOperation, setTaxonomyOperation] = useState("CREATE_CATEGORY_TYPE");
  const [taxonomyName, setTaxonomyName] = useState("");
  const [taxonomySlug, setTaxonomySlug] = useState("");
  const [taxonomyTypeSlug, setTaxonomyTypeSlug] = useState("");
  const [taxonomyCategorySlug, setTaxonomyCategorySlug] = useState("");
  const [intent, setIntent] = useState<{
    dialog: AdminPrivilegedActionIntent;
    identity: string;
    mutate: (idempotencyKey: string) => Promise<unknown>;
    success: string;
    closeEditor?: boolean;
  }>();
  const headingRef = useRef<HTMLElement>(null);
  const pageGeneration = useRef(0);
  const loadedPageCount = useRef(1);
  const pageController = useRef<AbortController | undefined>(undefined);
  const refreshQueue = useRef(new RefreshQueue());
  const { reportRequestError } = useAdminRuntime();
  useEffect(() => {
    if (categoryTypeId) headingRef.current?.scrollIntoView({ block: "start" });
  }, [categoryTypeId]);

  const filters = useMemo(() => ({
    query: query.trim(),
    categoryTypeId: (categoryId ? snapshot?.categories.find((item) => item.id === categoryId)?.categoryTypeId : categoryTypeId) || undefined,
    categoryId: categoryId || undefined,
    subcategoryId: subcategoryId || undefined,
    status: status ? status as V1AdminCataloguePageSku["status"] : undefined,
    qaStatus: qaStatus ? qaStatus as V1AdminCataloguePageSku["qaStatus"] : undefined,
  }), [categoryId, categoryTypeId, qaStatus, query, snapshot?.categories, status, subcategoryId]);

  const visibleCategories = useMemo(() => snapshot?.categories.filter((category) =>
    !categoryTypeId || category.categoryTypeId === categoryTypeId || category.id === categoryId) ?? [], [categoryId, categoryTypeId, snapshot]);
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

  const loadMetadata = useCallback(async (signal?: AbortSignal) => {
    const [nextSnapshot, nextBrowseMap] = await Promise.all([
      getV1AdminCatalogue({ ...auth, signal }), getV1CatalogueBrowseMap({ ...auth, signal }),
    ]);
    if (nextBrowseMap && validateBrowseMap(nextBrowseMap).length) throw new Error("The catalogue map needs attention.");
    if (!signal?.aborted) { setSnapshot(nextSnapshot); setBrowseMap(nextBrowseMap); }
  }, [auth]);
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
      loadedPageCount.current = append ? loadedPageCount.current + 1 : 1;
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
      if (!controller.signal.aborted) { setBrowseMap(undefined); setSnapshot(undefined); reportRequestError(loadError); setError(message(loadError)); }
    });
    return () => controller.abort();
  }, [loadMetadata, reportRequestError]);
  useEffect(() => {
    pageController.current?.abort();
    const controller = new AbortController();
    pageController.current = controller;
    setPageLoaded(false);
    loadedPageCount.current = 1;
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
    // Reconciliation is primarily about the exact SKU page.  A malformed or
    // temporarily stale metadata snapshot must not turn a completed mutation
    // into an "invalid text" failure and block the operator.  Keep the last
    // authoritative taxonomy snapshot when metadata cannot be refreshed.
    const metadataPromise = getV1AdminCatalogue({ ...auth, signal: controller.signal })
      .catch(() => snapshot);
    const pages: V1AdminCataloguePageSku[] = [];
    let nextCursor: { name: string; skuId: string } | undefined;
    let more = false;
    for (let pageNumber = 0; pageNumber < loadedPageCount.current; pageNumber += 1) {
      const page = await getV1AdminCataloguePage({
        ...auth, ...filters, limit: 50, cursor: nextCursor, signal: controller.signal,
      });
      pages.push(...page.skus);
      nextCursor = page.nextCursor;
      more = page.hasMore;
      if (!more) break;
    }
    const metadata = await metadataPromise;
    if (controller.signal.aborted || generation !== pageGeneration.current) return;
    if (metadata) setSnapshot(metadata);
    setSkus(pages); setCursor(nextCursor); setHasMore(more); setPageLoaded(true);
  }, [auth, filters, snapshot]);

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
    setSelectedRailLabel("");
    setSelectedHomeTile(undefined);
  };
  const chooseCategory = (value: string) => {
    setCategoryId(value);
    if (value) setCategoryTypeId(snapshot?.categories.find((item) => item.id === value)?.categoryTypeId ?? "");
    setSubcategoryId("");
    setSelectedRailLabel("");
    setSelectedHomeTile(undefined);
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
  const deleteSku = async (sku: V1AdminCataloguePageSku) => setIntent({ identity: `catalogue-sku-delete:${sku.id}`, success: `${sku.name} was permanently deleted.`, closeEditor: true, dialog: { title: `Permanently delete ${sku.name}?`, entityLabel: "Canonical SKU", entityValue: `${sku.name} · ${sku.id}`, currentState: `${label(sku.status)} · ${sku.packSize}`, resultingState: "Removed permanently", consequence: "Allowed only when no order, inventory, recovery, or merchant-selection records reference it. Otherwise the server requires archiving.", confirmLabel: "Delete permanently", tone: "danger" }, mutate: (idempotencyKey) => deleteV1AdminSku({ ...auth, skuId: sku.id, idempotencyKey }) });

  const selectedSkus = skus.filter((sku) => selectedSkuIds.has(sku.id));
  const toggleSkuSelection = (skuId: string) => setSelectedSkuIds((current) => {
    const next = new Set(current);
    if (next.has(skuId)) next.delete(skuId); else next.add(skuId);
    return next;
  });
  const clearSkuSelection = () => setSelectedSkuIds(new Set());
  const bulkMutation = (action: "ACTIVE" | "INACTIVE" | "DELETE") => {
    if (!selectedSkus.length) return;
    const selectedFingerprint = selectedSkus.map((sku) => `${sku.id}:${sku.version}`).sort().join(",");
    const blockedActivation = action === "ACTIVE" ? selectedSkus.filter((sku) => !sku.activationReady && sku.status !== "ACTIVE") : [];
    if (blockedActivation.length) {
      setError(`${blockedActivation.length} selected SKU${blockedActivation.length === 1 ? " is" : "s are"} not ready to activate. Select only verified SKUs.`);
      return;
    }
    const actionLabel = action === "DELETE" ? "permanently delete" : action === "ACTIVE" ? "activate" : "archive";
    setIntent({
      identity: `catalogue-sku-bulk:${action}:${selectedFingerprint}`,
      success: `${selectedSkus.length} SKU${selectedSkus.length === 1 ? "" : "s"} ${action === "DELETE" ? "were permanently deleted" : action === "ACTIVE" ? "are now active" : "were archived"}.`,
      dialog: {
        title: `${actionLabel[0].toUpperCase()}${actionLabel.slice(1)} ${selectedSkus.length} selected SKU${selectedSkus.length === 1 ? "" : "s"}?`,
        entityLabel: "Selected canonical SKUs",
        entityValue: `${selectedSkus.slice(0, 8).map((sku) => sku.name).join(" · ")}${selectedSkus.length > 8 ? ` · … and ${selectedSkus.length - 8} more` : ""}`,
        currentState: `${selectedSkus.length} selected · ${selectedSkus.filter((sku) => sku.status === "ACTIVE").length} active · ${selectedSkus.filter((sku) => sku.status === "INACTIVE").length} archived`,
        resultingState: action === "DELETE" ? "Removed permanently" : action === "ACTIVE" ? "Active and customer-visible when otherwise eligible" : "Archived (inactive and hidden from customers)",
        consequence: action === "DELETE" ? "Permanent deletion is governed per SKU. Any SKU with order, inventory, recovery or merchant-selection references will be rejected and must be archived instead." : "This updates the authoritative catalogue records and is recorded in audit history.",
        confirmLabel: action === "DELETE" ? "Delete permanently" : action === "ACTIVE" ? "Activate selected" : "Archive selected",
        tone: action === "ACTIVE" ? "primary" : "danger",
      },
      mutate: async (idempotencyKey) => {
        for (const sku of selectedSkus) {
          if (action === "DELETE") await deleteV1AdminSku({ ...auth, skuId: sku.id, idempotencyKey: `${idempotencyKey}:${sku.id}` });
          else await updateV1AdminSku({ ...auth, skuId: sku.id, expectedVersion: sku.version, patch: { status: action }, idempotencyKey: `${idempotencyKey}:${sku.id}` });
        }
      },
    });
  };

  const submitTaxonomy = (event: FormEvent) => {
    event.preventDefault();
    const payload: Record<string, unknown> = { name: taxonomyName.trim(), slug: taxonomySlug.trim() };
    if (taxonomyOperation.includes("CATEGORY") && taxonomyOperation !== "CREATE_CATEGORY_TYPE" && taxonomyOperation !== "ARCHIVE_CATEGORY_TYPE") payload.categoryTypeSlug = taxonomyTypeSlug.trim();
    if (taxonomyOperation.includes("SUBCATEGORY")) payload.categorySlug = taxonomyCategorySlug.trim();
    setIntent({ identity: `catalogue-taxonomy:${taxonomyOperation}:${JSON.stringify(payload)}`, success: "Catalogue taxonomy change committed and recorded in audit history.", dialog: {
      title: `${taxonomyOperation.startsWith("ARCHIVE") ? "Archive" : "Create or update"} catalogue taxonomy?`, entityLabel: "Taxonomy record", entityValue: `${taxonomyName} · ${taxonomySlug}`,
      currentState: "Authoritative catalogue", resultingState: taxonomyOperation.startsWith("ARCHIVE") ? "Inactive (recoverable)" : "Draft taxonomy record",
      consequence: "Archiving is soft and preserves historical SKU/order references. Creating records leaves them Draft until imagery, QA, pricing and activation requirements are complete.", confirmLabel: taxonomyOperation.startsWith("ARCHIVE") ? "Archive safely" : "Save taxonomy", tone: taxonomyOperation.startsWith("ARCHIVE") ? "danger" : "primary",
    }, mutate: (idempotencyKey) => mutateV1AdminCatalogueTaxonomy({ ...auth, operation: taxonomyOperation, payload, idempotencyKey }) });
  };

  const confirmMutation = async () => {
    if (!intent || busy) return;
    setBusy(true); setError(undefined); setNotice(undefined); setReconciliationBlocked(false);
    const result = await runAdminPrivilegedMutation({ operationIdentity: intent.identity, mutate: intent.mutate, reconcile: reconcileCatalogue });
    setBusy(false);
    if (result.kind === "completed") {
      setNotice(intent.success);
      if (intent.closeEditor) setEditingSku(undefined);
      if (intent.identity.startsWith("catalogue-sku-bulk:")) clearSkuSelection();
      setIntent(undefined);
    } else if (result.kind === "reconciled" || result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      if (result.kind === "reconciled") setIntent(undefined);
    } else if (result.kind === "uncertain_blocked") {
      setReconciliationBlocked(true); setError(result.message);
    } else { reportRequestError(result.error); setError(message(result.error)); }
  };

  const showProducts = Boolean(query.trim() || categoryTypeId || categoryId || subcategoryId || status || qaStatus);
  const riceExclusions = selectedRailLabel === "Rice" && snapshot?.categories.find((item) => item.id === categoryId)?.slug === "rice"
    ? riceRailExcludedSubcategoryIds((snapshot?.subcategories ?? []).filter((item) => item.categoryId === categoryId))
    : undefined;
  const displaySkus = selectedRailLabel && !categoryId ? []
    : riceExclusions ? skus.filter((sku) => !riceExclusions.has(sku.subcategoryId)) : skus;
  const activeSkus = displaySkus.filter((sku) => sku.status !== "INACTIVE");
  const archivedSkus = displaySkus.filter((sku) => sku.status === "INACTIVE");
  const selectedType = snapshot?.categoryTypes.find((type) => type.id === categoryTypeId);
  const navigationGroups = catalogueNavigationGroups(snapshot?.categoryTypes ?? []);
  const curatedRail = selectedType && snapshot && curatedCatalogueRails[selectedType.slug]?.map((target) => {
    const resolved = resolveCatalogueRail(target, snapshot.categoryTypes, snapshot.categories, snapshot.subcategories);
    const category = resolved && "categoryId" in resolved
      ? snapshot.categories.find((item) => item.id === resolved.categoryId)
      : resolved;
    return { label: target.label, item: resolved, categoryId: category?.id,
      subcategoryId: resolved && "categoryId" in resolved ? resolved.id : undefined };
  });
  const displayedRail = selectedHomeTile?.categoryId
    ? snapshot?.subcategories.filter((item) => item.categoryId === selectedHomeTile.categoryId).map((item) => ({ label: item.name, item, categoryId: item.categoryId, subcategoryId: item.id }))
    : curatedRail;

  if (browseMap === undefined) return <section className="admin-section v1-admin-catalogue" role="tabpanel">{error ? <><p className="order-error" role="alert"><CircleAlert size={16} /> {error}</p><button type="button" className="secondary-button" onClick={() => void loadMetadata().then(() => setError(undefined)).catch((cause) => setError(message(cause)))}>Retry catalogue</button></> : <div className="catalogue-loading" role="status"><span /> Loading catalogue map</div>}</section>;

  return <section className="admin-section v1-admin-catalogue" role="tabpanel">
    <header ref={headingRef} className="admin-section-heading admin-catalogue-heading"><div><p className="eyebrow">MASTER CATALOGUE</p><h2>{browseMap ? "Browse Dastak" : selectedType ? selectedHomeTile?.label ?? catalogueDepartmentName(selectedType.slug, selectedType.name) : "Browse departments"}</h2><p>{categoryTypeId ? "Review exact SKU facts, visibility, readiness and governed imagery." : "Find the exact product before reviewing its record or managing its images."}</p></div>{!browseMap && categoryTypeId ? <button type="button" className="admin-directory-back" onClick={() => chooseCategoryType("")}>All categories</button> : null}</header>
    {error ? <p className="order-error" role="alert"><CircleAlert size={16} /> {error}</p> : null}
    {notice ? <p className="v1-admin-notice" role="status"><Check size={17} /> {notice}</p> : null}
    <div className="admin-catalogue-toolbar">
      <label className="admin-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search SKU, brand, alias or category" aria-label="Search catalogue" /></label>
      {!browseMap ? <><Select label="Department" value={categoryTypeId} onChange={chooseCategoryType}><option value="">All departments</option>{snapshot?.categoryTypes.map((type) => <option value={type.id} key={type.id}>{catalogueDepartmentName(type.slug, type.name)}</option>)}</Select>
      <Select label="Category" value={categoryId} onChange={chooseCategory}><option value="">All categories</option>{visibleCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}</Select>
      <Select label="Subcategory" value={subcategoryId} onChange={(value) => { setSubcategoryId(value); setSelectedRailLabel(""); }}><option value="">All subcategories</option>{visibleSubcategories.map((subcategory) => <option value={subcategory.id} key={subcategory.id}>{subcategory.name}</option>)}</Select></> : null}
      <Select label="Visibility" value={status} onChange={setStatus}><option value="">Any status</option><option value="ACTIVE">Active</option><option value="DRAFT">Draft</option><option value="INACTIVE">Inactive</option></Select>
      <Select label="QA" value={qaStatus} onChange={setQaStatus}><option value="">Any QA state</option><option value="VERIFIED">Verified</option><option value="NEEDS_REVIEW">Needs review</option><option value="PENDING">Pending</option><option value="REJECTED">Rejected</option></Select>
    </div>
    {snapshot && browseMap && !showProducts ? <AdminReferenceBrowser auth={auth} map={browseMap} snapshot={snapshot} onOpen={setEditingSku} /> : null}
    {snapshot && !browseMap && !showProducts ? <div className="admin-catalogue-directory">{navigationGroups.map((group) => <section key={group.key}>
      <header><div><small>MASTER CATALOGUE</small><h3>{group.name}</h3></div></header>
      <div>{catalogueHomeTiles(group.key, group.types, snapshot.categoryTypes, snapshot.categories).map((tile) => <button type="button" key={tile.key} onClick={() => { chooseCategoryType(tile.typeId); if (tile.categoryId) setCategoryId(tile.categoryId); setSelectedHomeTile({ label: tile.label, categoryId: tile.categoryId }); }}>
        <AdminCategoryArtwork item={tile.item} supabaseUrl={auth.supabaseUrl} />
        <strong>{tile.label}</strong>{tile.item.status !== "ACTIVE" ? <small>Coming soon</small> : null}
      </button>)}</div>
    </section>)}</div> : null}
    {snapshot && showProducts ? <section className="v1-admin-skus">
      <header><Tags size={20} /><div><h3>{selectedRailLabel || (selectedHomeTile?.categoryId === categoryId ? selectedHomeTile.label : undefined) || "Product records"}</h3><p>Results reflect your filters. Open an exact SKU to review its full record.</p></div></header>
      <div className={`admin-catalogue-browser ${categoryTypeId && visibleCategories.length ? "with-rail" : ""}`}>
        {categoryTypeId && visibleCategories.length ? <div className="admin-subcategory-rail" role="group" aria-label="Subcategories">{displayedRail ? displayedRail.map(({ label, item, categoryId: targetCategoryId, subcategoryId: targetSubcategoryId }) => <button type="button" disabled={!item} className={selectedRailLabel === label ? "selected" : ""} aria-pressed={selectedRailLabel === label} key={label} onClick={() => { setCategoryId(targetCategoryId ?? ""); setSubcategoryId(targetSubcategoryId ?? ""); setSelectedRailLabel(label); }}>{item ? <AdminCategoryArtwork item={item} supabaseUrl={auth.supabaseUrl} /> : <Database size={28} />}<strong>{label}</strong></button>) : visibleCategories.map((category) => <button type="button" className={categoryId === category.id ? "selected" : ""} aria-pressed={categoryId === category.id} key={category.id} onClick={() => chooseCategory(category.id)}><AdminCategoryArtwork item={{ ...category, imageKey: category.imageKey ?? artworkKeys.categories.get(category.id) }} supabaseUrl={auth.supabaseUrl} /><strong>{category.name}</strong></button>)}</div> : null}
      <div className="admin-catalogue-products" key={categoryId}>{loading ? <div className="catalogue-loading" role="status"><span /> Loading exact SKUs</div> : displaySkus.length === 0 && pageLoaded ? <div className="admin-empty-state"><Database size={28} /><h3>No SKUs match these filters</h3><p>Clear a filter or search for another exact product.</p></div> : displaySkus.length > 0 ? <><BulkSkuToolbar selectedCount={selectedSkus.length} onArchive={() => bulkMutation("INACTIVE")} onActivate={() => bulkMutation("ACTIVE")} onDelete={() => bulkMutation("DELETE")} onClear={clearSkuSelection} /><div className="v1-admin-sku-grid">{activeSkus.map((sku) => <SkuSelectionCard key={`${sku.id}:${sku.version}`} sku={sku} selected={selectedSkuIds.has(sku.id)} onToggle={() => toggleSkuSelection(sku.id)} onOpen={() => setEditingSku(sku)} supabaseUrl={auth.supabaseUrl} />)}</div>{archivedSkus.length > 0 ? <section className="admin-archived-skus"><h3>Archived</h3><p>Inactive SKUs are kept here for historical continuity.</p><div className="v1-admin-sku-grid">{archivedSkus.map((sku) => <SkuSelectionCard key={`${sku.id}:${sku.version}`} sku={sku} selected={selectedSkuIds.has(sku.id)} onToggle={() => toggleSkuSelection(sku.id)} onOpen={() => setEditingSku(sku)} supabaseUrl={auth.supabaseUrl} />)}</div></section> : null}</> : null}</div>
      </div>
      {hasMore ? <button type="button" className="admin-load-more wide" onClick={() => void loadMore().catch(() => undefined)} disabled={loadingMore}>{loadingMore ? "Loading more…" : "Load next 50 products"}</button> : null}
    </section> : null}
    {snapshot ? <details className="admin-catalogue-operations"><summary><Settings2 size={18} /><span><strong>Catalogue operations</strong><small>Counts, hierarchy and launch configuration</small></span><ChevronDown size={17} /></summary><div className="admin-catalogue-operations-body"><div className="v1-admin-summary"><Summary label="Departments" value={snapshot.categoryTypes.length} /><Summary label="Categories" value={snapshot.categories.length} /><Summary label="Subcategories" value={snapshot.subcategories.length} /><Summary label="Canonical SKUs" value={snapshot.skuCount} /><Summary label="Retail branches" value={snapshot.branches.length} /></div><section className="v1-admin-config"><header><Settings2 size={20} /><div><h3>Launch configuration</h3><p>Effective settings and validation state for the customer catalogue.</p></div></header><div>{snapshot.configuration.map((setting) => <article key={setting.key} className={!setting.valid || (setting.required && !setting.explicit) ? "attention" : ""}><code>{setting.key}</code><strong>{displayValue(setting.value)}</strong><span>{setting.explicit ? "Explicit" : "Default"} · {setting.valid ? "Valid" : "Invalid"}</span></article>)}</div></section></div></details> : null}
    <details className="v1-admin-import"><summary><Tags size={18} /><span><strong>Create or archive taxonomy</strong><small>Manage departments, categories and subcategories without deleting historical data</small></span><ChevronDown size={17} /></summary><form onSubmit={submitTaxonomy} className="v1-taxonomy-form"><label><span>Action</span><select value={taxonomyOperation} onChange={(event) => setTaxonomyOperation(event.target.value)}><option value="CREATE_CATEGORY_TYPE">Create department</option><option value="CREATE_CATEGORY">Create category</option><option value="CREATE_SUBCATEGORY">Create subcategory</option><option value="ARCHIVE_CATEGORY_TYPE">Archive department</option><option value="ARCHIVE_CATEGORY">Archive category</option><option value="ARCHIVE_SUBCATEGORY">Archive subcategory</option></select></label><label><span>Name</span><input required value={taxonomyName} onChange={(event) => setTaxonomyName(event.target.value)} /></label><label><span>Slug</span><input required value={taxonomySlug} onChange={(event) => setTaxonomySlug(event.target.value)} placeholder="fresh-produce" /></label>{taxonomyOperation.includes("CATEGORY") && !taxonomyOperation.includes("TYPE") ? <label><span>Department slug</span><input required value={taxonomyTypeSlug} onChange={(event) => setTaxonomyTypeSlug(event.target.value)} /></label> : null}{taxonomyOperation.includes("SUBCATEGORY") ? <label><span>Category slug</span><input required value={taxonomyCategorySlug} onChange={(event) => setTaxonomyCategorySlug(event.target.value)} /></label> : null}<button className="primary-button" type="submit" disabled={busy}>Review taxonomy change</button></form></details>
    <details className="v1-admin-import"><summary><Upload size={18} /><span><strong>Advanced atomic import</strong><small>Create or update brands and SKUs in batches; imports enter Draft until separately activated</small></span><ChevronDown size={17} /></summary><form onSubmit={runImport}><label htmlFor="v1-catalogue-import">Catalogue JSON</label><textarea id="v1-catalogue-import" value={source} onChange={(event) => setSource(event.target.value)} rows={16} spellCheck={false} disabled={busy} /><p className="field-help">Use this for SKU creation, pack-size variants, brands, prices and batch updates. A successful import does not make a product customer-visible.</p><button className="primary-button" type="submit" disabled={busy}>{busy ? "Importing…" : "Validate and import as Draft"}</button></form></details>
    {editingSku ? <AdminRecordDialog title={editingSku.name} busy={busy} onDismiss={() => setEditingSku(undefined)}><SkuEditor auth={auth} sku={editingSku} taxonomy={snapshot} supabaseUrl={auth.supabaseUrl} disabled={busy} onSave={updateSku} onDelete={deleteSku} onCatalogueChanged={reconcileCatalogue} /></AdminRecordDialog> : null}
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

function AdminReferenceBrowser({ auth, map, snapshot, onOpen }: {
  auth: DastakV1Auth;
  map: V1CatalogueBrowseMap;
  snapshot: V1AdminSnapshot;
  onOpen: (sku: V1AdminCataloguePageSku) => void;
}) {
  const [destinationKey, setDestinationKey] = useState<string>();
  const [railKey, setRailKey] = useState<string>();
  const [allActiveSkus, setAllActiveSkus] = useState<V1AdminCataloguePageSku[]>();
  const [browseError, setBrowseError] = useState<string>();
  const destination = map.nodes.find((node) => node.key === destinationKey && node.kind === "DESTINATION");
  const rails = destination ? browseChildren(map, destination.key).filter((node) => node.kind === "RAIL") : [];
  const selectedNode = rails.find((node) => node.key === railKey) ?? destination;
  const activeDestinationKey = destination?.key;
  useEffect(() => {
    if (!activeDestinationKey) return;
    const controller = new AbortController();
    setAllActiveSkus(undefined);
    setBrowseError(undefined);
    void (async () => {
      const all: V1AdminCataloguePageSku[] = [];
      let cursor: { name: string; skuId: string } | undefined;
      for (let pageNumber = 0; pageNumber < 100; pageNumber += 1) {
        const page = await getV1AdminCataloguePage({ ...auth, status: "ACTIVE", limit: 50, cursor, signal: controller.signal });
        all.push(...page.skus);
        if (!page.hasMore) {
          if (!controller.signal.aborted) setAllActiveSkus(all);
          return;
        }
        if (!page.nextCursor || (cursor && cursor.name === page.nextCursor.name && cursor.skuId === page.nextCursor.skuId)) throw new Error("Catalogue pagination did not advance.");
        cursor = page.nextCursor;
      }
      throw new Error("The full catalogue could not be loaded.");
    })().catch((cause) => { if (!controller.signal.aborted) setBrowseError(message(cause)); });
    return () => controller.abort();
  }, [auth, activeDestinationKey]);
  const taxonomy = useMemo(() => ({
    types: snapshot.categoryTypes.map((item) => ({ id: item.id, slug: item.slug })),
    categories: snapshot.categories.flatMap((item) => item.categoryTypeId ? [{ id: item.id, typeId: item.categoryTypeId, slug: item.slug }] : []),
    subcategories: snapshot.subcategories.map((item) => ({ id: item.id, categoryId: item.categoryId, slug: item.slug })),
  }), [snapshot]);
  const selectedIds = useMemo(() => selectedNode && allActiveSkus ? browseSkuIds(map, selectedNode.key, taxonomy, allActiveSkus) : new Set<string>(), [allActiveSkus, map, selectedNode, taxonomy]);
  const visibleSkus = allActiveSkus?.filter((sku) => selectedIds.has(sku.id)) ?? [];
  const artworkFor = (node: V1CatalogueBrowseMap["nodes"][number]) => {
    const destinationImageKey = referenceBrowseArtworkKey(node);
    if (node.kind === "DESTINATION") return <AdminCategoryArtwork item={{ name: node.label, slug: node.key, imageKey: destinationImageKey ?? undefined }} supabaseUrl={auth.supabaseUrl} />;
    const source = node.sources[0];
    const category = snapshot.categories.find((item) => item.slug === source?.categorySlug &&
      snapshot.categoryTypes.some((type) => type.id === item.categoryTypeId && type.slug === source.typeSlug));
    const subcategory = snapshot.subcategories.find((item) => item.categoryId === category?.id && item.slug === source?.subcategorySlug);
    return <AdminCategoryArtwork item={subcategory ?? category ?? { name: node.label, slug: node.key }} supabaseUrl={auth.supabaseUrl} />;
  };
  return <>
    {!destination ? <div className="admin-catalogue-directory">{browseChildren(map, null).map((section) => <section key={section.key}>
      <header><div><small>MASTER CATALOGUE</small><h3>{section.label}</h3></div></header>
      <div>{browseChildren(map, section.key).map((node) => <button type="button" key={node.key} onClick={() => { setDestinationKey(node.key); setRailKey(undefined); }}>{artworkFor(node)}<strong>{node.label}</strong></button>)}</div>
    </section>)}</div> : <section className="v1-admin-skus">
      <header><Tags size={20} /><div><h3>{destination.label}</h3><p>Reference catalogue shelves and exact active SKUs.</p></div><button type="button" className="admin-directory-back" onClick={() => { setDestinationKey(undefined); setRailKey(undefined); }}>All categories</button></header>
      <div className="admin-catalogue-browser with-rail">
        <div className="admin-subcategory-rail" role="group" aria-label="Subcategories">{rails.map((node) => <button type="button" key={node.key} aria-pressed={selectedNode?.key === node.key} className={selectedNode?.key === node.key ? "selected" : ""} onClick={() => setRailKey(node.key)}>{artworkFor(node)}<strong>{node.label}</strong></button>)}</div>
        <div className="admin-catalogue-products" key={selectedNode?.key}>{browseError ? <p className="order-error" role="alert">{browseError}</p> : !allActiveSkus ? <div className="catalogue-loading" role="status"><span /> Loading exact SKUs</div> : <><header><h3>{selectedNode?.label}</h3><p>{visibleSkus.length} products</p></header>{visibleSkus.length ? <div className="v1-admin-sku-grid">{visibleSkus.map((sku) => <button className="admin-sku-open" type="button" key={sku.id} onClick={() => onOpen(sku)}><AdminSkuTile sku={sku} supabaseUrl={auth.supabaseUrl} /><ChevronRight size={18} /></button>)}</div> : <div className="admin-empty-state"><Database size={28} /><h3>No products here yet</h3></div>}</>}</div>
      </div>
    </section>}
  </>;
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

function BulkSkuToolbar({ selectedCount, onArchive, onActivate, onDelete, onClear }: { selectedCount: number; onArchive: () => void; onActivate: () => void; onDelete: () => void; onClear: () => void }) {
  return <div className="admin-bulk-toolbar" role="region" aria-label="Bulk SKU actions">
    <strong>{selectedCount ? `${selectedCount} selected` : "Select SKUs for bulk actions"}</strong>
    {selectedCount ? <><button type="button" className="secondary-button" onClick={onActivate}>Make active</button><button type="button" className="secondary-button" onClick={onArchive}>Archive</button><button type="button" className="secondary-button danger" onClick={onDelete}>Delete permanently</button><button type="button" className="admin-bulk-clear" onClick={onClear}>Clear selection</button></> : <span>Select the checkbox on any product card.</span>}
  </div>;
}

function SkuSelectionCard({ sku, selected, onToggle, onOpen, supabaseUrl }: { sku: V1AdminCataloguePageSku; selected: boolean; onToggle: () => void; onOpen: () => void; supabaseUrl: string }) {
  return <article className={`admin-sku-selection-card${selected ? " selected" : ""}`}>
    <label className="admin-sku-select"><input type="checkbox" checked={selected} onChange={onToggle} aria-label={`Select ${sku.name}`} /><span aria-hidden="true">{selected ? "✓" : ""}</span></label>
    <button type="button" className="admin-sku-open" onClick={onOpen}><AdminSkuTile sku={sku} supabaseUrl={supabaseUrl} /><ChevronRight size={18} /></button>
  </article>;
}

export function SkuEditor({ auth, sku, taxonomy, supabaseUrl, disabled, onSave, onDelete, onCatalogueChanged }: { auth: DastakV1Auth; sku: V1AdminCataloguePageSku; taxonomy?: V1AdminSnapshot; supabaseUrl: string; disabled: boolean; onSave: (sku: V1AdminCataloguePageSku, patch: Record<string, unknown>) => Promise<void>; onDelete: (sku: V1AdminCataloguePageSku) => Promise<void>; onCatalogueChanged: () => Promise<void> }) {
  const [name, setName] = useState(sku.name);
  const [variant, setVariant] = useState(sku.variant ?? "");
  const [productType, setProductType] = useState(catalogueProductType(sku.attributes) ?? "");
  const productTypeChanged = productType.trim() !== (catalogueProductType(sku.attributes) ?? "");
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
  const changed = productTypeChanged || listPricePaise !== sku.listPricePaise || sellingPricePaise !== sku.sellingPricePaise || status !== sku.status ||
    name.trim() !== sku.name || variant.trim() !== (sku.variant ?? "") || packSize.trim() !== sku.packSize ||
    description.trim() !== (sku.description ?? "") || subcategoryId !== sku.subcategoryId || brandId !== (sku.brandId ?? "") ||
    barcode.trim() !== (sku.barcode ?? "") || numericQuantity !== (sku.quantityValue ?? null) || quantityUnit !== (sku.quantityUnit ?? "") ||
    numericPackCount !== (sku.packCount ?? null) || manufacturerName.trim() !== (sku.manufacturerName ?? "") ||
    countryOfOriginCode.trim().toUpperCase() !== (sku.countryOfOriginCode ?? "") || hsnCode.trim() !== (sku.hsnCode ?? "") ||
    dietType !== sku.dietType || numericShelfLife !== (sku.shelfLifeDays ?? null) || taxRateBps !== sku.taxRateBps || qaStatus !== sku.qaStatus;
  const valid = validProductType(productType) && Boolean(name.trim() && packSize.trim() && subcategoryId) && listPricePaise !== undefined &&
    sellingPricePaise !== undefined && sellingPricePaise <= listPricePaise && taxRateBps !== undefined && taxRateBps <= 10000 &&
    !Number.isNaN(numericQuantity) && !Number.isNaN(numericPackCount) && !Number.isNaN(numericShelfLife);
  const activatingWithoutEvidence = status === "ACTIVE" && sku.status !== "ACTIVE" && !sku.activationReady;
  const canSave = valid && changed && !activatingWithoutEvidence;
  const patch = { name: name.trim(), variant: variant.trim() || null, packSize: packSize.trim(), description: description.trim() || null,
    subcategoryId, brandId: brandId || null, barcode: barcode.trim() || null, quantityValue: numericQuantity,
    quantityUnit: quantityUnit || null, packCount: numericPackCount, manufacturerName: manufacturerName.trim() || null,
    countryOfOriginCode: countryOfOriginCode.trim().toUpperCase() || null, hsnCode: hsnCode.trim() || null,
    dietType, shelfLifeDays: numericShelfLife, taxRateBps, qaStatus, listPricePaise, sellingPricePaise, status,
    ...(productTypeChanged && validProductType(productType) ? { attributes: withCatalogueProductType(sku.attributes, productType) } : {}) };
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
      <button className="secondary-button" type="button" onClick={() => { setStatus("INACTIVE"); }} disabled={disabled || status === "INACTIVE"}>Archive SKU</button><button className="secondary-button" type="button" onClick={() => void onDelete(sku)} disabled={disabled}>Delete permanently</button><button className="secondary-button" type="submit" disabled={disabled || !canSave}>{changed ? "Save changes" : "Up to date"}</button>
    </section>

    <AdminCatalogueAssets auth={auth} sku={sku} onCatalogueChanged={onCatalogueChanged} />

    <details className="admin-sku-record">
      <summary><span><strong>Full product record</strong><small>Identity, classification, evidence, compliance and operations</small></span><ChevronDown size={17} /></summary>
      <div className="admin-sku-facts">
        <SkuFact icon={<Tags />} label="Department" value={sku.categoryTypeName ?? "Not classified"} />
        <SkuFact icon={<Tags />} label="Category" value={sku.categoryName} />
        <SkuFact icon={<Tags />} label="Subcategory" value={sku.subcategoryName} />
        <SkuFact icon={<Tags />} label="Product Type" value={catalogueProductType(sku.attributes) ?? "Not recorded"} />
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
        <label className="wide"><span>Product Type</span><input value={productType} maxLength={PRODUCT_TYPE_MAX_LENGTH} disabled={disabled} onChange={(event) => setProductType(event.target.value)} aria-describedby={`product-type-help-${sku.id}`} /><small id={`product-type-help-${sku.id}`}>Verified classification within this subcategory, e.g. Full Cream or Toned. Separate from flavour/variant. Use the same wording for every pack; leave blank if unverified. Shared with Customer and Merchant.</small></label>
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
