import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatV1Price, submitV1Order, commitV1LaunchPayment, getV1Order } from "./dastakV1";
import type { DastakCustomerProps } from "./DastakCustomerView";
import { parseCustomerDestination } from "./customerNavigation";
import { customerDataIssue } from "./customerDataState";
import { existingCustomerUrl } from "./reimaginedOptIn";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { ReimaginedBucketReview } from "./ReimaginedBucketReview";
import { ReimaginedGroceryBilling } from "./ReimaginedGroceryBilling";
import { grocerySubtotal } from "./reimaginedCatalogue";
import { usePersistedReimaginedState } from "./usePersistedReimaginedState";
import { useReimaginedCatalogue } from "./useReimaginedCatalogue";
import { useCustomerOnline } from "./useCustomerOnline";
import { useReimaginedAddresses } from "./useReimaginedAddresses";
import { useReimaginedActiveOrder } from "./useReimaginedActiveOrder";
import { useReimaginedFood } from "./useReimaginedFood";
import { ReimaginedFood, ReimaginedFoodSuggestions } from "./ReimaginedFood";
import { ReimaginedFoodCheckout } from "./ReimaginedFoodCheckout";
import { ReimaginedFoodCounter } from "./ReimaginedFoodCounter";
import { foodRecoveryJournal, ReimaginedFoodRecovery } from "./reimaginedFoodRecovery";
import { ReimaginedAddressPicker } from "./ReimaginedAddressPicker";
import { ReimaginedGroceryCheckout } from "./reimaginedCheckout";
import { ReimaginedCheckoutCounter } from "./ReimaginedCheckoutCounter";
import { checkoutJournal } from "./reimaginedCheckoutJournal";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { useReimaginedWishlist } from "./useReimaginedWishlist";
import { ReimaginedWishlist } from "./ReimaginedWishlist";
import { prepareReimaginedReorder } from "./reimaginedReorder";
import { useDastakWebPush } from "./useDastakWebPush";
import { WebNotificationOnboarding } from "./WebNotificationOnboarding";
import type { ReimaginedAction } from "./reimaginedState";
import type { V1Order } from "./dastakV1";
import type { AccountProfile } from "./accountProfile";
import type { CustomerSection } from "./customerNavigation";
import { useReimaginedGreeting } from "./useReimaginedGreeting";

type Props = DastakCustomerProps;
const AccountWorkspace = lazy(() => import("./DastakCustomerView").then(module => ({ default: module.ExistingDastakCustomerView })));

// Key the entire session boundary: no cart or async response survives an account switch.
export function ReimaginedCustomerRoot(props: Props) {
  return <AccountExperience key={props.accountId} {...props} />;
}

function AccountExperience(props: Props) {
  const greeting = useReimaginedGreeting();
  const { state, dispatch: cartDispatch, cartIssue, canEditCart } = usePersistedReimaginedState(props.accountId);
  const [savedOpen, setSavedOpen] = useState(false);
  const [workspaceTitle, setWorkspaceTitle] = useState<string>();
  const [reorder, setReorder] = useState<ReturnType<typeof prepareReimaginedReorder>>();
  const [reorderError, setReorderError] = useState<string>();
  const [mixedOrder, setMixedOrder] = useState<V1Order>();
  const [reorderBusy, setReorderBusy] = useState(false);
  const reorderLock = useRef(false);
  const reorderContext = useRef("");
  const [profile, setProfile] = useState<AccountProfile>();
  const displayName = profile?.displayName ?? props.displayName;
  const phoneNumber = profile?.phoneNumber ?? props.phoneNumber;
  const dispatch = useCallback((action: ReimaginedAction) => { setSavedOpen(false); setWorkspaceTitle(undefined); cartDispatch(action); }, [cartDispatch]);
  const updateWorkspaceTitle = useCallback((section: CustomerSection) => setWorkspaceTitle(section === "payments" ? "Payments" : undefined), []);
  const [entry] = useState(() => parseCustomerDestination(window.location.hash));
  const [selectedOrderId, setSelectedOrderId] = useState(entry.entityType === "dastakV1Order" ? entry.entityId : undefined);
  useEffect(() => {
    if (entry.section === "orders" || entry.section === "account") dispatch({ type: "navigate", section: entry.section === "orders" ? "orders" : "profile" });
    // Restore a notification/deep link once; subsequent navigation belongs to this panel.
  }, [entry, dispatch]);
  const resource = useReimaginedCatalogue(props);
  const online = useCustomerOnline();
  reorderContext.current = JSON.stringify([props.accountId, props.accessToken, state.section, state.shopping, online, canEditCart]);
  const wishlist = useReimaginedWishlist(props, online);
  const { accountId, accessToken, supabaseUrl, publishableKey } = props;
  const checkout = useMemo(() => new ReimaginedGroceryCheckout({ accessToken, supabaseUrl, publishableKey }, undefined, undefined, undefined, checkoutJournal(accountId, supabaseUrl)), [accountId, accessToken, supabaseUrl, publishableKey]);
  const foodCheckout = useMemo(() => new ReimaginedFoodRecovery({ accessToken, supabaseUrl, publishableKey }, { submit: submitV1Order, commit: commitV1LaunchPayment, read: getV1Order }, foodRecoveryJournal(accountId, supabaseUrl, { getItem: key => window.localStorage.getItem(key), setItem: (key, value) => window.localStorage.setItem(key, value) })), [accountId, accessToken, supabaseUrl, publishableKey]);
  const addresses = useReimaginedAddresses(props, online && (state.locationOpen || (state.service === "grocery" ? state.exploration.grocery.checkout : state.exploration.food.checkout)));
  const tracking = useReimaginedActiveOrder(props, state.activeOrder, online);
  const foodView = state.exploration.food.view;
  const foodQuery = foodView.kind === "search" && !state.exploration.food.checkout && state.section === "home" ? foodView.query : "";
  const food = useReimaginedFood(props, state.service === "food" || savedOpen || state.section === "orders", online, undefined, foodQuery);
  const pushAuth = useMemo(() => ({ accountId, accessToken, supabaseUrl, publishableKey, publicKey: props.webPushPublicKey }), [accountId, accessToken, supabaseUrl, publishableKey, props.webPushPublicKey]);
  const webPush = useDastakWebPush(pushAuth);
  const onSessionExpired = props.onSignOut;
  useEffect(() => {
    if ([resource.error, addresses.error, tracking.error, food.error, wishlist.error].some(error => error && customerDataIssue(error).action === "sign_in")) onSessionExpired();
  }, [resource.error, addresses.error, tracking.error, food.error, wishlist.error, onSessionExpired]);
  const homeUrl = existingCustomerUrl("home", window.location.href);
  const accountUrl = existingCustomerUrl("account", window.location.href);
  const ordersUrl = existingCustomerUrl("orders", window.location.href);
  const subtotal = grocerySubtotal(state, resource.data);
  const addressPicker = <ReimaginedAddressPicker key={`location:${accessToken}`} resource={addresses} online={online} accountUrl={accountUrl} auth={props} onSessionExpired={onSessionExpired} />;
  const openWishlist = () => { dispatch({ type: "navigate", section: "home" }); setSavedOpen(true); };
  const openOrders = (id?: string) => { setSelectedOrderId(id); dispatch({ type: "navigate", section: "orders" }); };
  async function requestReorder(order: V1Order, selectedService?: "grocery" | "food") {
    if (reorderLock.current) return;
    setReorderError(undefined);
    const mixed = order.lines.some(line => line.lineType === "RETAIL_SKU") && order.lines.some(line => line.lineType === "FOOD_MENU_ITEM");
    if (mixed && !selectedService) { setMixedOrder(order); return; }
    reorderLock.current = true; setReorderBusy(true);
    const context = reorderContext.current;
    try {
      if (!online || !canEditCart) throw new Error("Reconnect and use the cart-editing tab before reordering.");
      let menus = food.data;
      const needsFood = selectedService === "food" || (!selectedService && order.lines.every(line => line.lineType === "FOOD_MENU_ITEM"));
      if (needsFood && order.restaurant && !menus?.some(menu => menu.restaurant.branchId === order.restaurant!.branchId) && food.findRestaurant) {
        const menu = await food.findRestaurant(order.restaurant.branchId);
        if (context !== reorderContext.current) throw new DOMException("Reorder context changed", "AbortError");
        if (menu) menus = [...(menus ?? []), menu];
      }
      const next = prepareReimaginedReorder(order, resource.data, menus, selectedService);
      const controller = next.service === "grocery" ? checkout : foodCheckout;
      if (controller.hasPendingAttempt && !controller.committed) throw new Error("Recover your pending checkout before replacing this cart.");
      setMixedOrder(undefined);
      const nonempty = next.service === "grocery" ? Object.keys(state.shopping.retail).length > 0 : state.shopping.food.length > 0;
      if (nonempty) setReorder(next);
      else dispatch({ type: "replaceServiceShopping", ...next });
    } catch (issue) {
      if (!(issue instanceof DOMException && issue.name === "AbortError")) {
        if (customerDataIssue(issue).action === "sign_in") onSessionExpired();
        else setReorderError(issue instanceof Error ? issue.message : "Order could not be added. Your carts are unchanged.");
      }
    } finally { reorderLock.current = false; setReorderBusy(false); }
  }
  function approveReorder() {
    if (!reorder || !online || !canEditCart) return;
    const controller = reorder.service === "grocery" ? checkout : foodCheckout;
    if (controller.hasPendingAttempt && !controller.committed) { setReorderError("Recover your pending checkout before replacing this cart."); return; }
    dispatch({ type: "replaceServiceShopping", ...reorder }); setReorder(undefined);
  }
  const foodInput = { food: state.shopping.food, menus: food.data, online, canEdit: canEditCart, address: addresses.selected, addressesReady: addresses.status === "ready", recipient: { name: displayName, phoneNumber } };
  const draft = subtotal !== undefined && addresses.status === "ready" && addresses.selected && displayName?.trim() && phoneNumber?.trim()
    ? { retail: state.shopping.retail, address: addresses.selected, recipient: { name: displayName, phoneNumber } } : undefined;
  const review = <ReimaginedGroceryBilling items={<ReimaginedBucketReview state={state} dispatch={dispatch} data={resource.data} supabaseUrl={supabaseUrl} canEdit={canEditCart} canIncrease={online && resource.status === "ready"} />}
    retail={state.shopping.retail} subtotal={subtotal} addresses={addresses} recipient={{ name: displayName, phoneNumber }} online={online} canEdit={canEditCart} accountUrl={accountUrl} addressManager={<ReimaginedAddressPicker key={`billing:${accessToken}`} resource={addresses} online={online} accountUrl={accountUrl} auth={props} onSessionExpired={onSessionExpired} compact />} onEditRecipient={() => dispatch({ type: "navigate", section: "profile" })}
    counter={<ReimaginedCheckoutCounter key={accessToken} checkout={checkout} draft={draft} enabled canEdit={canEditCart} online={online} dispatch={dispatch} onSessionExpired={onSessionExpired} ordersUrl={ordersUrl} onOpenOrders={openOrders} />} />;
  return <>
    <aside className="reimagined-local-notice" aria-label="Dastak interface recovery"><a href={homeUrl}>Use the existing Dastak interface</a></aside>
    {cartIssue ? <p role="status">{cartIssue}</p> : null}
    {tracking.storageIssue ? <p role="status">{tracking.storageIssue}</p> : null}
    {tracking.error && online ? <button type="button" onClick={tracking.retry}>Retry order status</button> : null}
    <ReimaginedShell state={{ ...state, activeOrder: tracking.activeOrder }} dispatch={dispatch} activeOrderLabel={tracking.label}
      directory={resource.data ? reimaginedDirectory(resource.data.map) : []}
      directoryStatus={resource.status} onRetryDirectory={resource.retry}
      displayName={displayName} greeting={greeting} locationLabel={online && addresses.selected ? addresses.selected.label : "Choose your location"}
      locationContent={addressPicker}
      onOpenWishlist={openWishlist} featureTitle={savedOpen ? "Wishlist" : workspaceTitle}
      onSignIn={onSessionExpired} onOpenActiveOrder={openOrders}
      shoppingTotalLabel={state.service === "grocery" && subtotal !== undefined ? `${formatV1Price(subtotal)} estimated` : undefined}
      searchSuggestions={state.service === "grocery" ? <ReimaginedGrocerySuggestions data={resource.data} query={state.exploration.grocery.searchDraft} dispatch={dispatch} /> : <ReimaginedFoodSuggestions menus={food.data} query={state.exploration.food.searchDraft} dispatch={dispatch} />}
      sectionContent={{
        [state.section]: state.section === "home" ? null : <Suspense fallback={<p role="status">Opening your {state.section}…</p>}>
          {reorderError ? <p role="alert">{reorderError}</p> : null}
          {mixedOrder ? <section aria-label="Rebuild mixed order"><h3>Rebuild this order as separate carts</h3><p>Choose which part to restore. The other cart is kept. Each service has its own checkout.</p><button type="button" disabled={!online || !canEditCart || reorderBusy} onClick={() => void requestReorder(mixedOrder, "grocery")}>Rebuild Grocery</button><button type="button" disabled={!online || !canEditCart || reorderBusy} onClick={() => void requestReorder(mixedOrder, "food")}>Rebuild Food</button><button type="button" disabled={reorderBusy} onClick={() => setMixedOrder(undefined)}>Keep current carts</button></section> : null}
          {reorderBusy ? <p role="status">Checking exact items and options…</p> : null}
          {reorder ? <section aria-label="Confirm cart replacement"><h3>Replace your current {reorder.service === "grocery" ? "Bucket" : "Food cart"}?</h3><p>The other service’s cart stays unchanged. Nothing is ordered until you complete checkout.</p><button type="button" onClick={() => setReorder(undefined)}>Keep current cart</button><button type="button" disabled={!online || !canEditCart} onClick={approveReorder}>Replace cart and review</button></section> : null}
          <AccountWorkspace key={`${state.section}:${selectedOrderId ?? ""}`} {...props} displayName={displayName} phoneNumber={phoneNumber} embedded accountPane={state.section === "profile" || state.section === "settings" ? state.section : undefined} onOpenProfile={() => dispatch({ type: "navigate", section: "profile" })} onOpenSettings={() => dispatch({ type: "navigate", section: "settings" })} onOpenOrders={openOrders} onOrderRecordClosed={() => setSelectedOrderId(undefined)} onViewChange={updateWorkspaceTitle} initialSection={state.section === "orders" ? "orders" : "account"} initialOrderId={state.section === "orders" ? selectedOrderId : undefined} onReturnToShopping={() => dispatch({ type: "navigate", section: "home" })} onOpenWishlist={openWishlist} onReorder={requestReorder} webPushController={webPush} onProfileChanged={setProfile} />
        </Suspense>,
      }}>
      {!online ? <p role="status">You’re offline. Your saved Bucket is retained; adding products is disabled until you reconnect.</p> : null}
      <p className="reimagined-commerce-note">Catalogue prices are estimates. Stock, delivery and final totals must be confirmed at checkout.</p>
      {wishlist.error ? <p role="alert">Your Wishlist couldn’t update. <button type="button" onClick={wishlist.retry}>Retry Wishlist</button></p> : null}
      {savedOpen ? <ReimaginedWishlist wishlist={wishlist} data={resource.data} menus={food.data} online={online} supabaseUrl={supabaseUrl} onClose={() => setSavedOpen(false)} onOpen={(skuId, branchId, itemId) => {
        dispatch({ type: "selectService", service: skuId ? "grocery" : "food" });
        if (branchId) dispatch({ type: "openRestaurant", branchId });
        if (skuId || itemId) dispatch({ type: "openDetail", id: (skuId ?? itemId)! });
      }} /> : state.service === "grocery" ? <ReimaginedGrocery state={state} dispatch={dispatch} data={resource.data} status={resource.status} wishlist={wishlist} online={online}
        onRetry={resource.retry} supabaseUrl={props.supabaseUrl}
        eligibility={() => ({
          canAdd: canEditCart && online && resource.status === "ready",
          canRemove: canEditCart,
          maximumQuantity: 99,
          reason: !canEditCart ? "This cart is read-only in this tab"
            : !online ? "Reconnect to add products"
              : resource.status !== "ready" ? "Wait for the catalogue to load before adding products" : undefined,
        })}
        checkoutContent={review} /> : <ReimaginedFood state={state} dispatch={dispatch} resource={food} supabaseUrl={props.supabaseUrl} online={online} legacyUrl={homeUrl} canEdit={canEditCart} wishlist={wishlist}
          checkoutContent={<><button type="button" onClick={() => dispatch({ type: "navigate", section: "profile" })}>Edit delivery recipient in Profile</button><ReimaginedFoodCheckout addressPicker={addressPicker} input={foodInput} counter={<ReimaginedFoodCounter key={accessToken} checkout={foodCheckout} input={foodInput} enabled dispatch={dispatch} onSessionExpired={onSessionExpired} ordersUrl={ordersUrl} onOpenOrders={openOrders} />} /></>} />}
    </ReimaginedShell>
    {webPush.shouldPrompt ? <WebNotificationOnboarding busy={webPush.status === "enabling"} onEnable={() => void webPush.enable()} onDismiss={webPush.dismiss} /> : null}
  </>;
}
