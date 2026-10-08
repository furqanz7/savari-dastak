import { useCallback, useReducer, useState } from "react";
import { createRoot } from "react-dom/client";
import { initialReimaginedState, reimaginedReducer, type ReimaginedAction } from "./reimaginedState";
import { useReimaginedNavigation, type ReimaginedNavigation } from "./useReimaginedNavigation";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";

export function NavigationCheck() {
  const [state, cartDispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "synthetic-navigation", shopping: { retail: { [fixtureId(6)]: 2 }, food: [{ branchId: "synthetic", itemId: "synthetic", optionIds: [], quantity: 1 }] } }));
  const [savedOpen, setSavedOpen] = useState(false), [payments, setPayments] = useState(false);
  const [record, setRecord] = useState<Pick<ReimaginedNavigation, "orderId" | "merchantOrderId">>({});
  const restore = useCallback((navigation: ReimaginedNavigation) => { setSavedOpen(navigation.savedOpen); setPayments(navigation.payments); setRecord({ orderId: navigation.orderId, merchantOrderId: navigation.merchantOrderId }); cartDispatch({ type: "restoreNavigation", navigation }); }, []);
  const exploration = state.exploration[state.service];
  useReimaginedNavigation("synthetic-navigation", { service: state.service, section: state.section, savedOpen, payments, ...record, exploration: { view: exploration.view, searchOpen: exploration.searchOpen, checkout: exploration.checkout, ...(exploration.detailId ? { detailId: exploration.detailId } : {}) } }, restore);
  const dispatch = (action: ReimaginedAction) => { setSavedOpen(false); setPayments(false); if (action.type === "navigate") setRecord({}); cartDispatch(action); };
  const workspace = <section><h2>{payments ? "Payment history" : record.merchantOrderId ? "Older merchant order" : record.orderId ? "V1 order" : state.section}</h2><p>Synthetic workspace. No account or order requests.</p>{record.merchantOrderId || record.orderId ? <p>Selected record: {record.merchantOrderId ?? record.orderId}</p> : null}<button onClick={() => { setRecord({}); setPayments(true); }}>Payments</button></section>;
  return <><aside className="reimagined-local-notice">Local navigation fixture · simulated data only · Grocery {state.shopping.retail[fixtureId(6)] ?? 0} · Food {state.shopping.food[0]?.quantity ?? 0}</aside><ReimaginedShell state={state} dispatch={dispatch} directory={reimaginedDirectory(groceryFixture.map)} greeting="Navigation test" locationLabel="Synthetic location" locationContent={null} onSignIn={() => {}} onOpenActiveOrder={() => {}} onOpenWishlist={() => { dispatch({ type: "navigate", section: "home" }); setSavedOpen(true); }} featureTitle={savedOpen ? "Wishlist" : payments ? "Payments" : undefined}
    searchSuggestions={<ReimaginedGrocerySuggestions data={groceryFixture} query={exploration.searchDraft} dispatch={dispatch} />}
    sectionContent={{ orders: workspace, profile: workspace, settings: workspace }} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />}>
    {savedOpen ? <section><h2>Your Wishlist</h2><p>Synthetic empty Wishlist.</p><button onClick={() => setSavedOpen(false)}>Back to shopping</button></section> : <ReimaginedGrocery state={state} dispatch={dispatch} data={groceryFixture} status="ready" onRetry={() => {}} supabaseUrl="https://example.invalid" eligibility={() => ({ canAdd: true, maximumQuantity: 99 })} checkoutContent={<p>Simulated review only</p>} />}
  </ReimaginedShell></>;
}
if (import.meta.env.DEV) {
  const root = createRoot(document.getElementById("root")!); root.render(<NavigationCheck />);
  import.meta.hot?.dispose(() => root.unmount());
}
