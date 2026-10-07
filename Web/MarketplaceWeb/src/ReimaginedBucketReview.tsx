import type { Dispatch } from "react";
import { Minus, Plus, Trash2 } from "lucide-react";
import { formatV1Price } from "./dastakV1";
import { GroceryImage } from "./ReimaginedGrocery";
import { grocerySubtotal, type ReimaginedCatalogue } from "./reimaginedCatalogue";
import type { ReimaginedAction, ReimaginedState } from "./reimaginedState";

export function ReimaginedBucketReview({ state, dispatch, data, supabaseUrl = "", canEdit = true, canIncrease = false, maximumQuantity = 99 }: {
  state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; data?: ReimaginedCatalogue;
  supabaseUrl?: string; canEdit?: boolean; canIncrease?: boolean; maximumQuantity?: number;
}) {
  const skus = new Map(data?.catalogue.skus.map(sku => [sku.id, sku]) ?? []);
  const lines = Object.entries(state.shopping.retail);
  const count = lines.reduce((total, [, quantity]) => total + quantity, 0);
  const subtotal = grocerySubtotal(state, data);
  const limit = Number.isSafeInteger(maximumQuantity) ? Math.max(0, Math.min(99, maximumQuantity)) : 0;
  return <section className="reimagined-bucket-review" aria-label="Review Grocery Bucket">
    <header className="reimagined-review-heading"><h2>Review your Grocery items</h2><p>{count} {count === 1 ? "item" : "items"} · {lines.length} {lines.length === 1 ? "product" : "products"}</p></header>
    {lines.length ? <ul className="reimagined-review-lines">{lines.map(([id, quantity]) => {
      const sku = skus.get(id);
      const label = sku ? `${sku.name}, ${sku.packSize}` : "saved product";
      return <li key={id} className="reimagined-review-line">
        {sku ? <GroceryImage key={id} sku={sku} supabaseUrl={supabaseUrl} /> : <div className="reimagined-review-missing-image" aria-hidden="true">?</div>}
        <div className="reimagined-review-product"><strong>{sku?.name ?? "Saved product — catalogue details unavailable"}</strong>
          {sku ? <><span>{[sku.variant, sku.packSize].filter(Boolean).join(" · ")}</span><small>{formatV1Price(sku.sellingPricePaise)} each</small><strong className="reimagined-review-line-total" aria-label={`${label} line total`}>{formatV1Price(sku.sellingPricePaise * quantity)}</strong></> : <small>This item has been retained, not silently removed.</small>}
        </div>
        <div className="reimagined-review-actions">
          <div className="reimagined-review-quantity" role="group" aria-label={`${label} Bucket quantity`}>
            <button type="button" disabled={!canEdit} aria-label={`Decrease ${label} in Bucket`} onClick={() => { if (canEdit && quantity > 0) dispatch({ type: "setGroceryQuantity", skuId: id, quantity: quantity - 1 }); }}><Minus size={16} aria-hidden="true" /></button>
            <output aria-live="polite" aria-label={`${label} quantity`}>{quantity}</output>
            <button type="button" disabled={!canEdit || !canIncrease || !sku || quantity >= limit} aria-label={`Increase ${label} in Bucket`} onClick={() => { if (canEdit && canIncrease && sku && quantity < limit) dispatch({ type: "setGroceryQuantity", skuId: id, quantity: quantity + 1 }); }}><Plus size={16} aria-hidden="true" /></button>
          </div>
          <button className="reimagined-review-remove" type="button" disabled={!canEdit} aria-label={`Remove ${sku?.name ?? "saved product"} from Bucket`} onClick={() => { if (canEdit) dispatch({ type: "setGroceryQuantity", skuId: id, quantity: 0 }); }}><Trash2 size={15} aria-hidden="true" /><span>Remove</span></button>
        </div>
      </li>;
    })}</ul> : <p>Your Grocery Bucket is empty. Continue Shopping to find something you need.</p>}
    <section className="reimagined-review-totals" aria-label="Grocery price estimate">
      {subtotal === undefined ? <p role="status">The complete price is unavailable until every saved item can be resolved.</p> : <p className="reimagined-review-subtotal"><span>Estimated item subtotal: </span><strong>{formatV1Price(subtotal)}</strong></p>}
      <p>Delivery, stock and final totals are not confirmed. The final payable amount comes from checkout.</p>
    </section>
  </section>;
}
