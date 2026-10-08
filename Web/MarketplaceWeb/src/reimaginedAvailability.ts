import type { V1AreaAvailability } from "./dastakV1";
import type { GroceryEligibility } from "./ReimaginedGrocery";

export function localGroceryEligibility(id: string, data: V1AreaAvailability | undefined, online: boolean, canEdit: boolean, hasLocation: boolean): GroceryEligibility {
  const maximumQuantity = data?.groceryServiceable ? Math.min(99, data.stock[id] ?? 0) : 0;
  const reason = !canEdit ? "This cart is read-only in this tab" : !online ? "Reconnect to add products"
    : !hasLocation ? "Choose your delivery location to check stock" : !data ? "Checking stock in your area…"
      : !data.groceryServiceable ? "Grocery delivery isn’t available in your area yet." : maximumQuantity < 1 ? "Out of stock" : undefined;
  return { canAdd: !reason && maximumQuantity > 0, canRemove: canEdit, maximumQuantity, reason };
}
export function areaCheckoutIssue(data: V1AreaAvailability | undefined, hasLocation: boolean, retail?: Record<string, number>) {
  if (!hasLocation) return "Choose your delivery location before placing an order.";
  if (!data) return "Checking availability in your area. Your cart is saved.";
  if (!data.deliveryAvailable) return "No delivery partners are available in your area right now. You can keep adding available items to your cart and order later.";
  if (retail && (!data.groceryServiceable || Object.entries(retail).some(([id, quantity]) => quantity > (data.stock[id] ?? 0)))) return "Some packs are out of stock in your area. Review your saved cart before ordering.";
  return undefined;
}
