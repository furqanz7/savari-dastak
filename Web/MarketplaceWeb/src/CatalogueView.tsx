import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import {
  CreditCard,
  ImageOff,
  LocateFixed,
  MapPin,
  Minus,
  PackageOpen,
  Plus,
  ReceiptText,
  RefreshCw,
  ShoppingBag,
  Store,
  Trash2,
  X,
} from "lucide-react";
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
  canCancelOrder,
  cancelMerchantOrder,
  createMerchantOrder,
  formatDeliveryDistance,
  getCustomerOrders,
  orderStatusLabel,
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

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
};

type SelectedLocation = { label: string; coordinates: CatalogueLocation };
type CatalogueState =
  | { phase: "idle" }
  | { phase: "loading" }
  | { phase: "ready"; stores: GroupedCatalogueStore[] }
  | { phase: "error"; code: string; message: string };
export function CatalogueView({ accessToken, displayName, email, phoneNumber, supabaseUrl, publishableKey }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [selectedLocation, setSelectedLocation] = useState<SelectedLocation>();
  const [discoveryRadiusKm, setDiscoveryRadiusKm] = useState(10);
  const [state, setState] = useState<CatalogueState>({ phase: "idle" });
  const [cartState, dispatchCart] = useReducer(cartReducer, undefined, createEmptyCart);
  const [quote, setQuote] = useState<MerchantOrderQuote>();
  const [orders, setOrders] = useState<MerchantOrderSnapshot[]>([]);
  const [ordersLoading, setOrdersLoading] = useState(true);
  const [orderBusy, setOrderBusy] = useState(false);
  const [orderError, setOrderError] = useState<string>();
  const [paymentMessage, setPaymentMessage] = useState<string>();
  const catalogueRequest = useRef(0);
  const orderCreationRequest = useRef<{ quoteId: string; idempotencyKey: string } | undefined>(undefined);

  const refreshOrders = useCallback(async () => {
    try {
      const snapshot = await getCustomerOrders(auth);
      setOrders(snapshot.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt)));
    } catch (error) {
      setOrderError(orderMessage(error));
    } finally {
      setOrdersLoading(false);
    }
  }, [auth]);

  useEffect(() => {
    void refreshOrders();
  }, [refreshOrders]);

  useEffect(() => {
    if (!orders.some((order) => !isFinalOrder(order))) return;
    const interval = window.setInterval(() => void refreshOrders(), 5_000);
    return () => window.clearInterval(interval);
  }, [orders, refreshOrders]);

  const load = async (location: SelectedLocation, radiusKm = discoveryRadiusKm) => {
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
  };

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
      }),
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

  const reviewOrder = async () => {
    if (!selectedLocation || !cartStoreId || cartEntries.length === 0) return;
    setOrderBusy(true);
    setOrderError(undefined);
    try {
      const nextQuote = await quoteMerchantOrder({
        ...auth,
        storeId: cartStoreId,
        lines: cartEntries.map((entry) => ({ productId: entry.product.productId, quantity: entry.quantity })),
        dropoff: selectedLocation.coordinates,
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
      name: displayName,
      email,
      phoneNumber,
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
      const snapshot = await getCustomerOrders(auth);
      setOrders(snapshot.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt)));
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

  const cancelOrder = async (order: MerchantOrderSnapshot) => {
    if (!window.confirm("Cancel this order?")) return;
    setOrderBusy(true);
    setOrderError(undefined);
    try {
      const cancelled = await cancelMerchantOrder({
        ...auth,
        orderId: order.orderId,
        reason: "Customer cancelled from web",
        idempotencyKey: crypto.randomUUID(),
      });
      setOrders((current) => current.map((item) => item.orderId === cancelled.orderId ? cancelled : item));
      if (cancelled.refundDecision?.decisionStatus === "review_required") {
        setPaymentMessage("Cancellation sent to Dastak for refund review.");
      } else if (cancelled.paymentState === "refund_pending") {
        const refund = await processOrderRefund({
          ...auth,
          orderId: cancelled.orderId,
          idempotencyKey: crypto.randomUUID(),
        });
        setPaymentMessage(refund.refundState === "processed" ? "Refund completed." : "Refund submitted.");
      }
    } catch (error) {
      setOrderError(orderMessage(error));
    } finally {
      setOrderBusy(false);
    }
  };

  return (
    <div className="catalogue-shell">
      <div className="catalogue-heading">
        <div>
          <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak customer"}</p>
          <h1>Nearby stores</h1>
          <p>{selectedLocation ? `Delivering near ${selectedLocation.label}` : "Choose where you want the order delivered."}</p>
        </div>
        <div className="location-actions" aria-label="Delivery location">
          <div className="range-filter" role="group" aria-label="Store search radius">
            <span>Search radius</span>
            <div className="range-stepper">
              <button
                type="button"
                onClick={() => changeDiscoveryRadius(-5)}
                disabled={discoveryRadiusKm === 10}
                aria-label="Decrease search radius"
                title="Decrease search radius"
              >
                <Minus size={15} />
              </button>
              <strong aria-live="polite">{discoveryRadiusKm} km</strong>
              <button
                type="button"
                onClick={() => changeDiscoveryRadius(5)}
                disabled={discoveryRadiusKm === 30}
                aria-label="Increase search radius"
                title="Increase search radius"
              >
                <Plus size={15} />
              </button>
            </div>
          </div>
          <button type="button" className="location-button primary-location" onClick={useCurrentLocation} disabled={state.phase === "loading"}>
            <LocateFixed size={18} /> Use current location
          </button>
        </div>
      </div>

      {(orderError ?? cartState.error) && <p className="order-error" role="alert">{orderError ?? cartState.error}</p>}
      {paymentMessage && <p className="payment-message" role="status">{paymentMessage}</p>}
      {!ordersLoading && orders.length > 0 && (
        <OrdersSection orders={orders} busy={orderBusy} onCancel={cancelOrder} onPay={retryPayment} onRefresh={refreshOrders} />
      )}
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
      {quote && <CheckoutSection quote={quote} busy={orderBusy} onPlaceOrder={placeOrder} />}

      {state.phase === "idle" && (
        <CatalogueMessage icon={<MapPin size={25} />} title="Set a delivery location">
          Stores and products are shown only for areas Dastak currently serves.
        </CatalogueMessage>
      )}
      {state.phase === "loading" && <div className="catalogue-loading" role="status"><span /> Finding nearby stores</div>}
      {state.phase === "error" && (
        <CatalogueMessage
          icon={<MapPin size={25} />}
          title={state.code === "outside_service_area" ? "Not available here yet" : "Could not load stores"}
        >
          <p>{state.message}</p>
          {selectedLocation && (
            <button type="button" className="secondary-button compact-button" onClick={() => void load(selectedLocation)}>
              <RefreshCw size={16} /> Retry
            </button>
          )}
        </CatalogueMessage>
      )}
      {state.phase === "ready" && state.stores.length === 0 && (
        <CatalogueMessage icon={<PackageOpen size={25} />} title="No stores are open yet">
          Dastak serves this area, but no merchant catalogue is currently available.
        </CatalogueMessage>
      )}
      {state.phase === "ready" && state.stores.length > 0 && (
        <div className="store-list" aria-live="polite">
          {state.stores.map((store) => (
            <StoreCatalogue
              key={store.storeId}
              store={store}
              supabaseUrl={supabaseUrl}
              cartStoreId={cartStoreId}
              quantities={cart}
              onQuantity={changeQuantity}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function OrdersSection({ orders, busy, onCancel, onPay, onRefresh }: {
  orders: MerchantOrderSnapshot[];
  busy: boolean;
  onCancel: (order: MerchantOrderSnapshot) => void;
  onPay: (order: MerchantOrderSnapshot) => void;
  onRefresh: () => Promise<void>;
}) {
  return (
    <section className="orders-section" aria-label="Your orders">
      <header>
        <div><p className="eyebrow">Orders</p><h2>Your orders</h2></div>
        <button className="icon-button" type="button" onClick={() => void onRefresh()} disabled={busy} aria-label="Refresh orders" title="Refresh orders">
          <RefreshCw size={18} />
        </button>
      </header>
      <div className="order-list">
        {orders.slice(0, 3).map((order) => (
          <article className="order-row" key={order.orderId}>
            <span className="order-icon"><ReceiptText size={20} /></span>
            <div className="order-main">
              <strong>{orderStatusLabel(order.status)}</strong>
              <small>{order.lines.map((line) => `${line.quantity} x ${line.name}`).join(", ")}</small>
              {order.handoffCode?.purpose === "delivery" && <span className="delivery-code">Delivery code <b>{order.handoffCode.code}</b></span>}
              {customerRefundText(order) && <span className="order-refund">{customerRefundText(order)}</span>}
            </div>
            <strong className="order-total">{formatPrice(order.total.paise)}</strong>
            {order.paymentState === "payment_pending" && order.status === "payment_pending" && (
              <button className="primary-button order-pay" type="button" onClick={() => onPay(order)} disabled={busy}>
                <CreditCard size={16} /> Pay
              </button>
            )}
            {canCancelOrder(order.status) && (
              <button className="order-cancel" type="button" onClick={() => onCancel(order)} disabled={busy}>
                <X size={16} /> Cancel
              </button>
            )}
          </article>
        ))}
      </div>
    </section>
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

function CheckoutSection({ quote, busy, onPlaceOrder }: {
  quote: MerchantOrderQuote;
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
