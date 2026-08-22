import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import {
  ArrowRight, Check, ChevronRight, CircleAlert, MapPin, Minus, PackageCheck,
  Plus, Search, ShieldCheck, ShoppingBag, Sparkles, X,
} from "lucide-react";
import { CustomerAddressBookSheet } from "./CustomerAddressBookSheet";
import { CustomerAddressSheet, type CustomerAddressDraft } from "./CustomerAddressSheet";
import {
  deleteCustomerAddress, getCustomerAddresses, saveCustomerAddress, setDefaultCustomerAddress,
  type CustomerDeliveryAddress,
} from "./customerAddresses";
import type { CustomerSection } from "./customerNavigation";
import {
  cancelV1Order, formatV1Price, getV1Catalogue, getV1Order, getV1Orders, submitV1Order,
  type DastakV1Auth, type V1CatalogueCategory, type V1CatalogueSku, type V1Order,
} from "./dastakV1";

type Props = DastakV1Auth & {
  accountId: string;
  displayName?: string;
  phoneNumber?: string;
  orderRefreshToken: number;
  section: Extract<CustomerSection, "home" | "search" | "orders">;
  onNavigate: (section: CustomerSection) => void;
  onOpenParcel: () => void;
};

type Cart = Record<string, number>;
const matchingStatuses = new Set(["CREATED", "MATCHING"]);
const cancellableStatuses = new Set(["CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT"]);

export function DastakV1CustomerExperience(props: Props) {
  const auth = useMemo<DastakV1Auth>(() => ({
    accessToken: props.accessToken,
    publishableKey: props.publishableKey,
    supabaseUrl: props.supabaseUrl,
  }), [props.accessToken, props.publishableKey, props.supabaseUrl]);
  const [catalogue, setCatalogue] = useState<Awaited<ReturnType<typeof getV1Catalogue>>>();
  const [searchResults, setSearchResults] = useState<V1CatalogueSku[]>([]);
  const [orders, setOrders] = useState<V1Order[]>([]);
  const [addresses, setAddresses] = useState<CustomerDeliveryAddress[]>([]);
  const [query, setQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<string>();
  const [cart, setCart] = useState<Cart>(() => loadCart(props.accountId));
  const [loading, setLoading] = useState(true);
  const [searching, setSearching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [showingCart, setShowingCart] = useState(false);
  const [showingAddressBook, setShowingAddressBook] = useState(false);
  const [editingAddress, setEditingAddress] = useState<CustomerDeliveryAddress | null>();
  const [selectedOrder, setSelectedOrder] = useState<V1Order>();
  const submissionKeys = useRef(new Map<string, string>());
  const selectedOrderId = selectedOrder?.id;
  const selectedOrderStatus = selectedOrder?.status;

  const refresh = useCallback(async () => {
    try {
      const [nextCatalogue, nextOrders, nextAddresses] = await Promise.all([
        getV1Catalogue({ ...auth, limit: 250 }),
        getV1Orders({ ...auth, limit: 50 }),
        getCustomerAddresses(auth),
      ]);
      setCatalogue(nextCatalogue);
      setOrders(nextOrders.orders);
      setAddresses(nextAddresses.addresses);
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      setLoading(false);
    }
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (props.orderRefreshToken === 0) return;
    void getV1Orders({ ...auth, limit: 50 }).then((result) => setOrders(result.orders)).catch(() => undefined);
  }, [auth, props.orderRefreshToken]);
  useEffect(() => { saveCart(props.accountId, cart); }, [cart, props.accountId]);

  useEffect(() => {
    const dismiss = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || busy) return;
      if (selectedOrderId) setSelectedOrder(undefined);
      else if (showingCart) setShowingCart(false);
    };
    window.addEventListener("keydown", dismiss);
    return () => window.removeEventListener("keydown", dismiss);
  }, [busy, selectedOrderId, showingCart]);

  useEffect(() => {
    const normalized = query.trim();
    if (!normalized) {
      setSearchResults([]);
      setSearching(false);
      return;
    }
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      setSearching(true);
      void getV1Catalogue({ ...auth, query: normalized, limit: 100, signal: controller.signal })
        .then((result) => { setSearchResults(result.skus); setError(undefined); })
        .catch((searchError) => {
          if (!(searchError instanceof DOMException && searchError.name === "AbortError")) setError(message(searchError));
        })
        .finally(() => { if (!controller.signal.aborted) setSearching(false); });
    }, 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [auth, query]);

  useEffect(() => {
    if (!selectedOrderId || !selectedOrderStatus || !matchingStatuses.has(selectedOrderStatus)) return;
    const controller = new AbortController();
    const poll = window.setInterval(() => {
      void getV1Order({ ...auth, orderId: selectedOrderId, signal: controller.signal })
        .then((order) => {
          setSelectedOrder(order);
          setOrders((current) => [order, ...current.filter((item) => item.id !== order.id)]);
        })
        .catch(() => undefined);
    }, 3000);
    return () => { window.clearInterval(poll); controller.abort(); };
  }, [auth, selectedOrderId, selectedOrderStatus]);

  const skuById = useMemo(() => {
    const result = new Map<string, V1CatalogueSku>();
    catalogue?.skus.forEach((sku) => result.set(sku.id, sku));
    searchResults.forEach((sku) => result.set(sku.id, sku));
    return result;
  }, [catalogue, searchResults]);
  const cartLines = useMemo(() => Object.entries(cart).flatMap(([skuId, quantity]) => {
    const sku = skuById.get(skuId);
    return sku && quantity > 0 ? [{ sku, quantity }] : [];
  }), [cart, skuById]);
  const cartCount = cartLines.reduce((total, line) => total + line.quantity, 0);
  const cartSubtotal = cartLines.reduce((total, line) => total + line.sku.sellingPricePaise * line.quantity, 0);
  const defaultAddress = addresses.find((address) => address.isDefault) ?? addresses[0];

  const add = (sku: V1CatalogueSku) => setCart((current) => ({
    ...current, [sku.id]: Math.min((current[sku.id] ?? 0) + 1, 99),
  }));
  const decrement = (skuId: string) => setCart((current) => {
    const quantity = (current[skuId] ?? 0) - 1;
    if (quantity > 0) return { ...current, [skuId]: quantity };
    const next = { ...current };
    delete next[skuId];
    return next;
  });

  const submit = async () => {
    if (!defaultAddress) { setShowingAddressBook(true); return; }
    if (!props.displayName?.trim() || !props.phoneNumber?.trim()) {
      setError("Complete your name and phone number in Account before placing an order.");
      return;
    }
    if (cartLines.length === 0 || busy) return;
    const fingerprint = JSON.stringify({
      addressId: defaultAddress.addressId,
      lines: cartLines.map(({ sku, quantity }) => [sku.id, quantity]).sort(),
      phone: props.phoneNumber,
    });
    const idempotencyKey = submissionKeys.current.get(fingerprint) ?? crypto.randomUUID();
    submissionKeys.current.set(fingerprint, idempotencyKey);
    setBusy(true);
    setError(undefined);
    try {
      const order = await submitV1Order({
        ...auth,
        idempotencyKey,
        order: {
          deliveryAddress: {
            label: defaultAddress.label,
            line1: defaultAddress.address,
            line2: [defaultAddress.building, defaultAddress.floor].filter(Boolean).join(", ") || undefined,
            landmark: defaultAddress.landmark,
            countryCode: "IN",
            latitude: defaultAddress.location.latitude,
            longitude: defaultAddress.location.longitude,
            instructions: defaultAddress.deliveryNotes,
          },
          recipient: { name: props.displayName.trim(), phoneNumber: props.phoneNumber.trim() },
          lines: cartLines.map(({ sku, quantity }) => ({ lineType: "RETAIL_SKU", skuId: sku.id, quantity })),
        },
      });
      submissionKeys.current.delete(fingerprint);
      setOrders((current) => [order, ...current.filter((item) => item.id !== order.id)]);
      setCart({});
      setShowingCart(false);
      setSelectedOrder(order);
    } catch (submitError) {
      setError(message(submitError));
    } finally {
      setBusy(false);
    }
  };

  const cancelOrder = async () => {
    if (!selectedOrder || busy) return;
    setBusy(true);
    setError(undefined);
    try {
      const order = await cancelV1Order({
        ...auth, orderId: selectedOrder.id, expectedVersion: selectedOrder.version, idempotencyKey: crypto.randomUUID(),
      });
      setSelectedOrder(order);
      setOrders((current) => [order, ...current.filter((item) => item.id !== order.id)]);
    } catch (cancelError) {
      setError(message(cancelError));
    } finally {
      setBusy(false);
    }
  };

  const saveAddress = async (draft: CustomerAddressDraft) => {
    setBusy(true);
    setError(undefined);
    try {
      const result = await saveCustomerAddress({
        ...auth, addressId: draft.addressId, label: draft.label, address: draft.place.address,
        building: draft.building, floor: draft.floor, landmark: draft.landmark,
        deliveryNotes: draft.deliveryNotes, location: { latitude: draft.place.latitude, longitude: draft.place.longitude },
        makeDefault: true, idempotencyKey: crypto.randomUUID(),
      });
      setAddresses(result.addresses);
      setEditingAddress(undefined);
      setShowingAddressBook(false);
    } catch (addressError) {
      setError(message(addressError));
    } finally {
      setBusy(false);
    }
  };

  const selectAddress = async (address: CustomerDeliveryAddress) => {
    if (address.isDefault) { setShowingAddressBook(false); return; }
    setBusy(true);
    try {
      const result = await setDefaultCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: crypto.randomUUID() });
      setAddresses(result.addresses);
      setShowingAddressBook(false);
    } catch (addressError) { setError(message(addressError)); }
    finally { setBusy(false); }
  };

  const deleteAddress = async (address: CustomerDeliveryAddress) => {
    setBusy(true);
    try {
      const result = await deleteCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: crypto.randomUUID() });
      setAddresses(result.addresses);
    } catch (addressError) { setError(message(addressError)); }
    finally { setBusy(false); }
  };

  if (loading) return <div className="v1-loading" role="status"><span /> Opening Dastak catalogue</div>;

  return <main className="v1-customer-shell">
    <CustomerHeader address={defaultAddress} count={cartCount} onCart={() => setShowingCart(true)} />
    {error && <div className="v1-alert" role="alert"><CircleAlert size={18} /><span>{error}</span><button type="button" onClick={() => setError(undefined)} aria-label="Dismiss error"><X size={16} /></button></div>}
    {props.section === "home" ? <HomeSection
      categories={catalogue?.categories ?? []}
      skus={catalogue?.skus ?? []}
      selectedCategory={selectedCategory}
      onCategory={setSelectedCategory}
      onSearch={() => props.onNavigate("search")}
      onOrders={() => props.onNavigate("orders")}
      onParcel={props.onOpenParcel}
      onAdd={add}
    /> : props.section === "search" ? <SearchSection
      query={query} onQuery={setQuery} searching={searching}
      skus={query.trim() ? searchResults : catalogue?.skus ?? []} onAdd={add}
    /> : <OrdersSection orders={orders} onOpen={setSelectedOrder} />}

    {cartCount > 0 && !showingCart && <button className="v1-cart-bar" type="button" onClick={() => setShowingCart(true)}>
      <span><ShoppingBag size={18} /> {cartCount} {cartCount === 1 ? "item" : "items"}</span>
      <strong>{formatV1Price(cartSubtotal)}</strong><span>Review <ArrowRight size={17} /></span>
    </button>}
    {showingCart && <CartSheet
      lines={cartLines} subtotal={cartSubtotal} address={defaultAddress} busy={busy}
      onDismiss={() => setShowingCart(false)} onAdd={add} onDecrement={decrement}
      onAddress={() => addresses.length ? setShowingAddressBook(true) : setEditingAddress(null)} onSubmit={submit}
    />}
    {selectedOrder && <MatchingSheet order={selectedOrder} busy={busy} error={error} onDismiss={() => setSelectedOrder(undefined)} onCancel={cancelOrder} />}
    {showingAddressBook && <CustomerAddressBookSheet
      addresses={addresses} selectedAddressId={defaultAddress?.addressId} busy={busy} error={error} context="checkout"
      onDismiss={() => setShowingAddressBook(false)} onAdd={() => { setShowingAddressBook(false); setEditingAddress(null); }}
      onEdit={(address) => { setShowingAddressBook(false); setEditingAddress(address); }} onSelect={selectAddress} onDelete={deleteAddress}
    />}
    {editingAddress !== undefined && <CustomerAddressSheet
      address={editingAddress ?? undefined} busy={busy} error={error} context="checkout"
      onDismiss={() => setEditingAddress(undefined)} onSave={saveAddress}
    />}
  </main>;
}

function CustomerHeader({ address, count, onCart }: { address?: CustomerDeliveryAddress; count: number; onCart: () => void }) {
  return <header className="v1-customer-header">
    <div className="v1-wordmark">Dastak<span>.</span></div>
    <div className="v1-deliver-to"><MapPin size={17} /><span><small>DELIVER TO</small><strong>{address?.label ?? "Choose at checkout"}</strong></span></div>
    <button type="button" onClick={onCart} aria-label={`Basket, ${count} items`}><ShoppingBag size={21} />{count > 0 ? <b>{count}</b> : null}</button>
  </header>;
}

function HomeSection({ categories, skus, selectedCategory, onCategory, onSearch, onOrders, onParcel, onAdd }: {
  categories: V1CatalogueCategory[]; skus: V1CatalogueSku[]; selectedCategory?: string;
  onCategory: (id?: string) => void; onSearch: () => void; onOrders: () => void; onParcel: () => void; onAdd: (sku: V1CatalogueSku) => void;
}) {
  const visible = selectedCategory ? skus.filter((sku) => sku.categoryId === selectedCategory) : skus;
  return <>
    <section className="v1-hero"><p>YOUR EVERYDAY, DELIVERED</p><h1>One basket.<br />Dastak finds every item.</h1><span><ShieldCheck size={18} /> You pay only after your full basket is secured</span></section>
    <button className="v1-search-launch" type="button" onClick={onSearch}><Search size={19} /><span>Search products and essentials</span><ChevronRight size={18} /></button>
    <section className="v1-section"><header><div><p>CANONICAL CATALOGUE</p><h2>Browse categories</h2></div></header>
      <div className="v1-category-rail">
        <button className={!selectedCategory ? "selected" : ""} type="button" onClick={() => onCategory(undefined)}><Sparkles size={22} /><span>All</span></button>
        {categories.map((category) => <button className={selectedCategory === category.id ? "selected" : ""} type="button" key={category.id} onClick={() => onCategory(category.id)}><PackageCheck size={22} /><span>{category.name}</span></button>)}
      </div>
    </section>
    <section className="v1-section"><header><div><p>EXACT PRODUCTS</p><h2>{categories.find((category) => category.id === selectedCategory)?.name ?? "Everyday essentials"}</h2></div><span>{visible.length} products</span></header>
      <ProductGrid skus={visible} onAdd={onAdd} />
    </section>
    <section className="v1-service-band"><PackageCheck size={24} /><div><strong>Send a parcel</strong><span>Door-to-door delivery across your city</span></div><button type="button" onClick={onParcel}>Open <ChevronRight size={17} /></button></section>
    <button className="v1-order-link" type="button" onClick={onOrders}>View your Dastak orders <ArrowRight size={17} /></button>
  </>;
}

function SearchSection({ query, onQuery, searching, skus, onAdd }: { query: string; onQuery: (value: string) => void; searching: boolean; skus: V1CatalogueSku[]; onAdd: (sku: V1CatalogueSku) => void }) {
  const submit = (event: FormEvent) => event.preventDefault();
  return <section className="v1-search-page"><header><p>CANONICAL CATALOGUE</p><h1>Find an exact product</h1><span>Search by product, brand or category. Retail merchant identity stays private.</span></header>
    <form className="v1-search-field" role="search" onSubmit={submit}><Search size={20} /><input autoFocus value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Products, brands and categories" aria-label="Search Dastak products" />{query ? <button type="button" onClick={() => onQuery("")} aria-label="Clear search"><X size={17} /></button> : null}</form>
    {searching ? <div className="v1-inline-loading" role="status"><span /> Searching Dastak</div> : skus.length ? <ProductGrid skus={skus} onAdd={onAdd} /> : <EmptyState title={query ? "No exact matches" : "Catalogue is empty"} copy={query ? "Try another product, brand or category." : "Dastak is preparing launch products."} />}
  </section>;
}

function ProductGrid({ skus, onAdd }: { skus: V1CatalogueSku[]; onAdd: (sku: V1CatalogueSku) => void }) {
  if (!skus.length) return <EmptyState title="No products here yet" copy="Choose another category." />;
  return <div className="v1-product-grid">{skus.map((sku) => <article className="v1-product-card" key={sku.id}>
    <div className="v1-product-art"><ShoppingBag size={30} /></div>
    <div className="v1-product-copy">{sku.brand ? <small>{sku.brand.name.toUpperCase()}</small> : null}<h3>{sku.name}</h3><p>{[sku.variant, sku.packSize].filter(Boolean).join(" · ")}</p>
      <div><span><strong>{formatV1Price(sku.sellingPricePaise)}</strong>{sku.listPricePaise > sku.sellingPricePaise ? <del>{formatV1Price(sku.listPricePaise)}</del> : null}</span><button type="button" onClick={() => onAdd(sku)} aria-label={`Add ${sku.name}`}><Plus size={18} /></button></div>
    </div>
  </article>)}</div>;
}

function CartSheet({ lines, subtotal, address, busy, onDismiss, onAdd, onDecrement, onAddress, onSubmit }: {
  lines: Array<{ sku: V1CatalogueSku; quantity: number }>; subtotal: number; address?: CustomerDeliveryAddress; busy: boolean;
  onDismiss: () => void; onAdd: (sku: V1CatalogueSku) => void; onDecrement: (id: string) => void; onAddress: () => void; onSubmit: () => void;
}) {
  return <div className="v1-overlay" role="presentation"><section className="v1-sheet v1-cart-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-cart-title">
    <header><div><p>DASTAK V1</p><h2 id="v1-cart-title">Your basket</h2></div><button type="button" onClick={onDismiss} aria-label="Close basket"><X size={19} /></button></header>
    <div className="v1-security-note"><ShieldCheck size={20} /><span><strong>Matched before payment</strong><small>Dastak secures the complete basket first. Submission does not charge you.</small></span></div>
    <div className="v1-cart-lines">{lines.map(({ sku, quantity }) => <article key={sku.id}><div><strong>{sku.name}</strong><small>{sku.packSize}</small><b>{formatV1Price(sku.sellingPricePaise * quantity)}</b></div><div className="v1-quantity"><button type="button" onClick={() => onDecrement(sku.id)} aria-label={`Remove one ${sku.name}`}><Minus size={16} /></button><span>{quantity}</span><button type="button" onClick={() => onAdd(sku)} disabled={quantity >= 99} aria-label={`Add one ${sku.name}`}><Plus size={16} /></button></div></article>)}</div>
    <div className="v1-cart-total"><span>Catalogue subtotal</span><strong>{formatV1Price(subtotal)}</strong><small>Delivery, platform fees and final total appear after all items are secured.</small></div>
    <button className="v1-address-button" type="button" onClick={onAddress}><MapPin size={19} /><span><strong>{address ? `Deliver to ${address.label}` : "Add delivery address"}</strong><small>{address?.displayAddress ?? "Add a precise pin and doorstep details."}</small></span><ChevronRight size={18} /></button>
    <button className="primary-button v1-submit" type="button" disabled={busy || !lines.length} onClick={onSubmit}>{busy ? "Placing order…" : address ? "Place order" : "Add address to continue"}<ArrowRight size={18} /></button>
  </section></div>;
}

function OrdersSection({ orders, onOpen }: { orders: V1Order[]; onOpen: (order: V1Order) => void }) {
  return <section className="v1-orders-page"><header><p>YOUR ORDERS</p><h1>Dastak activity</h1><span>Canonical retail orders and live matching status.</span></header>
    {orders.length ? <div className="v1-order-list">{orders.map((order) => <button type="button" key={order.id} onClick={() => onOpen(order)}><span className="v1-order-icon"><PackageCheck size={21} /></span><span><strong>{statusTitle(order.status)}</strong><small>{order.displayOrderNumber} · {order.lines.length} products</small></span><b>{formatV1Price(order.price.totalPaise)}</b><ChevronRight size={18} /></button>)}</div> : <EmptyState title="No Dastak orders yet" copy="Submitted baskets and matching progress will appear here." />}
  </section>;
}

function MatchingSheet({ order, busy, error, onDismiss, onCancel }: { order: V1Order; busy: boolean; error?: string; onDismiss: () => void; onCancel: () => void }) {
  const matching = matchingStatuses.has(order.status);
  return <div className="v1-overlay" role="presentation"><section className="v1-sheet v1-matching-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-order-status-title">
    <header><div><p>{order.displayOrderNumber}</p><h2 id="v1-order-status-title">Order status</h2></div><button type="button" onClick={onDismiss} aria-label="Close order status"><X size={19} /></button></header>
    <div className="v1-status-hero"><span className={matching ? "matching" : ""}>{matching ? <i /> : <Check size={34} />}</span><h3>{statusTitle(order.status)}</h3><p>{statusMessage(order.status)}</p><small><ShieldCheck size={16} /> No charge until the complete basket is secured</small></div>
    <div className="v1-matching-lines">{order.lines.map((line) => <div key={line.id}><span>{line.quantity}× {line.name}</span><strong>{formatV1Price(line.lineTotalPaise)}</strong></div>)}<div className="total"><span>Current total</span><strong>{formatV1Price(order.price.totalPaise)}</strong></div></div>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {cancellableStatuses.has(order.status) ? <button className="v1-cancel" type="button" disabled={busy} onClick={onCancel}>{busy ? "Cancelling…" : "Cancel before payment"}</button> : null}
  </section></div>;
}

function EmptyState({ title, copy }: { title: string; copy: string }) {
  return <div className="v1-empty"><ShoppingBag size={30} /><strong>{title}</strong><span>{copy}</span></div>;
}

function statusTitle(status: V1Order["status"]) {
  switch (status) {
    case "CREATED": case "MATCHING": return "Finding every item";
    case "FULLY_SECURED": case "AWAITING_PAYMENT": return "Your basket is secured";
    case "PAID": case "PREPARING": return "Preparing your order";
    case "PICKUP_IN_PROGRESS": return "Pickup in progress";
    case "OUT_FOR_DELIVERY": return "On the way";
    case "DELIVERED": return "Delivered";
    case "UNAVAILABLE": return "Basket unavailable";
    case "PAYMENT_EXPIRED": return "Payment window expired";
    case "CANCELLED_PREPAYMENT": return "Order cancelled";
    case "DASTAK_FULFILMENT_FAILURE": return "Order needs attention";
  }
}

function statusMessage(status: V1Order["status"]) {
  if (matchingStatuses.has(status)) return "Dastak is matching your exact products. Retail merchant identities stay private.";
  if (status === "FULLY_SECURED" || status === "AWAITING_PAYMENT") return "Every item has been reserved. Secure payment is requested before preparation.";
  if (status === "UNAVAILABLE") return "Dastak could not secure the complete basket. You were not charged.";
  if (status === "CANCELLED_PREPAYMENT") return "This order was cancelled before payment.";
  if (status === "PAYMENT_EXPIRED") return "The reservation expired without payment.";
  return "The latest verified order state is shown below.";
}

function loadCart(accountId: string): Cart {
  try {
    const value = JSON.parse(localStorage.getItem(cartKey(accountId)) ?? "null") as unknown;
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    const source = value as Record<string, unknown>;
    if (source.version !== 1 || !source.quantities || typeof source.quantities !== "object" || Array.isArray(source.quantities)) return {};
    return Object.fromEntries(Object.entries(source.quantities as Record<string, unknown>).filter(([, quantity]) => typeof quantity === "number" && Number.isInteger(quantity) && quantity > 0 && quantity <= 99)) as Cart;
  } catch { return {}; }
}
function saveCart(accountId: string, cart: Cart) {
  try { localStorage.setItem(cartKey(accountId), JSON.stringify({ version: 1, quantities: cart })); } catch { /* Private storage may be unavailable. */ }
}
function cartKey(accountId: string) { return `dastak:v1-cart:${accountId}`; }
function message(error: unknown) { return error instanceof Error ? error.message : "Dastak could not complete this request."; }
