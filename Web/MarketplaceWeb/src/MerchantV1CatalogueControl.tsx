import { useCallback, useEffect, useMemo, useState } from "react";
import { Check, CirclePause, RefreshCw, Search, ShieldCheck, Store } from "lucide-react";
import { formatPrice } from "./catalogue";
import { userFacingError } from "./userFacingError";
import {
  getV1MerchantCanonicalCatalogue,
  updateV1MerchantBranchState,
  updateV1MerchantSkuSelection,
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
  const [categoryId, setCategoryId] = useState<string>();

  const refresh = useCallback(async () => {
    try {
      setSnapshot(await getV1MerchantCanonicalCatalogue(auth));
      setError(undefined);
    } catch (requestError) {
      setError(message(requestError));
    } finally {
      setLoading(false);
    }
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);

  const visibleSkus = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    return (snapshot?.skus ?? []).filter((sku) =>
      (!categoryId || sku.categoryId === categoryId) &&
      (!normalized || `${sku.name} ${sku.brandName ?? ""} ${sku.variant ?? ""} ${sku.packSize}`
        .toLowerCase().includes(normalized))
    );
  }, [categoryId, query, snapshot]);

  const setSelection = async (sku: V1MerchantCanonicalCatalogue["skus"][number]) => {
    if (!snapshot || busy) return;
    setBusy(sku.skuId);
    setError(undefined);
    try {
      await updateV1MerchantSkuSelection({
        ...auth,
        branchId: snapshot.branch.branchId,
        skuId: sku.skuId,
        selected: !sku.selected,
        expectedVersion: sku.selectionVersion,
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
  if (!snapshot) return <section className="merchant-v1-control"><p className="order-error" role="alert">{error ?? "Merchant catalogue unavailable."}</p><button className="secondary-button" onClick={() => void refresh()}><RefreshCw size={16} /> Retry</button></section>;

  const { branch } = snapshot;
  return <section className="merchant-v1-control">
    <header className="merchant-orders-heading">
      <div><p className="eyebrow">V1 retail operations</p><h1>{branch.branchName}</h1><p>{branch.organizationName}</p></div>
      <button className="icon-button" type="button" onClick={() => void refresh()} disabled={Boolean(busy)} aria-label="Refresh catalogue"><RefreshCw size={18} /></button>
    </header>

    {error && <p className="order-error" role="alert">{error}</p>}

    <div className="merchant-v1-operation-grid">
      <article><Store size={19} /><span><strong>{branch.operationalState.isOpen ? "Branch open" : "Branch closed"}</strong><small>Controls branch availability</small></span><button type="button" className="secondary-button" disabled={Boolean(busy)} onClick={() => void setOperation(!branch.operationalState.isOpen, false)}>{branch.operationalState.isOpen ? "Close" : "Open"}</button></article>
      <article><CirclePause size={19} /><span><strong>{branch.operationalState.acceptingOrders ? "Accepting orders" : "New orders paused"}</strong><small>Paid commitments continue</small></span><button type="button" className="secondary-button" disabled={Boolean(busy)} onClick={() => void setOperation(true, !branch.operationalState.acceptingOrders)}>{branch.operationalState.acceptingOrders ? "Pause" : "Accept"}</button></article>
      <article><ShieldCheck size={19} /><span><strong>{branch.capacity.available} of {branch.capacity.limit} slots available</strong><small>{branch.capacity.held} preparation slots held</small></span><b>Live</b></article>
    </div>

    <div className="merchant-v1-canonical-note"><ShieldCheck size={18} /><span><strong>Dastak canonical catalogue</strong><small>Choose what this branch can physically supply. Identity, image, brand, pack size and price are server-managed.</small></span></div>

    <div className="merchant-v1-catalogue-tools">
      <label><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search canonical SKUs" aria-label="Search canonical SKUs" /></label>
      <div role="group" aria-label="Catalogue category">
        <button type="button" className={!categoryId ? "selected" : ""} onClick={() => setCategoryId(undefined)}>All</button>
        {snapshot.categories.map((category) => <button key={category.categoryId} type="button" className={categoryId === category.categoryId ? "selected" : ""} onClick={() => setCategoryId(category.categoryId)}>{category.name}</button>)}
      </div>
    </div>

    <div className="merchant-v1-sku-list" aria-live="polite">
      {visibleSkus.length === 0 ? <p>No matching canonical SKUs.</p> : visibleSkus.map((sku) => {
        const subcategory = snapshot.subcategories.find((item) => item.subcategoryId === sku.subcategoryId);
        return <article key={sku.skuId}>
          <span className={`merchant-v1-selection ${sku.selected ? "selected" : ""}`} aria-hidden="true">{sku.selected && <Check size={16} />}</span>
          <span><strong>{sku.name}</strong><small>{[sku.brandName, sku.variant, sku.packSize, subcategory?.name].filter(Boolean).join(" · ")}</small></span>
          <span className="merchant-v1-price"><strong>{formatPrice(sku.sellingPricePaise)}</strong>{sku.listPricePaise > sku.sellingPricePaise && <small>{formatPrice(sku.listPricePaise)}</small>}</span>
          <button type="button" className={sku.selected ? "secondary-button" : "primary-button"} disabled={Boolean(busy) || sku.catalogueStatus !== "ACTIVE"} aria-pressed={sku.selected} onClick={() => void setSelection(sku)}>{busy === sku.skuId ? "Saving…" : sku.selected ? "Uncheck" : "Select"}</button>
        </article>;
      })}
    </div>
    {snapshot.truncated && <p className="merchant-v1-truncated">Showing the first 1,000 SKUs. Refine the canonical catalogue before launch.</p>}
  </section>;
}

function message(error: unknown) {
  return userFacingError(error, "The merchant control could not be completed.");
}
