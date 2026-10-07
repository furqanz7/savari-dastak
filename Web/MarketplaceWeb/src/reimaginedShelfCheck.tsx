import { useReducer } from "react";
import { createRoot } from "react-dom/client";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { useReimaginedGreeting } from "./useReimaginedGreeting";
import "./styles.css";
import "./design/customer-experience.css";

// DEV-only synthetic data; no authenticated APIs, inventory or cart persistence.
const base = { ...groceryFixture.catalogue.skus[0], name: "Test Tall Milk Carton", variant: "Toned", quantityValue: 200, quantityUnit: "ml", brand: { id: fixtureId(40), name: "Test brand", slug: "test" }, imageKey: "local/shelf-tall.svg", galleryImageKeys: ["local/shelf-square.svg"] };
const data = { ...groceryFixture, catalogue: { ...groceryFixture.catalogue, skus: [
  { ...base, packSize: "200 ml" },
  { ...base, id: fixtureId(41), packSize: "1 L", quantityValue: 1, quantityUnit: "l", sellingPricePaise: 16000, listPricePaise: 20000 },
  { ...base, id: fixtureId(42), packSize: "500 ml", quantityValue: 500, sellingPricePaise: 12500 },
  { ...base, id: fixtureId(43), name: "Test Long Product Name Dairy Whitener For Shelf Readability", variant: "Dairy Whitener", quantityUnit: "g", imageKey: "local/shelf-square.svg", packSize: "200 g", galleryImageKeys: [] },
  { ...base, id: fixtureId(44), name: "Test Long Product Name Dairy Whitener For Shelf Readability", variant: "Dairy Whitener", quantityUnit: "g", quantityValue: 400, imageKey: "local/shelf-square.svg", packSize: "400 g", sellingPricePaise: 18000, galleryImageKeys: [] },
  { ...base, id: fixtureId(45), name: "Test Unavailable Milk", variant: undefined, quantityValue: 1, quantityUnit: "l", imageKey: undefined, galleryImageKeys: [], packSize: "1 L" },
 ] } };
export function ShelfCheck() {
  const greeting = useReimaginedGreeting();
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "synthetic" }), { type: "openBrowseDestination", nodeKey: "atta-flour-dal", railKey: "rice" }));
  const wishlist = { items: [], ready: true, busy: false, error: undefined, retry: () => {}, saved: () => false, toggle: async () => {} };
  return <><aside className="reimagined-local-notice">Synthetic shelf check · local only · no live shopping</aside><ReimaginedShell state={state} dispatch={dispatch} directory={reimaginedDirectory(data.map)} displayName="Test customer" greeting={greeting} locationLabel="Synthetic location" locationContent={null} onSignIn={() => {}} onOpenActiveOrder={() => {}} onOpenWishlist={() => {}} sectionContent={{}} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />} searchSuggestions={<ReimaginedGrocerySuggestions data={data} query={state.exploration.grocery.searchDraft} dispatch={dispatch} />}>
    <p className="reimagined-commerce-note">Catalogue prices are estimates. Stock, delivery and final totals must be confirmed at checkout.</p>
    <ReimaginedGrocery state={state} dispatch={dispatch} data={data} status="ready" onRetry={() => {}} supabaseUrl="" eligibility={sku => ({ canAdd: sku.id !== fixtureId(45), maximumQuantity: 99 })} checkoutContent={<p>Simulated review only</p>} wishlist={wishlist} />
  </ReimaginedShell><output hidden id="shelf-check-state">{JSON.stringify(state.shopping.retail)}</output></>;
}
if (import.meta.env.DEV && ["127.0.0.1", "localhost", "::1"].includes(location.hostname)) {
  const root = createRoot(document.getElementById("root")!);
  root.render(<ShelfCheck />);
  import.meta.hot?.dispose(() => root.unmount());
}
