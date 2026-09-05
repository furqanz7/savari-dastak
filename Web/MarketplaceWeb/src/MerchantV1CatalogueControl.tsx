import { useCallback, useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Check, CirclePause, PackageCheck, Search, ShieldCheck, Store } from "lucide-react";
import { catalogueImageUrl, formatPrice } from "./catalogue";
import { userFacingError } from "./userFacingError";
import {
  getV1MerchantCanonicalCatalogue,
  updateV1MerchantBranchState,
  updateV1MerchantSkuSelections,
  type DastakV1Auth,
  type V1MerchantCanonicalCatalogue,
} from "./dastakV1";

type Props = { auth: DastakV1Auth };

export function MerchantV1CatalogueControl({ auth }: Props) {
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
  const selectionSaveKey = useRef<string | undefined>(undefined);
  const deferredQuery = useDeferredValue(query);

  const refresh = useCallback(async () => {
    try {
      const next = await getV1MerchantCanonicalCatalogue(auth);
      setSnapshot(next);
      setPendingSelections((current) => {
        const retained = Object.fromEntries(Object.entries(current).filter(([skuId, selected]) =>
          next.skus.find((sku) => sku.skuId === skuId)?.selected !== selected));
        if (Object.keys(retained).length === 0) selectionSaveKey.current = undefined;
        return retained;
      });
      setError(undefined);
    } catch (requestError) {
      setError(message(requestError));
    } finally {
      setLoading(false);
    }
  }, [auth]);

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

  const setSelection = (sku: V1MerchantCanonicalCatalogue["skus"][number]) => {
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

  if (loading) return <div className="catalogue-loading" role="status"><span /> Loading canonical catalogue</div>;
  if (!snapshot) return <section className="merchant-v1-control"><p className="order-error" role="alert">{error ?? "Merchant catalogue unavailable."}</p></section>;

  const { branch } = snapshot;
  return <section className="merchant-v1-control">
    <header className="merchant-orders-heading">
      <div><p className="eyebrow">STORE &amp; CATALOGUE</p><h1>{branch.branchName}</h1><p>{branch.organizationName}</p></div>
    </header>

    {error && <p className="order-error" role="alert">{error}</p>}

    <div className="merchant-v1-operation-grid">
      <article><Store size={19} /><span><strong>{branch.operationalState.isOpen ? "Branch open" : "Branch closed"}</strong><small>Controls branch availability</small></span><button type="button" className="secondary-button" disabled={Boolean(busy)} onClick={() => void setOperation(!branch.operationalState.isOpen, false)}>{branch.operationalState.isOpen ? "Close" : "Open"}</button></article>
      <article><CirclePause size={19} /><span><strong>{branch.operationalState.acceptingOrders ? "Accepting orders" : "New orders paused"}</strong><small>Paid commitments continue</small></span><button type="button" className="secondary-button" disabled={Boolean(busy)} onClick={() => void setOperation(true, !branch.operationalState.acceptingOrders)}>{branch.operationalState.acceptingOrders ? "Pause" : "Accept"}</button></article>
      <article><ShieldCheck size={19} /><span><strong>{branch.capacity.available} of {branch.capacity.limit} slots available</strong><small>{branch.capacity.held} preparation slots held</small></span><b>Live</b></article>
    </div>

    <div className="merchant-v1-canonical-note"><ShieldCheck size={18} /><span><strong>Your storefront, from Dastak’s product library</strong><small>Select only products this branch genuinely sells. Product identity, imagery, pack quantity and customer price stay consistent everywhere.</small></span></div>

    <div className="merchant-v1-catalogue-tools">
      <label><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search products, brands, packs or categories" aria-label="Search products" /></label>
      <div className="merchant-v1-view-switch" role="group" aria-label="Catalogue scope"><button type="button" className={!selectedOnly ? "selected" : ""} onClick={() => setSelectedOnly(false)}>All products</button><button type="button" className={selectedOnly ? "selected" : ""} onClick={() => setSelectedOnly(true)}>My storefront</button></div>
      <div role="group" aria-label="Catalogue department">
        <button type="button" className={!categoryTypeId ? "selected" : ""} onClick={() => { setCategoryTypeId(undefined); setCategoryId(undefined); setSubcategoryId(undefined); }}>All departments</button>
        {snapshot.categoryTypes.map((type) => <button key={type.categoryTypeId} type="button" className={categoryTypeId === type.categoryTypeId ? "selected" : ""} onClick={() => { setCategoryTypeId(type.categoryTypeId); setCategoryId(undefined); setSubcategoryId(undefined); }}>{type.name}</button>)}
      </div>
      <div className="merchant-v1-category-directory">{snapshot.categoryTypes.filter((type) => !categoryTypeId || type.categoryTypeId === categoryTypeId).map((type) => {
        const categories = snapshot.categories.filter((category) => category.categoryTypeId === type.categoryTypeId);
        return categories.length ? <section key={type.categoryTypeId}><h2>{type.name}</h2><div className="merchant-v1-visual-categories" role="group" aria-label={`${type.name} categories`}>{categories.map((category) => <button key={category.categoryId} type="button" className={categoryId === category.categoryId ? "selected" : ""} onClick={() => { setCategoryTypeId(type.categoryTypeId); setCategoryId(category.categoryId); setSubcategoryId(undefined); }}><MerchantImage supabaseUrl={auth.supabaseUrl} imageKey={category.imageKey} /><span>{category.name}</span></button>)}</div></section> : null;
      })}</div>
      {categoryId ? <div role="group" aria-label="Catalogue collection"><button type="button" className={!subcategoryId ? "selected" : ""} onClick={() => setSubcategoryId(undefined)}>All</button>{snapshot.subcategories.filter((item) => item.categoryId === categoryId).map((item) => <button key={item.subcategoryId} type="button" className={subcategoryId === item.subcategoryId ? "selected" : ""} onClick={() => setSubcategoryId(item.subcategoryId)}>{item.name}</button>)}</div> : null}
    </div>

    {categoryId || selectedOnly || deferredQuery.trim() ? <div className="merchant-v1-sku-list merchant-v1-sku-gallery" aria-live="polite">
      {visibleSkus.length === 0 ? <p>No matching canonical SKUs.</p> : visibleSkus.map((sku) => {
        const subcategory = snapshot.subcategories.find((item) => item.subcategoryId === sku.subcategoryId);
        const selected = pendingSelections[sku.skuId] ?? sku.selected;
        return <article key={sku.skuId}>
          <MerchantImage supabaseUrl={auth.supabaseUrl} imageKey={sku.imageKey} />
          <span className={`merchant-v1-selection ${selected ? "selected" : ""}`} aria-hidden="true">{selected && <Check size={16} />}</span>
          <span><strong>{sku.name}</strong><small>{[sku.brandName, sku.variant, sku.packSize, subcategory?.name].filter(Boolean).join(" · ")}</small>{selected ? <em><Check size={13} /> {pendingSelections[sku.skuId] === undefined ? "Visible in your store" : "Selected — not saved yet"}</em> : null}</span>
          <span className="merchant-v1-price"><strong>{formatPrice(sku.sellingPricePaise)}</strong>{sku.listPricePaise > sku.sellingPricePaise && <small>{formatPrice(sku.listPricePaise)}</small>}</span>
          <button type="button" className={selected ? "secondary-button" : "primary-button"} disabled={busy === "catalogue" || sku.catalogueStatus !== "ACTIVE"} aria-pressed={selected} onClick={() => setSelection(sku)}>{selected ? "Remove" : "Select"}</button>
        </article>;
      })}
    </div> : null}
    {Object.keys(pendingSelections).length ? <div className="merchant-v1-save-bar" role="status"><span><strong>{Object.keys(pendingSelections).length} unsaved {Object.keys(pendingSelections).length === 1 ? "change" : "changes"}</strong><small>Keep selecting, then save once.</small></span><button type="button" className="secondary-button" disabled={busy === "catalogue"} onClick={() => { setPendingSelections({}); selectionSaveKey.current = undefined; }}>Discard</button><button type="button" className="primary-button" disabled={busy === "catalogue"} onClick={() => void saveSelections()}>{busy === "catalogue" ? "Saving…" : "Save storefront"}</button></div> : null}
    {snapshot.truncated && <p className="merchant-v1-truncated">Showing the first 1,000 SKUs. Refine the canonical catalogue before launch.</p>}
  </section>;
}

function MerchantImage({ supabaseUrl, imageKey }: { supabaseUrl: string; imageKey?: string }) {
  const source = catalogueImageUrl(supabaseUrl, imageKey ?? null);
  return <span className="merchant-v1-product-art" aria-hidden="true">{source
    ? <img src={source} alt="" loading="lazy" decoding="async" />
    : <PackageCheck size={25} />}</span>;
}

function message(error: unknown) {
  return userFacingError(error, "The merchant control could not be completed.");
}
