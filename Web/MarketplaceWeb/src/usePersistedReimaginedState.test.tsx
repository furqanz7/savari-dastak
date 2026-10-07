// @vitest-environment jsdom
import { act, StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadCustomerCart, saveCustomerCart } from "./customerCartPersistence";
import { usePersistedReimaginedState } from "./usePersistedReimaginedState";
import { cartStorageFixture, checkoutLocksFixture } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement; let current: ReturnType<typeof usePersistedReimaginedState>;
function Harness({ accountId }: { accountId: string }) {
  current = usePersistedReimaginedState(accountId);
  return <output>{JSON.stringify(current.state)}</output>;
}
function mount(accountId: string) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness accountId={accountId} />)); }
beforeEach(() => { vi.stubGlobal("localStorage", cartStorageFixture()); vi.stubGlobal("navigator", { locks: checkoutLocksFixture() }); });
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); localStorage.clear(); vi.unstubAllGlobals(); });
describe("single persisted Reimagined cart owner", () => {
  it("acknowledges Food once across remounts without removing Grocery or other options", async () => {
    const line = { branchId: "branch", itemId: "meal", optionIds: ["large"], quantity: 4 };
    saveCustomerCart("a", { retail: { rice: 3 }, food: [line, { ...line, optionIds: ["small"], quantity: 1 }] }); mount("a");
    const action = { type: "checkoutSucceeded" as const, service: "food" as const, orderId: "food-order", purchased: { retail: {}, food: [{ ...line, quantity: 2 }] } };
    act(() => current.dispatch(action)); act(() => current.dispatch(action));
    expect(loadCustomerCart("a")).toEqual({ retail: { rice: 3 }, food: [{ ...line, quantity: 2 }, { ...line, optionIds: ["small"], quantity: 1 }] });
    await act(async () => root.unmount()); host.remove(); await act(async () => mount("a"));
    act(() => current.dispatch(action)); expect(loadCustomerCart("a").food[0].quantity).toBe(2);
  });
  it("persists Food choices independently and restores them after remount", async () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a");
    act(() => current.dispatch({ type: "selectService", service: "food" }));
    const line = { branchId: "branch", itemId: "dish", optionIds: ["large"], quantity: 2 };
    act(() => current.dispatch({ type: "setFoodQuantity", line }));
    expect(loadCustomerCart("a")).toEqual({ retail: { rice: 3 }, food: [line] });
    await act(async () => root.unmount()); host.remove();
    await act(async () => mount("a"));
    expect(current.state.shopping).toEqual({ retail: { rice: 3 }, food: [line] });
  });
  it("never writes shopping during mount, navigation or an incoming storage update", () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a");
    const write = vi.spyOn(localStorage, "setItem");
    saveCustomerCart("a", { retail: { rice: 5, poha: 2 }, food: [] }); write.mockClear();
    act(() => current.dispatch({ type: "navigate", section: "orders" }));
    expect(loadCustomerCart("a").retail).toEqual({ rice: 5, poha: 2 }); expect(write).not.toHaveBeenCalled();
    act(() => window.dispatchEvent(new StorageEvent("storage", { key: "dastak:v1-cart:a" })));
    expect(current.state.shopping.retail).toEqual({ rice: 5, poha: 2 }); expect(write).not.toHaveBeenCalled();
  });
  it("refreshes instead of overwriting a changed cart when its storage event was delayed", () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a");
    saveCustomerCart("a", { retail: { rice: 5 }, food: [] });
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
    expect(current.state.shopping.retail.rice).toBe(5); expect(loadCustomerCart("a").retail.rice).toBe(5);
    expect(current.cartIssue).toContain("changed in another view");
  });
  it("keeps a second editor read-only, synchronizes it, then hands ownership over", async () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a"); const first = current;
    let second!: ReturnType<typeof usePersistedReimaginedState>;
    function Other() { second = usePersistedReimaginedState("a"); return null; }
    const otherHost = document.createElement("div"); const otherRoot = createRoot(otherHost);
    try {
      act(() => otherRoot.render(<Other />)); expect(second.canEditCart).toBe(false);
      act(() => second.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 99 }));
      expect(loadCustomerCart("a").retail.rice).toBe(3);
      act(() => first.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
      act(() => window.dispatchEvent(new StorageEvent("storage", { key: "dastak:v1-cart:a" })));
      expect(second.state.shopping.retail.rice).toBe(4);
      await act(async () => root.unmount());
      expect(second.canEditCart).toBe(true);
      act(() => second.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 5 }));
      expect(loadCustomerCart("a").retail.rice).toBe(5);
    } finally { await act(async () => otherRoot.unmount()); }
  });
  it("retains the previous cart when saving fails and does not overwrite corrupt storage", () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a");
    vi.spyOn(localStorage, "setItem").mockImplementationOnce(() => { throw new Error("quota full"); });
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
    expect(current.state.shopping.retail.rice).toBe(3); expect(current.cartIssue).toContain("quota full");
    localStorage.setItem("dastak:v1-cart:a", '{"version":99}');
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 5 }));
    expect(localStorage.getItem("dastak:v1-cart:a")).toBe('{"version":99}'); expect(current.state.shopping.retail.rice).toBe(3);
  });
  it("fails closed when browser locking is unavailable", () => {
    vi.stubGlobal("navigator", {}); saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a");
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
    expect(current.canEditCart).toBe(false); expect(loadCustomerCart("a").retail.rice).toBe(3);
  });
  it("reacquires editing after StrictMode cleanup without leaking ownership", async () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    await act(async () => root.render(<StrictMode><Harness accountId="a" /></StrictMode>));
    expect(current.canEditCart).toBe(true);
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
    expect(loadCustomerCart("a").retail.rice).toBe(4);
  });
  it("restores existing Grocery/Food shopping and writes the same versioned key", () => {
    const food = [{ branchId: "branch", itemId: "meal", optionIds: ["option"], quantity: 2 }];
    saveCustomerCart("a", { retail: { rice: 3 }, food });
    mount("a");
    expect(current.state.bucketAcquired).toBe(true);
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
    act(() => current.dispatch({ type: "navigate", section: "orders" }));
    act(() => current.dispatch({ type: "selectService", service: "food" }));
    expect(loadCustomerCart("a")).toEqual({ retail: { rice: 4 }, food });
    expect(localStorage.length).toBe(1);
    expect(localStorage.getItem("dastak:v1-cart:a")).not.toContain("accessToken");
  });
  it("resets exploration and restores only the new account on switch; rejects stale dispatch", () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] });
    saveCustomerCart("b", { retail: { poha: 1 }, food: [] });
    mount("a"); const oldDispatch = current.dispatch;
    act(() => current.dispatch({ type: "openBrowseDestination", nodeKey: "masalas" }));
    act(() => root.render(<Harness accountId="b" />));
    expect(current.state.accountId).toBe("b");
    expect(current.state.exploration.grocery.view).toEqual({ kind: "home" });
    act(() => oldDispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 99 }));
    expect(current.state.shopping.retail).toEqual({ poha: 1 });
    expect(loadCustomerCart("a").retail).toEqual({ rice: 3 });
    expect(loadCustomerCart("b").retail).toEqual({ poha: 1 });
  });
  it("keeps Bucket gating and preserves the other service after checkout acknowledgement", () => {
    mount("a");
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 1 }));
    expect(current.state.bucketPrompt).toBe(true);
    expect(loadCustomerCart("a").retail).toEqual({});
    act(() => current.dispatch({ type: "takeBucket" }));
    act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 3 }));
    act(() => current.dispatch({ type: "selectService", service: "food" }));
    act(() => current.dispatch({ type: "setFoodQuantity", line: { branchId: "branch", itemId: "meal", optionIds: [], quantity: 2 } }));
    act(() => current.dispatch({ type: "checkoutSucceeded", service: "grocery", orderId: "order", purchased: { retail: { rice: 2 }, food: [] } }));
    expect(loadCustomerCart("a")).toEqual({ retail: { rice: 1 }, food: [{ branchId: "branch", itemId: "meal", optionIds: [], quantity: 2 }] });
  });
  it("does not let UI authentication events replace the host account", () => {
    mount("a"); act(() => current.dispatch({ type: "signedIn", accountId: "b" }));
    act(() => current.dispatch({ type: "signedOut" }));
    expect(current.state.accountId).toBe("a");
    expect(localStorage.getItem("dastak:v1-cart:b")).toBeNull();
  });
  it("deduplicates checkout acknowledgements across remount and preserves later added quantities", async () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a");
    const action = { type: "checkoutSucceeded" as const, service: "grocery" as const, orderId: "order", purchased: { retail: { rice: 2 }, food: [] } };
    act(() => current.dispatch(action)); act(() => current.dispatch({ type: "setGroceryQuantity", skuId: "rice", quantity: 4 }));
    await act(async () => root.unmount()); host.remove(); mount("a"); act(() => current.dispatch(action));
    expect(current.state.shopping.retail.rice).toBe(4); expect(loadCustomerCart("a").retail.rice).toBe(4);
  });
  it("does not let a stale checkout completion write either account after switching", () => {
    saveCustomerCart("a", { retail: { rice: 3 }, food: [] }); mount("a"); const oldDispatch = current.dispatch;
    act(() => root.render(<Harness accountId="b" />));
    act(() => oldDispatch({ type: "checkoutSucceeded", service: "grocery", orderId: "order", purchased: { retail: { rice: 2 }, food: [] } }));
    expect(loadCustomerCart("a").retail.rice).toBe(3); expect(current.state.accountId).toBe("b");
    expect(localStorage.getItem("dastak:v1-cart:a")).not.toContain("Acknowledgements");
  });
});
