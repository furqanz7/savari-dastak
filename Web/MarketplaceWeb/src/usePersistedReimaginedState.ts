import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { acknowledgeFoodCheckout, acknowledgeGroceryCheckout, loadCustomerCart, loadCustomerCartStrict, saveCustomerCartStrict } from "./customerCartPersistence";
import { initialReimaginedState, reimaginedReducer, type ReimaginedAction } from "./reimaginedState";

type StorageAdapter = Parameters<typeof loadCustomerCart>[1];
function restore(accountId: string, storage: StorageAdapter) {
  return { accountId, state: reimaginedReducer(initialReimaginedState(), {
    type: "signedIn", accountId, shopping: loadCustomerCart(accountId, storage),
  }) };
}

// Sole cart owner while Reimagined is visible. Uses the existing v2 key
// and serializer, so returning to the existing UI restores the same shopping.
export function usePersistedReimaginedState(accountId: string, storage?: StorageAdapter) {
  const liveAccount = useRef<string | undefined>(accountId);
  useLayoutEffect(() => { liveAccount.current = accountId; return () => { liveAccount.current = undefined; }; }, [accountId]);
  const [owned, setOwned] = useState(() => restore(accountId, storage));
  const editing = useRef(false);
  const [editorAccount, setEditorAccount] = useState<string>();
  const [cartIssue, setCartIssue] = useState<string>();
  const claimEditing = useRef<(() => void) | undefined>(undefined);
  const requestCartEditing = useCallback(() => claimEditing.current?.(), []);
  const snapshot = useRef(owned);
  if (owned.accountId !== accountId) setOwned(restore(accountId, storage));
  const current = owned.accountId === accountId ? owned.state : restore(accountId, storage).state;
  useLayoutEffect(() => { snapshot.current = { accountId, state: current }; }, [accountId, current]);
  useEffect(() => {
    let closed = false;
    let release: (() => void) | undefined;
    let controller: AbortController | undefined;
    let waitingTimer: ReturnType<typeof setTimeout> | undefined;
    let pageAway = false;
    editing.current = false;
    setEditorAccount(undefined);
    const key = `dastak:v1-cart:${accountId}`;
    let channel: BroadcastChannel | undefined;
    const relinquish = () => {
      editing.current = false;
      setEditorAccount(undefined);
      clearTimeout(waitingTimer);
      controller?.abort();
      release?.(); release = undefined;
    };
    const acquire = (handoff = false) => {
      if (closed || pageAway || document.visibilityState === "hidden" || editing.current || !navigator.locks) return;
      controller?.abort();
      clearTimeout(waitingTimer);
      const attempt = new AbortController();
      controller = attempt;
      setCartIssue(handoff ? "Moving cart editing to this tab…" : "Checking cart editing…");
      waitingTimer = setTimeout(() => {
        if (!closed && !attempt.signal.aborted && !editing.current) {
          setCartIssue("Cart editing is waiting to become available. Choose Edit cart in this tab to try again. An older Dastak page may need refreshing, even if its cart is closed.");
        }
      }, 1500);
      void navigator.locks.request(`${key}:reimagined-editor`, { mode: "exclusive", signal: attempt.signal }, async lock => {
        if (closed || pageAway || document.visibilityState === "hidden" || attempt.signal.aborted) return;
        if (!lock) throw new Error("Cart editing is unavailable. Try again.");
        clearTimeout(waitingTimer);
        // Never take ownership using this tab's stale snapshot of the cart.
        const shopping = loadCustomerCartStrict(accountId, storage);
        const next = { accountId, state: { ...snapshot.current.state, shopping, bucketAcquired: snapshot.current.state.bucketAcquired || Object.keys(shopping.retail).length > 0 } };
        snapshot.current = next; setOwned(next);
        editing.current = true; setEditorAccount(accountId); setCartIssue(undefined);
        await new Promise<void>(resolve => { release = resolve; });
      }).catch((issue: unknown) => {
        if (!closed && !attempt.signal.aborted && controller === attempt) {
          clearTimeout(waitingTimer);
          editing.current = false; setEditorAccount(undefined);
          setCartIssue(issue instanceof Error ? issue.message : "Cart editing is unavailable. Try again.");
        }
      });
      // Cooperative handoff: the current owner stops writes before releasing
      // the exclusive Web Lock. Do not steal a lock from an in-flight editor.
      if (handoff) channel?.postMessage("request-editing");
    };
    if (typeof navigator === "undefined" || !navigator.locks) {
      setCartIssue("This browser cannot safely coordinate cart tabs. Cart editing is disabled.");
    } else {
      try {
        if (typeof BroadcastChannel !== "undefined") {
          channel = new BroadcastChannel(`${key}:editor-handoff`);
          channel.onmessage = event => {
            if (closed || event.data !== "request-editing") return;
            relinquish();
            setCartIssue("Cart editing moved to another tab. Choose Edit cart in this tab to move it back.");
          };
        }
      } catch { /* Web Locks still protect the cart if messaging is unavailable. */ }
      claimEditing.current = () => acquire(true);
      acquire();
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
    const leave = () => { pageAway = true; relinquish(); };
    const resume = () => { pageAway = false; acquire(); };
    // Background tabs may be suspended before receiving a handoff message.
    // Release eagerly on visibility change, not only when the page closes.
    const visibility = () => {
      if (document.visibilityState === "hidden") {
        relinquish();
        setCartIssue(undefined);
      } else if (!pageAway) acquire(true);
    };
    window.addEventListener("pagehide", leave);
    window.addEventListener("pageshow", resume);
    document.addEventListener("visibilitychange", visibility);
    return () => {
      closed = true; editing.current = false; claimEditing.current = undefined;
      clearTimeout(waitingTimer); controller?.abort(); release?.(); channel?.close();
      window.removeEventListener("storage", sync);
      window.removeEventListener("pagehide", leave); window.removeEventListener("pageshow", resume);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, [accountId, storage]);
  const dispatch = useCallback((action: ReimaginedAction) => {
    if (liveAccount.current !== accountId) return;
    // Authentication is owned by the application's existing session, not UI events.
    if (action.type === "signedIn" || action.type === "signedOut") return;
    const changesCart = action.type === "setGroceryQuantity" || action.type === "setFoodQuantity" || action.type === "checkoutSucceeded" || action.type === "replaceServiceShopping";
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
    if (changesCart) setCartIssue(undefined);
  }, [accountId, storage]);
  return { state: current, dispatch, cartIssue, canEditCart: editorAccount === accountId, requestCartEditing };
}
