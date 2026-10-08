import { useReducer } from "react";
import { createRoot } from "react-dom/client";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedFood, ReimaginedFoodSuggestions } from "./ReimaginedFood";
import { foodPanelTitle } from "./reimaginedFoodPanel";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { nearestFoodMenus, prepareFoodMenus } from "./reimaginedFoodCatalogue";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { ReimaginedFoodCheckout } from "./ReimaginedFoodCheckout";
import { useReimaginedGreeting } from "./useReimaginedGreeting";

const menu = foodMenuFixture();
menu.categories.push({ ...menu.categories[0], id: "00000000-0000-4000-8000-000000000040", name: "Drinks", sortOrder: 2, items: [{ ...menu.categories[0].items[0], id: "00000000-0000-4000-8000-000000000041", name: "Test Mango Drink", basePricePaise: 6000, optionGroups: [] }] });
menu.restaurant.distanceMeters = 350;
const far = foodMenuFixture("00000000-0000-4000-8000-000000000050");
far.restaurant.branchName = "Test Far Café"; far.restaurant.distanceMeters = 2500;
const unknown = foodMenuFixture("00000000-0000-4000-8000-000000000051"); unknown.restaurant.branchName = "Test Unmapped Café";
const menus = nearestFoodMenus(prepareFoodMenus([far, unknown, menu]));
// Controlled data only; no authenticated/hosted requests or real cart storage.
export function Fixture() {
  const greeting = useReimaginedGreeting();
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "__reimagined_food_browser_check__", shopping: { retail: { retained: 2 }, food: [] } }), { type: "selectService", service: "food" }));
  return <><aside className="reimagined-local-notice">Local Food test fixture · synthetic menu · no backend or checkout requests</aside>
    <ReimaginedShell state={state} dispatch={dispatch} directory={[]} greeting={greeting} locationLabel="Test location" locationContent={<p>Test location only</p>} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{ orders: <p>Test Orders</p> }} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />}
      featureTitle={state.section === "home" ? foodPanelTitle(state, menus) : undefined} searchSuggestions={<ReimaginedFoodSuggestions menus={menus} query={state.exploration.food.searchDraft} dispatch={dispatch} />}>
      <ReimaginedFood state={state} dispatch={dispatch} resource={{ data: menus, nearest: true, status: "ready", error: undefined, retry: () => {} }} supabaseUrl={window.location.origin} online legacyUrl="/#home" headingOwnedByShell
        checkoutContent={<ReimaginedFoodCheckout addressPicker={<p>Synthetic saved address: Test home</p>} input={{ food: state.shopping.food, menus, online: true, canEdit: true, addressesReady: true, recipient: { name: "Test customer", phoneNumber: "+919876543210" }, address: { addressId: "test", label: "Test home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-09-30" } }} counter={<p role="status">Synthetic local review only. No order can be placed.</p>} />} />
    </ReimaginedShell><output data-testid="food-check-shopping" hidden>{JSON.stringify(state.shopping)}</output></>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  const root = createRoot(document.getElementById("root")!);
  root.render(<Fixture />);
  import.meta.hot?.dispose(() => root.unmount());
} else document.body.textContent = "Local test fixture disabled.";
