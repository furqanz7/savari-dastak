import { createRoot } from "react-dom/client";
import { usePersistedReimaginedState } from "./usePersistedReimaginedState";

// Explicit local-only test surface, never imported by an app entrypoint.
export function Fixture() {
  const { state, dispatch, canEditCart, cartIssue } = usePersistedReimaginedState("__reimagined_browser_cart_check__");
  return <main><h1>Local cart test — no catalogue, authentication or order requests</h1>
    <output data-testid="editing">{String(canEditCart)}</output>
    <output data-testid="shopping">{JSON.stringify(state.shopping)}</output>
    <p role="status">{cartIssue}</p>
    <button onClick={() => dispatch({ type: "takeBucket" })}>Take Bucket</button>
    <button disabled={!canEditCart} onClick={() => dispatch({ type: "setGroceryQuantity", skuId: "browser-test-rice", quantity: (state.shopping.retail["browser-test-rice"] ?? 0) + 1 })}>Add rice</button>
    <button disabled={!canEditCart} onClick={() => {
      dispatch({ type: "selectService", service: "food" });
      dispatch({ type: "setFoodQuantity", line: { branchId: "test", itemId: "test-meal", optionIds: [], quantity: 2 } });
      dispatch({ type: "selectService", service: "grocery" });
    }}>Add test Food</button>
    <button onClick={() => dispatch({ type: "navigate", section: "orders" })}>Navigate Orders</button>
    <button disabled={!canEditCart} onClick={() => dispatch({ type: "checkoutSucceeded", service: "grocery", orderId: "browser-test-confirmation", purchased: { retail: { "browser-test-rice": 1 }, food: [] } })}>Simulate local acknowledgement</button>
  </main>;
}
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  createRoot(document.getElementById("root")!).render(<Fixture />);
} else document.body.textContent = "Local test fixture disabled.";
