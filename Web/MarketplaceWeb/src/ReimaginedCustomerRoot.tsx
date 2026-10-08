import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatV1Price, submitV1Order, commitV1LaunchPayment, getV1Order } from "./dastakV1";
import type { DastakCustomerProps } from "./DastakCustomerView";
import { customerDataIssue } from "./customerDataState";
import { useCustomerSessionRecovery } from "./useCustomerSessionRecovery";
import { existingCustomerUrl } from "./reimaginedOptIn";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { ReimaginedBucketReview } from "./ReimaginedBucketReview";
import { ReimaginedGroceryBilling } from "./ReimaginedGroceryBilling";
import { grocerySubtotal } from "./reimaginedCatalogue";
import { usePersistedReimaginedState } from "./usePersistedReimaginedState";
import { useReimaginedCatalogue } from "./useReimaginedCatalogue";
import { useReimaginedGrocerySearch } from "./useReimaginedGrocerySearch";
import { useReimaginedAvailability } from "./useReimaginedAvailability";
import { areaCheckoutIssue, localGroceryEligibility } from "./reimaginedAvailability";
import { foodAcceptingOrders } from "./reimaginedFoodCatalogue";
import { useCustomerOnline } from "./useCustomerOnline";
import { useReimaginedAddresses } from "./useReimaginedAddresses";
import { useReimaginedActiveOrder } from "./useReimaginedActiveOrder";
import { useReimaginedFood } from "./useReimaginedFood";
import { ReimaginedFood, ReimaginedFoodSuggestions } from "./ReimaginedFood";
import { foodPanelTitle } from "./reimaginedFoodPanel";
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
import { useReimaginedNavigation, type ReimaginedNavigation } from "./useReimaginedNavigation";

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
  const [selectedOrderId, setSelectedOrderId] = useState<string>();
  const [selectedMerchantOrderId, setSelectedMerchantOrderId] = useState<string>();
  const [reorder, setReorder] = useState<ReturnType<typeof prepareReimaginedReorder>>();
  const [reorderError, setReorderError] = useState<string>();
  const [mixedOrder, setMixedOrder] = useState<V1Order>();
  const [reorderBusy, setReorderBusy] = useState(false);
  const reorderLock = useRef(false);
  const reorderContext = useRef("");
  const [profile, setProfile] = useState<AccountProfile>();
  const displayName = profile?.displayName ?? props.displayName;
  const phoneNumber = profile?.phoneNumber ?? props.phoneNumber;
  const dispatch = useCallback((action: ReimaginedAction) => { setSavedOpen(false); setWorkspaceTitle(undefined); if (action.type === "navigate") { setSelectedOrderId(undefined); setSelectedMerchantOrderId(undefined); } cartDispatch(action); }, [cartDispatch]);
  const updateWorkspaceTitle = useCallback((section: CustomerSection) => setWorkspaceTitle(section === "payments" ? "Payments" : undefined), []);
  const restoreNavigation = useCallback((navigation: ReimaginedNavigation) => {
    setSavedOpen(navigation.savedOpen); setWorkspaceTitle(navigation.payments ? "Payments" : undefined);
    setSelectedOrderId(navigation.orderId);
    setSelectedMerchantOrderId(navigation.merchantOrderId);
    cartDispatch({ type: "restoreNavigation", navigation });
  }, [cartDispatch]);
  const exploration = state.exploration[state.service];
  useReimaginedNavigation(props.accountId, { service: state.service, section: state.section, savedOpen, payments: workspaceTitle === "Payments",
    ...(state.section === "orders" && selectedOrderId ? { orderId: selectedOrderId } : {}),
    ...(state.section === "orders" && selectedMerchantOrderId ? { merchantOrderId: selectedMerchantOrderId } : {}),
    exploration: { view: exploration.view, searchOpen: exploration.searchOpen, checkout: exploration.checkout, ...(exploration.detailId ? { detailId: exploration.detailId } : {}) } }, restoreNavigation);
  const resource = useReimaginedCatalogue(props);
  const online = useCustomerOnline();
  const groceryExploration = state.exploration.grocery;
  const groceryQuery = groceryExploration.view.kind === "search" ? groceryExploration.view.query : "";
  const grocerySearch = useReimaginedGrocerySearch(props, groceryExploration.searchDraft, groceryQuery,
    groceryExploration.searchOpen, state.service === "grocery" && state.section === "home" && !groceryExploration.checkout, online);
  const groceryData = useMemo(() => {
    if (!resource.data) return undefined;
    const skus = new Map(resource.data.catalogue.skus.map(sku => [sku.id, sku]));
    for (const sku of grocerySearch.facts ?? []) if (!skus.has(sku.id)) skus.set(sku.id, sku);
    for (const sku of grocerySearch.results ?? []) skus.set(sku.id, sku);
    for (const sku of grocerySearch.suggestions ?? []) if (!skus.has(sku.id) || groceryExploration.detailId === sku.id) skus.set(sku.id, sku);
    return { ...resource.data, catalogue: { ...resource.data.catalogue, skus: [...skus.values()] } };
  }, [resource.data, grocerySearch.facts, grocerySearch.results, grocerySearch.suggestions, groceryExploration.detailId]);
  const wishlist = useReimaginedWishlist(props, online);
  const { accountId, accessToken, supabaseUrl, publishableKey } = props;
  const checkout = useMemo(() => new ReimaginedGroceryCheckout({ accessToken, supabaseUrl, publishableKey }, undefined, undefined, undefined, checkoutJournal(accountId, supabaseUrl)), [accountId, accessToken, supabaseUrl, publishableKey]);
  const foodCheckout = useMemo(() => new ReimaginedFoodRecovery({ accessToken, supabaseUrl, publishableKey }, { submit: submitV1Order, commit: commitV1LaunchPayment, read: getV1Order }, foodRecoveryJournal(accountId, supabaseUrl, { getItem: key => window.localStorage.getItem(key), setItem: (key, value) => window.localStorage.setItem(key, value) })), [accountId, accessToken, supabaseUrl, publishableKey]);
  const foodEnabled = state.service === "food" || savedOpen || state.section === "orders";
  const addresses = useReimaginedAddresses(props, online);
  const tracking = useReimaginedActiveOrder(props, state.activeOrder, online);
  const foodView = state.exploration.food.view;
  const foodQuery = foodView.kind === "search" && !state.exploration.food.checkout && state.section === "home" ? foodView.query : "";
  const foodLocation = addresses.selected ? { addressId: addresses.selected.addressId, updatedAt: addresses.selected.updatedAt } : undefined;
  const availability = useReimaginedAvailability(props, foodLocation, online);
  reorderContext.current = JSON.stringify([props.accountId, props.accessToken, state.section, state.shopping, online, canEditCart, foodLocation, availability.data?.checkedAt]);
  const foodResource = useReimaginedFood(props, foodEnabled && Boolean(foodLocation), online, undefined, foodQuery, foodLocation);
  const localMenu = (menu: NonNullable<typeof foodResource.data>[number]) => {
    const accepting = availability.data?.restaurants[menu.restaurant.branchId] === true;
    return { ...menu, restaurant: { ...menu.restaurant, acceptingOrders: accepting,
      isOpen: accepting, branchStatus: accepting ? "ACTIVE" : menu.restaurant.branchStatus } };
  };
  const locallyListed = (menu: NonNullable<typeof foodResource.data>[number]) => !availability.data || Object.hasOwn(availability.data.restaurants, menu.restaurant.branchId);
  const food = { ...foodResource, data: foodResource.data?.filter(locallyListed).map(localMenu), searchData: foodResource.searchData?.filter(locallyListed).map(localMenu),
    findRestaurant: async (id: string) => { const menu = await foodResource.findRestaurant?.(id); return menu && locallyListed(menu) ? localMenu(menu) : undefined; } };
  const groceryEligibility = (sku: { id: string }) => localGroceryEligibility(sku.id, availability.data, online, canEditCart, Boolean(foodLocation));
  const deliveryIssue = areaCheckoutIssue(availability.data, Boolean(foodLocation));
  const groceryIssue = areaCheckoutIssue(availability.data, Boolean(foodLocation), state.shopping.retail);
  const areaNotice = (service: "grocery" | "food") => <section role="status">
    <p>{!foodLocation ? "Choose your delivery location to see what’s available nearby." : availability.status === "unavailable" ? "Couldn’t check availability in your area. Your carts are saved." : availability.status !== "ready" ? "Checking availability in your area…" : service === "grocery" ? "Grocery delivery isn’t available in your area yet." : "Food delivery isn’t available in your area yet"}</p>
    <button type="button" onClick={() => dispatch({ type: "openLocation" })}>Change location</button>
    {foodLocation ? <button type="button" disabled={!online} onClick={availability.retry}>Check availability again</button> : null}
  </section>;
  const pushAuth = useMemo(() => ({ accountId, accessToken, supabaseUrl, publishableKey, publicKey: props.webPushPublicKey }), [accountId, accessToken, supabaseUrl, publishableKey, props.webPushPublicKey]);
  const webPush = useDastakWebPush(pushAuth);
  const onSessionExpired = useCustomerSessionRecovery(props.client, accessToken);
  useEffect(() => {
    if ([resource.error, grocerySearch.error, addresses.error, tracking.error, food.error, wishlist.error, availability.error].some(error => error && customerDataIssue(error).action === "sign_in")) onSessionExpired();
  }, [resource.error, grocerySearch.error, addresses.error, tracking.error, food.error, wishlist.error, availability.error, onSessionExpired]);
  const homeUrl = existingCustomerUrl("home", window.location.href);
  const accountUrl = existingCustomerUrl("account", window.location.href);
  const ordersUrl = existingCustomerUrl("orders", window.location.href);
  const subtotal = grocerySubtotal(state, groceryData);
  const addressPicker = <ReimaginedAddressPicker key={`location:${accessToken}`} resource={addresses} online={online} accountUrl={accountUrl} auth={props} onSessionExpired={onSessionExpired} />;
  const openWishlist = () => { dispatch({ type: "navigate", section: "home" }); setSavedOpen(true); };
  const openOrders = (id?: string) => { dispatch({ type: "navigate", section: "orders" }); setSelectedOrderId(id); };
  const openMerchantOrder = (id: string) => { dispatch({ type: "navigate", section: "orders" }); setSelectedMerchantOrderId(id); };
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
      const next = prepareReimaginedReorder(order, groceryData, menus, selectedService);
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
    if (reorder.service === "grocery" && Object.entries(reorder.shopping.retail).some(([id, quantity]) => {
      const policy = groceryEligibility({ id }); return !policy.canAdd || quantity > policy.maximumQuantity;
    })) { setReorderError("Some exact packs are out of stock in your area. Your current carts are unchanged."); return; }
    if (reorder.service === "food" && reorder.shopping.food.some(line => availability.data?.restaurants[line.branchId] !== true)) {
      setReorderError("Store closed. Your current carts are unchanged."); return;
    }
    const controller = reorder.service === "grocery" ? checkout : foodCheckout;
    if (controller.hasPendingAttempt && !controller.committed) { setReorderError("Recover your pending checkout before replacing this cart."); return; }
    dispatch({ type: "replaceServiceShopping", ...reorder }); setReorder(undefined);
  }
  const foodInput = { food: state.shopping.food, menus: food.data, online, canEdit: canEditCart, address: addresses.selected, addressesReady: addresses.status === "ready", recipient: { name: displayName, phoneNumber } };
  const draft = subtotal !== undefined && addresses.status === "ready" && addresses.selected && displayName?.trim() && phoneNumber?.trim()
    ? { retail: state.shopping.retail, address: addresses.selected, recipient: { name: displayName, phoneNumber } } : undefined;
  const review = <ReimaginedGroceryBilling items={<ReimaginedBucketReview state={state} dispatch={dispatch} data={groceryData} supabaseUrl={supabaseUrl} canEdit={canEditCart} eligibility={groceryEligibility} />}
    retail={state.shopping.retail} subtotal={subtotal} addresses={addresses} recipient={{ name: displayName, phoneNumber }} online={online} canEdit={canEditCart} accountUrl={accountUrl} addressManager={<ReimaginedAddressPicker key={`billing:${accessToken}`} resource={addresses} online={online} accountUrl={accountUrl} auth={props} onSessionExpired={onSessionExpired} compact />} onEditRecipient={() => dispatch({ type: "navigate", section: "profile" })}
    counter={<ReimaginedCheckoutCounter key={accessToken} checkout={checkout} draft={draft} enabled submissionIssue={groceryIssue} deliveryIssue={deliveryIssue} canEdit={canEditCart} online={online} dispatch={dispatch} onSessionExpired={onSessionExpired} ordersUrl={ordersUrl} onOpenOrders={openOrders} />} />;
  return <>
    <aside className="reimagined-local-notice" aria-label="Dastak interface recovery"><a href={homeUrl}>Use the existing Dastak interface</a></aside>
    <ReimaginedShell state={{ ...state, activeOrder: tracking.activeOrder }} dispatch={dispatch} activeOrderLabel={tracking.label}
      noticeContent={(state.section === "home" && cartIssue) || tracking.storageIssue || (tracking.error && online) ? <div className="reimagined-status-stack">
        {state.section === "home" && cartIssue ? <p role="status">{cartIssue}</p> : null}
        {tracking.storageIssue ? <p role="status">{tracking.storageIssue}</p> : null}
        {tracking.error && online ? <button type="button" onClick={tracking.retry}>Retry order status</button> : null}
      </div> : null}
      directory={resource.data ? reimaginedDirectory(resource.data.map) : []}
      directoryStatus={resource.status} onRetryDirectory={resource.retry}
      displayName={displayName} greeting={greeting} locationLabel={online && addresses.selected ? addresses.selected.label : "Choose your location"}
      locationContent={addressPicker}
      onOpenWishlist={openWishlist} featureTitle={savedOpen ? "Your Wishlist" : workspaceTitle ?? (state.section === "home" && state.service === "food" ? foodPanelTitle(state, food.data) : undefined)}
      onSignIn={onSessionExpired} onOpenActiveOrder={id => {
        if (tracking.activeCount > 1) openOrders();
        else if (tracking.activeOrder?.kind === "merchant") openMerchantOrder(id);
        else openOrders(id);
      }}
      shoppingTotalLabel={state.service === "grocery" && subtotal !== undefined ? `${formatV1Price(subtotal)} estimated` : undefined}
      searchSuggestions={state.service === "grocery" ? <><ReimaginedGrocerySuggestions data={groceryData} results={grocerySearch.suggestions} query={groceryExploration.searchDraft} dispatch={dispatch} />{grocerySearch.loading ? <p role="status">Searching the catalogue…</p> : null}{grocerySearch.error ? <p role="alert">Couldn’t check catalogue search. <button type="button" disabled={!online} onClick={() => grocerySearch.retry()}>Retry search</button></p> : null}</> : <ReimaginedFoodSuggestions menus={food.data} query={state.exploration.food.searchDraft} dispatch={dispatch} />}
      sectionContent={{
        [state.section]: state.section === "home" ? null : <Suspense fallback={<p role="status">Opening your {state.section}…</p>}>
          {reorderError ? <p role="alert">{reorderError}</p> : null}
          {mixedOrder ? <section aria-label="Rebuild mixed order"><h3>Rebuild this order as separate carts</h3><p>Choose which part to restore. The other cart is kept. Each service has its own checkout.</p><button type="button" disabled={!online || !canEditCart || reorderBusy} onClick={() => void requestReorder(mixedOrder, "grocery")}>Rebuild Grocery</button><button type="button" disabled={!online || !canEditCart || reorderBusy} onClick={() => void requestReorder(mixedOrder, "food")}>Rebuild Food</button><button type="button" disabled={reorderBusy} onClick={() => setMixedOrder(undefined)}>Keep current carts</button></section> : null}
          {reorderBusy ? <p role="status">Checking exact items and options…</p> : null}
          {reorder ? <section aria-label="Confirm cart replacement"><h3>Replace your current {reorder.service === "grocery" ? "Bucket" : "Food cart"}?</h3><p>The other service’s cart stays unchanged. Nothing is ordered until you complete checkout.</p><button type="button" onClick={() => setReorder(undefined)}>Keep current cart</button><button type="button" disabled={!online || !canEditCart} onClick={approveReorder}>Replace cart and review</button></section> : null}
          <AccountWorkspace key={`${state.section}:${workspaceTitle ?? ""}:${selectedOrderId ?? ""}:${selectedMerchantOrderId ?? ""}`} {...props} displayName={displayName} phoneNumber={phoneNumber} embedded accountPane={state.section === "profile" || state.section === "settings" ? state.section : undefined} onOpenProfile={() => dispatch({ type: "navigate", section: "profile" })} onOpenSettings={() => dispatch({ type: "navigate", section: "settings" })} onOpenPayments={() => { dispatch({ type: "navigate", section: "orders" }); setWorkspaceTitle("Payments"); }} onOpenOrders={openOrders} onOpenMerchantOrder={openMerchantOrder} onOrderRecordClosed={() => { setSelectedOrderId(undefined); setSelectedMerchantOrderId(undefined); }} onViewChange={updateWorkspaceTitle} initialSection={workspaceTitle === "Payments" ? "payments" : state.section === "orders" ? "orders" : "account"} initialOrderId={state.section === "orders" ? selectedOrderId : undefined} initialMerchantOrderId={state.section === "orders" ? selectedMerchantOrderId : undefined} onReturnToShopping={() => dispatch({ type: "navigate", section: "home" })} onOpenWishlist={openWishlist} onReorder={requestReorder} webPushController={webPush} onProfileChanged={setProfile} />
        </Suspense>,
      }}>
      {!online ? <p role="status">You’re offline. Your saved Bucket is retained; adding products is disabled until you reconnect.</p> : null}
      <p className="reimagined-commerce-note">Catalogue prices are estimates. Stock, delivery and final totals must be confirmed at checkout.</p>
      {resource.data && resource.error ? <p role="alert">Couldn’t refresh the catalogue. Your previous shelves and cart are retained. <button type="button" disabled={!online || resource.refreshing} onClick={resource.retry}>Retry catalogue refresh</button></p> : null}
      {availability.data && !availability.data.deliveryAvailable ? <p role="status">No delivery partners are available in your area right now. You can keep adding available items to your cart and order later.</p> : null}
      {wishlist.error ? <p role="alert">Your Wishlist couldn’t update. <button type="button" onClick={wishlist.retry}>Retry Wishlist</button></p> : null}
      {savedOpen ? <ReimaginedWishlist headingOwnedByShell wishlist={wishlist} data={resource.data} menus={food.data} online={online} supabaseUrl={supabaseUrl} onClose={() => setSavedOpen(false)} onOpen={(skuId, branchId, itemId) => {
        if (branchId && !food.data?.some(menu => menu.restaurant.branchId === branchId && foodAcceptingOrders(menu))) return;
        dispatch({ type: "selectService", service: skuId ? "grocery" : "food" });
        if (branchId) dispatch({ type: "openRestaurant", branchId });
        if (skuId || itemId) dispatch({ type: "openDetail", id: (skuId ?? itemId)! });
      }} /> : state.service === "grocery" ? <ReimaginedGrocery state={state} dispatch={dispatch} data={groceryExploration.view.kind === "search" || groceryExploration.detailId ? groceryData : resource.data} status={resource.status} wishlist={wishlist} online={online}
        searchResults={grocerySearch.results} searchLoading={grocerySearch.resultsLoading} searchError={grocerySearch.resultsError} onRetrySearch={() => { dispatch({ type: "closeSearch" }); grocerySearch.retry(groceryQuery); }}
        availabilityNotice={!availability.data?.groceryServiceable ? areaNotice("grocery") : undefined}
        onRetry={resource.retry} supabaseUrl={props.supabaseUrl}
        eligibility={groceryEligibility}
        checkoutContent={review} /> : <ReimaginedFood state={state} dispatch={dispatch} resource={food} supabaseUrl={props.supabaseUrl} online={online} legacyUrl={homeUrl} canEdit={canEditCart} wishlist={wishlist} headingOwnedByShell
          availabilityNotice={!availability.data?.foodServiceable ? areaNotice("food") : undefined}
          checkoutContent={<><button type="button" onClick={() => dispatch({ type: "navigate", section: "profile" })}>Edit delivery recipient in Profile</button><ReimaginedFoodCheckout addressPicker={addressPicker} input={foodInput} counter={<ReimaginedFoodCounter key={accessToken} checkout={foodCheckout} input={foodInput} enabled deliveryIssue={deliveryIssue} dispatch={dispatch} onSessionExpired={onSessionExpired} ordersUrl={ordersUrl} onOpenOrders={openOrders} />} /></>} />}
    </ReimaginedShell>
    {webPush.shouldPrompt ? <WebNotificationOnboarding busy={webPush.status === "enabling"} onEnable={() => void webPush.enable()} onDismiss={webPush.dismiss} /> : null}
  </>;
}
