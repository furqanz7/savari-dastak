import { useReducer } from "react";
import { createRoot } from "react-dom/client";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedFood, ReimaginedFoodSuggestions } from "./ReimaginedFood";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { prepareFoodMenus } from "./reimaginedFoodCatalogue";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { ReimaginedFoodCheckout } from "./ReimaginedFoodCheckout";

const menus = prepareFoodMenus([foodMenuFixture()]);
// Controlled data only; no authenticated/hosted requests or real cart storage.
export function Fixture() {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "__reimagined_food_browser_check__", shopping: { retail: { retained: 2 }, food: [] } }), { type: "selectService", service: "food" }));
  return <><aside className="reimagined-local-notice">Local Food test fixture · synthetic menu · no backend or checkout requests</aside>
    <ReimaginedShell state={state} dispatch={dispatch} directory={[]} greeting="Welcome" locationLabel="Test location" locationContent={<p>Test location only</p>} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{ orders: <p>Test Orders</p> }}
      searchSuggestions={<ReimaginedFoodSuggestions menus={menus} query={state.exploration.food.searchDraft} dispatch={dispatch} />}>
      <ReimaginedFood state={state} dispatch={dispatch} resource={{ data: menus, status: "ready", error: undefined, retry: () => {} }} supabaseUrl={window.location.origin} online legacyUrl="/#home"
        checkoutContent={<ReimaginedFoodCheckout addressPicker={<p>Synthetic saved address: Test home</p>} input={{ food: state.shopping.food, menus, online: true, canEdit: true, addressesReady: true, recipient: { name: "Test customer", phoneNumber: "+919876543210" }, address: { addressId: "test", label: "Test home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-09-30" } }} />} />
    </ReimaginedShell><output data-testid="food-check-shopping" hidden>{JSON.stringify(state.shopping)}</output></>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  createRoot(document.getElementById("root")!).render(<Fixture />);
} else document.body.textContent = "Local test fixture disabled.";
