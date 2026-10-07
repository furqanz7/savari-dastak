import { lazy, Suspense, useEffect, useMemo, useState } from "react";
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

type Props = DastakCustomerProps;
const AccountWorkspace = lazy(() => import("./DastakCustomerView").then(module => ({ default: module.ExistingDastakCustomerView })));

// Key the entire session boundary: no cart or async response survives an account switch.
export function ReimaginedCustomerRoot(props: Props) {
  return <AccountExperience key={props.accountId} {...props} />;
}

function AccountExperience(props: Props) {
  const { state, dispatch, cartIssue, canEditCart } = usePersistedReimaginedState(props.accountId);
  const [entry] = useState(() => parseCustomerDestination(window.location.hash));
  const [selectedOrderId, setSelectedOrderId] = useState(entry.entityType === "dastakV1Order" ? entry.entityId : undefined);
  useEffect(() => {
    if (entry.section === "orders" || entry.section === "account") dispatch({ type: "navigate", section: entry.section === "orders" ? "orders" : "profile" });
    // Restore a notification/deep link once; subsequent navigation belongs to this panel.
  }, [entry, dispatch]);
  const resource = useReimaginedCatalogue(props);
  const online = useCustomerOnline();
  const { accountId, accessToken, supabaseUrl, publishableKey } = props;
  const checkout = useMemo(() => new ReimaginedGroceryCheckout({ accessToken, supabaseUrl, publishableKey }, undefined, undefined, undefined, checkoutJournal(accountId, supabaseUrl)), [accountId, accessToken, supabaseUrl, publishableKey]);
  const foodCheckout = useMemo(() => new ReimaginedFoodRecovery({ accessToken, supabaseUrl, publishableKey }, { submit: submitV1Order, commit: commitV1LaunchPayment, read: getV1Order }, foodRecoveryJournal(accountId, supabaseUrl, { getItem: key => window.localStorage.getItem(key), setItem: (key, value) => window.localStorage.setItem(key, value) })), [accountId, accessToken, supabaseUrl, publishableKey]);
  const addresses = useReimaginedAddresses(props, online && (state.locationOpen || (state.service === "grocery" ? state.exploration.grocery.checkout : state.exploration.food.checkout)));
  const tracking = useReimaginedActiveOrder(props, state.activeOrder, online);
  const food = useReimaginedFood(props, state.service === "food", online);
  const onSessionExpired = props.onSignOut;
  useEffect(() => {
    if ([resource.error, addresses.error, tracking.error, food.error].some(error => error && customerDataIssue(error).action === "sign_in")) onSessionExpired();
  }, [resource.error, addresses.error, tracking.error, food.error, onSessionExpired]);
  const homeUrl = existingCustomerUrl("home", window.location.href);
  const accountUrl = existingCustomerUrl("account", window.location.href);
  const ordersUrl = existingCustomerUrl("orders", window.location.href);
  const subtotal = grocerySubtotal(state, resource.data);
  const addressPicker = <ReimaginedAddressPicker resource={addresses} online={online} accountUrl={accountUrl} />;
  const foodInput = { food: state.shopping.food, menus: food.data, online, canEdit: canEditCart, address: addresses.selected, addressesReady: addresses.status === "ready", recipient: { name: props.displayName, phoneNumber: props.phoneNumber } };
  const draft = subtotal !== undefined && addresses.status === "ready" && addresses.selected && props.displayName?.trim() && props.phoneNumber?.trim()
    ? { retail: state.shopping.retail, address: addresses.selected, recipient: { name: props.displayName, phoneNumber: props.phoneNumber } } : undefined;
  const review = <ReimaginedGroceryBilling items={<ReimaginedBucketReview state={state} dispatch={dispatch} data={resource.data} supabaseUrl={supabaseUrl} canEdit={canEditCart} canIncrease={online && resource.status === "ready"} />}
    retail={state.shopping.retail} subtotal={subtotal} addresses={addresses} recipient={{ name: props.displayName, phoneNumber: props.phoneNumber }} online={online} canEdit={canEditCart} accountUrl={accountUrl}
    counter={<ReimaginedCheckoutCounter key={accessToken} checkout={checkout} draft={draft} enabled canEdit={canEditCart} online={online} dispatch={dispatch} onSessionExpired={onSessionExpired} ordersUrl={ordersUrl} />} />;
  return <>
    <aside className="reimagined-local-notice" aria-label="Dastak interface recovery"><a href={homeUrl}>Use the existing Dastak interface</a></aside>
    {cartIssue ? <p role="status">{cartIssue}</p> : null}
    {tracking.storageIssue ? <p role="status">{tracking.storageIssue}</p> : null}
    {tracking.error && online ? <button type="button" onClick={tracking.retry}>Retry order status</button> : null}
    <ReimaginedShell state={{ ...state, activeOrder: tracking.activeOrder }} dispatch={dispatch} activeOrderLabel={tracking.label}
      directory={resource.data ? reimaginedDirectory(resource.data.map) : []}
      directoryStatus={resource.status} onRetryDirectory={resource.retry}
      displayName={props.displayName} greeting="Welcome" locationLabel={online && addresses.selected ? addresses.selected.label : "Choose your location"}
      locationContent={addressPicker}
      onSignIn={onSessionExpired} onOpenActiveOrder={id => { setSelectedOrderId(id); dispatch({ type: "navigate", section: "orders" }); }}
      shoppingTotalLabel={state.service === "grocery" && subtotal !== undefined ? `${formatV1Price(subtotal)} estimated` : undefined}
      searchSuggestions={state.service === "grocery" ? <ReimaginedGrocerySuggestions data={resource.data} query={state.exploration.grocery.searchDraft} dispatch={dispatch} /> : <ReimaginedFoodSuggestions menus={food.data} query={state.exploration.food.searchDraft} dispatch={dispatch} />}
      sectionContent={{
        [state.section]: state.section === "home" ? null : <Suspense fallback={<p role="status">Opening your {state.section}…</p>}>
          <AccountWorkspace key={`${state.section}:${selectedOrderId ?? ""}`} {...props} embedded initialSection={state.section === "orders" ? "orders" : "account"} initialOrderId={state.section === "orders" ? selectedOrderId : undefined} onReturnToShopping={() => dispatch({ type: "navigate", section: "home" })} />
        </Suspense>,
      }}>
      {!online ? <p role="status">You’re offline. Your saved Bucket is retained; adding products is disabled until you reconnect.</p> : null}
      <p className="reimagined-commerce-note">Catalogue prices are estimates. Stock, delivery and final totals must be confirmed at checkout.</p>
      {state.service === "grocery" ? <ReimaginedGrocery state={state} dispatch={dispatch} data={resource.data} status={resource.status}
        onRetry={resource.retry} supabaseUrl={props.supabaseUrl}
        eligibility={() => ({
          canAdd: canEditCart && online && resource.status === "ready",
          canRemove: canEditCart,
          maximumQuantity: 99,
          reason: !canEditCart ? "This cart is read-only in this tab"
            : !online ? "Reconnect to add products"
              : resource.status !== "ready" ? "Wait for the catalogue to load before adding products" : undefined,
        })}
        checkoutContent={review} /> : <ReimaginedFood state={state} dispatch={dispatch} resource={food} supabaseUrl={props.supabaseUrl} online={online} legacyUrl={homeUrl} canEdit={canEditCart}
          checkoutContent={<ReimaginedFoodCheckout addressPicker={addressPicker} input={foodInput} counter={<ReimaginedFoodCounter key={accessToken} checkout={foodCheckout} input={foodInput} enabled dispatch={dispatch} onSessionExpired={onSessionExpired} ordersUrl={ordersUrl} />} />} />}
    </ReimaginedShell>
  </>;
}
