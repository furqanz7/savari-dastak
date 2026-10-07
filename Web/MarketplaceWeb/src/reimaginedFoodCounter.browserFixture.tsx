import { useState } from "react";
import { createRoot } from "react-dom/client";
import { ReimaginedFoodCounter } from "./ReimaginedFoodCounter";
import { ReimaginedFoodCheckout } from "./ReimaginedFoodCheckout";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
import { foodRecoveryJournal, ReimaginedFoodRecovery } from "./reimaginedFoodRecovery";
import { acknowledgeFoodCheckout, loadCustomerCart, saveCustomerCart } from "./customerCartPersistence";
import type { V1Order } from "./dastakV1";
import type { ReimaginedAction } from "./reimaginedState";
import "./design/reimagined.css";

// Dedicated DEV-only page. Never uses authenticated clients or real cart namespaces.
export function Fixture() {
  const scenario = new URLSearchParams(location.search).get("scenario") ?? "normal";
  const account = "__food_counter_browser_fixture__";
  const [storage] = useState(() => ({ getItem: (key: string) => sessionStorage.getItem(`fixture:${key}`), setItem: (key: string, value: string) => sessionStorage.setItem(`fixture:${key}`, value) }));
  const [menu] = useState(foodMenuFixture);
  const item = menu.categories[0].items[0];
  const food = [{ branchId: menu.restaurant.branchId, itemId: item.id, optionIds: [item.optionGroups[0].options[0].id], quantity: 2 }];
  const [cart, setCart] = useState(() => {
    if (!sessionStorage.getItem("fixture:seeded")) {
      saveCustomerCart(account, { retail: { [fixtureId(1)]: 3 }, food }, storage);
      sessionStorage.setItem("fixture:seeded", "yes");
    }
    return loadCustomerCart(account, storage);
  });
  const [checkout] = useState(() => {
    const reserved = (): V1Order => ({ id: fixtureId(70), createdAt: "2026-09-30", updatedAt: "2026-09-30", displayOrderNumber: "SYNTHETIC-FOOD-70", orderType: "FOOD_ONLY", restaurant: menu.restaurant, version: 3, status: "AWAITING_PAYMENT",
      lines: [{ id: fixtureId(71), name: "Test dish", lineType: "FOOD_MENU_ITEM", menuItemId: item.id, quantity: 2, unitPricePaise: 18000, lineTotalPaise: 36000, status: "SECURED", foodSelection: { options: [{ ...item.optionGroups[0].options[0], groupId: fixtureId(34), groupName: "Size" }] } }],
      price: { snapshotKind: "FINAL", subtotalPaise: 36000, deliveryFeePaise: 1000, platformFeePaise: 0, discountPaise: 0, taxPaise: 0, totalPaise: 37000, currencyCode: "INR" },
      launchPayment: { optionLabel: "Pay via UPI/Cash on Delivery", reservationSecondsRemaining: 60, state: "READY_TO_CONFIRM", reservationState: "ACTIVE", reservationExpiresAt: "2099-01-01T00:00:00Z", canCommit: true, noChargeNow: true, payAtDoorstep: true } } as V1Order);
    const paid = () => ({ ...reserved(), version: 4, status: "PREPARING", launchPayment: { ...reserved().launchPayment!, state: "PAYMENT_DUE_AT_DELIVERY", reservationState: "COMMITTED", canCommit: false } } as V1Order);
    const log = (operation: string, key?: string) => {
      const events = JSON.parse(sessionStorage.getItem("fixture:events") ?? "[]") as object[];
      events.push({ operation, key }); sessionStorage.setItem("fixture:events", JSON.stringify(events));
      return events.filter(event => "operation" in event && event.operation === operation).length;
    };
    return new ReimaginedFoodRecovery({ accessToken: "synthetic-token", supabaseUrl: location.origin, publishableKey: "synthetic-public" }, {
      submit: async input => { const count = log("submit", input.idempotencyKey); if (scenario === "lost-submit" && count === 1) throw new Error("Synthetic submission response lost"); return reserved(); },
      commit: async input => { log("commit", input.idempotencyKey); sessionStorage.setItem("fixture:committed", "yes"); if (scenario === "lost-commit") throw new Error("Synthetic commitment response lost"); return paid(); },
      read: async () => {
        log("read");
        if (scenario === "refresh-fail") throw new Error("Synthetic status unavailable");
        if (sessionStorage.getItem("fixture:committed")) return paid();
        if (scenario === "expiry") return { ...reserved(), version: 4, status: "PAYMENT_EXPIRED", launchPayment: { ...reserved().launchPayment!, state: "RESERVATION_EXPIRED", reservationState: "EXPIRED", canCommit: false } } as V1Order;
        return reserved();
      },
    }, foodRecoveryJournal(account, location.origin, storage));
  });
  const input = { food, menus: [menu], online: scenario !== "offline", canEdit: scenario !== "read-only", addressesReady: true, recipient: { name: "Synthetic customer", phoneNumber: "+919876543210" }, address: { addressId: "test", label: "Test home", address: "Synthetic street", building: "1", details: "", displayAddress: "Synthetic street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-09-30" } };
  function dispatch(action: ReimaginedAction) {
    if (action.type !== "checkoutSucceeded") return;
    if (scenario === "ack-fail" && !sessionStorage.getItem("fixture:ack-retried")) { sessionStorage.setItem("fixture:ack-retried", "yes"); throw new Error("Synthetic cart save unavailable"); }
    acknowledgeFoodCheckout(account, action.orderId, action.purchased.food, storage);
    setCart(loadCustomerCart(account, storage));
  }
  return <main style={{ maxWidth: 600, margin: "auto", padding: 16 }}><h1>Local Food counter test</h1><p>Synthetic orders only. No hosted requests. Production checkout is disabled.</p>
    <ReimaginedFoodCheckout input={input} addressPicker={<p>Synthetic saved address: Test home</p>} counter={<ReimaginedFoodCounter checkout={checkout} input={input} enabled={scenario !== "disabled"} dispatch={dispatch} onSessionExpired={() => { throw new Error("Unexpected session expiry"); }} ordersUrl="#synthetic-orders" />} />
    <output data-testid="counter-cart" hidden>{JSON.stringify(cart)}</output></main>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(location.hostname)) createRoot(document.getElementById("root")!).render(<Fixture />);
else document.body.textContent = "Local test fixture disabled.";
