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
import { useReimaginedFood } from "./useReimaginedFood";
import { useReimaginedFoodSearch } from "./useReimaginedFoodSearch";
import { ReimaginedFoodCounter } from "./ReimaginedFoodCounter";
import { foodRecoveryJournal, ReimaginedFoodRecovery } from "./reimaginedFoodRecovery";
import type { getV1RestaurantPage } from "./dastakV1";

const scenario = new URLSearchParams(window.location.search).get("state");
const menu = foodMenuFixture();
if (scenario === "long") {
  menu.restaurant.branchName = "Test Neighbourhood Kitchen and Café with a very long branch name";
  menu.categories[0].name = "Freshly prepared meals with customisable accompaniments";
  menu.categories[0].items[0].name = "Test slow-cooked paneer and fragrant rice with seasonal accompaniments";
  const group = menu.categories[0].items[0].optionGroups[0];
  group.name = "ChooseYourPreferredMealSizeAndAccompaniments";
  group.options[0].name = "LargeMealWithExtraSeasonalAccompaniments";
}
menu.categories.push({ ...menu.categories[0], id: "00000000-0000-4000-8000-000000000040", name: "Drinks", sortOrder: 2, items: [{ ...menu.categories[0].items[0], id: "00000000-0000-4000-8000-000000000041", name: "Test Mango Drink", basePricePaise: 6000, optionGroups: [] }] });
menu.restaurant.distanceMeters = 350;
menu.restaurant.description = "Synthetic local menu: meals, drinks and customisable dishes.";
const far = foodMenuFixture("00000000-0000-4000-8000-000000000050");
far.restaurant.branchName = "Test Far Café"; far.restaurant.distanceMeters = 2500;
const unknown = foodMenuFixture("00000000-0000-4000-8000-000000000051"); unknown.restaurant.branchName = "Test Unmapped Café";
const closed = foodMenuFixture("00000000-0000-4000-8000-000000000052"); closed.restaurant.branchName = "Test Closed Café"; closed.restaurant.acceptingOrders = false;
const menus = nearestFoodMenus(prepareFoodMenus([far, unknown, menu, closed]));
const remote = foodMenuFixture("00000000-0000-4000-8000-000000000099");
remote.restaurant.branchName = "Test Regional Café"; remote.restaurant.distanceMeters = 700;
remote.categories[0].items[0].name = "Regional Paneer Rice";
const auth = { accountId: "__reimagined_food_browser_check__", accessToken: "synthetic", supabaseUrl: window.location.origin, publishableKey: "synthetic" };
const savedLocation = { addressId: "00000000-0000-4000-8000-000000000070", updatedAt: "2026-10-09T00:00:00Z" };
const loader: typeof getV1RestaurantPage = async input => {
  if (scenario === "search-error" && input.query) throw new Error("Synthetic Food search failure");
  return { restaurants: input.query ? prepareFoodMenus([remote, closed]) : menus, ordering: "NEAREST" };
};
const checkout = new ReimaginedFoodRecovery(auth, {
  submit: async () => { throw new Error("Synthetic fixture cannot submit orders"); },
  commit: async () => { throw new Error("Synthetic fixture cannot commit orders"); },
  read: async () => { throw new Error("Synthetic fixture cannot read orders"); },
}, foodRecoveryJournal(auth.accountId, auth.supabaseUrl, { getItem: () => null, setItem: () => {} }));
// Controlled data only; no authenticated/hosted requests or real cart storage.
export function Fixture() {
  const greeting = useReimaginedGreeting();
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "__reimagined_food_browser_check__", shopping: { retail: { retained: 2 }, food: [] } }), { type: "selectService", service: "food" }));
  const resource = useReimaginedFood(auth, true, scenario !== "offline", loader, state.exploration.food.view.kind === "search" ? state.exploration.food.view.query : "", savedLocation);
  const search = useReimaginedFoodSearch(auth, state.exploration.food.searchDraft, state.exploration.food.searchOpen, scenario !== "offline", savedLocation, loader);
  const knownMenus = resource.data ?? menus;
  const input = { food: state.shopping.food, menus: knownMenus, online: true, canEdit: true, addressesReady: true, recipient: { name: "Test customer", phoneNumber: "+919876543210" }, address: { addressId: savedLocation.addressId, label: "Test home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: savedLocation.updatedAt } };
  return <><aside className="reimagined-local-notice">Local Food test fixture · synthetic menu · no backend or checkout requests</aside>
    <ReimaginedShell state={state} dispatch={dispatch} directory={[]} greeting={greeting} locationLabel="Test location" locationContent={<p>Test location only</p>} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{ orders: <p>Test Orders</p> }} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />}
      featureTitle={state.section === "home" ? foodPanelTitle(state, knownMenus) : undefined} searchSuggestions={<><ReimaginedFoodSuggestions canonical menus={search.menus} query={state.exploration.food.searchDraft} dispatch={dispatch} onSelect={value => resource.rememberRestaurant?.(value) === true} />{search.loading ? <p role="status">Searching restaurants and dishes in your area…</p> : null}{search.error ? <p role="alert">Couldn’t search Food in your area. <button onClick={search.retry}>Retry Food search</button></p> : null}</>}>
      <ReimaginedFood state={state} dispatch={dispatch} resource={{ ...resource, data: scenario === "loading" || scenario === "error" || scenario === "offline" ? undefined : scenario === "empty" ? [] : knownMenus, nearest: true, status: scenario === "loading" ? "loading" : scenario === "error" ? "unavailable" : "ready" }} supabaseUrl={window.location.origin} online={scenario !== "offline"} legacyUrl="/#home" headingOwnedByShell
        checkoutContent={<ReimaginedFoodCheckout addressPicker={<p>Synthetic saved address: Test home</p>} input={input} counter={<ReimaginedFoodCounter checkout={checkout} input={input} enabled deliveryIssue="No delivery partners are available in your area right now. Keep your cart and try later." dispatch={dispatch} onSessionExpired={() => {}} ordersUrl="#synthetic-orders" />} />} />
    </ReimaginedShell><output data-testid="food-check-shopping" hidden>{JSON.stringify(state.shopping)}</output></>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  const root = createRoot(document.getElementById("root")!);
  root.render(<Fixture />);
  import.meta.hot?.dispose(() => root.unmount());
} else document.body.textContent = "Local test fixture disabled.";
