import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { acknowledgeFoodCheckout, acknowledgeGroceryCheckout, loadCustomerCart, loadCustomerCartStrict, saveCustomerCartStrict } from "./customerCartPersistence";
import { initialReimaginedState, reimaginedReducer, type ReimaginedAction } from "./reimaginedState";

type StorageAdapter = Parameters<typeof loadCustomerCart>[1];
function restore(accountId: string, storage: StorageAdapter) {
  return { accountId, state: reimaginedReducer(initialReimaginedState(), {
    type: "signedIn", accountId, shopping: loadCustomerCart(accountId, storage),
  }) };
}

// Sole cart owner while the local opt-in is mounted. Uses the existing v2 key
// and serializer, so returning to the existing UI restores the same shopping.
export function usePersistedReimaginedState(accountId: string, storage?: StorageAdapter) {
  const liveAccount = useRef<string | undefined>(accountId);
  useLayoutEffect(() => { liveAccount.current = accountId; return () => { liveAccount.current = undefined; }; }, [accountId]);
  const [owned, setOwned] = useState(() => restore(accountId, storage));
  const editing = useRef(false);
  const [editorAccount, setEditorAccount] = useState<string>();
  const [cartIssue, setCartIssue] = useState<string>();
  const snapshot = useRef(owned);
  if (owned.accountId !== accountId) setOwned(restore(accountId, storage));
  const current = owned.accountId === accountId ? owned.state : restore(accountId, storage).state;
  useLayoutEffect(() => { snapshot.current = { accountId, state: current }; }, [accountId, current]);
  useEffect(() => {
    let closed = false;
    let release: (() => void) | undefined;
    const controller = new AbortController();
    editing.current = false;
    setEditorAccount(undefined);
    setCartIssue("Cart editing is held by another tab or is being checked. This view is read-only until ownership is available.");
    const key = `dastak:v1-cart:${accountId}`;
    if (typeof navigator === "undefined" || !navigator.locks) {
      setCartIssue("This browser cannot safely coordinate cart tabs. Cart editing is disabled.");
    } else {
      void navigator.locks.request(`${key}:reimagined-editor`, { mode: "exclusive", signal: controller.signal }, async lock => {
        if (closed) return;
        if (!lock) { setCartIssue("Another Reimagined tab owns cart editing. Close that tab, then reopen this view to edit here."); return; }
        const shopping = loadCustomerCartStrict(accountId, storage);
        const next = { accountId, state: { ...snapshot.current.state, shopping, bucketAcquired: snapshot.current.state.bucketAcquired || Object.keys(shopping.retail).length > 0 } };
        snapshot.current = next; setOwned(next);
        editing.current = true; setEditorAccount(accountId); setCartIssue(undefined);
        await new Promise<void>(resolve => { release = resolve; });
      }).catch(() => { if (!closed) { editing.current = false; setCartIssue("Cart ownership is unavailable. Cart editing is disabled."); } });
    }
    const sync = (event: StorageEvent) => {
      if (event.key !== key && event.key !== null) return;
      if (closed || liveAccount.current !== accountId) return;
      let shopping;
      try { shopping = loadCustomerCartStrict(accountId, storage); }
      catch { setCartIssue("Saved cart data cannot be read safely. It was not overwritten."); return; }
      const next = { accountId, state: { ...snapshot.current.state, shopping, bucketAcquired: snapshot.current.state.bucketAcquired || Object.keys(shopping.retail).length > 0 } };
      snapshot.current = next; setOwned(next);
    };
    window.addEventListener("storage", sync);
    return () => { closed = true; editing.current = false; controller.abort(); release?.(); window.removeEventListener("storage", sync); };
  }, [accountId, storage]);
  const dispatch = (action: ReimaginedAction) => {
    if (liveAccount.current !== accountId) return;
    // Authentication is owned by the application's existing session, not UI events.
    if (action.type === "signedIn" || action.type === "signedOut") return;
    const changesCart = action.type === "setGroceryQuantity" || action.type === "setFoodQuantity" || action.type === "checkoutSucceeded";
    let base = snapshot.current.state;
    if (changesCart) {
      if (!editing.current) {
        if (action.type === "checkoutSucceeded") throw new Error("This tab does not own cart editing. Recover checkout in the editing tab.");
        return;
      }
      // A legacy tab may have changed storage without our editor lock. Do not overwrite it.
      let fresh;
      try { fresh = loadCustomerCartStrict(accountId, storage); }
      catch (issue) {
        setCartIssue(issue instanceof Error ? issue.message : "Cart storage is unavailable.");
        if (action.type === "checkoutSucceeded") throw issue;
        return;
      }
      if (action.type !== "checkoutSucceeded" && JSON.stringify(fresh) !== JSON.stringify(base.shopping)) {
        const next = { accountId, state: { ...base, shopping: fresh } };
        snapshot.current = next; setOwned(next);
        setCartIssue("Your cart changed in another view. It has been refreshed; review it before editing again.");
        return;
      }
      base = { ...base, shopping: fresh };
    }
    // Persist before scheduling React state; do not perform storage writes in an updater.
    // Duplicate acknowledgement only updates the order strip, never subtracts again.
    if (action.type === "checkoutSucceeded") {
      const fresh = action.service === "grocery" ? acknowledgeGroceryCheckout(accountId, action.orderId, action.purchased.retail, storage) : acknowledgeFoodCheckout(accountId, action.orderId, action.purchased.food, storage);
      if (!fresh) {
        const next = { accountId, state: reimaginedReducer(base, { type: "orderUpdated", order: { id: action.orderId, service: action.service } }) };
        snapshot.current = next; setOwned(next);
        return;
      }
    }
    const state = reimaginedReducer(base, action);
    if (changesCart && action.type !== "checkoutSucceeded") {
      try { saveCustomerCartStrict(accountId, state.shopping, storage); }
      catch (issue) { setCartIssue(issue instanceof Error ? issue.message : "Cart could not be saved."); return; }
    }
    const next = { accountId, state };
    snapshot.current = next; setOwned(next);
  };
  return { state: current, dispatch, cartIssue, canEditCart: editorAccount === accountId };
}
