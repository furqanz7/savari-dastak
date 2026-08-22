import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Check, CircleAlert, Database, RefreshCw, Upload } from "lucide-react";
import {
  formatV1Price, getV1AdminCatalogue, importV1AdminCatalogue, updateV1AdminSku,
  type DastakV1Auth, type V1AdminSku, type V1AdminSnapshot,
} from "./dastakV1";

const importTemplate = `{
  "categories": [{ "slug": "grocery", "name": "Grocery", "status": "ACTIVE", "sortOrder": 10 }],
  "subcategories": [{ "categorySlug": "grocery", "slug": "staples", "name": "Staples", "status": "ACTIVE", "sortOrder": 10 }],
  "brands": [{ "slug": "example-brand", "name": "Example Brand", "status": "ACTIVE" }],
  "skus": [{
    "categorySlug": "grocery", "subcategorySlug": "staples", "brandSlug": "example-brand",
    "slug": "example-rice-1kg", "canonicalName": "Example Rice", "packSize": "1 kg",
    "listPricePaise": 10000, "sellingPricePaise": 9500, "currencyCode": "INR",
    "taxRateBps": 0, "status": "DRAFT", "logisticsAttributes": { "weightGrams": 1000 }
  }]
}`;

export function AdminCataloguePanel({ auth }: { auth: DastakV1Auth }) {
  const [snapshot, setSnapshot] = useState<V1AdminSnapshot>();
  const [source, setSource] = useState(importTemplate);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const importKeys = useRef(new Map<string, string>());

  const refresh = useCallback(async () => {
    try {
      setSnapshot(await getV1AdminCatalogue(auth));
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      setLoading(false);
    }
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);

  const runImport = async (event: FormEvent) => {
    event.preventDefault();
    let catalogue: unknown;
    try { catalogue = JSON.parse(source); }
    catch { setError("Import must be valid JSON."); return; }
    if (!catalogue || typeof catalogue !== "object" || Array.isArray(catalogue)) {
      setError("Import must be one catalogue object.");
      return;
    }
    const fingerprint = source.trim();
    const idempotencyKey = importKeys.current.get(fingerprint) ?? crypto.randomUUID();
    importKeys.current.set(fingerprint, idempotencyKey);
    setBusy(true);
    setError(undefined);
    try {
      await importV1AdminCatalogue({ ...auth, catalogue: catalogue as Record<string, unknown>, idempotencyKey });
      importKeys.current.delete(fingerprint);
      setNotice("Catalogue import committed atomically and recorded in audit history.");
      await refresh();
    } catch (importError) {
      setError(message(importError));
    } finally {
      setBusy(false);
    }
  };

  const updateSku = async (sku: V1AdminSku, patch: Record<string, unknown>) => {
    setBusy(true);
    setError(undefined);
    try {
      await updateV1AdminSku({
        ...auth, skuId: sku.id, expectedVersion: sku.version, patch, idempotencyKey: crypto.randomUUID(),
      });
      setNotice(`${sku.name} updated with optimistic version protection.`);
      await refresh();
    } catch (updateError) {
      setError(message(updateError));
    } finally {
      setBusy(false);
    }
  };

  if (loading) return <div className="catalogue-loading" role="status"><span /> Loading canonical catalogue</div>;

  return <section className="admin-section v1-admin-catalogue" role="tabpanel">
    <header><div><h2>Canonical catalogue</h2><p>Customer-visible categories, exact SKUs, standardized prices and launch configuration.</p></div><button className="secondary-button" type="button" onClick={() => void refresh()} disabled={busy}><RefreshCw size={17} /> Refresh</button></header>
    {error ? <p className="order-error" role="alert"><CircleAlert size={16} /> {error}</p> : null}
    {notice ? <p className="v1-admin-notice" role="status"><Check size={17} /> {notice}</p> : null}

    {snapshot && <>
      <div className="v1-admin-summary">
        <Summary label="Categories" value={snapshot.categories.length} />
        <Summary label="Subcategories" value={snapshot.subcategories.length} />
        <Summary label="Canonical SKUs" value={snapshot.skuCount} />
        <Summary label="Retail branches" value={snapshot.branches.length} />
      </div>

      <section className="v1-admin-config"><header><Database size={20} /><div><h3>Launch configuration</h3><p>Read-only effective V1 settings for this batch.</p></div></header><div>{snapshot.configuration.map((setting) => <article key={setting.key} className={!setting.valid || (setting.required && !setting.explicit) ? "attention" : ""}><code>{setting.key}</code><strong>{displayValue(setting.value)}</strong><span>{setting.explicit ? "Explicit" : "Default"} · {setting.valid ? "Valid" : "Invalid"}</span></article>)}</div></section>

      <section className="v1-admin-import"><header><Upload size={20} /><div><h3>Atomic catalogue import</h3><p>Upsert categories, subcategories, brands and SKUs by stable slug. Review JSON before submitting.</p></div></header><form onSubmit={runImport}><label htmlFor="v1-catalogue-import">Catalogue JSON</label><textarea id="v1-catalogue-import" value={source} onChange={(event) => setSource(event.target.value)} rows={16} spellCheck={false} disabled={busy} /><button className="primary-button" type="submit" disabled={busy}>{busy ? "Importing…" : "Validate and import"}</button></form></section>

      <section className="v1-admin-skus"><header><div><h3>SKU activation and price visibility</h3><p>{snapshot.truncated ? `Showing the first ${snapshot.skus.length} of ${snapshot.skuCount} SKUs.` : `${snapshot.skuCount} SKUs loaded.`} Merchant selection counts are operational visibility only.</p></div></header>
        <div className="v1-admin-sku-list">{snapshot.skus.map((sku) => <SkuEditor key={`${sku.id}:${sku.version}`} sku={sku} disabled={busy} onSave={updateSku} />)}</div>
      </section>
    </>}
  </section>;
}

function SkuEditor({ sku, disabled, onSave }: { sku: V1AdminSku; disabled: boolean; onSave: (sku: V1AdminSku, patch: Record<string, unknown>) => Promise<void> }) {
  const [listPrice, setListPrice] = useState((sku.listPricePaise / 100).toFixed(2));
  const [sellingPrice, setSellingPrice] = useState((sku.sellingPricePaise / 100).toFixed(2));
  const [status, setStatus] = useState(sku.status);
  const changed = Math.round(Number(listPrice) * 100) !== sku.listPricePaise || Math.round(Number(sellingPrice) * 100) !== sku.sellingPricePaise || status !== sku.status;
  const valid = Number.isFinite(Number(listPrice)) && Number.isFinite(Number(sellingPrice)) && Number(sellingPrice) >= 0 && Number(sellingPrice) <= Number(listPrice);
  return <form onSubmit={(event) => {
    event.preventDefault();
    if (!valid || !changed) return;
    void onSave(sku, { listPricePaise: Math.round(Number(listPrice) * 100), sellingPricePaise: Math.round(Number(sellingPrice) * 100), status });
  }}>
    <div><strong>{sku.name}</strong><small>{sku.packSize} · {sku.selectionCount} merchant selections · v{sku.version}</small></div>
    <label><span>MRP (₹)</span><input inputMode="decimal" value={listPrice} onChange={(event) => setListPrice(event.target.value)} aria-label={`${sku.name} MRP`} /></label>
    <label><span>Selling (₹)</span><input inputMode="decimal" value={sellingPrice} onChange={(event) => setSellingPrice(event.target.value)} aria-label={`${sku.name} selling price`} /></label>
    <label><span>Visibility</span><select value={status} onChange={(event) => setStatus(event.target.value as V1AdminSku["status"])} aria-label={`${sku.name} visibility`}><option value="DRAFT">Draft</option><option value="ACTIVE">Active</option><option value="INACTIVE">Inactive</option></select></label>
    <span className={`v1-admin-status ${status.toLowerCase()}`}>{status}<small>{formatV1Price(sku.sellingPricePaise)}</small></span>
    <button className="secondary-button" type="submit" disabled={disabled || !changed || !valid}>Save</button>
  </form>;
}

function Summary({ label, value }: { label: string; value: number }) { return <div><strong>{value}</strong><span>{label}</span></div>; }
function displayValue(value: unknown) { return typeof value === "string" ? value : JSON.stringify(value); }
function message(error: unknown) { return error instanceof Error ? error.message : "Catalogue operation failed."; }
