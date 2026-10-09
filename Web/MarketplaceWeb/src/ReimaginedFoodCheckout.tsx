import { useState, type ReactNode } from "react";
import { formatV1Price, type DastakV1Auth } from "./dastakV1";
import { ReimaginedCheckoutEstimate } from "./ReimaginedCheckoutEstimate";
import { prepareFoodCheckout } from "./reimaginedFoodCheckoutPreparation";

export function ReimaginedFoodCheckout({ input, addressPicker, counter, auth }: { input: Parameters<typeof prepareFoodCheckout>[0]; addressPicker: ReactNode; counter?: ReactNode | ((onReservationChange: (reserved: boolean) => void) => ReactNode); auth?: DastakV1Auth }) {
  const [reserved, setReserved] = useState(false);
  const preparation = prepareFoodCheckout(input);
  return <section className="reimagined-food-checkout-preparation" aria-label="Food checkout preparation">
    <h3>Prepare Food checkout</h3>
    {addressPicker}
    <p>{preparation.estimatedSubtotalPaise === undefined ? "A complete item estimate is unavailable until every saved selection is valid." : `Estimated Food item subtotal: ${formatV1Price(preparation.estimatedSubtotalPaise)}`}</p>
    {preparation.issues.length ? <ul aria-label="Food checkout blockers">{preparation.issues.map(issue => <li key={issue}>{issue}</li>)}</ul> : <p role="status">Your Food selections, recipient and saved address pass local checks. Reservation and confirmation are separate steps.</p>}
    <p>Local checks do not guarantee restaurant availability or delivery eligibility. Reservation uses server-calculated fees, taxes and the final total.</p>
    {reserved ? <p role="status">Review the server-confirmed bill for your reservation below. Later cart or address edits do not change that bill.</p> : auth ? <ReimaginedCheckoutEstimate auth={auth} online={input.online} subtotalEstimate={preparation.estimatedSubtotalPaise} enabled={preparation.estimatedSubtotalPaise !== undefined && input.addressesReady}
      location={input.address ? { addressId: input.address.addressId, updatedAt: input.address.updatedAt } : undefined}
      restaurantBranchId={input.food[0]?.branchId} lines={input.food.map(line => ({ lineType: "FOOD_MENU_ITEM", menuItemId: line.itemId, optionIds: [...line.optionIds].sort(), quantity: line.quantity }))} /> : null}
    <p>Pay via UPI/Cash on Delivery — pay your delivery partner at the doorstep. No charge now.</p>
    {(typeof counter === "function" ? counter(setReserved) : counter) ?? <button type="button" disabled>Food checkout integration pending</button>}
  </section>;
}
