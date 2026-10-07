import type { CustomerDeliveryAddress } from "./customerAddresses";
import type { PersistedFoodCartLine } from "./customerCartPersistence";
import type { V1OrderSubmission, V1RestaurantMenu } from "./dastakV1";
import { prepareFoodMenus } from "./reimaginedFoodCatalogue";
import { foodSelection } from "./reimaginedFoodSelection";

type Input = {
  food: PersistedFoodCartLine[]; menus?: V1RestaurantMenu[]; online: boolean; canEdit: boolean;
  address?: CustomerDeliveryAddress; addressesReady: boolean;
  recipient: { name?: string; phoneNumber?: string };
};
type Preparation = { issues: string[]; estimatedSubtotalPaise?: number; submission?: V1OrderSubmission };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Pure local preparation only: no order client, request key, storage or mutation.
// The server must still validate availability, serviceability and final prices.
export function prepareFoodCheckout(input: Input): Preparation {
  const issues: string[] = [];
  if (!input.online) issues.push("Reconnect before preparing Food checkout.");
  if (!input.canEdit) issues.push("This tab does not own cart editing.");
  if (!input.food.length) issues.push("Your Food cart is empty.");
  let menus: V1RestaurantMenu[] = [];
  try { menus = prepareFoodMenus(input.menus ?? []); }
  catch { issues.push("Food menu identities or option rules are ambiguous. Refresh menus."); }
  if (!input.menus) issues.push("Load the current Food menus before preparing checkout.");
  const branches = new Set(input.food.map(line => line.branchId));
  if (branches.size > 1) issues.push("Food checkout requires one restaurant. Review your saved items.");
  const branchId = input.food[0]?.branchId;
  const menu = menus.find(value => value.restaurant.branchId === branchId);
  if (input.food.length && (!menu || !uuid.test(branchId))) issues.push("The saved restaurant is unavailable in the loaded menus.");
  if (menu && (menu.restaurant.branchStatus !== "ACTIVE" || !menu.restaurant.isOpen || !menu.restaurant.acceptingOrders)) issues.push("This restaurant is closed or has paused orders.");
  let estimatedSubtotalPaise = 0; let priced = input.food.length > 0 && Boolean(menu);
  const identities = new Set<string>();
  for (const line of input.food) {
    const item = menu?.categories.flatMap(category => category.items).find(value => value.id === line.itemId);
    const selection = item ? foodSelection(item, line.optionIds) : undefined;
    const identity = JSON.stringify([line.branchId, line.itemId, [...line.optionIds].sort()]);
    if (identities.has(identity)) { issues.push("Duplicate Food selections must be combined before checkout."); priced = false; }
    identities.add(identity);
    if (line.branchId !== branchId || !uuid.test(line.itemId) || line.optionIds.some(id => !uuid.test(id)) || !Number.isSafeInteger(line.quantity) || line.quantity < 1 || line.quantity > 99) {
      issues.push("A saved Food identity or quantity is invalid. Review your items."); priced = false;
    }
    if (!item || !selection?.valid) { issues.push("A saved dish or its chosen options is unavailable or incomplete. Review your items."); priced = false; }
    if (selection && (!Number.isSafeInteger(selection.pricePaise) || selection.pricePaise < 0)) { issues.push("A dish estimate is invalid. Refresh menus."); priced = false; }
    if (selection) estimatedSubtotalPaise += selection.pricePaise * line.quantity;
  }
  if (!Number.isSafeInteger(estimatedSubtotalPaise) || estimatedSubtotalPaise < 0) { issues.push("The complete Food estimate is unavailable."); priced = false; }
  const name = input.recipient.name?.trim(); const phoneNumber = input.recipient.phoneNumber?.trim();
  if (!name || name.length > 80 || !phoneNumber || !/^\+[1-9]\d{7,14}$/.test(phoneNumber)) issues.push("Complete a valid name and international phone number in Account.");
  const address = input.address;
  if (!input.addressesReady || !address || !address.address.trim() || address.address.trim().length > 300 || !Number.isFinite(address.location.latitude) || Math.abs(address.location.latitude) > 90 || !Number.isFinite(address.location.longitude) || Math.abs(address.location.longitude) > 180) issues.push("Choose a valid saved delivery address.");
  const result: Preparation = { issues: [...new Set(issues)], estimatedSubtotalPaise: priced ? estimatedSubtotalPaise : undefined };
  if (!issues.length && address && name && phoneNumber) result.submission = {
    restaurantBranchId: branchId,
    recipient: { name, phoneNumber },
    deliveryAddress: { label: address.label, line1: address.address, line2: [address.building, address.floor].filter(Boolean).join(", ") || undefined, landmark: address.landmark, countryCode: "IN", latitude: address.location.latitude, longitude: address.location.longitude, instructions: address.deliveryNotes },
    lines: input.food.map(line => ({ lineType: "FOOD_MENU_ITEM" as const, menuItemId: line.itemId, optionIds: [...line.optionIds].sort(), quantity: line.quantity })).sort((a, b) => JSON.stringify([a.menuItemId, a.optionIds]).localeCompare(JSON.stringify([b.menuItemId, b.optionIds]))),
  };
  return result;
}
