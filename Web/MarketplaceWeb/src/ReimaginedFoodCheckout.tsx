import type { ReactNode } from "react";
import { formatV1Price } from "./dastakV1";
import { prepareFoodCheckout } from "./reimaginedFoodCheckoutPreparation";

export function ReimaginedFoodCheckout({ input, addressPicker, counter }: { input: Parameters<typeof prepareFoodCheckout>[0]; addressPicker: ReactNode; counter?: ReactNode }) {
  const preparation = prepareFoodCheckout(input);
  return <section aria-label="Food checkout preparation">
    <h3>Prepare Food checkout</h3>
    {addressPicker}
    <p>{preparation.estimatedSubtotalPaise === undefined ? "A complete item estimate is unavailable until every saved selection is valid." : `Estimated Food item subtotal: ${formatV1Price(preparation.estimatedSubtotalPaise)}`}</p>
    {preparation.issues.length ? <ul aria-label="Food checkout blockers">{preparation.issues.map(issue => <li key={issue}>{issue}</li>)}</ul> : <p role="status">Your Food selections, recipient and saved address pass local checks. Reservation and confirmation are separate steps.</p>}
    <p>Local checks do not guarantee restaurant availability or delivery eligibility. Reservation uses server-calculated fees, taxes and the final total.</p>
    <p>Pay via UPI/Cash on Delivery — pay your delivery partner at the doorstep. No charge now.</p>
    {counter ?? <button type="button" disabled>Food checkout integration pending</button>}
  </section>;
}
