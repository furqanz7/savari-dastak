import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ImagePlus, LocateFixed, PackagePlus, Pencil, Plus, RefreshCw, Save, Store, X } from "lucide-react";
import { userFacingError } from "./userFacingError";
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
  mode: "catalogue" | "store";
  onOpenStore: () => void;
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

export function MerchantCatalogueView({
  accessToken,
  accountId,
  client,
  supabaseUrl,
  publishableKey,
  mode,
  onOpenStore,
}: Props) {
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
  const [productStep, setProductStep] = useState<"details" | "availability">("details");

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
  useEffect(() => {
    if (!productDraft) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setProductDraft(undefined);
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [productDraft]);

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
    if (
      !storeName.trim() ||
      !storeAddress.trim() ||
      !Number.isFinite(lat) ||
      !Number.isFinite(lng) ||
      lat < -90 ||
      lat > 90 ||
      lng < -180 ||
      lng > 180
    ) return;
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
    const pricePaise = productPricePaise(productDraft.priceRupees);
    if (!productDraft.categoryId || !productDraft.name.trim() || !productDraft.unitLabel.trim() || pricePaise === undefined) return;
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
      setProductStep("details");
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
    setProductStep("details");
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
        <div>
          <p className="eyebrow">Dastak Merchant</p>
          <h1>{mode === "store" ? "Store" : "Catalogue"}</h1>
          <p>{mode === "store" ? "Customer-facing location and availability." : "Categories, products, prices, and stock."}</p>
        </div>
        <button className="icon-button" type="button" onClick={() => void load()} disabled={busy} aria-label="Refresh catalogue" title="Refresh catalogue"><RefreshCw size={19} /></button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="success-text" role="status">{notice}</p>}

      {mode === "store" ? (
        <form className="catalogue-editor-section store-editor" onSubmit={saveStore}>
          <header><span><Store size={20} /></span><div><h2>{hasStore ? storeName : "Set up your storefront"}</h2><p>{hasStore ? storeAddress : "Add the store customers will discover."}</p></div></header>
          <div className="editor-grid">
            <label>Store name<input autoComplete="organization" value={storeName} maxLength={120} onChange={(event) => setStoreName(event.target.value)} required /></label>
            <label>Address<input autoComplete="street-address" value={storeAddress} maxLength={300} onChange={(event) => setStoreAddress(event.target.value)} required /></label>
            <label>Latitude<input inputMode="decimal" value={latitude} onChange={(event) => setLatitude(event.target.value)} required /></label>
            <label>Longitude<input inputMode="decimal" value={longitude} onChange={(event) => setLongitude(event.target.value)} required /></label>
          </div>
          <div className="editor-actions spread">
            <button className="secondary-button" type="button" onClick={locateStore} disabled={busy}><LocateFixed size={17} /> Use current location</button>
            <div className="toggle-row">
              <label className="switch-control">
                <input type="checkbox" checked={published} onChange={(event) => { setPublished(event.target.checked); if (!event.target.checked) setAcceptingOrders(false); }} />
                <span className="switch-track" aria-hidden="true" />
                <span>Published</span>
              </label>
              <label className="switch-control">
                <input type="checkbox" checked={acceptingOrders} disabled={!published} onChange={(event) => setAcceptingOrders(event.target.checked)} />
                <span className="switch-track" aria-hidden="true" />
                <span>Accepting orders</span>
              </label>
            </div>
            <button className="primary-button" type="submit" disabled={busy}><Save size={17} /> Save store</button>
          </div>
        </form>
      ) : !hasStore ? (
        <section className="catalogue-message merchant-setup-message">
          <span className="message-icon"><Store size={21} /></span>
          <div>
            <h2>Set up your store first</h2>
            <p>Store details are required before products can be published.</p>
            <button className="secondary-button compact-button" type="button" onClick={onOpenStore}><Store size={17} /> Open Store</button>
          </div>
        </section>
      ) : (
        <>
          <section className="catalogue-editor-section">
            <header><div><h2>Categories</h2><p>{categories.length} total</p></div></header>
            <form className="inline-editor" onSubmit={saveCategory}>
              <input value={categoryName} maxLength={80} onChange={(event) => setCategoryName(event.target.value)} aria-label="Category name" placeholder="Category name" required />
              <button className="primary-button" type="submit" disabled={busy || !categoryName.trim()}>{editingCategory ? <Save size={17} /> : <Plus size={17} />}{editingCategory ? "Save" : "Add"}</button>
              {editingCategory && <button className="icon-button" type="button" onClick={() => { setEditingCategory(undefined); setCategoryName(""); }} aria-label="Cancel category edit" title="Cancel"><X size={17} /></button>}
            </form>
            {categories.length === 0 ? <p className="merchant-orders-empty">Add a category before adding products.</p> : (
              <div className="catalogue-row-list">
                {categories.map((category) => (
                  <div key={category.categoryId} className={!category.isActive ? "muted-row" : ""}>
                    <strong>{category.name}</strong>
                    <span>{category.isActive ? "Visible" : "Hidden"}</span>
                    <button className="icon-button" type="button" onClick={() => { setEditingCategory(category); setCategoryName(category.name); }} aria-label={`Edit ${category.name}`} title="Edit category"><Pencil size={16} /></button>
                    <button className="secondary-button compact-button" type="button" disabled={busy} onClick={() => void toggleCategory(category)}>{category.isActive ? "Hide" : "Show"}</button>
                  </div>
                ))}
              </div>
            )}
          </section>

          {categories.length > 0 && (
            <section className="catalogue-editor-section">
              <header><div><h2>Products</h2><p>{products.length} total</p></div><button className="secondary-button" type="button" onClick={() => { setProductDraft(emptyProduct(categories[0].categoryId)); setProductStep("details"); }}><PackagePlus size={17} /> Add product</button></header>
              {products.length === 0 ? <p className="merchant-orders-empty">No products yet.</p> : (
                <div className="merchant-product-list">
                  {products.map((product) => {
                    const image = catalogueImageUrl(supabaseUrl, product.imageObjectPath);
                    return (
                      <article key={product.productId} className={!product.isActive ? "muted-row" : ""}>
                        <div className="merchant-product-image">{image ? <img src={image} alt={product.name} /> : <PackagePlus size={22} />}</div>
                        <div><strong>{product.name}</strong><small>{categories.find((category) => category.categoryId === product.categoryId)?.name} · {product.unitLabel}{product.restrictedApprovalState !== "not_applicable" ? ` · ${approvalLabel(product.restrictedApprovalState)}` : ""}</small></div>
                        <span>{product.availability === "in_stock" ? "In stock" : "Out of stock"}</span>
                        <b>{formatPrice(product.price.paise)}</b>
                        <button className="icon-button" type="button" onClick={() => editProduct(product)} aria-label={`Edit ${product.name}`} title="Edit product"><Pencil size={16} /></button>
                      </article>
                    );
                  })}
                </div>
              )}
            </section>
          )}
        </>
      )}

      {productDraft && (
        <div className="editor-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setProductDraft(undefined); }}>
          <form className="editor-dialog" onSubmit={saveProduct} role="dialog" aria-modal="true" aria-labelledby="product-editor-title">
            <header><div><p className="eyebrow">Step {productStep === "details" ? "1 of 2" : "2 of 2"}</p><h2 id="product-editor-title">{productDraft.productId ? "Edit product" : "Add product"}</h2><p>{productStep === "details" ? "Customer-facing product details" : "Availability and publication"}</p></div><button className="icon-button" type="button" onClick={() => setProductDraft(undefined)} aria-label="Close product editor" title="Close"><X size={18} /></button></header>
            {productStep === "details" ? (
              <>
                <div className="editor-grid">
                  <label>Name<input autoFocus value={productDraft.name} maxLength={160} onChange={(event) => setProductDraft({ ...productDraft, name: event.target.value })} required /></label>
                  <label>Category<select value={productDraft.categoryId} onChange={(event) => setProductDraft({ ...productDraft, categoryId: event.target.value })}>{categories.filter((category) => category.isActive).map((category) => <option key={category.categoryId} value={category.categoryId}>{category.name}</option>)}</select></label>
                  <label>Unit<input value={productDraft.unitLabel} maxLength={40} onChange={(event) => setProductDraft({ ...productDraft, unitLabel: event.target.value })} placeholder="1 kg, 500 ml, 1 piece" required /></label>
                  <label>Price (₹)<input type="number" inputMode="decimal" min="0.01" max="1000000" step="0.01" value={productDraft.priceRupees} onChange={(event) => setProductDraft({ ...productDraft, priceRupees: event.target.value })} required /></label>
                </div>
                <label>Description<textarea value={productDraft.description} maxLength={1000} onChange={(event) => setProductDraft({ ...productDraft, description: event.target.value })} /></label>
              </>
            ) : (
              <>
                <div className="editor-grid">
                  <label>Type<select value={productDraft.catalogueKind} onChange={(event) => setProductDraft({ ...productDraft, catalogueKind: event.target.value as ProductDraft["catalogueKind"] })}><option value="general">General</option><option value="otc_medicine">OTC medicine</option><option value="prescription_medicine">Prescription medicine</option><option value="paan_corner">Paan Corner</option></select></label>
                  <label>Stock<select value={productDraft.availability} onChange={(event) => setProductDraft({ ...productDraft, availability: event.target.value as ProductDraft["availability"] })}><option value="in_stock">In stock</option><option value="out_of_stock">Out of stock</option></select></label>
                </div>
                <label className="file-button"><ImagePlus size={18} /> {productImage?.name ?? "Choose product image"}<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setProductImage(event.target.files?.[0])} /></label>
                <label className="switch-control product-visibility"><input type="checkbox" checked={productDraft.isActive} onChange={(event) => setProductDraft({ ...productDraft, isActive: event.target.checked })} /><span className="switch-track" aria-hidden="true" /><span>Visible in catalogue</span></label>
              </>
            )}
            <div className="editor-actions spread">
              <button className="secondary-button" type="button" onClick={() => productStep === "availability" ? setProductStep("details") : setProductDraft(undefined)}>{productStep === "availability" ? "Back" : "Cancel"}</button>
              {productStep === "details" ? (
                <button className="primary-button" type="button" disabled={!productDetailsValid(productDraft)} onClick={() => setProductStep("availability")}>Continue</button>
              ) : (
                <button className="primary-button" type="submit" disabled={busy}><Save size={17} /> Save product</button>
              )}
            </div>
          </form>
        </div>
      )}
    </div>
  );
}

function message(error: unknown) {
  return userFacingError(error, "The catalogue could not be updated.");
}

function productPricePaise(value: string) {
  const normalized = value.trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return undefined;
  const paise = Number(normalized) * 100;
  if (!Number.isSafeInteger(paise) || paise < 1 || paise > 100_000_000) return undefined;
  return paise;
}

function productDetailsValid(draft: ProductDraft) {
  return Boolean(
    draft.categoryId &&
    draft.name.trim() &&
    draft.unitLabel.trim() &&
    productPricePaise(draft.priceRupees) !== undefined
  );
}

function approvalLabel(state: CatalogueProduct["restrictedApprovalState"]) {
  switch (state) {
    case "pending": return "Approval pending";
    case "approved": return "Approved";
    case "rejected": return "Approval rejected";
    case "suspended": return "Approval suspended";
    default: return "";
  }
}
