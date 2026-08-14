import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import {
  ArrowLeft,
  Bell,
  Bike,
  ChevronRight,
  CircleHelp,
  CreditCard,
  Globe2,
  Hand,
  ImageOff,
  LocateFixed,
  LogOut,
  MapPin,
  Minus,
  PackageOpen,
  Plus,
  Phone,
  ReceiptText,
  RefreshCw,
  Search,
  ShieldAlert,
  ShoppingBag,
  Store,
  Trash2,
  UserRound,
  X,
} from "lucide-react";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { AccountActionDialog } from "./AccountActionDialog";
import { deleteAccount, updateAccountProfile, type AccountProfile } from "./accountProfile";
import {
  browseCatalogue,
  catalogueImageUrl,
  CatalogueRequestError,
  formatPrice,
  groupCatalogue,
  type CatalogueLocation,
  type CatalogueProduct,
  type GroupedCatalogueStore,
} from "./catalogue";
import {
  cancelMerchantOrder,
  createMerchantOrder,
  formatDeliveryDistance,
  getCustomerOrders,
  quoteMerchantOrder,
  type MerchantOrderQuote,
  type MerchantOrderSnapshot,
} from "./orders";
import {
  createCheckoutSession,
  openRazorpayCheckout,
  processOrderRefund,
} from "./payments";
import {
  cartReducer,
  createEmptyCart,
  MAX_CART_PRODUCT_QUANTITY,
  summarizeCart,
  type CartEntries,
} from "./cart";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import { customerDataIssue, type CustomerDataIssue } from "./customerDataState";
import type { CustomerSection } from "./customerNavigation";
import {
  getCustomerAddresses,
  saveDefaultCustomerAddress,
  type CustomerDeliveryAddress,
} from "./customerAddresses";
import { CustomerAddressSheet, type CustomerAddressDraft } from "./CustomerAddressSheet";
import { CancellationSheet, CustomerRouteMap, CustomerTimeline } from "./CustomerDeliveryDetails";
import { merchantOrderPresentation, paymentStateLabel } from "./customerLifecycle";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  section: CustomerSection;
  selectedOrderId?: string;
  onNavigate: (section: CustomerSection) => void;
  onOpenOrder: (orderId: string) => void;
  onCloseOrder: () => void;
  onOpenParcel: () => void;
  onSignOut: () => void;
};

type SelectedLocation = { label: string; coordinates: CatalogueLocation };
type CustomerDiscoveryPreference = {
  version: 1;
  location?: SelectedLocation;
  radiusKm: number;
};

const customerDiscoveryStorageKey = "dastak.customer.discovery.v1";

function savedCustomerDiscovery(): CustomerDiscoveryPreference {
  if (typeof window === "undefined") return { version: 1, radiusKm: 10 };
  try {
    const parsed: unknown = JSON.parse(window.localStorage.getItem(customerDiscoveryStorageKey) ?? "null");
    if (!parsed || typeof parsed !== "object") return { version: 1, radiusKm: 10 };
    const value = parsed as Partial<CustomerDiscoveryPreference>;
    const radiusKm = typeof value.radiusKm === "number" && [10, 15, 20, 25, 30].includes(value.radiusKm)
      ? value.radiusKm
      : 10;
    const location = value.location;
    if (!location || typeof location.label !== "string" ||
      typeof location.coordinates?.latitude !== "number" || typeof location.coordinates?.longitude !== "number") {
      return { version: 1, radiusKm };
    }
    return { version: 1, radiusKm, location };
  } catch {
    return { version: 1, radiusKm: 10 };
  }
}

function saveCustomerDiscovery(location: SelectedLocation | undefined, radiusKm: number) {
  try {
    window.localStorage.setItem(customerDiscoveryStorageKey, JSON.stringify({ version: 1, location, radiusKm }));
  } catch {
    // Storage can be unavailable in private browsing; the current session still works.
  }
}

type CatalogueState =
  | { phase: "idle" }
  | { phase: "loading" }
  | { phase: "ready"; stores: GroupedCatalogueStore[] }
  | { phase: "error"; code: string; message: string };
export function CatalogueView({
  accessToken,
  displayName,
  email,
  phoneNumber,
  supabaseUrl,
  publishableKey,
  section,
  selectedOrderId,
  onNavigate,
  onOpenOrder,
  onCloseOrder,
  onOpenParcel,
  onSignOut,
}: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [initialDiscovery] = useState(savedCustomerDiscovery);
  const [selectedLocation, setSelectedLocation] = useState<SelectedLocation | undefined>(initialDiscovery.location);
  const [discoveryRadiusKm, setDiscoveryRadiusKm] = useState(initialDiscovery.radiusKm);
  const [state, setState] = useState<CatalogueState>({ phase: "idle" });
  const [cartState, dispatchCart] = useReducer(cartReducer, undefined, createEmptyCart);
  const [quote, setQuote] = useState<MerchantOrderQuote>();
  const [orders, setOrders] = useState<MerchantOrderSnapshot[]>([]);
  const [ordersLoading, setOrdersLoading] = useState(true);
  const [orderBusy, setOrderBusy] = useState(false);
  const [orderError, setOrderError] = useState<string>();
  const [ordersRefreshIssue, setOrdersRefreshIssue] = useState<CustomerDataIssue>();
  const [paymentMessage, setPaymentMessage] = useState<string>();
  const [deliveryAddress, setDeliveryAddress] = useState<CustomerDeliveryAddress>();
  const [addressLoading, setAddressLoading] = useState(true);
  const [addressEditorOpen, setAddressEditorOpen] = useState(false);
  const [addressError, setAddressError] = useState<string>();
  const [reviewAfterAddress, setReviewAfterAddress] = useState(false);
  const [accountProfile, setAccountProfile] = useState<AccountProfile>({
    displayName: displayName ?? "",
    phoneNumber: phoneNumber ?? "",
  });
  const [profileEditorOpen, setProfileEditorOpen] = useState(false);
  const [profileBusy, setProfileBusy] = useState(false);
  const [profileError, setProfileError] = useState<string>();
  const [showSignOutConfirmation, setShowSignOutConfirmation] = useState(false);
  const [showDeleteConfirmation, setShowDeleteConfirmation] = useState(false);
  const [cancellingOrder, setCancellingOrder] = useState<MerchantOrderSnapshot>();
  const [searchQuery, setSearchQuery] = useState("");
  const catalogueRequest = useRef(0);
  const orderCreationRequest = useRef<{ quoteId: string; idempotencyKey: string } | undefined>(undefined);
  const restoredDiscovery = useRef(false);
  const ordersRefreshInFlight = useRef(false);
  const addressSaveRequest = useRef<string | undefined>(undefined);

  useEffect(() => {
    saveCustomerDiscovery(selectedLocation, discoveryRadiusKm);
  }, [selectedLocation, discoveryRadiusKm]);

  const refreshOrders = useCallback(async () => {
    if (ordersRefreshInFlight.current) return;
    ordersRefreshInFlight.current = true;
    try {
      const snapshot = await getCustomerOrders(auth);
      setOrders(snapshot.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt)));
      setOrdersRefreshIssue(undefined);
    } catch (error) {
      setOrdersRefreshIssue(customerDataIssue(error));
    } finally {
      setOrdersLoading(false);
      ordersRefreshInFlight.current = false;
    }
  }, [auth]);

  useEffect(() => {
    void refreshOrders();
  }, [refreshOrders]);

  const hasActiveOrders = orders.some((order) => !isFinalOrder(order));

  useEffect(() => {
    if (!hasActiveOrders || ordersRefreshIssue?.kind === "session") return;
    const interval = window.setInterval(() => void refreshOrders(), 10_000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void refreshOrders();
    };
    const onOnline = () => void refreshOrders();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onOnline);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onOnline);
    };
  }, [hasActiveOrders, ordersRefreshIssue?.kind, refreshOrders]);

  const load = useCallback(async (location: SelectedLocation, radiusKm: number) => {
    const requestId = ++catalogueRequest.current;
    setSelectedLocation(location);
    setQuote(undefined);
    orderCreationRequest.current = undefined;
    setState({ phase: "loading" });
    try {
      const snapshot = await browseCatalogue({
        ...auth,
        location: location.coordinates,
        discoveryRadiusKm: radiusKm,
      });
      if (requestId !== catalogueRequest.current) return;
      setState({ phase: "ready", stores: groupCatalogue(snapshot) });
    } catch (error) {
      if (requestId !== catalogueRequest.current) return;
      const requestError = error instanceof CatalogueRequestError
        ? error
        : new CatalogueRequestError("catalogue_unavailable", "The catalogue is unavailable right now.", 0);
      setState({ phase: "error", code: requestError.code, message: requestError.message });
    }
  }, [auth]);

  useEffect(() => {
    if (restoredDiscovery.current || !selectedLocation) return;
    restoredDiscovery.current = true;
    void load(selectedLocation, discoveryRadiusKm);
  }, [discoveryRadiusKm, load, selectedLocation]);

  useEffect(() => {
    let active = true;
    void getCustomerAddresses(auth).then((snapshot) => {
      if (!active) return;
      const saved = snapshot.addresses.find((address) => address.isDefault) ?? snapshot.addresses[0];
      setDeliveryAddress(saved);
      setAddressError(undefined);
      if (saved) {
        void load({ label: saved.displayAddress, coordinates: saved.location }, initialDiscovery.radiusKm);
      } else {
        setAddressEditorOpen(true);
      }
    }).catch((error) => {
      if (active) {
        setAddressError(orderMessage(error));
        setAddressEditorOpen(true);
      }
    }).finally(() => {
      if (active) setAddressLoading(false);
    });
    return () => { active = false; };
  }, [auth, initialDiscovery.radiusKm, load]);

  const useCurrentLocation = () => {
    if (!navigator.geolocation) {
      setState({ phase: "error", code: "location_unavailable", message: "This browser cannot provide your location." });
      return;
    }
    setState({ phase: "loading" });
    navigator.geolocation.getCurrentPosition(
      (position) => void load({
        label: "Current location",
        coordinates: { latitude: position.coords.latitude, longitude: position.coords.longitude },
      }, discoveryRadiusKm),
      () => setState({
        phase: "error",
        code: "location_denied",
        message: "Location access was not allowed. Enable location access to browse nearby stores.",
      }),
      { enableHighAccuracy: true, timeout: 12_000, maximumAge: 60_000 },
    );
  };

  const changeDiscoveryRadius = (deltaKm: number) => {
    const nextRadius = Math.min(30, Math.max(10, discoveryRadiusKm + deltaKm));
    setDiscoveryRadiusKm(nextRadius);
    if (selectedLocation) void load(selectedLocation, nextRadius);
  };

  const cart = cartState.entries;
  const cartSummary = summarizeCart(cart);
  const cartEntries = cartSummary.items;
  const cartStoreId = cartSummary.storeId;
  const visibleStores = useMemo(
    () => filterCatalogueStores(state.phase === "ready" ? state.stores : [], section === "search" ? searchQuery : ""),
    [searchQuery, section, state],
  );

  const chooseLocation = (place: SelectedPlace) => {
    void load({
      label: place.address,
      coordinates: { latitude: place.latitude, longitude: place.longitude },
    }, discoveryRadiusKm);
  };

  const changeQuantity = (store: GroupedCatalogueStore, product: CatalogueProduct, delta: -1 | 1) => {
    setOrderError(undefined);
    setQuote(undefined);
    orderCreationRequest.current = undefined;
    dispatchCart({
      type: "changeQuantity",
      store: { storeId: store.storeId, name: store.name },
      product,
      delta,
    });
  };

  const clearCart = () => {
    dispatchCart({ type: "clear" });
    setQuote(undefined);
    orderCreationRequest.current = undefined;
    setOrderError(undefined);
  };

  const requestOrderQuote = async (location: SelectedLocation) => {
    if (!cartStoreId || cartEntries.length === 0) return;
    setOrderBusy(true);
    setOrderError(undefined);
    try {
      const nextQuote = await quoteMerchantOrder({
        ...auth,
        storeId: cartStoreId,
        lines: cartEntries.map((entry) => ({ productId: entry.product.productId, quantity: entry.quantity })),
        dropoff: location.coordinates,
        idempotencyKey: crypto.randomUUID(),
      });
      setQuote(nextQuote);
      orderCreationRequest.current = {
        quoteId: nextQuote.quoteId,
        idempotencyKey: crypto.randomUUID(),
      };
    } catch (error) {
      setOrderError(orderMessage(error));
    } finally {
      setOrderBusy(false);
    }
  };

  const reviewOrder = () => {
    if (!selectedLocation || !cartStoreId || cartEntries.length === 0 || addressLoading) return;
    if (!deliveryAddress || !sameLocation(deliveryAddress.location, selectedLocation.coordinates)) {
      setReviewAfterAddress(true);
      setAddressEditorOpen(true);
      return;
    }
    void requestOrderQuote(selectedLocation);
  };

  const saveAddress = async (draft: CustomerAddressDraft) => {
    setOrderBusy(true);
    setAddressError(undefined);
    try {
      addressSaveRequest.current ??= crypto.randomUUID();
      const snapshot = await saveDefaultCustomerAddress({
        ...auth,
        label: draft.label,
        address: draft.place.address,
        details: draft.details,
        location: { latitude: draft.place.latitude, longitude: draft.place.longitude },
        idempotencyKey: addressSaveRequest.current,
      });
      const saved = snapshot.addresses.find((address) => address.isDefault) ?? snapshot.addresses[0];
      if (!saved) throw new Error("The saved delivery address was not returned.");
      addressSaveRequest.current = undefined;
      setDeliveryAddress(saved);
      const location = { label: saved.displayAddress, coordinates: saved.location };
      setSelectedLocation(location);
      setAddressEditorOpen(false);
      setAddressLoading(false);
      if (reviewAfterAddress) {
        setReviewAfterAddress(false);
        await requestOrderQuote(location);
      } else {
        void load(location, discoveryRadiusKm);
      }
    } catch (error) {
      setAddressError(orderMessage(error));
    } finally {
      setOrderBusy(false);
    }
  };

  const saveProfile = async (profile: AccountProfile) => {
    setProfileBusy(true);
    setProfileError(undefined);
    try {
      const updated = await updateAccountProfile({ ...auth, ...profile });
      setAccountProfile(updated);
      setProfileEditorOpen(false);
    } catch (error) {
      setProfileError(orderMessage(error));
    } finally {
      setProfileBusy(false);
    }
  };

  const confirmAccountDeletion = async () => {
    setProfileBusy(true);
    setProfileError(undefined);
    try {
      await deleteAccount(auth);
      onSignOut();
    } catch (error) {
      setProfileError(orderMessage(error));
      setShowDeleteConfirmation(false);
    } finally {
      setProfileBusy(false);
    }
  };

  const placeOrder = async () => {
    if (!quote) return;
    setOrderBusy(true);
    setOrderError(undefined);
    try {
      const request = orderCreationRequest.current?.quoteId === quote.quoteId
        ? orderCreationRequest.current
        : { quoteId: quote.quoteId, idempotencyKey: crypto.randomUUID() };
      orderCreationRequest.current = request;
      const created = await createMerchantOrder({ ...auth, ...request });
      setOrders((current) => [created, ...current.filter((order) => order.orderId !== created.orderId)]);
      dispatchCart({ type: "clear" });
      setQuote(undefined);
      orderCreationRequest.current = undefined;
      await checkoutOrder(created);
    } catch (error) {
      setOrderError(orderMessage(error));
    } finally {
      setOrderBusy(false);
    }
  };

  const checkoutOrder = async (order: MerchantOrderSnapshot) => {
    setPaymentMessage(undefined);
    const session = await createCheckoutSession({
      ...auth,
      orderId: order.orderId,
      idempotencyKey: crypto.randomUUID(),
    });
    const result = await openRazorpayCheckout(session, {
      name: accountProfile.displayName,
      email,
      phoneNumber: accountProfile.phoneNumber,
    });
    if (result === "dismissed") {
      setPaymentMessage("Payment was not completed. You can pay from your order.");
      return;
    }
    if (result === "failed") {
      setPaymentMessage("Payment failed. No order will be fulfilled until payment succeeds.");
      return;
    }

    setPaymentMessage("Payment received. Confirming securely...");
    for (let attempt = 0; attempt < 10; attempt += 1) {
      await delay(1_500);
      let snapshot: MerchantOrderSnapshot[];
      try {
        snapshot = await getCustomerOrders(auth);
      } catch (error) {
        setOrdersRefreshIssue(customerDataIssue(error));
        setPaymentMessage("Payment was received. We are confirming it securely and will update your order shortly.");
        return;
      }
      setOrders(snapshot.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt)));
      setOrdersRefreshIssue(undefined);
      const updated = snapshot.find((item) => item.orderId === order.orderId);
      if (updated && updated.paymentState !== "payment_pending") {
        setPaymentMessage(updated.paymentState === "paid" ? "Payment confirmed." : "Payment status updated.");
        return;
      }
    }
    setPaymentMessage("Payment confirmation is taking longer than expected. This order will update automatically.");
  };

  const retryPayment = async (order: MerchantOrderSnapshot) => {
    setOrderBusy(true);
    setOrderError(undefined);
    try {
      await checkoutOrder(order);
    } catch (error) {
      setOrderError(orderMessage(error));
    } finally {
      setOrderBusy(false);
    }
  };

  const cancelOrder = async (order: MerchantOrderSnapshot, reason: string) => {
    setOrderBusy(true);
    setOrderError(undefined);
    try {
      const cancelled = await cancelMerchantOrder({
        ...auth,
        orderId: order.orderId,
        reason,
        idempotencyKey: crypto.randomUUID(),
      });
      setOrders((current) => current.map((item) => item.orderId === cancelled.orderId ? cancelled : item));
      if (cancelled.refundDecision?.decisionStatus === "review_required") {
        setPaymentMessage("Cancellation sent to Dastak for refund review.");
      } else if (cancelled.paymentState === "refund_pending") {
        try {
          const refund = await processOrderRefund({
            ...auth,
            orderId: cancelled.orderId,
            idempotencyKey: crypto.randomUUID(),
          });
          setPaymentMessage(refund.refundState === "processed" ? "Refund completed." : "Refund submitted.");
        } catch {
          setPaymentMessage("Order cancelled. Your refund is queued and will update automatically.");
        }
      }
      setCancellingOrder(undefined);
    } catch (error) {
      setOrderError(orderMessage(error));
    } finally {
      setOrderBusy(false);
    }
  };

  return (
    <div className={`catalogue-shell customer-section customer-section-${section}`}>
      {(orderError ?? cartState.error) && <p className="order-error" role="alert">{orderError ?? cartState.error}</p>}
      {ordersRefreshIssue && <CustomerDataNotice issue={ordersRefreshIssue} onRetry={refreshOrders} onSignOut={onSignOut} />}
      {paymentMessage && <p className="payment-message" role="status">{paymentMessage}</p>}
      {section === "home" && (
        <>
          <header className="customer-home-heading">
            <p className="eyebrow">{accountProfile.displayName ? `Hello, ${accountProfile.displayName}` : "Dastak"}</p>
            <h1>What do you need today?</h1>
            <button className="customer-search-prompt" type="button" onClick={() => onNavigate("search")}>
              <Search size={20} /><span>Search products and stores</span>
            </button>
          </header>
          <LocationControls
            selectedLocation={selectedLocation}
            discoveryRadiusKm={discoveryRadiusKm}
            loading={state.phase === "loading"}
            onChooseLocation={chooseLocation}
            onUseCurrentLocation={useCurrentLocation}
            onChangeRadius={changeDiscoveryRadius}
          />
          <button className="parcel-promo" type="button" onClick={onOpenParcel}>
            <span className="parcel-promo-icon"><Bike size={22} /></span>
            <span><strong>Send a parcel</strong><small>Immediate pickup and delivery</small></span>
            <ChevronRight size={20} />
          </button>
          {cartEntries.length > 0 && (
            <CartSummary
              itemCount={cartSummary.itemCount}
              subtotal={cartSummary.subtotalPaise}
              storeName={cartSummary.storeName ?? "Store"}
              busy={orderBusy}
              onClear={clearCart}
              onReview={reviewOrder}
            />
          )}
          {quote && <CheckoutSection quote={quote} address={deliveryAddress} busy={orderBusy} onPlaceOrder={placeOrder} />}
          {!ordersLoading && hasActiveOrders && (
            <div className="customer-active-order">
              <OrdersSection
                orders={orders.filter((order) => !isFinalOrder(order)).slice(0, 1)}
                busy={orderBusy}
                onCancel={setCancellingOrder}
                onPay={retryPayment}
                onOpen={onOpenOrder}
                onRefresh={refreshOrders}
                title="Active order"
              />
              <button type="button" onClick={() => onNavigate("orders")}>View all orders <ChevronRight size={16} /></button>
            </div>
          )}
          <CatalogueContent
            state={state}
            stores={visibleStores}
            selectedLocation={selectedLocation}
            supabaseUrl={supabaseUrl}
            cartStoreId={cartStoreId}
            cart={cart}
            onQuantity={changeQuantity}
            onRetry={() => selectedLocation && void load(selectedLocation, discoveryRadiusKm)}
            heading="Nearby"
          />
        </>
      )}

      {section === "search" && (
        <>
          <header className="customer-page-heading"><p className="eyebrow">Discovery</p><h1>Search</h1></header>
          <label className="customer-product-search">
            <Search size={20} />
            <input
              value={searchQuery}
              onChange={(event) => setSearchQuery(event.target.value)}
              placeholder="Products, categories, or stores"
              autoFocus
            />
            {searchQuery && <button type="button" onClick={() => setSearchQuery("")} aria-label="Clear search" title="Clear search"><X size={17} /></button>}
          </label>
          <LocationControls
            selectedLocation={selectedLocation}
            discoveryRadiusKm={discoveryRadiusKm}
            loading={state.phase === "loading"}
            onChooseLocation={chooseLocation}
            onUseCurrentLocation={useCurrentLocation}
            onChangeRadius={changeDiscoveryRadius}
            compact
          />
          {cartEntries.length > 0 && (
            <CartSummary
              itemCount={cartSummary.itemCount}
              subtotal={cartSummary.subtotalPaise}
              storeName={cartSummary.storeName ?? "Store"}
              busy={orderBusy}
              onClear={clearCart}
              onReview={reviewOrder}
            />
          )}
          {quote && <CheckoutSection quote={quote} address={deliveryAddress} busy={orderBusy} onPlaceOrder={placeOrder} />}
          <CatalogueContent
            state={state}
            stores={visibleStores}
            selectedLocation={selectedLocation}
            supabaseUrl={supabaseUrl}
            cartStoreId={cartStoreId}
            cart={cart}
            onQuantity={changeQuantity}
            onRetry={() => selectedLocation && void load(selectedLocation, discoveryRadiusKm)}
            heading={searchQuery ? "Results" : "Browse all"}
            emptySearch={Boolean(searchQuery)}
          />
        </>
      )}

      {section === "orders" && (
        <>
          {selectedOrderId && orders.find((order) => order.orderId === selectedOrderId) ? (
            <CustomerOrderDetail
              order={orders.find((order) => order.orderId === selectedOrderId)!}
              busy={orderBusy}
              onBack={onCloseOrder}
              onPay={retryPayment}
              onCancel={setCancellingOrder}
              onRefresh={refreshOrders}
            />
          ) : <>
            <header className="customer-page-heading"><p className="eyebrow">Purchases</p><h1>Orders</h1></header>
            {ordersLoading ? <div className="catalogue-loading" role="status"><span /> Loading orders</div> : orders.length > 0 ? (
              <OrdersSection orders={orders} busy={orderBusy} onCancel={setCancellingOrder} onPay={retryPayment} onOpen={onOpenOrder} onRefresh={refreshOrders} title="Your orders" />
            ) : ordersRefreshIssue ? (
              <CustomerDataRecovery issue={ordersRefreshIssue} onRetry={refreshOrders} onSignOut={onSignOut} />
            ) : (
              <CatalogueMessage icon={<ReceiptText size={25} />} title="No orders yet">
                Your orders and delivery updates will appear here.
              </CatalogueMessage>
            )}
          </>}
        </>
      )}

      {section === "account" && (
        <section className="customer-account">
          <header className="customer-page-heading"><p className="eyebrow">Dastak account</p><h1>{accountProfile.displayName || "Your account"}</h1></header>
          <button className="customer-profile-card" type="button" onClick={() => setProfileEditorOpen(true)}>
            <span className="customer-account-icon"><UserRound size={25} /></span>
            <span><strong>{accountProfile.displayName}</strong><small>{accountProfile.phoneNumber}</small>{email && <small>{email}</small>}</span>
            <ChevronRight size={19} />
          </button>

          <section className="customer-account-group" aria-labelledby="account-delivery-title">
            <h2 id="account-delivery-title">Delivery</h2>
            <div className="customer-account-rows">
              <button className="customer-account-row" type="button" onClick={() => setAddressEditorOpen(true)} disabled={addressLoading}>
                <MapPin size={20} />
                <span><strong>Delivery address</strong><small>{deliveryAddress?.displayAddress ?? "Add a house, flat or landmark"}</small></span>
                <ChevronRight size={18} />
              </button>
              <div className="customer-account-row">
                <LocateFixed size={20} />
                <span><strong>Discovery range</strong><small>Stores shown around your delivery location</small></span>
                <b>{discoveryRadiusKm} km</b>
              </div>
            </div>
            {addressError && <small className="error-text customer-account-error">{addressError}</small>}
          </section>

          <section className="customer-account-group" aria-labelledby="account-preferences-title">
            <h2 id="account-preferences-title">Preferences</h2>
            <div className="customer-account-rows">
              <div className="customer-account-row"><Bell size={20} /><span><strong>Order updates</strong><small>Shown in Dastak</small></span><b>On</b></div>
              <div className="customer-account-row"><Globe2 size={20} /><span><strong>Language</strong><small>Uses your browser language</small></span><b>Auto</b></div>
            </div>
          </section>

          <section className="customer-account-group" aria-labelledby="account-support-title">
            <h2 id="account-support-title">Help and safety</h2>
            <div className="customer-account-rows">
              <button className="customer-account-row" type="button" onClick={() => onNavigate("orders")}>
                <CircleHelp size={20} /><span><strong>Help with an order</strong><small>Open an order to get relevant support</small></span><ChevronRight size={18} />
              </button>
              <a className="customer-account-row emergency" href="tel:112">
                <ShieldAlert size={20} /><span><strong>Emergency assistance</strong><small>Call India emergency services</small></span><ChevronRight size={18} />
              </a>
            </div>
          </section>

          <section className="customer-account-group" aria-labelledby="account-privacy-title">
            <h2 id="account-privacy-title">Privacy and account</h2>
            <div className="customer-account-rows">
              <div className="customer-account-row customer-privacy-row">
                <Hand size={20} /><span><strong>Privacy and data</strong><small>Your unverified number is shared only for an active delivery. Your saved address is used for discovery, pricing and fulfilment.</small></span>
              </div>
              <button className="customer-account-row" type="button" onClick={() => setShowSignOutConfirmation(true)}>
                <LogOut size={20} /><span><strong>Sign out</strong><small>Keep this account and end this session</small></span><ChevronRight size={18} />
              </button>
              <button className="customer-account-row destructive" type="button" onClick={() => setShowDeleteConfirmation(true)}>
                <Trash2 size={20} /><span><strong>Delete account</strong><small>Permanently remove your Dastak account</small></span><ChevronRight size={18} />
              </button>
            </div>
          </section>
          {profileError && !profileEditorOpen && <p className="error-text" role="alert">{profileError}</p>}
        </section>
      )}
      {addressEditorOpen && <CustomerAddressSheet
        address={deliveryAddress}
        initialPlace={selectedLocation ? { address: selectedLocation.label, latitude: selectedLocation.coordinates.latitude, longitude: selectedLocation.coordinates.longitude } : undefined}
        busy={orderBusy}
        error={addressError}
        required={!addressLoading && !deliveryAddress}
        onDismiss={() => { if (!deliveryAddress) return; addressSaveRequest.current = undefined; setAddressEditorOpen(false); setReviewAfterAddress(false); setAddressError(undefined); }}
        onSave={saveAddress}
      />}
      {profileEditorOpen && <AccountProfileSheet
        profile={accountProfile}
        busy={profileBusy}
        error={profileError}
        onDismiss={() => { setProfileEditorOpen(false); setProfileError(undefined); }}
        onSave={saveProfile}
      />}
      {showSignOutConfirmation && <AccountActionDialog
        action="sign-out"
        message="You'll need to sign in again to access your account and orders."
        onConfirm={onSignOut}
        onDismiss={() => setShowSignOutConfirmation(false)}
      />}
      {showDeleteConfirmation && <AccountActionDialog
        action="delete-account"
        busy={profileBusy}
        message="Completed order records may be retained without your identity where legally required. This cannot be undone."
        onConfirm={() => void confirmAccountDeletion()}
        onDismiss={() => setShowDeleteConfirmation(false)}
      />}
      {cancellingOrder && <CancellationSheet
        title={merchantOrderPresentation(cancellingOrder.status, cancellingOrder.paymentState).primaryAction === "request_cancellation" ? "Request cancellation?" : "Cancel this order?"}
        busy={orderBusy}
        onDismiss={() => setCancellingOrder(undefined)}
        onConfirm={(reason) => cancelOrder(cancellingOrder, reason)}
      />}
    </div>
  );
}

function CustomerDataNotice({ issue, onRetry, onSignOut }: {
  issue: CustomerDataIssue;
  onRetry: () => Promise<void>;
  onSignOut: () => void;
}) {
  return (
    <div className="customer-data-notice" role="status">
      <span><strong>{issue.title}</strong><small>{issue.message}</small></span>
      <button type="button" className="secondary-button compact-button" onClick={issue.action === "sign_in" ? onSignOut : () => void onRetry()}>
        {issue.action === "sign_in" ? "Sign in again" : "Try again"}
      </button>
    </div>
  );
}

function CustomerDataRecovery({ issue, onRetry, onSignOut }: {
  issue: CustomerDataIssue;
  onRetry: () => Promise<void>;
  onSignOut: () => void;
}) {
  return (
    <CatalogueMessage icon={<RefreshCw size={25} />} title={issue.title}>
      <p>{issue.message}</p>
      <button type="button" className="secondary-button compact-button" onClick={issue.action === "sign_in" ? onSignOut : () => void onRetry()}>
        {issue.action === "sign_in" ? "Sign in again" : "Try again"}
      </button>
    </CatalogueMessage>
  );
}

function LocationControls({ selectedLocation, discoveryRadiusKm, loading, compact = false, onChooseLocation, onUseCurrentLocation, onChangeRadius }: {
  selectedLocation?: SelectedLocation;
  discoveryRadiusKm: number;
  loading: boolean;
  compact?: boolean;
  onChooseLocation: (place: SelectedPlace) => void;
  onUseCurrentLocation: () => void;
  onChangeRadius: (deltaKm: number) => void;
}) {
  const place = selectedLocation ? {
    address: selectedLocation.label,
    latitude: selectedLocation.coordinates.latitude,
    longitude: selectedLocation.coordinates.longitude,
  } : undefined;

  return (
    <section className={`customer-location-band ${compact ? "compact" : ""}`} aria-label="Delivery area">
      <LocationSearchField label="Delivery location" value={place} onChange={onChooseLocation} disabled={loading} />
      <button type="button" className="location-current-button" onClick={onUseCurrentLocation} disabled={loading} aria-label="Use current location" title="Use current location">
        <LocateFixed size={18} />
      </button>
      <div className="range-filter" role="group" aria-label="Store search radius">
        <span>Range</span>
        <div className="range-stepper">
          <button type="button" onClick={() => onChangeRadius(-5)} disabled={discoveryRadiusKm === 10} aria-label="Decrease search radius" title="Decrease search radius"><Minus size={15} /></button>
          <strong aria-live="polite">{discoveryRadiusKm} km</strong>
          <button type="button" onClick={() => onChangeRadius(5)} disabled={discoveryRadiusKm === 30} aria-label="Increase search radius" title="Increase search radius"><Plus size={15} /></button>
        </div>
      </div>
    </section>
  );
}

function CatalogueContent({ state, stores, selectedLocation, supabaseUrl, cartStoreId, cart, onQuantity, onRetry, heading, emptySearch = false }: {
  state: CatalogueState;
  stores: GroupedCatalogueStore[];
  selectedLocation?: SelectedLocation;
  supabaseUrl: string;
  cartStoreId?: string;
  cart: CartEntries;
  onQuantity: (store: GroupedCatalogueStore, product: CatalogueProduct, delta: -1 | 1) => void;
  onRetry: () => void;
  heading: string;
  emptySearch?: boolean;
}) {
  return (
    <section className="customer-catalogue">
      {state.phase === "ready" && state.stores.length > 0 && <h2>{heading}</h2>}
      {state.phase === "idle" && (
        <CatalogueMessage icon={<MapPin size={25} />} title="Choose a delivery location">
          Search any city where Dastak has an active service area.
        </CatalogueMessage>
      )}
      {state.phase === "loading" && <div className="catalogue-loading" role="status"><span /> Finding nearby stores</div>}
      {state.phase === "error" && (
        <CatalogueMessage icon={<MapPin size={25} />} title={state.code === "outside_service_area" ? "Not available here yet" : "Could not load stores"}>
          <p>{state.message}</p>
          {selectedLocation && <button type="button" className="secondary-button compact-button" onClick={onRetry}><RefreshCw size={16} /> Retry</button>}
        </CatalogueMessage>
      )}
      {state.phase === "ready" && state.stores.length === 0 && (
        <CatalogueMessage icon={<PackageOpen size={25} />} title="No stores are open yet">
          Dastak serves this area, but no merchant catalogue is currently available.
        </CatalogueMessage>
      )}
      {state.phase === "ready" && state.stores.length > 0 && stores.length === 0 && (
        <CatalogueMessage icon={<Search size={25} />} title={emptySearch ? "No matching products" : "Nothing to show"}>
          Try another product, category, or store.
        </CatalogueMessage>
      )}
      {state.phase === "ready" && stores.length > 0 && (
        <div className="store-list" aria-live="polite">
          {stores.map((store) => (
            <StoreCatalogue key={store.storeId} store={store} supabaseUrl={supabaseUrl} cartStoreId={cartStoreId} quantities={cart} onQuantity={onQuantity} />
          ))}
        </div>
      )}
    </section>
  );
}

function OrdersSection({ orders, busy, onCancel, onPay, onOpen, onRefresh, title }: {
  orders: MerchantOrderSnapshot[];
  busy: boolean;
  onCancel: (order: MerchantOrderSnapshot) => void;
  onPay: (order: MerchantOrderSnapshot) => void;
  onOpen: (orderId: string) => void;
  onRefresh: () => Promise<void>;
  title: string;
}) {
  return (
    <section className="orders-section" aria-label="Your orders">
      <header>
        <div><p className="eyebrow">Orders</p><h2>{title}</h2></div>
        <button className="icon-button" type="button" onClick={() => void onRefresh()} disabled={busy} aria-label="Refresh orders" title="Refresh orders">
          <RefreshCw size={18} />
        </button>
      </header>
      <div className="order-list">
        {orders.map((order) => {
          const presentation = merchantOrderPresentation(order.status, order.paymentState);
          return <article className="order-row" key={order.orderId}>
            <span className="order-icon"><ReceiptText size={20} /></span>
            <div className="order-main">
              <strong>{presentation.title}</strong>
              <small>{presentation.message}</small>
              <small>{order.lines.map((line) => `${line.quantity} x ${line.name}`).join(", ")}</small>
              {order.handoffCode?.purpose === "delivery" && <span className="delivery-code">Delivery code <b>{order.handoffCode.code}</b></span>}
              {customerRefundText(order) && <span className="order-refund">{customerRefundText(order)}</span>}
            </div>
            <strong className="order-total">{formatPrice(order.total.paise)}</strong>
            <button className="order-open" type="button" onClick={() => onOpen(order.orderId)}>View details <ChevronRight size={16} /></button>
            {presentation.primaryAction === "pay" && (
              <button className="primary-button order-pay" type="button" onClick={() => onPay(order)} disabled={busy}>
                <CreditCard size={16} /> Pay
              </button>
            )}
            {(presentation.primaryAction === "cancel" || presentation.primaryAction === "request_cancellation") && (
              <button className="order-cancel" type="button" onClick={() => onCancel(order)} disabled={busy}>
                <X size={16} /> {presentation.primaryAction === "request_cancellation" ? "Request cancellation" : "Cancel"}
              </button>
            )}
          </article>
        })}
      </div>
    </section>
  );
}

function CustomerOrderDetail({ order, busy, onBack, onPay, onCancel, onRefresh }: {
  order: MerchantOrderSnapshot;
  busy: boolean;
  onBack: () => void;
  onPay: (order: MerchantOrderSnapshot) => void;
  onCancel: (order: MerchantOrderSnapshot) => void;
  onRefresh: () => Promise<void>;
}) {
  const presentation = merchantOrderPresentation(order.status, order.paymentState);
  const timeline = order.timeline;
  const points = [
    ...(order.store ? [{ label: order.store.name, ...order.store.pickup, kind: "pickup" as const }] : []),
    { label: "Delivery address", address: order.deliveryAddress?.displayAddress ?? "Selected delivery location", ...order.dropoff, kind: "dropoff" as const },
    ...(order.courier?.location ? [{ label: order.courier.displayName, address: "Delivery partner's latest location", ...order.courier.location, kind: "courier" as const }] : []),
  ];

  return (
    <article className="customer-delivery-detail">
      <header className="customer-detail-header">
        <button className="customer-back-button" type="button" onClick={onBack}><ArrowLeft size={18} /> Orders</button>
        <button className="icon-button" type="button" onClick={() => void onRefresh()} disabled={busy} aria-label="Refresh order" title="Refresh"><RefreshCw size={18} /></button>
      </header>
      <section className="customer-status-hero">
        <p className="eyebrow">Order {order.orderId.slice(-6).toUpperCase()}</p>
        <h1>{presentation.title}</h1>
        <p>{presentation.message}</p>
        <span>{paymentStateLabel(order.paymentState)}</span>
      </section>
      <CustomerRouteMap points={points} />
      {order.courier && <section className="customer-contact-card"><span className="order-icon"><Bike size={20} /></span><div><strong>{order.courier.displayName}</strong><small>Your delivery partner · {order.courier.deliveryMethod}</small></div><a href={`tel:${order.courier.phoneNumber}`} aria-label="Call delivery partner"><Phone size={18} /></a></section>}
      {order.handoffCode?.purpose === "delivery" && <section className="customer-handoff"><small>Share only at your door</small><strong>{order.handoffCode.code}</strong><span>Delivery code</span></section>}
      <section className="customer-receipt">
        <header><h2>Receipt</h2><strong>{formatPrice(order.total.paise)}</strong></header>
        {order.lines.map((line) => <div key={line.productId}><span>{line.quantity} × {line.name}<small>{line.unitLabel}</small></span><strong>{formatPrice(line.lineSubtotal.paise)}</strong></div>)}
        <div><span>Delivery · {formatDeliveryDistance(order.deliveryDistanceMeters)}</span><strong>{formatPrice(order.deliveryFee.paise)}</strong></div>
        {order.deliveryAddress?.displayAddress && <div className="receipt-address"><MapPin size={17} /><span>{order.deliveryAddress.displayAddress}</span></div>}
      </section>
      <CustomerTimeline items={[
        { label: "Order placed", value: timeline?.createdAt ?? order.createdAt },
        { label: "Store accepted", value: timeline?.acceptedAt },
        { label: "Ready for pickup", value: timeline?.readyAt },
        { label: "Partner assigned", value: timeline?.assignedAt },
        { label: "Picked up", value: timeline?.pickedUpAt },
        { label: "On the way", value: timeline?.inTransitAt },
        { label: "Delivered", value: timeline?.deliveredAt },
        { label: "Cancelled", value: timeline?.cancelledAt },
      ]} />
      {customerRefundText(order) && <p className="payment-message">{customerRefundText(order)}</p>}
      <div className="customer-detail-actions">
        {presentation.primaryAction === "pay" && <button className="primary-button" type="button" disabled={busy} onClick={() => onPay(order)}><CreditCard size={18} /> Pay {formatPrice(order.total.paise)}</button>}
        {(presentation.primaryAction === "cancel" || presentation.primaryAction === "request_cancellation") && <button className="danger-button" type="button" disabled={busy} onClick={() => onCancel(order)}><X size={18} /> {presentation.primaryAction === "request_cancellation" ? "Request cancellation" : "Cancel order"}</button>}
      </div>
    </article>
  );
}

function customerRefundText(order: MerchantOrderSnapshot) {
  const decision = order.refundDecision;
  if (!decision) return null;
  if (decision.decisionStatus === "review_required") return "Cancellation under review";
  if (decision.decisionStatus === "denied") return "Refund denied";

  const amount = (decision.itemRefund?.paise ?? 0) + (decision.deliveryFeeRefund?.paise ?? 0);
  if (amount <= 0) return null;
  if (order.paymentState === "refunded") return `Refunded ${formatPrice(amount)}`;
  if (order.paymentState === "refund_pending") {
    return order.status === "returning_to_merchant"
      ? `${formatPrice(amount)} refund after return`
      : `${formatPrice(amount)} refund processing`;
  }
  return null;
}

function CartSummary({ itemCount, subtotal, storeName, busy, onClear, onReview }: {
  itemCount: number;
  subtotal: number;
  storeName: string;
  busy: boolean;
  onClear: () => void;
  onReview: () => void;
}) {
  return (
    <section className="cart-summary" aria-label="Cart">
      <span className="cart-icon"><ShoppingBag size={21} /></span>
      <div><strong>{itemCount} {itemCount === 1 ? "item" : "items"}</strong><small>{storeName} · Subtotal {formatPrice(subtotal)}</small></div>
      <button className="icon-button" type="button" onClick={onClear} disabled={busy} aria-label="Clear cart" title="Clear cart"><Trash2 size={17} /></button>
      <button className="primary-button cart-review" type="button" onClick={onReview} disabled={busy}>Review order</button>
    </section>
  );
}

function CheckoutSection({ quote, address, busy, onPlaceOrder }: {
  quote: MerchantOrderQuote;
  address?: CustomerDeliveryAddress;
  busy: boolean;
  onPlaceOrder: () => void;
}) {
  return (
    <section className="checkout-section" aria-label="Order total">
      <header><p className="eyebrow">Checkout</p><h2>Order total</h2></header>
      <div className="checkout-lines">
        {quote.lines.map((line) => (
          <div key={line.productId}><span>{line.quantity} x {line.name}</span><strong>{formatPrice(line.lineSubtotal.paise)}</strong></div>
        ))}
      </div>
      <dl className="checkout-totals">
        <div><dt>Items</dt><dd>{formatPrice(quote.itemSubtotal.paise)}</dd></div>
        <div>
          <dt>Delivery ({formatDeliveryDistance(quote.deliveryDistanceMeters)})</dt>
          <dd>{formatPrice(quote.deliveryFee.paise)}</dd>
        </div>
        <div className="checkout-grand-total"><dt>Total</dt><dd>{formatPrice(quote.total.paise)}</dd></div>
      </dl>
      {address && <div className="checkout-address"><MapPin size={18} /><span><small>Deliver to {address.label}</small><strong>{address.displayAddress}</strong></span></div>}
      <button className="primary-button checkout-button" type="button" onClick={onPlaceOrder} disabled={busy}>
        <CreditCard size={17} /> Pay {formatPrice(quote.total.paise)}
      </button>
    </section>
  );
}

function delay(milliseconds: number) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function CatalogueMessage({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <section className="catalogue-message">
      <span className="message-icon" aria-hidden="true">{icon}</span>
      <div><h2>{title}</h2><div className="message-body">{children}</div></div>
    </section>
  );
}

function StoreCatalogue({ store, supabaseUrl, cartStoreId, quantities, onQuantity }: {
  store: GroupedCatalogueStore;
  supabaseUrl: string;
  cartStoreId?: string;
  quantities: CartEntries;
  onQuantity: (store: GroupedCatalogueStore, product: CatalogueProduct, delta: -1 | 1) => void;
}) {
  const productCount = store.categories.reduce((count, category) => count + category.products.length, 0);
  const anotherStoreSelected = Boolean(cartStoreId && cartStoreId !== store.storeId);
  return (
    <section className="store-section">
      <header className="store-heading">
        <span className="store-icon"><Store size={20} /></span>
        <div><h2>{store.name}</h2><p>{store.address}</p></div>
        <span className={`store-status ${store.acceptingOrders ? "open" : "unavailable"}`}>
          {store.acceptingOrders ? "Accepting orders" : "Unavailable"}
        </span>
      </header>
      {productCount === 0 ? <p className="store-empty">This store is preparing its catalogue.</p> : store.categories.map((category) => (
        category.products.length > 0 && <div className="category-section" key={category.categoryId}>
          <h3>{category.name}</h3>
          <div className="product-grid">
            {category.products.map((product) => {
              const imageUrl = catalogueImageUrl(supabaseUrl, product.imageObjectPath);
              const unavailable = product.availability === "out_of_stock" || !store.acceptingOrders;
              const quantity = quantities[product.productId]?.quantity ?? 0;
              return (
                <article className={`product-card ${unavailable ? "unavailable" : ""}`} key={product.productId}>
                  <div className="product-image">
                    {imageUrl ? <img src={imageUrl} alt="" loading="lazy" /> : <ImageOff size={24} aria-label="No product image" />}
                  </div>
                  <div className="product-copy">
                    <h4>{product.name}</h4>
                    <p>{product.unitLabel}</p>
                    <strong>{formatPrice(product.price.paise)}</strong>
                    {product.availability === "out_of_stock" && <span>Out of stock</span>}
                    {quantity > 0 ? (
                      <div className="quantity-control" aria-label={`${product.name} quantity`}>
                        <button type="button" onClick={() => onQuantity(store, product, -1)} aria-label={`Remove one ${product.name}`} title="Remove one"><Minus size={16} /></button>
                        <strong aria-live="polite">{quantity}</strong>
                        <button
                          type="button"
                          onClick={() => onQuantity(store, product, 1)}
                          disabled={unavailable || quantity >= MAX_CART_PRODUCT_QUANTITY}
                          aria-label={`Add one ${product.name}`}
                          title={quantity >= MAX_CART_PRODUCT_QUANTITY ? "Maximum quantity reached" : "Add one"}
                        >
                          <Plus size={16} />
                        </button>
                      </div>
                    ) : (
                      <button
                        className="add-product"
                        type="button"
                        disabled={unavailable || anotherStoreSelected}
                        title={anotherStoreSelected ? "Clear the current cart to order from this store" : undefined}
                        onClick={() => onQuantity(store, product, 1)}
                      >
                        <Plus size={16} /> Add
                      </button>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        </div>
      ))}
    </section>
  );
}

function isFinalOrder(order: MerchantOrderSnapshot) {
  return order.status === "cancelled" || order.status === "delivered";
}

function orderMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The order request is unavailable right now.";
}

function sameLocation(left: CatalogueLocation, right: CatalogueLocation) {
  return Math.abs(left.latitude - right.latitude) < .00001 && Math.abs(left.longitude - right.longitude) < .00001;
}

function filterCatalogueStores(stores: GroupedCatalogueStore[], query: string) {
  const needle = query.trim().toLocaleLowerCase();
  if (!needle) return stores;

  return stores.flatMap((store) => {
    const storeMatches = `${store.name} ${store.address}`.toLocaleLowerCase().includes(needle);
    const categories = store.categories.flatMap((category) => {
      const categoryMatches = category.name.toLocaleLowerCase().includes(needle);
      const products = storeMatches || categoryMatches
        ? category.products
        : category.products.filter((product) =>
          `${product.name} ${product.description ?? ""} ${product.unitLabel}`.toLocaleLowerCase().includes(needle)
        );
      return products.length > 0 ? [{ ...category, products }] : [];
    });
    return categories.length > 0 ? [{ ...store, categories }] : [];
  });
}
