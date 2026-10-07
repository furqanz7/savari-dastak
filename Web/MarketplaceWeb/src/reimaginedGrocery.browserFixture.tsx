import { useReducer } from "react";
import { createRoot } from "react-dom/client";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery } from "./ReimaginedGrocery";
import { groceryFixture } from "./reimaginedCatalogue.testFixtures";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";

// Existing synthetic SKUs, grouped by a real search projection; no inventory or storage writes.
export function Fixture() {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => {
    let initial = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "__reimagined_grocery_layout_check__" });
    if (new URLSearchParams(window.location.search).has("home")) return initial;
    initial = reimaginedReducer(initial, { type: "typeSearch", query: "Test" });
    return reimaginedReducer(initial, { type: "submitSearch" });
  });
  return <><aside className="reimagined-local-notice">Local Grocery fixture · synthetic existing test data · no backend or checkout requests</aside>
    <ReimaginedShell state={state} dispatch={dispatch} directory={reimaginedDirectory(groceryFixture.map)} greeting="Welcome" locationLabel="Test location" locationContent={<p>Test address only</p>} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{}}>
      <ReimaginedGrocery state={state} dispatch={dispatch} data={groceryFixture} status="ready" onRetry={() => {}} supabaseUrl="" eligibility={() => ({ canAdd: true, maximumQuantity: 2, reason: "Local simulation only" })}
        checkoutContent={<section className="reimagined-bucket-review"><p>Local review only. No order can be placed.</p><button type="button" disabled>Grocery checkout integration pending</button></section>} />
    </ReimaginedShell><output data-testid="grocery-check-shopping" hidden>{JSON.stringify(state.shopping)}</output></>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  createRoot(document.getElementById("root")!).render(<Fixture />);
} else document.body.textContent = "Local test fixture disabled.";
