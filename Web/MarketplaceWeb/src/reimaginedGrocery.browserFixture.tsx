import { useReducer } from "react";
import { createRoot } from "react-dom/client";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery } from "./ReimaginedGrocery";
import { groceryFixture } from "./reimaginedCatalogue.testFixtures";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { ReimaginedGroceryBilling } from "./ReimaginedGroceryBilling";
import { ReimaginedBucketReview } from "./ReimaginedBucketReview";
import { grocerySubtotal } from "./reimaginedCatalogue";
import "./styles.css";
import "./design/customer.css";
import "./design/customer-experience.css";

const address = { addressId: "synthetic", label: "Synthetic home", address: "Test street", building: "1", details: "", displayAddress: "Synthetic building, Test street — a long address for phone wrapping checks", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "2026-10-09" };

// Existing synthetic SKUs, grouped by a real search projection; no inventory or storage writes.
export function Fixture() {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => {
    let initial = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "__reimagined_grocery_layout_check__" });
    if (new URLSearchParams(window.location.search).has("home")) return initial;
    initial = reimaginedReducer(initial, { type: "typeSearch", query: "Test" });
    return reimaginedReducer(initial, { type: "submitSearch" });
  });
  return <><aside className="reimagined-local-notice">Local Grocery fixture · synthetic existing test data · no backend or checkout requests</aside>
    <ReimaginedShell state={state} dispatch={dispatch} directory={reimaginedDirectory(groceryFixture.map)} greeting="Welcome" locationLabel="Test location" locationContent={<p>Test address only</p>} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{}} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />}>
      <ReimaginedGrocery state={state} dispatch={dispatch} data={groceryFixture} status="ready" onRetry={() => {}} supabaseUrl="" eligibility={() => ({ canAdd: true, maximumQuantity: 2, reason: "Local simulation only" })}
        checkoutContent={<ReimaginedGroceryBilling items={<ReimaginedBucketReview state={state} dispatch={dispatch} data={groceryFixture} canIncrease maximumQuantity={2} />} retail={state.shopping.retail} subtotal={grocerySubtotal(state, groceryFixture)} addresses={{ status: "ready", addresses: [address], selected: address, retry: () => {}, select: () => {}, error: undefined }} recipient={{ name: "Synthetic customer with a long name", phoneNumber: "+919876543210" }} online canEdit accountUrl="#profile" counter={<p role="status">Synthetic local review only. No order can be placed.</p>} />} />
    </ReimaginedShell><output data-testid="grocery-check-shopping" hidden>{JSON.stringify(state.shopping)}</output></>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  const root = createRoot(document.getElementById("root")!); root.render(<Fixture />);
  import.meta.hot?.dispose(() => root.unmount());
} else document.body.textContent = "Local test fixture disabled.";
