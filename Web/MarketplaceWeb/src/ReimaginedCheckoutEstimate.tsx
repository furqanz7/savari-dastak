import { formatV1Price, type DastakV1Auth, type V1OrderSubmission, type V1RestaurantLocation } from "./dastakV1";
import { useCheckoutEstimate } from "./useCheckoutEstimate";

export function ReimaginedCheckoutEstimate({ auth, location, lines, restaurantBranchId, online, enabled = true, subtotalEstimate }: {
  auth?: DastakV1Auth; location?: V1RestaurantLocation; lines: V1OrderSubmission["lines"];
  restaurantBranchId?: string; online: boolean; enabled?: boolean; subtotalEstimate?: number;
}) {
  const quote = useCheckoutEstimate(auth, location, lines, restaurantBranchId, online, enabled);
  return <section className="reimagined-billing-estimate" aria-label="Billing estimate"><h3>Price review</h3>
    {quote.data ? <><dl>
      <div><dt>Items</dt><dd>{formatV1Price(quote.data.subtotalPaise)}</dd></div>
      <div><dt>Delivery</dt><dd>{formatV1Price(quote.data.deliveryFeePaise)}</dd></div>
      <div><dt>Platform fee</dt><dd>{formatV1Price(quote.data.platformFeePaise)}</dd></div>
      <div><dt>Estimated total</dt><dd>{formatV1Price(quote.data.totalPaise)}</dd></div>
    </dl><p>Tax is included</p>
    {!quote.data.deliveryAvailable ? <p role="status">No delivery partner is available right now. You can keep your cart and order later.</p> : null}</>
    : <><dl><div><dt>Estimated items</dt><dd>{subtotalEstimate === undefined ? "Unavailable" : formatV1Price(subtotalEstimate)}</dd></div><div><dt>Delivery</dt><dd>Not confirmed</dd></div><div><dt>Platform fee</dt><dd>Not confirmed</dd></div><div><dt>Estimated total</dt><dd>Not confirmed</dd></div></dl>
      <p role="status">{quote.status === "loading" ? "Checking delivery and platform fees…" : quote.status === "unavailable" ? "Couldn’t confirm current fees. No amount has been charged." : "Choose a saved delivery address and valid items to check fees."}</p>
      {quote.status === "unavailable" ? <button type="button" disabled={!online} onClick={quote.retry}>Retry price estimate</button> : null}</>}
  </section>;
}
