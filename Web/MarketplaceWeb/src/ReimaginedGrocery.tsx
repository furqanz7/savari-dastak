import { useMemo, useRef, type Dispatch, type ReactNode } from "react";
import { ArrowLeft, ArrowRight, Minus, Package, Plus, ShoppingBasket, TrendingUp, X } from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import { formatV1Price, type V1CatalogueSku } from "./dastakV1";
import { groceryQuickPicks, groceryShelves, searchGrocery, type GroceryShelf, type ReimaginedCatalogue } from "./reimaginedCatalogue";
import type { ReimaginedAction, ReimaginedState } from "./reimaginedState";

export type GroceryEligibility = { canAdd: boolean; canRemove?: boolean; maximumQuantity: number; reason?: string };
export type GroceryTrending = { city: string; skuIds: string[]; preview?: boolean };
type Props = {
  state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; data?: ReimaginedCatalogue;
  status: "loading" | "ready" | "unavailable"; onRetry: () => void; supabaseUrl: string;
  eligibility: (sku: V1CatalogueSku) => GroceryEligibility;
  relatedSkuIds?: (sku: V1CatalogueSku) => string[];
  checkoutContent: ReactNode;
  trending?: GroceryTrending;
};

export function ReimaginedGrocery({ state, dispatch, data, status, onRetry, supabaseUrl, eligibility, relatedSkuIds, checkoutContent, trending }: Props) {
  const exploration = state.exploration.grocery;
  const shelves = useMemo(() => data ? groceryShelves(data, exploration.view) : [], [data, exploration.view]);
  const quickPicks = useMemo(() => data ? groceryQuickPicks(data) : [], [data]);
  const trendingSkus = useMemo(() => {
    if (!data || !trending?.city.trim()) return [];
    const byId = new Map(data.catalogue.skus.map(sku => [sku.id, sku]));
    return [...new Set(trending.skuIds)].slice(0, 12).flatMap(id => {
      const sku = byId.get(id); return sku ? [sku] : [];
    });
  }, [data, trending]);
  const selected = data?.catalogue.skus.find(sku => sku.id === exploration.detailId);
  const variants = selected && relatedSkuIds && data ? [...new Set([selected.id, ...relatedSkuIds(selected)])]
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
  if (status === "loading") return <div className="reimagined-shelf-loading" role="status" aria-label="Loading Grocery products">Opening the shelves…<div /><div /></div>;
  if (status === "unavailable" || !data) return <section role="status"><p>Couldn’t open the Grocery shelves right now.</p><button type="button" onClick={onRetry}>Try again</button></section>;
  const detail = exploration.detailId ? selected ? <section className="reimagined-product-detail reimagined-grocery-detail" aria-label={`${selected.name} details`}>
    <button type="button" className="reimagined-detail-close" onClick={() => dispatch({ type: "closeDetail" })}><X size={18} />Close product details</button>
    <div className="reimagined-detail-hero">
      <GroceryImage key={selected.id} sku={selected} supabaseUrl={supabaseUrl} />
      <div className="reimagined-detail-identity"><p className="reimagined-kicker">{selected.brand?.name ?? "Dastak"}</p><h2>{selected.name}</h2>
        <p>{[selected.variant, selected.packSize].filter(Boolean).join(" · ")}</p><GroceryPrice sku={selected} /></div>
    </div>
    {variants.length > 1 ? <section className="reimagined-detail-packs"><h3>Pack sizes & variants</h3><div className="reimagined-variants" role="group" aria-label="Related pack sizes and variants">{variants.map(sku => <button key={sku.id} type="button" aria-pressed={sku.id === selected.id} onClick={() => dispatch({ type: "openDetail", id: sku.id })}>{sku.name} · {sku.packSize}</button>)}</div></section> : null}
    <div className="reimagined-detail-purchase"><p className="reimagined-availability">{eligibility(selected).reason ?? (eligibility(selected).canAdd ? "Purchase availability will be confirmed at checkout." : "Currently unavailable to add.")}</p>
      <GroceryQuantity sku={selected} count={state.shopping.retail[selected.id] ?? 0} policy={eligibility(selected)} onQuantity={quantity} /></div>
    {selected.description ? <section className="reimagined-detail-information"><h3>About this product</h3><p>{selected.description}</p></section> : null}
  </section> : <section role="status"><p>This exact product is no longer in the loaded catalogue.</p><button type="button" onClick={() => dispatch({ type: "closeDetail" })}>Back to shelves</button></section> : null;
  const browse = exploration.view.kind === "home" ? <div className="reimagined-grocery-home">
    <section className="reimagined-quick-picks" aria-label="Quick subcategory picks">
      <header><h2>Quick picks</h2><span>Find your everyday essentials</span></header>
      {quickPicks.length ? <div className="reimagined-quick-track" tabIndex={0} aria-label="Quick subcategory shortcuts">{quickPicks.map(pick => <button type="button" key={pick.key} onClick={() => dispatch({ type: "openBrowseDestination", nodeKey: pick.destinationKey, railKey: pick.key })}>
        <span className="reimagined-quick-icon"><ShoppingBasket size={25} aria-hidden="true" /></span><span>{pick.label}</span>
      </button>)}</div> : <p>Choose a category from the store directory to explore.</p>}
    </section>
    <section className="reimagined-trending" aria-label="City trending products">
      {trending?.preview ? <p className="reimagined-discovery-note">Preview ranking · sample products, not local order statistics.</p> : null}
      {trendingSkus.length ? <WoodenShelf shelf={{ key: "city-trending", label: trending?.preview ? "Trending in your city" : `Trending in ${trending!.city}`, skus: trendingSkus }} state={state} dispatch={dispatch} supabaseUrl={supabaseUrl} eligibility={eligibility} onQuantity={quantity} /> : <>
        <h2>Trending in your city</h2>
        <div className="reimagined-trending-empty"><TrendingUp size={24} aria-hidden="true" /><div><strong>Local favourites are on their way.</strong><p>Explore the quick picks or store directory while city favourites are unavailable.</p></div></div>
      </>}
    </section>
  </div> : <div className="reimagined-grocery-shelves">
    {!shelves.length ? <p role="status">This category could not be resolved. Choose a category from the directory.</p> : shelves.map(shelf => <WoodenShelf key={shelf.key} shelf={shelf} state={state} dispatch={dispatch} supabaseUrl={supabaseUrl} eligibility={eligibility} onQuantity={quantity} />)}
  </div>;
  // Retain the same DOM tracks (and their scroll positions), but remove the
  // underlying shelves from keyboard/accessibility navigation during details or review.
  const hideBrowse = Boolean(exploration.detailId) || exploration.checkout;
  return <><div className="reimagined-grocery-browse" hidden={hideBrowse} inert={hideBrowse}>{browse}</div>{exploration.checkout ? checkoutContent : detail}</>;
}

export function ReimaginedGrocerySuggestions({ data, query, dispatch }: { data?: ReimaginedCatalogue; query: string; dispatch: Dispatch<ReimaginedAction> }) {
  const results = useMemo(() => data ? searchGrocery(data, query).slice(0, 8) : [], [data, query]);
  if (!query.trim()) return <p>Search products, brands or categories.</p>;
  if (!data) return <p role="status">Load the catalogue to see suggestions.</p>;
  return <div className="reimagined-grocery-suggestions">{results.length ? results.map(sku => <button key={sku.id} type="button" onClick={() => { dispatch({ type: "closeSearch" }); dispatch({ type: "openDetail", id: sku.id }); }}><span>{sku.name}</span><small>{sku.packSize}</small></button>) : <p>No matching products in the loaded catalogue.</p>}</div>;
}

function WoodenShelf({ shelf, state, dispatch, supabaseUrl, eligibility, onQuantity }: { shelf: GroceryShelf; state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; supabaseUrl: string; eligibility: Props["eligibility"]; onQuantity: (sku: V1CatalogueSku, quantity: number) => void }) {
  const track = useRef<HTMLDivElement>(null);
  const move = (direction: number) => track.current?.scrollBy({ left: direction * track.current.clientWidth * .8, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
  return <section className="reimagined-wooden-shelf reimagined-grocery-shelf" aria-label={shelf.label}>
    <header><div><h2>{shelf.label}</h2><small>{shelf.skus.length} {shelf.skus.length === 1 ? "product" : "products"}</small></div>{shelf.skus.length ? <div><button type="button" aria-label={`Previous products in ${shelf.label}`} onClick={() => move(-1)}><ArrowLeft size={18} /></button><button type="button" aria-label={`Next products in ${shelf.label}`} onClick={() => move(1)}><ArrowRight size={18} /></button></div> : null}</header>
    {shelf.skus.length ? <div className="reimagined-shelf-track" ref={track} tabIndex={0} aria-label={`${shelf.label} product shelf`}>{shelf.skus.map(sku => <article className="reimagined-shelf-product" key={sku.id}>
      <button className="reimagined-product-open" type="button" aria-label={`View ${sku.name}, ${sku.packSize} details`} title={sku.name} onClick={() => dispatch({ type: "openDetail", id: sku.id })}><GroceryImage sku={sku} supabaseUrl={supabaseUrl} /><span className="reimagined-product-name">{sku.name}</span></button>
      <p>{sku.packSize}</p><GroceryPrice sku={sku} />
      {!eligibility(sku).canAdd ? <small className="reimagined-availability">{eligibility(sku).reason ?? "Currently unavailable"}</small> : null}
      <GroceryQuantity sku={sku} count={state.shopping.retail[sku.id] ?? 0} policy={eligibility(sku)} onQuantity={onQuantity} />
    </article>)}</div> : <p className="reimagined-empty-shelf">No products in this shelf yet.</p>}
  </section>;
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
