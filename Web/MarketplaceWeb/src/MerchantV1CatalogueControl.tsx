import { useCallback, useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Check, CirclePause, Leaf, PackageCheck, Search, ShieldCheck, Store } from "lucide-react";
import { catalogueImageUrl, formatPrice } from "./catalogue";
import { ProductDetailCard, type DetailProduct } from "./ProductDetailCard";
import { ProductDetailOverlay } from "./ProductDetailOverlay";
import { merchantStockAction } from "./productDetail";
import { userFacingError } from "./userFacingError";
import { CustomerEmptyState, CustomerNotice, CustomerSkeleton } from "./CustomerUI";
import {
  DastakV1RequestError,
  getV1MerchantCanonicalCatalogue,
  updateV1MerchantBranchState,
  updateV1MerchantSkuSelections,
  type DastakV1Auth,
  type V1MerchantCanonicalCatalogue,
} from "./dastakV1";

type Props = { auth: DastakV1Auth; branchId: string; onSessionExpired: () => void };

const cataloguePageSize = 80;

export function MerchantV1CatalogueControl({ auth, branchId, onSessionExpired }: Props) {
  const [snapshot, setSnapshot] = useState<V1MerchantCanonicalCatalogue>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [query, setQuery] = useState("");
  const [categoryTypeId, setCategoryTypeId] = useState<string>();
  const [categoryId, setCategoryId] = useState<string>();
  const [subcategoryId, setSubcategoryId] = useState<string>();
  const [selectedOnly, setSelectedOnly] = useState(false);
  const [pendingSelections, setPendingSelections] = useState<Record<string, boolean>>({});
  const [detailId, setDetailId] = useState<string>();
  const [visibleLimit, setVisibleLimit] = useState(cataloguePageSize);
  const selectionSaveKey = useRef<string | undefined>(undefined);
  const headingRef = useRef<HTMLElement>(null);
  useEffect(() => {
    if (categoryTypeId) headingRef.current?.scrollIntoView({ block: "start" });
  }, [categoryTypeId]);
  const deferredQuery = useDeferredValue(query);
  useEffect(() => setVisibleLimit(cataloguePageSize), [categoryId, categoryTypeId, deferredQuery, selectedOnly, subcategoryId]);

  const refresh = useCallback(async () => {
    try {
      const next = await getV1MerchantCanonicalCatalogue({ ...auth, branchId, limit: 5000 });
      setSnapshot(next);
      setPendingSelections((current) => {
        const retained = Object.fromEntries(Object.entries(current).filter(([skuId, selected]) =>
          next.skus.find((sku) => sku.skuId === skuId)?.selected !== selected));
        if (Object.keys(retained).length === 0) selectionSaveKey.current = undefined;
        return retained;
      });
      setError(undefined);
      return next;
    } catch (requestError) {
      if (isSessionError(requestError)) onSessionExpired();
      setError(message(requestError));
    } finally {
      setLoading(false);
    }
  }, [auth, branchId, onSessionExpired]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    const resume = () => { if (document.visibilityState === "visible") void refresh(); };
    window.addEventListener("focus", resume);
    document.addEventListener("visibilitychange", resume);
    return () => { window.removeEventListener("focus", resume); document.removeEventListener("visibilitychange", resume); };
  }, [refresh]);

  const visibleSkus = useMemo(() => {
    const normalized = deferredQuery.trim().toLowerCase();
    const categories = new Map((snapshot?.categories ?? []).map((item) => [item.categoryId, item.name]));
    const subcategories = new Map((snapshot?.subcategories ?? []).map((item) => [item.subcategoryId, item.name]));
    return (snapshot?.skus ?? []).filter((sku) =>
      (!categoryTypeId || sku.categoryTypeId === categoryTypeId) &&
      (!categoryId || sku.categoryId === categoryId) &&
      (!subcategoryId || sku.subcategoryId === subcategoryId) &&
      (!selectedOnly || (pendingSelections[sku.skuId] ?? sku.selected)) &&
      (!normalized || `${sku.name} ${sku.brandName ?? ""} ${sku.variant ?? ""} ${sku.packSize} ${categories.get(sku.categoryId) ?? ""} ${subcategories.get(sku.subcategoryId) ?? ""} ${sku.searchTerms.join(" ")}`
        .toLowerCase().includes(normalized))
    );
  }, [categoryId, categoryTypeId, deferredQuery, pendingSelections, selectedOnly, snapshot, subcategoryId]);

  const artworkKeys = useMemo(() => {
    const categories = new Map<string, string>();
    const subcategories = new Map<string, string>();
    for (const sku of snapshot?.skus ?? []) {
      if (!sku.imageKey) continue;
      if (!categories.has(sku.categoryId)) categories.set(sku.categoryId, sku.imageKey);
      if (!subcategories.has(sku.subcategoryId)) subcategories.set(sku.subcategoryId, sku.imageKey);
    }
    return { categories, subcategories };
  }, [snapshot]);

  const setSelection = (sku: V1MerchantCanonicalCatalogue["skus"][number]) => {
    if (sku.stockQuantity === 0 && !sku.selected) { setDetailId(sku.skuId); return; }
    if (busy === "catalogue" || sku.catalogueStatus !== "ACTIVE") return;
    setPendingSelections((current) => {
      const selected = !(current[sku.skuId] ?? sku.selected);
      const next = { ...current };
      if (selected === sku.selected) delete next[sku.skuId];
      else next[sku.skuId] = selected;
      return next;
    });
    selectionSaveKey.current = undefined;
    setError(undefined);
  };

  const saveSelections = async () => {
    if (!snapshot || busy || Object.keys(pendingSelections).length === 0) return;
    const selections = snapshot.skus.flatMap((sku) => pendingSelections[sku.skuId] === undefined ? [] : [{
      skuId: sku.skuId,
      selected: pendingSelections[sku.skuId],
      expectedVersion: sku.selectionVersion,
    }]);
    if (!selections.length) { setPendingSelections({}); return; }
    setBusy("catalogue");
    setError(undefined);
    try {
      const idempotencyKey = selectionSaveKey.current ?? crypto.randomUUID();
      selectionSaveKey.current = idempotencyKey;
      await updateV1MerchantSkuSelections({
        ...auth,
        branchId: snapshot.branch.branchId,
        selections,
        idempotencyKey,
      });
      setPendingSelections({});
      selectionSaveKey.current = undefined;
      await refresh();
    } catch (requestError) {
      await refresh();
      setError(message(requestError));
    } finally {
      setBusy(undefined);
    }
  };

  const setOperation = async (isOpen: boolean, acceptingOrders: boolean) => {
    if (!snapshot || busy) return;
    setBusy("branch");
    setError(undefined);
    try {
      await updateV1MerchantBranchState({
        ...auth,
        branchId: snapshot.branch.branchId,
        isOpen,
        acceptingOrders,
        expectedVersion: snapshot.branch.operationalState.version,
        idempotencyKey: crypto.randomUUID(),
      });
      await refresh();
    } catch (requestError) {
      setError(message(requestError));
      await refresh();
    } finally {
      setBusy(undefined);
    }
  };

  const saveStock = async (sku: V1MerchantCanonicalCatalogue["skus"][number], quantity: number) => {
    if (!snapshot || busy) return undefined;
    setBusy("stock"); setError(undefined);
    try {
      await updateV1MerchantSkuSelections({ ...auth, branchId: snapshot.branch.branchId,
        selections: [{ skuId: sku.skuId, selected: quantity > 0, expectedVersion: sku.selectionVersion, stockQuantity: quantity }], idempotencyKey: crypto.randomUUID() });
      setPendingSelections((current) => { const next = { ...current }; delete next[sku.skuId]; return next; });
      selectionSaveKey.current = undefined;
      return (await refresh())?.skus.find((item) => item.skuId === sku.skuId);
    } catch (requestError) { await refresh(); setError(message(requestError)); return undefined; }
    finally { setBusy(undefined); }
  };

  const addSku = async (sku: V1MerchantCanonicalCatalogue["skus"][number]) => {
    if (!snapshot || busy || sku.selected || sku.stockQuantity === 0 || sku.catalogueStatus !== "ACTIVE") return undefined;
    setBusy("stock"); setError(undefined);
    try {
      await updateV1MerchantSkuSelections({ ...auth, branchId: snapshot.branch.branchId,
        selections: [{ skuId: sku.skuId, selected: true, expectedVersion: sku.selectionVersion }], idempotencyKey: crypto.randomUUID() });
      setPendingSelections((current) => { const next = { ...current }; delete next[sku.skuId]; return next; });
      selectionSaveKey.current = undefined;
      return (await refresh())?.skus.find((item) => item.skuId === sku.skuId);
    } catch (requestError) { await refresh(); setError(message(requestError)); return undefined; }
    finally { setBusy(undefined); }
  };

  if (loading) return <CustomerSkeleton label="Loading your Store" />;
  if (!snapshot) return <section className="merchant-v1-control"><CustomerNotice title="Store couldn’t load" onRetry={() => void refresh()}>{error ?? "Your product library is temporarily unavailable."}</CustomerNotice></section>;

  const { branch } = snapshot;
  const selectedType = snapshot.categoryTypes.find((type) => type.categoryTypeId === categoryTypeId);
  const navigationGroups = merchantNavigationGroups(snapshot.categoryTypes);
  const showDirectory = !categoryTypeId && !selectedOnly && !deferredQuery.trim();
  const railCategories = snapshot.categories.filter((category) => category.categoryTypeId === categoryTypeId);
  const productTypes = snapshot.subcategories.filter((item) => item.categoryId === categoryId);
  const detailSku = snapshot.skus.find((sku) => sku.skuId === detailId);
  return <section className="merchant-v1-control">
    <header className="merchant-orders-heading">
      <div><p className="eyebrow">YOUR STORE</p><h1>Stocked for the everyday.</h1><p>Products, stock and availability for {branch.branchName}.</p></div>
    </header>

    {error && <CustomerNotice title="Store update needs attention" onRetry={() => void refresh()}>{error}</CustomerNotice>}

    <div className="merchant-v1-operation-grid">
      <article><Store size={19} /><span><strong>{branch.operationalState.isOpen ? "Branch open" : "Branch closed"}</strong><small>Controls branch availability</small></span><button type="button" className="secondary-button" disabled={Boolean(busy)} onClick={() => void setOperation(!branch.operationalState.isOpen, false)}>{branch.operationalState.isOpen ? "Close" : "Open"}</button></article>
      <article><CirclePause size={19} /><span><strong>{branch.operationalState.acceptingOrders ? "Accepting orders" : "New orders paused"}</strong><small>Confirmed orders continue</small></span><button type="button" className="secondary-button" disabled={Boolean(busy)} onClick={() => void setOperation(true, !branch.operationalState.acceptingOrders)}>{branch.operationalState.acceptingOrders ? "Pause" : "Resume"}</button></article>
      <article><ShieldCheck size={19} /><span><strong>{branch.capacity.available} of {branch.capacity.limit} slots available</strong><small>{branch.capacity.held} preparation slots held</small></span><b>Live</b></article>
    </div>

    <div className="merchant-v1-canonical-note"><ShieldCheck size={18} /><span><strong>Your storefront, from Dastak’s product library</strong><small>Select only products this branch genuinely sells. Product identity, imagery, pack quantity and customer price stay consistent everywhere.</small></span></div>

    <div className="merchant-v1-catalogue-tools">
      <label><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search products, brands, packs or categories" aria-label="Search products" /></label>
      <div className="merchant-v1-view-switch" role="group" aria-label="Catalogue scope"><button type="button" aria-pressed={!selectedOnly} className={!selectedOnly ? "selected" : ""} onClick={() => setSelectedOnly(false)}>Product library</button><button type="button" aria-pressed={selectedOnly} className={selectedOnly ? "selected" : ""} onClick={() => setSelectedOnly(true)}>In my store</button></div>
      {showDirectory ? <div className="merchant-v1-category-directory">
        {navigationGroups.map((group) => <section key={group.key}>
          <header><div><small>PRODUCT LIBRARY</small><h2>{group.name}</h2></div></header>
          <div className="merchant-v1-visual-categories" role="group" aria-label={`${group.name} categories`}>{group.types.map((type) => <button key={type.categoryTypeId} type="button" onClick={() => {
            const children = snapshot.categories.filter((item) => item.categoryTypeId === type.categoryTypeId);
            setCategoryTypeId(type.categoryTypeId);
            setCategoryId((children.find((item) => item.status === "ACTIVE") ?? children[0])?.categoryId);
            setSubcategoryId(undefined);
          }}>
            <MerchantCategoryImage supabaseUrl={auth.supabaseUrl} imageKey={type.imageKey} previewImageKeys={type.previewImageKeys} slug={type.slug} />
            <span>{type.name}{type.status && type.status !== "ACTIVE" ? <small>Coming soon</small> : null}</span>
          </button>)}</div>
        </section>)}
      </div> : null}
    </div>

    {selectedType ? <header ref={headingRef} className="merchant-v1-browser-heading"><h2>{selectedType.name}</h2><button type="button" className="secondary-button" onClick={() => { setCategoryTypeId(undefined); setCategoryId(undefined); setSubcategoryId(undefined); }}>All categories</button></header> : null}
    {categoryTypeId ? <label className="merchant-category-select">Category<select value={categoryId ?? ""} onChange={(event) => { setCategoryId(event.target.value || undefined); setSubcategoryId(undefined); }}>{railCategories.map((item) => <option key={item.categoryId} value={item.categoryId}>{item.name}</option>)}</select></label> : null}
    {categoryTypeId ? <section className="merchant-v1-category-browser">
      <aside className="merchant-v1-subcategory-rail" role="group" aria-label="Subcategories">
        {railCategories.map((item) => <button key={item.categoryId} type="button" aria-pressed={categoryId === item.categoryId} className={categoryId === item.categoryId ? "selected" : ""} onClick={() => { setCategoryId(item.categoryId); setSubcategoryId(undefined); }}><MerchantCategoryImage supabaseUrl={auth.supabaseUrl} imageKey={item.imageKey ?? artworkKeys.categories.get(item.categoryId)} previewImageKeys={item.previewImageKeys} slug={item.slug} /><strong>{item.name}</strong></button>)}
      </aside>
      <div className="merchant-v1-category-results" key={categoryId}><header><h2>{snapshot.categories.find((item) => item.categoryId === categoryId)?.name ?? "Products"}</h2><span>{visibleSkus.length} products</span></header>
        {productTypes.length ? <label className="merchant-v1-type-filter">Type<select aria-label="Product type" value={subcategoryId ?? ""} onChange={(event) => setSubcategoryId(event.target.value || undefined)}><option value="">All types</option>{productTypes.map((item) => <option key={item.subcategoryId} value={item.subcategoryId}>{item.name}</option>)}</select></label> : null}
        <MerchantSkuGallery auth={auth} skus={visibleSkus.slice(0, visibleLimit)} total={visibleSkus.length} onLoadMore={() => setVisibleLimit((current) => current + cataloguePageSize)} subcategories={snapshot.subcategories} pendingSelections={pendingSelections} busy={busy} onSelection={setSelection} onDetail={setDetailId} /></div>
    </section> : selectedOnly || deferredQuery.trim() ? <MerchantSkuGallery auth={auth} skus={visibleSkus.slice(0, visibleLimit)} total={visibleSkus.length} onLoadMore={() => setVisibleLimit((current) => current + cataloguePageSize)} subcategories={snapshot.subcategories} pendingSelections={pendingSelections} busy={busy} onSelection={setSelection} onDetail={setDetailId} /> : null}
    {Object.keys(pendingSelections).length ? <div className="merchant-v1-save-bar" role="status"><span><strong>{Object.keys(pendingSelections).length} unsaved {Object.keys(pendingSelections).length === 1 ? "change" : "changes"}</strong><small>Keep selecting, then save once.</small></span><button type="button" className="secondary-button" disabled={busy === "catalogue"} onClick={() => { setPendingSelections({}); selectionSaveKey.current = undefined; }}>Discard</button><button type="button" className="primary-button" disabled={busy === "catalogue"} onClick={() => void saveSelections()}>{busy === "catalogue" ? "Saving…" : "Save storefront"}</button></div> : null}
    {snapshot.truncated && <p className="merchant-v1-truncated">Dastak loaded the first 5,000 authorised catalogue products. Use search or a category to narrow this branch’s storefront.</p>}
    {detailSku ? <MerchantProductDetail sku={detailSku} products={snapshot.skus.filter((item) => item.categoryId === detailSku.categoryId)} branch={branch.branchName} supabaseUrl={auth.supabaseUrl} onSelect={(id) => { if (!busy) setDetailId(id); }} onClose={() => { if (!busy) setDetailId(undefined); }} onAdd={addSku} onSave={saveStock} busy={Boolean(busy)} error={error} /> : null}
  </section>;
}

function MerchantSkuGallery({ auth, skus, total, onLoadMore, subcategories, pendingSelections, busy, onSelection, onDetail }: {
  auth: DastakV1Auth;
  skus: V1MerchantCanonicalCatalogue["skus"];
  total: number;
  onLoadMore: () => void;
  subcategories: V1MerchantCanonicalCatalogue["subcategories"];
  pendingSelections: Record<string, boolean>;
  busy?: string;
  onSelection: (sku: V1MerchantCanonicalCatalogue["skus"][number]) => void;
  onDetail: (id: string) => void;
}) {
  if (!skus.length) return <CustomerEmptyState title="No matching products" copy="Choose another collection or change your search." />;
  const names = new Map(subcategories.map((item) => [item.subcategoryId, item.name]));
  return <><div className="merchant-v1-sku-list merchant-v1-sku-gallery">{skus.map((sku) => {
    const selected = pendingSelections[sku.skuId] ?? sku.selected;
    return <article className={selected ? "selected" : ""} key={sku.skuId}>
      <button type="button" className="product-open-button" onClick={() => onDetail(sku.skuId)} aria-label={`View ${sku.name} details and stock`}><MerchantImage supabaseUrl={auth.supabaseUrl} imageKey={sku.imageKey} /></button>
      <span className={`merchant-v1-selection ${selected ? "selected" : ""}`} aria-hidden="true">{selected && <Check size={16} />}</span>
      <span className="merchant-v1-product-copy">{sku.brandName ? <b>{sku.brandName.toUpperCase()}</b> : null}<strong>{sku.name}</strong><small>{[sku.variant, sku.packSize, names.get(sku.subcategoryId)].filter(Boolean).join(" · ")}</small>{selected ? <em><Check size={13} /> {pendingSelections[sku.skuId] === undefined ? "In your store" : "Selected — not saved"}</em> : null}</span>
      <span className="merchant-v1-price"><strong>{formatPrice(sku.sellingPricePaise)}</strong>{sku.listPricePaise > sku.sellingPricePaise && <small>{formatPrice(sku.listPricePaise)}</small>}</span>
      {sku.selected ? <small className="merchant-stock-label">{sku.stockQuantity === undefined ? "Stock count not set" : `${sku.stockQuantity} available`}{sku.stockReservedQuantity ? ` · ${sku.stockReservedQuantity} reserved` : ""}</small> : null}
      <button type="button" className={selected ? "secondary-button" : "primary-button"} disabled={busy === "catalogue" || sku.catalogueStatus !== "ACTIVE"} aria-label={`${selected ? "Remove" : "Select"} ${sku.name}`} aria-pressed={selected} onClick={() => onSelection(sku)}>{selected ? "Remove" : "Select"}</button>
    </article>;
  })}</div>{skus.length < total ? <button className="secondary-button merchant-v1-load-more" type="button" onClick={onLoadMore}>Show more products · {total - skus.length} remaining</button> : null}</>;
}

function MerchantImage({ supabaseUrl, imageKey }: { supabaseUrl: string; imageKey?: string }) {
  const source = catalogueImageUrl(supabaseUrl, imageKey ?? null);
  return <span className="merchant-v1-product-art" aria-hidden="true">{source
    ? <MerchantArtworkImage source={source} />
    : <PackageCheck size={25} />}</span>;
}

function MerchantCategoryImage({ supabaseUrl, imageKey, previewImageKeys = [], slug = "" }: {
  supabaseUrl: string;
  imageKey?: string;
  previewImageKeys?: string[];
  slug?: string;
}) {
  const keys = [imageKey, ...previewImageKeys]
    .filter((value, index, values): value is string => Boolean(value) && values.indexOf(value) === index)
    .slice(0, 2);
  return <span className={`merchant-v1-product-art merchant-v1-category-art count-${keys.length}`} aria-hidden="true">{keys.length
    ? keys.map((key) => <MerchantArtworkImage key={key} source={catalogueImageUrl(supabaseUrl, key)} />)
    : slug.includes("paan") || slug.includes("produce") ? <Leaf size={27} />
      : slug.includes("pharmacy") || slug.includes("medicine") || slug.includes("health") ? <ShieldCheck size={27} />
        : <PackageCheck size={25} />}</span>;
}

function MerchantArtworkImage({ source }: { source: string | null }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [source]);
  return source && !failed
    ? <img src={source} alt="" loading="lazy" decoding="async" onError={() => setFailed(true)} />
    : <PackageCheck size={22} />;
}

function merchantNavigationGroups(categoryTypes: V1MerchantCanonicalCatalogue["categoryTypes"]) {
  const groups = new Map<string, {
    key: string;
    name: string;
    sortOrder: number;
    types: V1MerchantCanonicalCatalogue["categoryTypes"];
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

function message(error: unknown) {
  return userFacingError(error, "The merchant control could not be completed.");
}

function isSessionError(error: unknown) {
  return error instanceof DastakV1RequestError && (error.status === 401 || error.code === "authentication_required");
}

function merchantDetail(sku: V1MerchantCanonicalCatalogue["skus"][number]): DetailProduct {
  return { ...sku, id: sku.skuId, brand: sku.brandName, price: sku.sellingPricePaise, listPrice: sku.listPricePaise, facts: [["Diet", sku.dietType]] };
}

type MerchantDetailSKU = V1MerchantCanonicalCatalogue["skus"][number];

export function MerchantProductDetail({ sku, products, branch, supabaseUrl, onSelect, onClose, onSave, onAdd, busy, error }: {
  sku: MerchantDetailSKU; products: MerchantDetailSKU[];
  branch: string; supabaseUrl: string; onSelect: (id: string) => void; onClose: () => void;
  onSave: (sku: MerchantDetailSKU, quantity: number) => Promise<MerchantDetailSKU | undefined>;
  onAdd: (sku: MerchantDetailSKU) => Promise<MerchantDetailSKU | undefined>; busy: boolean; error?: string;
}) {
  return <ProductDetailOverlay selectedId={sku.skuId} products={products.map(merchantDetail)} supabaseUrl={supabaseUrl} showPagingControls
    onSelect={onSelect} onClose={onClose} disabled={busy} renderProduct={(product, select) => {
      const item = products.find((candidate) => candidate.skuId === product.id);
      return item ? <MerchantProductPage sku={item} products={products} branch={branch} supabaseUrl={supabaseUrl}
        onSelect={select} onClose={onClose} onSave={onSave} onAdd={onAdd} busy={busy} error={error} /> : null;
    }} />;
}

function MerchantProductPage({ sku, products, branch, supabaseUrl, onSelect, onClose, onSave, onAdd, busy, error }: {
  sku: MerchantDetailSKU; products: MerchantDetailSKU[];
  branch: string; supabaseUrl: string; onSelect: (id: string) => void; onClose: () => void;
  onSave: (sku: MerchantDetailSKU, quantity: number) => Promise<MerchantDetailSKU | undefined>;
  onAdd: (sku: MerchantDetailSKU) => Promise<MerchantDetailSKU | undefined>; busy: boolean; error?: string;
}) {
  const initialDraft = (item: MerchantDetailSKU) => ({
    id: item.skuId, text: item.stockQuantity?.toString() ?? "", version: item.selectionVersion,
    saved: false, addingEmptySKU: false,
  });
  const [storedDraft, setDraft] = useState(() => initialDraft(sku));
  // Switching products never carries another SKU's stock draft or remounts the modal.
  const draft = storedDraft.id === sku.skuId ? storedDraft : initialDraft(sku);
  const stale = draft.version !== sku.selectionVersion;
  const state = merchantStockAction({ text: draft.text, currentQuantity: sku.stockQuantity,
    reserved: sku.stockReservedQuantity, selected: sku.selected, addingEmptySKU: draft.addingEmptySKU,
    stale, busy, active: sku.catalogueStatus === "ACTIVE" });
  const change = (text: string) => setDraft({ ...draft, text, saved: false });
  const selectProduct = (id: string) => {
    const next = products.find((item) => item.skuId === id);
    if (busy || !next) return;
    onSelect(id);
  };
  const submit = async () => {
    if (!state.canSubmit) return;
    if (!state.stockMode && sku.stockQuantity === 0) {
      setDraft({ ...draft, addingEmptySKU: true });
      return;
    }
    const latest = state.stockMode ? await onSave(sku, state.quantity) : await onAdd(sku);
    if (latest) setDraft({ ...initialDraft(latest), saved: state.stockMode });
  };
  return <ProductDetailCard product={merchantDetail(sku)} products={products.map(merchantDetail)} supabaseUrl={supabaseUrl} onSelect={selectProduct} onClose={onClose}
    action={<button type="button" disabled={!state.canSubmit} aria-busy={busy} onClick={() => void submit()}>{busy ? <span className="product-action-spinner" aria-hidden="true" /> : null}{state.title}</button>}>
    <section className="product-detail-info product-stock-editor">
      <div className="product-stock-heading"><h3>Available stock</h3><span>{sku.selected ? "In your store" : "Not available"}</span></div>
      <p>{branch} · units of {sku.packSize}</p>
      <div className="product-stock-summary"><span>{sku.stockQuantity === undefined ? "Count not set" : String(sku.stockQuantity) + " available"}</span><span>{sku.stockReservedQuantity ?? 0} reserved</span></div>
      <div className="product-stock-input" data-product-swipe-ignore>
        <button type="button" disabled={!state.canEdit || state.quantity <= 0} aria-label="Decrease stock count" onClick={() => change(String(Math.max(0, (state.quantity || 0) - 1)))}>−</button>
        <input inputMode="numeric" pattern="[0-9]*" aria-label="Stock quantity" placeholder="Not set" value={draft.text} disabled={!state.canEdit} onChange={(event) => change(event.target.value)} />
        <button type="button" disabled={!state.canEdit || state.quantity >= 1_000_000 - (sku.stockReservedQuantity ?? 0)} aria-label="Increase stock count" onClick={() => change(String(Math.min(1_000_000 - (sku.stockReservedQuantity ?? 0), (state.quantity || 0) + 1)))}>+</button>
      </div>
      <p>{!state.stockMode ? "Add this product to your store to manage stock." : draft.addingEmptySKU ? "Enter a positive stock count to finish adding this product." : "Orders update stock automatically. Change this count only for restocking or corrections."}</p>
      <p>Enter available, unreserved units. Saving zero makes this product unavailable.</p>
      {stale ? <p role="status">The stock count has changed. <button type="button" disabled={busy} onClick={() => setDraft(initialDraft(sku))}>Use latest stock count</button></p> : null}
      {error ? <p role="alert">{error}</p> : draft.saved ? <p role="status" className="product-stock-saved">Stock count saved.</p> : null}
    </section>
  </ProductDetailCard>;
}
