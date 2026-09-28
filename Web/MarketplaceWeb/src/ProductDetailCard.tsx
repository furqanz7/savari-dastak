import { useEffect, useRef, useState, type ReactNode } from "react";
import { Bookmark, ChevronDown, ChevronLeft, ChevronRight, Package, Share2 } from "lucide-react";
import { catalogueImageUrl, formatPrice } from "./catalogue";
import "./design/product-detail.css";

import { productUnitPrice, sameProductFamily, type DetailProduct } from "./productDetail";
export type { DetailProduct } from "./productDetail";

export function ProductDetailCard({ product, products, supabaseUrl, onClose, action, children, saved, savingWishlist, onWishlist }: {
  product: DetailProduct; products: DetailProduct[]; supabaseUrl: string;
  onSelect: (id: string) => void; onClose: () => void; action: ReactNode | ((product: DetailProduct) => ReactNode); children?: ReactNode;
  saved?: boolean; savingWishlist?: boolean; onWishlist?: () => void;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const [imageIndex, setImageIndex] = useState(0);
  const [selectedPackId, setSelectedPackId] = useState(product.id);
  const [shareStatus, setShareStatus] = useState("");
  useEffect(() => { setSelectedPackId(product.id); setImageIndex(0); }, [product.id]);
  const selectedProduct = products.find((item) => item.id === selectedPackId) ?? product;
  const keys = [...new Set([selectedProduct.imageKey, ...selectedProduct.galleryImageKeys].filter((key): key is string => Boolean(key)))];
  const packs = products.filter((item) => sameProductFamily(selectedProduct, item));
  const share = async () => {
    const text = `${selectedProduct.name} · ${selectedProduct.packSize} · ${formatPrice(selectedProduct.price)} — Dastak`;
    try {
      if (navigator.share) await navigator.share({ title: product.name, text });
      else { await navigator.clipboard.writeText(text); setShareStatus("Product details copied"); }
    } catch (error) { if (!(error instanceof DOMException && error.name === "AbortError")) setShareStatus("Sharing is unavailable on this device"); }
  };
  return <section className="product-detail-card" aria-label={selectedProduct.name} data-product-id={selectedProduct.id}>
        <header className="product-detail-toolbar">
          <button type="button" onClick={onClose} aria-label="Close product details"><ChevronDown /></button>
          <span />
          {onWishlist ? <button type="button" disabled={savingWishlist} onClick={onWishlist} aria-label={saved ? "Remove from Wishlist" : "Save to Wishlist"} aria-pressed={saved}><Bookmark fill={saved ? "currentColor" : "none"} /></button> : null}
          <button type="button" onClick={() => void share()} aria-label="Share product"><Share2 /></button>
        </header>
        <div className="product-detail-scroll" ref={scroller} tabIndex={0} aria-label="Scrollable product information">
          <div className="product-detail-hero">
            <DetailImage key={keys[imageIndex] ?? selectedProduct.id} source={catalogueImageUrl(supabaseUrl, keys[imageIndex] ?? null, 1024)} name={selectedProduct.name} />
            {keys.length > 1 ? <><button className="product-photo-previous" type="button" aria-label="Previous product image" onClick={() => setImageIndex((index) => (index - 1 + keys.length) % keys.length)}><ChevronLeft /></button><button className="product-photo-next" type="button" aria-label="Next product image" onClick={() => setImageIndex((index) => (index + 1) % keys.length)}><ChevronRight /></button><nav className="product-photo-dots" aria-label="Product photos">{keys.map((key, index) => <button key={key} type="button" aria-label={`View photo ${index + 1}`} aria-current={index === imageIndex} onClick={() => setImageIndex(index)} />)}</nav></> : null}
          </div>
          <section className="product-detail-info">
            {selectedProduct.brand ? <p className="product-detail-brand">{selectedProduct.brand}</p> : null}
            <h2>{selectedProduct.name}</h2>
            {selectedProduct.description ? <p className="product-detail-description">{selectedProduct.description}</p> : null}
            <p className="product-detail-pack-label">{selectedProduct.packSize}</p>
            {packs.length > 1 ? <div className="product-pack-options" role="group" aria-label="Choose pack size" data-product-swipe-ignore>{packs.map((pack) => <button type="button" key={pack.id} aria-pressed={pack.id === selectedProduct.id} onClick={() => { setSelectedPackId(pack.id); setImageIndex(0); }}><strong>{pack.packSize}</strong><b>{formatPrice(pack.price)}</b><small>{productUnitPrice(pack)}</small></button>)}</div> : <div className="product-detail-price"><strong>{formatPrice(selectedProduct.price)}</strong>{selectedProduct.listPrice > selectedProduct.price ? <del>{formatPrice(selectedProduct.listPrice)}</del> : null}<small>{productUnitPrice(selectedProduct)}</small></div>}
          </section>
          {children}
          <section className="product-detail-info product-detail-facts"><h3>Product information</h3><dl>{[["Brand", selectedProduct.brand], ["Variant", selectedProduct.variant], ["Pack size", selectedProduct.packSize], ...(selectedProduct.facts ?? [])].filter(([, value]) => value).map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl><p>Refer to the product packaging for the most up-to-date ingredients, allergens and usage information.</p></section>
          {shareStatus ? <p role="status" className="product-share-status">{shareStatus}</p> : null}
        </div>
        <footer className="product-detail-action"><div><span>{selectedProduct.packSize}</span><strong>{formatPrice(selectedProduct.price)}</strong><small>{productUnitPrice(selectedProduct)}</small></div>{typeof action === "function" ? action(selectedProduct) : action}</footer>
      </section>;
}

export function DetailImage({ source, name }: { source: string | null; name: string }) {
  const [attempt, setAttempt] = useState(0);
  const original = source?.includes("/storage/v1/render/image/public/") ? source.replace("/render/image/public/", "/object/public/").split("?")[0] : undefined;
  const url = attempt === 0 ? source : attempt === 1 ? original : undefined;
  return url ? <img src={url} alt={name} draggable={false} decoding="async" loading={name ? "eager" : "lazy"} onError={() => setAttempt((value) => value + 1)} /> : <span className="product-detail-image-fallback"><Package size={40} /><small>Image unavailable</small></span>;
}
