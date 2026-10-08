import { useReducer, useState } from "react";
import { createRoot } from "react-dom/client";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery } from "./ReimaginedGrocery";
import { ReimaginedFood } from "./ReimaginedFood";
import { ReimaginedWishlist } from "./ReimaginedWishlist";
import { ReimaginedAddressPicker } from "./ReimaginedAddressPicker";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { reimaginedDirectory } from "./reimaginedDirectory";
import type { CustomerWishlistItem, CustomerWishlistItemKind } from "./customerWishlist";
import "./design/customer-experience.css";
import "./design/customer.css";
import "./styles.css";

export function Check({ phoneAudit = false }: { phoneAudit?: boolean }) {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "synthetic-check" }));
  const [saved, setSaved] = useState<CustomerWishlistItem[]>([]); const [open, setOpen] = useState(false);
  const menu = foodMenuFixture();
  const addresses = Array.from({ length: 10 }, (_, index) => ({ addressId: `preview-${index}`, label: `Preview address ${index + 1}`, address: "Synthetic test street", building: "1", details: "", displayAddress: "Synthetic test street, example building and doorstep", location: { latitude: 0, longitude: 0 }, isDefault: index === 0, updatedAt: "today" }));
  const addressResource = { addresses, selected: addresses[0], status: "ready" as const, error: undefined, select: () => {}, retry: () => {} };
  const wishlist = { items: saved, ready: true, busy: false, error: undefined, retry: () => {}, saved: (kind: CustomerWishlistItemKind, id: string) => saved.some(value => value.kind === kind && value.itemId === id), toggle: async (kind: CustomerWishlistItemKind, id: string) => setSaved(previous => previous.some(value => value.kind === kind && value.itemId === id) ? previous.filter(value => value.kind !== kind || value.itemId !== id) : [...previous, { kind, itemId: id, createdAt: new Date().toISOString() }]) };
  return <><aside className="reimagined-local-notice">Synthetic local feature check · no live inventory, account writes or checkout</aside>
    <ReimaginedShell state={state} dispatch={action => { setOpen(false); dispatch(action); }} directory={reimaginedDirectory(groceryFixture.map)} displayName="Test customer" greeting="Preview" locationLabel="Synthetic location" locationContent={phoneAudit ? <ReimaginedAddressPicker resource={addressResource} online accountUrl="#" auth={{ accessToken: "synthetic-only", publishableKey: "synthetic-only", supabaseUrl: "https://example.invalid" }} /> : null} onSignIn={() => {}} onOpenActiveOrder={() => {}} sectionContent={{}} onOpenWishlist={() => setOpen(true)} featureTitle={open ? "Wishlist" : phoneAudit ? "Tea Coffee and Milk Drinks" : undefined} environment={<div style={{ minHeight: "100vh", background: "#d2dbcf" }} />}>
      {open ? <ReimaginedWishlist wishlist={wishlist} data={groceryFixture} menus={[menu]} online supabaseUrl="https://example.invalid" onClose={() => setOpen(false)} onOpen={(skuId, branchId, itemId) => { setOpen(false); dispatch({ type: "selectService", service: skuId ? "grocery" : "food" }); if (branchId) dispatch({ type: "openRestaurant", branchId }); dispatch({ type: "openDetail", id: skuId ?? itemId ?? fixtureId(6) }); }} /> : state.service === "grocery" ? <ReimaginedGrocery state={state} dispatch={dispatch} data={groceryFixture} status="ready" onRetry={() => {}} supabaseUrl="https://example.invalid" eligibility={() => ({ canAdd: true, maximumQuantity: 99 })} checkoutContent={<p>Simulated review only</p>} wishlist={wishlist} /> : <ReimaginedFood state={state} dispatch={dispatch} resource={{ data: [menu], status: "ready", error: undefined, retry: () => {} }} supabaseUrl="https://example.invalid" online legacyUrl="#" wishlist={wishlist} checkoutContent={<p>Simulated review only</p>} />}
    </ReimaginedShell>
  </>;
}
if (import.meta.env.DEV) {
  const root = createRoot(document.getElementById("root")!);
  root.render(<Check phoneAudit={new URLSearchParams(window.location.search).has("phone-audit")} />);
  import.meta.hot?.dispose(() => root.unmount());
}
