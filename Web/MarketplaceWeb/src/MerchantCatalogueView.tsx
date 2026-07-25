import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ImagePlus, LocateFixed, PackagePlus, Pencil, Plus, RefreshCw, Save, Store, X } from "lucide-react";
import {
  catalogueImageUrl,
  formatPrice,
  getMerchantCatalogue,
  upsertCatalogueCategory,
  upsertCatalogueProduct,
  upsertMerchantStore,
  uploadCatalogueImage,
  type CatalogueCategory,
  type CatalogueProduct,
  type CatalogueSnapshot,
} from "./catalogue";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  supabaseUrl: string;
  publishableKey: string;
};

type ProductDraft = {
  productId?: string;
  categoryId: string;
  name: string;
  description: string;
  unitLabel: string;
  priceRupees: string;
  imageObjectPath?: string;
  availability: CatalogueProduct["availability"];
  catalogueKind: CatalogueProduct["catalogueKind"];
  isActive: boolean;
};

const emptyProduct = (categoryId = ""): ProductDraft => ({
  categoryId,
  name: "",
  description: "",
  unitLabel: "",
  priceRupees: "",
  availability: "in_stock",
  catalogueKind: "general",
  isActive: true,
});

export function MerchantCatalogueView({ accessToken, accountId, client, supabaseUrl, publishableKey }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [snapshot, setSnapshot] = useState<CatalogueSnapshot>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [storeName, setStoreName] = useState("");
  const [storeAddress, setStoreAddress] = useState("");
  const [latitude, setLatitude] = useState("");
  const [longitude, setLongitude] = useState("");
  const [published, setPublished] = useState(false);
  const [acceptingOrders, setAcceptingOrders] = useState(false);
  const [categoryName, setCategoryName] = useState("");
  const [editingCategory, setEditingCategory] = useState<CatalogueCategory>();
  const [productDraft, setProductDraft] = useState<ProductDraft>();
  const [productImage, setProductImage] = useState<File>();

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const next = await getMerchantCatalogue(auth);
      setSnapshot(next);
      const store = next.stores[0];
      if (store) {
        setStoreName(store.name);
        setStoreAddress(store.address);
        setLatitude(String(store.location.latitude));
        setLongitude(String(store.location.longitude));
        setPublished(store.isPublished);
        setAcceptingOrders(store.acceptingOrders);
      }
      setError(undefined);
    } catch (loadError) {
      setError(message(loadError));
    } finally {
      setLoading(false);
    }
  }, [auth]);

  useEffect(() => { void load(); }, [load]);

  const locateStore = () => {
    if (!navigator.geolocation) {
      setError("This browser cannot provide the store location.");
      return;
    }
    setBusy(true);
    navigator.geolocation.getCurrentPosition((position) => {
      setLatitude(position.coords.latitude.toFixed(6));
      setLongitude(position.coords.longitude.toFixed(6));
      setBusy(false);
    }, () => {
      setError("Location access was not allowed.");
      setBusy(false);
    }, { enableHighAccuracy: true, timeout: 12_000, maximumAge: 60_000 });
  };

  const saveStore = async (event: FormEvent) => {
    event.preventDefault();
    const lat = Number(latitude);
    const lng = Number(longitude);
    if (!storeName.trim() || !storeAddress.trim() || !Number.isFinite(lat) || !Number.isFinite(lng)) return;
    await mutate(async () => {
      await upsertMerchantStore({
        ...auth,
        name: storeName,
        address: storeAddress,
        location: { latitude: lat, longitude: lng },
        isPublished: published,
        acceptingOrders: published && acceptingOrders,
        idempotencyKey: crypto.randomUUID(),
      });
      await load();
      setNotice("Store settings saved.");
    });
  };

  const saveCategory = async (event: FormEvent) => {
    event.preventDefault();
    if (!categoryName.trim()) return;
    await mutate(async () => {
      await upsertCatalogueCategory({
        ...auth,
        categoryId: editingCategory?.categoryId,
        name: categoryName,
        displayOrder: editingCategory?.displayOrder ?? (snapshot?.categories.length ?? 0),
        isActive: editingCategory?.isActive ?? true,
        idempotencyKey: crypto.randomUUID(),
      });
      setCategoryName("");
      setEditingCategory(undefined);
      await load();
      setNotice("Category saved.");
    });
  };

  const toggleCategory = async (category: CatalogueCategory) => {
    await mutate(async () => {
      await upsertCatalogueCategory({
        ...auth,
        categoryId: category.categoryId,
        name: category.name,
        displayOrder: category.displayOrder,
        isActive: !category.isActive,
        idempotencyKey: crypto.randomUUID(),
      });
      await load();
    });
  };

  const saveProduct = async (event: FormEvent) => {
    event.preventDefault();
    if (!productDraft) return;
    const pricePaise = Math.round(Number(productDraft.priceRupees) * 100);
    if (!productDraft.categoryId || !productDraft.name.trim() || !productDraft.unitLabel.trim() || pricePaise < 1) return;
    await mutate(async () => {
      const imageObjectPath = productImage
        ? await uploadCatalogueImage(client, accountId, productImage)
        : productDraft.imageObjectPath;
      await upsertCatalogueProduct({
        ...auth,
        ...productDraft,
        pricePaise,
        imageObjectPath,
        idempotencyKey: crypto.randomUUID(),
      });
      setProductDraft(undefined);
      setProductImage(undefined);
      await load();
      setNotice("Product saved.");
    });
  };

  const editProduct = (product: CatalogueProduct) => {
    setProductDraft({
      productId: product.productId,
      categoryId: product.categoryId,
      name: product.name,
      description: product.description ?? "",
      unitLabel: product.unitLabel,
      priceRupees: String(product.price.paise / 100),
      imageObjectPath: product.imageObjectPath ?? undefined,
      availability: product.availability,
      catalogueKind: product.catalogueKind,
      isActive: product.isActive,
    });
    setProductImage(undefined);
  };

  const mutate = async (operation: () => Promise<void>) => {
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    try { await operation(); }
    catch (mutationError) { setError(message(mutationError)); }
    finally { setBusy(false); }
  };

  if (loading && !snapshot) return <div className="catalogue-loading" role="status"><span /> Loading catalogue</div>;

  const categories = snapshot?.categories ?? [];
  const products = snapshot?.products ?? [];
  const hasStore = Boolean(snapshot?.stores[0]);

  return (
    <div className="merchant-catalogue-shell">
      <header className="merchant-orders-heading">
        <div><h1>Catalogue</h1><p>Store availability, categories, and products.</p></div>
        <button className="icon-button" type="button" onClick={() => void load()} disabled={busy} aria-label="Refresh catalogue" title="Refresh catalogue"><RefreshCw size={19} /></button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="success-text" role="status">{notice}</p>}

      <form className="catalogue-editor-section store-editor" onSubmit={saveStore}>
        <header><span><Store size={20} /></span><div><h2>Store</h2><p>{hasStore ? "Customer-facing settings" : "Set up your storefront"}</p></div></header>
        <div className="editor-grid">
          <label>Store name<input value={storeName} maxLength={120} onChange={(event) => setStoreName(event.target.value)} required /></label>
          <label>Address<input value={storeAddress} maxLength={300} onChange={(event) => setStoreAddress(event.target.value)} required /></label>
          <label>Latitude<input inputMode="decimal" value={latitude} onChange={(event) => setLatitude(event.target.value)} required /></label>
          <label>Longitude<input inputMode="decimal" value={longitude} onChange={(event) => setLongitude(event.target.value)} required /></label>
        </div>
        <div className="editor-actions spread">
          <button className="secondary-button" type="button" onClick={locateStore} disabled={busy}><LocateFixed size={17} /> Use current location</button>
          <div className="toggle-row">
            <label><input type="checkbox" checked={published} onChange={(event) => { setPublished(event.target.checked); if (!event.target.checked) setAcceptingOrders(false); }} /> Published</label>
            <label><input type="checkbox" checked={acceptingOrders} disabled={!published} onChange={(event) => setAcceptingOrders(event.target.checked)} /> Accepting orders</label>
          </div>
          <button className="primary-button" type="submit" disabled={busy}><Save size={17} /> Save store</button>
        </div>
      </form>

      {hasStore && (
        <section className="catalogue-editor-section">
          <header><div><h2>Categories</h2><p>{categories.length} total</p></div></header>
          <form className="inline-editor" onSubmit={saveCategory}>
            <input value={categoryName} maxLength={80} onChange={(event) => setCategoryName(event.target.value)} aria-label="Category name" placeholder="Category name" required />
            <button className="primary-button" type="submit" disabled={busy || !categoryName.trim()}>{editingCategory ? <Save size={17} /> : <Plus size={17} />}{editingCategory ? "Save" : "Add"}</button>
          </form>
          <div className="catalogue-row-list">
            {categories.map((category) => (
              <div key={category.categoryId} className={!category.isActive ? "muted-row" : ""}>
                <strong>{category.name}</strong>
                <span>{category.isActive ? "Active" : "Hidden"}</span>
                <button className="icon-button" type="button" onClick={() => { setEditingCategory(category); setCategoryName(category.name); }} aria-label={`Edit ${category.name}`} title="Edit category"><Pencil size={16} /></button>
                <button className="secondary-button compact-button" type="button" disabled={busy} onClick={() => void toggleCategory(category)}>{category.isActive ? "Hide" : "Show"}</button>
              </div>
            ))}
          </div>
        </section>
      )}

      {categories.length > 0 && (
        <section className="catalogue-editor-section">
          <header><div><h2>Products</h2><p>{products.length} total</p></div><button className="secondary-button" type="button" onClick={() => setProductDraft(emptyProduct(categories[0].categoryId))}><PackagePlus size={17} /> Add product</button></header>
          <div className="merchant-product-list">
            {products.map((product) => {
              const image = catalogueImageUrl(supabaseUrl, product.imageObjectPath);
              return (
                <article key={product.productId} className={!product.isActive ? "muted-row" : ""}>
                  <div className="merchant-product-image">{image ? <img src={image} alt="" /> : <PackagePlus size={22} />}</div>
                  <div><strong>{product.name}</strong><small>{categories.find((category) => category.categoryId === product.categoryId)?.name} · {product.unitLabel}</small></div>
                  <span>{product.availability === "in_stock" ? "In stock" : "Out of stock"}</span>
                  <b>{formatPrice(product.price.paise)}</b>
                  <button className="icon-button" type="button" onClick={() => editProduct(product)} aria-label={`Edit ${product.name}`} title="Edit product"><Pencil size={16} /></button>
                </article>
              );
            })}
          </div>
        </section>
      )}

      {productDraft && (
        <div className="editor-dialog-backdrop" role="presentation">
          <form className="editor-dialog" onSubmit={saveProduct} aria-label="Product editor">
            <header><div><h2>{productDraft.productId ? "Edit product" : "Add product"}</h2><p>Availability and customer pricing</p></div><button className="icon-button" type="button" onClick={() => setProductDraft(undefined)} aria-label="Close product editor" title="Close"><X size={18} /></button></header>
            <div className="editor-grid">
              <label>Name<input value={productDraft.name} maxLength={160} onChange={(event) => setProductDraft({ ...productDraft, name: event.target.value })} required /></label>
              <label>Category<select value={productDraft.categoryId} onChange={(event) => setProductDraft({ ...productDraft, categoryId: event.target.value })}>{categories.filter((category) => category.isActive).map((category) => <option key={category.categoryId} value={category.categoryId}>{category.name}</option>)}</select></label>
              <label>Unit<input value={productDraft.unitLabel} maxLength={40} onChange={(event) => setProductDraft({ ...productDraft, unitLabel: event.target.value })} placeholder="1 kg, 500 ml, 1 piece" required /></label>
              <label>Price (₹)<input type="number" inputMode="decimal" min="0.01" step="0.01" value={productDraft.priceRupees} onChange={(event) => setProductDraft({ ...productDraft, priceRupees: event.target.value })} required /></label>
              <label>Type<select value={productDraft.catalogueKind} onChange={(event) => setProductDraft({ ...productDraft, catalogueKind: event.target.value as ProductDraft["catalogueKind"] })}><option value="general">General</option><option value="otc_medicine">OTC medicine</option><option value="prescription_medicine">Prescription medicine</option><option value="paan_corner">Paan Corner</option></select></label>
              <label>Stock<select value={productDraft.availability} onChange={(event) => setProductDraft({ ...productDraft, availability: event.target.value as ProductDraft["availability"] })}><option value="in_stock">In stock</option><option value="out_of_stock">Out of stock</option></select></label>
            </div>
            <label>Description<textarea value={productDraft.description} maxLength={1000} onChange={(event) => setProductDraft({ ...productDraft, description: event.target.value })} /></label>
            <label className="file-button"><ImagePlus size={18} /> Product image<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setProductImage(event.target.files?.[0])} /></label>
            <label className="checkbox-line"><input type="checkbox" checked={productDraft.isActive} onChange={(event) => setProductDraft({ ...productDraft, isActive: event.target.checked })} /> Visible in catalogue</label>
            <div className="editor-actions"><button className="secondary-button" type="button" onClick={() => setProductDraft(undefined)}>Cancel</button><button className="primary-button" type="submit" disabled={busy}><Save size={17} /> Save product</button></div>
          </form>
        </div>
      )}
    </div>
  );
}

function message(error: unknown) {
  return error instanceof Error ? error.message : "The catalogue could not be updated.";
}
