import { useId, useMemo, useRef, useState, type Dispatch, type ReactNode } from "react";
import { ArrowLeft, ArrowRight, Minus, Package, Plus, ShoppingBasket, TrendingUp } from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import { catalogueProductType } from "./catalogueProductType";
import { formatV1Price, type V1CatalogueSku } from "./dastakV1";
import { filterGroceryShelf, groceryProductTypes, groupGroceryProducts, groceryQuickPicks, groceryShelves, searchGrocery, type GroceryShelf, type ReimaginedCatalogue } from "./reimaginedCatalogue";
import type { ReimaginedAction, ReimaginedState } from "./reimaginedState";
import { WishlistButton } from "./ReimaginedWishlist";
import type { useReimaginedWishlist } from "./useReimaginedWishlist";
import { productUnitPrice, type DetailProduct } from "./productDetail";
import { DetailImage } from "./ProductDetailCard";
import { ReimaginedProductBrowser } from "./ReimaginedProductBrowser";

export type GroceryEligibility = { canAdd: boolean; canRemove?: boolean; maximumQuantity: number; reason?: string };
export type GroceryTrending = { city: string; skuIds: string[]; preview?: boolean };
type Props = {
  state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; data?: ReimaginedCatalogue;
  status: "loading" | "ready" | "unavailable"; onRetry: () => void; supabaseUrl: string;
  eligibility: (sku: V1CatalogueSku) => GroceryEligibility;
  relatedSkuIds?: (sku: V1CatalogueSku) => string[];
  checkoutContent: ReactNode;
  availabilityNotice?: ReactNode;
  trending?: GroceryTrending;
  searchResults?: V1CatalogueSku[]; searchLoading?: boolean; searchError?: unknown; onRetrySearch?: () => void;
  wishlist?: ReturnType<typeof useReimaginedWishlist>;
  online?: boolean;
};

export function ReimaginedGrocery({ state, dispatch, data, status, onRetry, supabaseUrl, eligibility, relatedSkuIds, checkoutContent, availabilityNotice, trending, wishlist, online = true, searchResults, searchLoading, searchError, onRetrySearch }: Props) {
  const packChoicePrefix = useId();
  const exploration = state.exploration.grocery;
  const sourceShelves = useMemo(() => exploration.view.kind === "search" && searchResults !== undefined
    ? [{ key: `search:${exploration.view.query}`, label: `Results for “${exploration.view.query}”`, skus: searchResults }]
    : data ? groceryShelves(data, exploration.view) : [], [data, exploration.view, searchResults]);
  const shelves = useMemo(() => exploration.view.kind === "browse" ? sourceShelves.map(shelf => filterGroceryShelf(shelf, exploration.productTypeFilters[shelf.key])) : sourceShelves, [sourceShelves, exploration.productTypeFilters, exploration.view.kind]);
  const quickPicks = useMemo(() => data ? groceryQuickPicks(data) : [], [data]);
  const productFamilies = useMemo(() => data ? groupGroceryProducts(data.catalogue.skus) : [], [data]);
  const trendingSkus = useMemo(() => {
    if (!data || !trending?.city.trim()) return [];
    const byId = new Map(data.catalogue.skus.map(sku => [sku.id, sku]));
    return [...new Set(trending.skuIds)].slice(0, 12).flatMap(id => {
      const sku = byId.get(id); return sku ? [sku] : [];
    });
  }, [data, trending]);
  const browsingGroups = useMemo(() => {
    const bySku = new Map(productFamilies.flatMap(packs => packs.map(sku => [sku.id, packs] as const)));
    const visible = exploration.view.kind === "home" ? trendingSkus : shelves.flatMap(shelf => shelf.skus);
    const seen = new Set<string>();
    return visible.flatMap(sku => {
      const family = bySku.get(sku.id);
      if (!family || seen.has(family[0].id)) return [];
      seen.add(family[0].id);
      // Preserve the matching/search-ranked pack as each product's initial choice.
      return [[sku, ...family.filter(pack => pack.id !== sku.id)]];
    });
  }, [productFamilies, shelves, trendingSkus, exploration.view.kind]);
  const selected = data?.catalogue.skus.find(sku => sku.id === exploration.detailId);
  const detailGroups = selected ? browsingGroups.some(packs => packs.some(sku => sku.id === selected.id)) ? browsingGroups
    : [productFamilies.find(packs => packs.some(sku => sku.id === selected.id)) ?? [selected]] : [];
  const variants = selected && data ? [...new Set([selected.id, ...(relatedSkuIds ? relatedSkuIds(selected) : productFamilies.find(packs => packs.some(sku => sku.id === selected.id))?.map(sku => sku.id) ?? [])])]
    .map(id => data.catalogue.skus.find(sku => sku.id === id)).filter((sku): sku is V1CatalogueSku => Boolean(sku)) : [];
  const quantity = (sku: V1CatalogueSku, value: number) => {
    // Removal stays possible even if an existing line is now unavailable.
    const policy = eligibility(sku);
    const previous = state.shopping.retail[sku.id] ?? 0;
    if (value < previous && policy.canRemove === false) return;
    if (value > previous && (!policy.canAdd || value > maximumQuantity(policy))) return;
    dispatch({ type: "setGroceryQuantity", skuId: sku.id, quantity: value });
  };
  if (state.service !== "grocery") return null;
  if (exploration.checkout && (status !== "ready" || !data)) return <>{checkoutContent}</>;
  if (availabilityNotice && !exploration.checkout) return <>{availabilityNotice}</>;
  if (status === "loading") return <div className="reimagined-shelf-loading" role="status" aria-label="Loading Grocery products">Opening the shelves…<div /><div /></div>;
  if (!exploration.detailId && exploration.view.kind === "search" && searchResults === undefined && searchLoading) return <p role="status">Searching the catalogue…</p>;
  if (!exploration.detailId && exploration.view.kind === "search" && searchError) return <section role="alert"><p>{searchError === "offline" ? "Reconnect to search the catalogue. Your cart is retained." : "Couldn’t load search results. Your cart is retained."}</p><button type="button" disabled={!online} onClick={onRetrySearch}>Retry search</button></section>;
  if (status === "unavailable" || !data) return <section role="status"><p>Couldn’t open the Grocery shelves right now.</p><button type="button" onClick={onRetry}>Try again</button></section>;
  const detail = exploration.detailId ? selected ? <ReimaginedProductBrowser groups={detailGroups} selectedId={selected.id} supabaseUrl={supabaseUrl} onSelect={id => dispatch({ type: "openDetail", id })} onClose={() => dispatch({ type: "closeDetail" })}>{select => <section className="reimagined-product-detail reimagined-grocery-detail" aria-label={`${selected.name} details`}>
    <div className="reimagined-detail-hero">
      <GroceryGallery key={selected.id} sku={selected} supabaseUrl={supabaseUrl} />
      <div className="reimagined-detail-identity"><p className="reimagined-kicker">{selected.brand?.name ?? "Dastak"}</p><h2>{selected.name}</h2>
        <p>{[selected.variant, selected.packSize].filter(Boolean).join(" · ")}</p>{catalogueProductType(selected.attributes) ? <p>Product Type: {catalogueProductType(selected.attributes)}</p> : null}<GroceryPrice sku={selected} /><small>{productUnitPrice(detailProduct(selected))}</small><WishlistButton wishlist={wishlist} kind="RETAIL_SKU" id={selected.id} name={selected.name} online={online} /><GroceryShare sku={selected} /></div>
    </div>
    {variants.length > 1 ? <section className="reimagined-detail-packs"><h3>Pack sizes & variants</h3><div className="reimagined-variants" role="group" aria-label="Related pack sizes and variants">{variants.map(sku => <button key={sku.id} type="button" aria-label={`${sku.name} · ${sku.packSize}`} aria-describedby={`${packChoicePrefix}-${sku.id}-price ${packChoicePrefix}-${sku.id}-unit`} aria-pressed={sku.id === selected.id} onClick={() => select(sku.id)}><span>{sku.name} · {sku.packSize}</span><strong id={`${packChoicePrefix}-${sku.id}-price`}>{formatV1Price(sku.sellingPricePaise)}</strong><small id={`${packChoicePrefix}-${sku.id}-unit`}>{productUnitPrice(detailProduct(sku))}</small></button>)}</div></section> : null}
    <div className="reimagined-detail-purchase"><p className="reimagined-availability">{eligibility(selected).reason ?? (eligibility(selected).canAdd ? "Purchase availability will be confirmed at checkout." : "Currently unavailable to add.")}</p>
      <GroceryQuantity sku={selected} count={state.shopping.retail[selected.id] ?? 0} policy={eligibility(selected)} onQuantity={quantity} /></div>
    {selected.description ? <section className="reimagined-detail-information"><h3>About this product</h3><p>{selected.description}</p></section> : null}
    <section className="reimagined-detail-information"><h3>Product information</h3><dl>{[["Brand", selected.brand?.name], ["Variant", selected.variant], ["Pack size", selected.packSize], ["Manufacturer", selected.manufacturerName], ["Country of origin", selected.countryOfOriginCode], ["Diet", selected.dietType], ["Shelf life", selected.shelfLifeDays ? `${selected.shelfLifeDays} days` : undefined], ["Barcode", selected.barcode]].filter(([, value]) => value).map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl><p>Refer to product packaging for current ingredients, allergens and usage information.</p></section>
  </section>}</ReimaginedProductBrowser> : <section role="status"><p>This exact product is no longer in the loaded catalogue.</p><button type="button" onClick={() => dispatch({ type: "closeDetail" })}>Back to shelves</button></section> : null;
  const browse = exploration.view.kind === "home" ? <div className="reimagined-grocery-home">
    <section className="reimagined-quick-picks" aria-label="Quick subcategory picks">
      <header><h2>Quick picks</h2><span>Find your everyday essentials</span></header>
      {quickPicks.length ? <div className="reimagined-quick-track" tabIndex={0} aria-label="Quick subcategory shortcuts">{quickPicks.map(pick => <button type="button" key={pick.key} onClick={() => dispatch({ type: "openBrowseDestination", nodeKey: pick.destinationKey, railKey: pick.key })}>
        <span className="reimagined-quick-icon"><ShoppingBasket size={25} aria-hidden="true" /></span><span>{pick.label}</span>
      </button>)}</div> : <p>Choose a category from the store directory to explore.</p>}
    </section>
    <section className="reimagined-trending" aria-label="City trending products">
      {trending?.preview ? <p className="reimagined-discovery-note">Preview ranking · sample products, not local order statistics.</p> : null}
      {trendingSkus.length ? <WoodenShelf shelf={{ key: "city-trending", label: trending?.preview ? "Trending in your city" : `Trending in ${trending!.city}`, skus: trendingSkus }} state={state} dispatch={dispatch} supabaseUrl={supabaseUrl} eligibility={eligibility} onQuantity={quantity} wishlist={wishlist} online={online} /> : <>
        <h2>Trending in your city</h2>
        <div className="reimagined-trending-empty"><TrendingUp size={24} aria-hidden="true" /><div><strong>Local favourites are on their way.</strong><p>Explore the quick picks or store directory while city favourites are unavailable.</p></div></div>
      </>}
    </section>
  </div> : <div className="reimagined-grocery-shelves">
    {!shelves.length ? <p role="status">This category could not be resolved. Choose a category from the directory.</p> : shelves.map((shelf, index) => <WoodenShelf key={shelf.key} shelf={shelf} productTypes={exploration.view.kind === "browse" ? groceryProductTypes(sourceShelves[index].skus) : undefined} state={state} dispatch={dispatch} supabaseUrl={supabaseUrl} eligibility={eligibility} onQuantity={quantity} wishlist={wishlist} online={online} />)}
  </div>;
  // Retain the same DOM tracks (and their scroll positions), but remove the
  // underlying shelves from keyboard/accessibility navigation during details or review.
  const hideBrowse = Boolean(exploration.detailId) || exploration.checkout;
  return <><div className="reimagined-grocery-browse" hidden={hideBrowse} inert={hideBrowse}>{browse}</div>{exploration.checkout ? checkoutContent : detail}</>;
}

export function ReimaginedGrocerySuggestions({ data, results: canonicalResults, query, dispatch }: { data?: ReimaginedCatalogue; results?: V1CatalogueSku[]; query: string; dispatch: Dispatch<ReimaginedAction> }) {
  const results = useMemo(() => canonicalResults ? groupGroceryProducts(canonicalResults).slice(0, 8) : data ? groupGroceryProducts(searchGrocery(data, query)).slice(0, 8) : [], [data, query, canonicalResults]);
  if (!query.trim()) return <p>Search products, brands or categories.</p>;
  if (!data) return <p role="status">Load the catalogue to see suggestions.</p>;
  return <div className="reimagined-grocery-suggestions">{results.length ? results.map(([sku, ...packs]) => <button key={sku.id} type="button" onClick={() => { dispatch({ type: "closeSearch" }); dispatch({ type: "openDetail", id: sku.id }); }}><span>{sku.name}</span><small>{sku.packSize}{packs.length ? ` · ${packs.length + 1} sizes` : ""}</small></button>) : <p>No matching products in the loaded catalogue.</p>}</div>;
}

function WoodenShelf({ shelf, productTypes = [], state, dispatch, supabaseUrl, eligibility, onQuantity, wishlist, online }: { shelf: GroceryShelf; productTypes?: string[]; state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; supabaseUrl: string; eligibility: Props["eligibility"]; onQuantity: (sku: V1CatalogueSku, quantity: number) => void; wishlist?: Props["wishlist"]; online: boolean }) {
  const track = useRef<HTMLDivElement>(null);
  const groups = useMemo(() => groupGroceryProducts(shelf.skus), [shelf.skus]);
  const chosenType = state.exploration.grocery.productTypeFilters[shelf.key];
  const move = (direction: number) => track.current?.scrollBy({ left: direction * track.current.clientWidth * .8, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
  return <section className="reimagined-wooden-shelf reimagined-grocery-shelf" aria-label={shelf.label}>
    <header><div><h2>{shelf.label}</h2><small>{groups.length} {groups.length === 1 ? "product" : "products"}</small></div><div className="reimagined-shelf-tools">{productTypes.length > 1 ? <label className="reimagined-product-type"><span>Product Type</span><select aria-label={`Product Type in ${shelf.label}`} value={chosenType && productTypes.includes(chosenType) ? chosenType : ""} onChange={event => dispatch({ type: "setProductType", subcategoryId: shelf.key, productTypeId: event.target.value || undefined })}><option value="">All</option>{productTypes.map(type => <option key={type} value={type}>{type}</option>)}</select></label> : null}{groups.length ? <div className="reimagined-shelf-arrows"><button type="button" aria-label={`Previous products in ${shelf.label}`} onClick={() => move(-1)}><ArrowLeft size={18} /></button><button type="button" aria-label={`Next products in ${shelf.label}`} onClick={() => move(1)}><ArrowRight size={18} /></button></div> : null}</div></header>
    {groups.length ? <div className="reimagined-shelf-track" ref={track} tabIndex={0} aria-label={`${shelf.label} product shelf`}>{groups.map(packs => <GroceryShelfProduct key={packs[0].id} packs={packs} state={state} dispatch={dispatch} supabaseUrl={supabaseUrl} eligibility={eligibility} onQuantity={onQuantity} wishlist={wishlist} online={online} />)}</div> : <p className="reimagined-empty-shelf">No products in this shelf yet.</p>}
  </section>;
}

function GroceryShelfProduct({ packs, state, dispatch, supabaseUrl, eligibility, onQuantity, wishlist, online }: { packs: V1CatalogueSku[]; state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; supabaseUrl: string; eligibility: Props["eligibility"]; onQuantity: (sku: V1CatalogueSku, quantity: number) => void; wishlist?: Props["wishlist"]; online: boolean }) {
  const [selectedId, setSelectedId] = useState(packs[0].id);
  const sku = packs.find(pack => pack.id === selectedId) ?? packs[0];
  const discount = sku.listPricePaise > sku.sellingPricePaise && sku.listPricePaise > 0 ? Math.round((1 - sku.sellingPricePaise / sku.listPricePaise) * 100) : 0;
  return <article className="reimagined-shelf-product" data-sku-id={sku.id}>
      {discount > 0 ? <span className="reimagined-product-saving">{discount}% off</span> : null}
      <small className="reimagined-product-brand">{sku.brand?.name ?? "Dastak selection"}</small>
      <button className="reimagined-product-open" type="button" aria-label={`View ${sku.name}, ${sku.packSize} details`} title={sku.name} onClick={() => dispatch({ type: "openDetail", id: sku.id })}><GroceryImage sku={sku} supabaseUrl={supabaseUrl} /><span className="reimagined-product-name">{sku.name}</span></button>
      {packs.length > 1 ? <label className="reimagined-shelf-packs"><span>{packs.length} pack sizes</span><select aria-label={`Pack size for ${packs[0].name}`} value={sku.id} onChange={event => setSelectedId(event.target.value)}>{packs.map(pack => <option key={pack.id} value={pack.id}>{pack.packSize} · {formatV1Price(pack.sellingPricePaise)}</option>)}</select></label> : <p className="reimagined-shelf-single-pack">{sku.packSize}</p>}<GroceryPrice sku={sku} />
      {!eligibility(sku).canAdd ? <small className="reimagined-availability">{eligibility(sku).reason ?? "Currently unavailable"}</small> : null}
      <div className="reimagined-shelf-actions"><GroceryQuantity sku={sku} count={state.shopping.retail[sku.id] ?? 0} policy={eligibility(sku)} onQuantity={onQuantity} />
      <WishlistButton wishlist={wishlist} kind="RETAIL_SKU" id={sku.id} name={sku.name} online={online} />
      </div>
    </article>;
}

function GroceryPrice({ sku }: { sku: V1CatalogueSku }) {
  return <p className="reimagined-sku-price"><strong>{formatV1Price(sku.sellingPricePaise)}</strong>{sku.listPricePaise > sku.sellingPricePaise ? <del aria-label={`MRP ${formatV1Price(sku.listPricePaise)}`}>{formatV1Price(sku.listPricePaise)}</del> : null}</p>;
}

function GroceryQuantity({ sku, count, policy, onQuantity }: { sku: V1CatalogueSku; count: number; policy: GroceryEligibility; onQuantity: (sku: V1CatalogueSku, quantity: number) => void }) {
  const label = `${sku.name}, ${sku.packSize}`;
  return count > 0 ? <div className="reimagined-sku-quantity" role="group" aria-label={`${label} quantity`}><button type="button" disabled={policy.canRemove === false} aria-label={`Remove one ${label}`} onClick={() => onQuantity(sku, count - 1)}><Minus size={16} /></button><output aria-live="polite">{count}</output><button type="button" aria-label={`Add one ${label}`} disabled={!policy.canAdd || count >= maximumQuantity(policy)} onClick={() => onQuantity(sku, count + 1)}><Plus size={16} /></button></div> : <button className="reimagined-sku-add" type="button" aria-label={`Add ${label}`} disabled={!policy.canAdd || maximumQuantity(policy) < 1} onClick={() => onQuantity(sku, 1)}><Plus size={17} /><span>Add</span></button>;
}

function maximumQuantity(policy: GroceryEligibility) {
  return Number.isSafeInteger(policy.maximumQuantity) ? Math.max(0, Math.min(99, policy.maximumQuantity)) : 0;
}

export function GroceryImage({ sku, supabaseUrl }: { sku: V1CatalogueSku; supabaseUrl: string }) {
  const url = sku.imageKey && (sku.imageKey.startsWith("local/") || supabaseUrl) ? catalogueImageUrl(supabaseUrl, sku.imageKey) : null;
  return <div className="reimagined-sku-image" key={url ?? sku.id}>{url ? <img src={url} alt={`${sku.name}, ${sku.packSize}`} loading="lazy" onError={event => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.setAttribute("data-image-unavailable", "true"); }} /> : null}<span className="reimagined-sku-image-fallback" aria-hidden="true" data-fallback={!url}><Package size={30} /><small>Image unavailable</small></span></div>;
}

function detailProduct(sku: V1CatalogueSku): DetailProduct {
  return { ...sku, brand: sku.brand?.name, price: sku.sellingPricePaise, listPrice: sku.listPricePaise };
}

function GroceryGallery({ sku, supabaseUrl }: { sku: V1CatalogueSku; supabaseUrl: string }) {
  const [index, setIndex] = useState(0);
  const keys = [...new Set([sku.imageKey, ...sku.galleryImageKeys].filter((key): key is string => Boolean(key)))];
  if (keys.length < 2) return <GroceryImage sku={sku} supabaseUrl={supabaseUrl} />;
  const activeIndex = Math.min(index, keys.length - 1);
  return <div className="reimagined-product-gallery"><div className="reimagined-sku-image"><DetailImage key={keys[activeIndex]} source={catalogueImageUrl(supabaseUrl, keys[activeIndex], 1024)} name={`${sku.name}, ${sku.packSize}`} /></div>
    <div role="group" aria-label="Product photos"><button type="button" aria-label="Previous product photo" onClick={() => setIndex((activeIndex - 1 + keys.length) % keys.length)}>←</button><output>{activeIndex + 1} / {keys.length}</output><button type="button" aria-label="Next product photo" onClick={() => setIndex((activeIndex + 1) % keys.length)}>→</button></div>
    <nav className="reimagined-photo-dots" aria-label="Choose product photo">{keys.map((key, photo) => <button key={key} type="button" aria-label={`View product photo ${photo + 1}`} aria-current={photo === activeIndex ? "true" : undefined} onClick={() => setIndex(photo)}><span aria-hidden="true" /></button>)}</nav>
  </div>;
}

function GroceryShare({ sku }: { sku: V1CatalogueSku }) {
  const [message, setMessage] = useState("");
  async function share() {
    const text = `${sku.name} · ${sku.packSize} · ${formatV1Price(sku.sellingPricePaise)} — Dastak`;
    try {
      if (navigator.share) await navigator.share({ title: sku.name, text });
      else { await navigator.clipboard.writeText(text); setMessage("Product details copied"); }
    } catch (issue) { if (!(issue instanceof DOMException && issue.name === "AbortError")) setMessage("Sharing is unavailable on this device"); }
  }
  return <><button type="button" onClick={() => void share()}>Share product</button>{message ? <p role="status">{message}</p> : null}</>;
}
