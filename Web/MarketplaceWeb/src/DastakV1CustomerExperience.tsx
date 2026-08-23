import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
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
  cancelV1Order, formatV1Price, getV1Catalogue, getV1Order, getV1Orders,
  getV1Restaurants, reportV1CustomerIssue, submitV1Order, uploadV1CustomerIssueEvidence,
  type DastakV1Auth, type V1CatalogueCategory, type V1CatalogueSku, type V1Order,
  type V1RestaurantMenu, type V1RestaurantMenuItem,
} from "./dastakV1";
import {
  createV1CheckoutSession,
  openRazorpayCheckout,
  reportV1CheckoutFailure,
} from "./payments";

type Props = DastakV1Auth & {
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  phoneNumber?: string;
  orderRefreshToken: number;
  section: Extract<CustomerSection, "home" | "search" | "orders">;
  onNavigate: (section: CustomerSection) => void;
  onOpenParcel: () => void;
};

type Cart = Record<string, number>;
type FoodCartLine = {
  key: string;
  branchId: string;
  restaurantName: string;
  item: V1RestaurantMenuItem;
  optionIds: string[];
  optionNames: string[];
  unitPricePaise: number;
  quantity: number;
};
const matchingStatuses = new Set(["CREATED", "MATCHING"]);
const liveStatuses = new Set([
  "CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT", "PAID", "PREPARING",
  "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY",
]);
const cancellableStatuses = new Set(["CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT"]);

export function DastakV1CustomerExperience(props: Props) {
  const auth = useMemo<DastakV1Auth>(() => ({
    accessToken: props.accessToken,
    publishableKey: props.publishableKey,
    supabaseUrl: props.supabaseUrl,
  }), [props.accessToken, props.publishableKey, props.supabaseUrl]);
  const [catalogue, setCatalogue] = useState<Awaited<ReturnType<typeof getV1Catalogue>>>();
  const [restaurants, setRestaurants] = useState<V1RestaurantMenu[]>([]);
  const [selectedRestaurant, setSelectedRestaurant] = useState<V1RestaurantMenu>();
  const [searchResults, setSearchResults] = useState<V1CatalogueSku[]>([]);
  const [orders, setOrders] = useState<V1Order[]>([]);
  const [addresses, setAddresses] = useState<CustomerDeliveryAddress[]>([]);
  const [query, setQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<string>();
  const [cart, setCart] = useState<Cart>(() => loadCart(props.accountId));
  const [foodCart, setFoodCart] = useState<FoodCartLine[]>([]);
  const [loading, setLoading] = useState(true);
  const [searching, setSearching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [paymentMessage, setPaymentMessage] = useState<string>();
  const [showingCart, setShowingCart] = useState(false);
  const [showingAddressBook, setShowingAddressBook] = useState(false);
  const [editingAddress, setEditingAddress] = useState<CustomerDeliveryAddress | null>();
  const [selectedOrder, setSelectedOrder] = useState<V1Order>();
  const submissionKeys = useRef(new Map<string, string>());
  const selectedOrderId = selectedOrder?.id;
  const selectedOrderStatus = selectedOrder?.status;

  const refresh = useCallback(async () => {
    try {
      const [nextCatalogue, nextRestaurants, nextOrders, nextAddresses] = await Promise.all([
        getV1Catalogue({ ...auth, limit: 250 }),
        getV1Restaurants({ ...auth, limit: 50 }),
        getV1Orders({ ...auth, limit: 50 }),
        getCustomerAddresses(auth),
      ]);
      setCatalogue(nextCatalogue);
      setRestaurants(nextRestaurants);
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
    if (!selectedOrderId || !selectedOrderStatus || !liveStatuses.has(selectedOrderStatus)) return;
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
  const cartCount = cartLines.reduce((total, line) => total + line.quantity, 0) +
    foodCart.reduce((total, line) => total + line.quantity, 0);
  const cartSubtotal = cartLines.reduce((total, line) => total + line.sku.sellingPricePaise * line.quantity, 0) +
    foodCart.reduce((total, line) => total + line.unitPricePaise * line.quantity, 0);
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

  const addFood = (
    restaurant: V1RestaurantMenu,
    item: V1RestaurantMenuItem,
    optionIds: string[],
  ) => {
    const existingBranch = foodCart[0]?.branchId;
    if (existingBranch && existingBranch !== restaurant.restaurant.branchId) {
      setError("A basket can contain food from one Restaurant/Cafe. Remove it before choosing another.");
      return;
    }
    const options = item.optionGroups.flatMap((group) => group.options)
      .filter((option) => optionIds.includes(option.id));
    const normalizedIds = options.map((option) => option.id).sort();
    const key = `${item.id}:${normalizedIds.join(",")}`;
    const unitPricePaise = item.basePricePaise +
      options.reduce((total, option) => total + option.priceDeltaPaise, 0);
    setFoodCart((current) => {
      const found = current.find((line) => line.key === key);
      if (found) {
        return current.map((line) => line.key === key
          ? { ...line, quantity: Math.min(line.quantity + 1, 99) }
          : line);
      }
      return [...current, {
        key,
        branchId: restaurant.restaurant.branchId,
        restaurantName: restaurant.restaurant.name,
        item,
        optionIds: normalizedIds,
        optionNames: options.map((option) => option.name),
        unitPricePaise,
        quantity: 1,
      }];
    });
    setError(undefined);
  };
  const decrementFood = (key: string) => setFoodCart((current) => current.flatMap((line) =>
    line.key !== key
      ? [line]
      : line.quantity > 1
        ? [{ ...line, quantity: line.quantity - 1 }]
        : []
  ));
  const incrementFood = (key: string) => setFoodCart((current) => current.map((line) =>
    line.key === key ? { ...line, quantity: Math.min(line.quantity + 1, 99) } : line
  ));

  const submit = async () => {
    if (!defaultAddress) { setShowingAddressBook(true); return; }
    if (!props.displayName?.trim() || !props.phoneNumber?.trim()) {
      setError("Complete your name and phone number in Account before placing an order.");
      return;
    }
    if ((cartLines.length === 0 && foodCart.length === 0) || busy) return;
    const fingerprint = JSON.stringify({
      addressId: defaultAddress.addressId,
      lines: cartLines.map(({ sku, quantity }) => [sku.id, quantity]).sort(),
      food: foodCart.map(({ item, optionIds, quantity }) => [item.id, optionIds, quantity]).sort(),
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
          restaurantBranchId: foodCart[0]?.branchId,
          lines: [
            ...cartLines.map(({ sku, quantity }) => ({
              lineType: "RETAIL_SKU" as const, skuId: sku.id, quantity,
            })),
            ...foodCart.map(({ item, optionIds, quantity }) => ({
              lineType: "FOOD_MENU_ITEM" as const, menuItemId: item.id, optionIds, quantity,
            })),
          ],
        },
      });
      submissionKeys.current.delete(fingerprint);
      setOrders((current) => [order, ...current.filter((item) => item.id !== order.id)]);
      setCart({});
      setFoodCart([]);
      setShowingCart(false);
      setSelectedOrder(order);
    } catch (submitError) {
      setError(message(submitError));
    } finally {
      setBusy(false);
    }
  };

  const cancelOrder = async () => {
    if (!selectedOrder || busy) return false;
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

  const refreshSelectedOrder = useCallback(async (orderId: string) => {
    const order = await getV1Order({ ...auth, orderId });
    setSelectedOrder(order);
    setOrders((current) => [order, ...current.filter((item) => item.id !== order.id)]);
    return order;
  }, [auth]);

  const payOrder = async () => {
    if (!selectedOrder || selectedOrder.status !== "AWAITING_PAYMENT" || !selectedOrder.payment?.canAttempt || busy) {
      return;
    }
    setBusy(true);
    setError(undefined);
    setPaymentMessage(undefined);
    try {
      const session = await createV1CheckoutSession({
        ...auth,
        orderId: selectedOrder.id,
        idempotencyKey: crypto.randomUUID(),
      });
      const result = await openRazorpayCheckout(session, {
        name: props.displayName,
        phoneNumber: props.phoneNumber,
      });
      if (result !== "success") {
        if (session.attemptId) {
          await reportV1CheckoutFailure({
            ...auth,
            orderId: selectedOrder.id,
            paymentAttemptId: session.attemptId,
            failureCode: result === "failed" ? "CHECKOUT_FAILED" : "CHECKOUT_DISMISSED",
            idempotencyKey: crypto.randomUUID(),
          }).catch(() => undefined);
        }
        await refreshSelectedOrder(selectedOrder.id).catch(() => undefined);
        setPaymentMessage(
          result === "failed"
            ? "Payment failed. Your secured basket is still reserved—try again before the timer ends."
            : "Payment was not completed. Your reservation is unchanged and you can retry.",
        );
        return;
      }

      setPaymentMessage("Payment received. Confirming it securely with Dastak…");
      for (let attempt = 0; attempt < 8; attempt += 1) {
        const order = await refreshSelectedOrder(selectedOrder.id);
        if (order.status === "PAID" || order.status === "PREPARING" || order.status === "PAYMENT_EXPIRED") break;
        await new Promise((resolve) => window.setTimeout(resolve, 1_500));
      }
    } catch (paymentError) {
      setError(message(paymentError));
    } finally {
      setBusy(false);
    }
  };

  const reportIssue = async (input: {
    category: string;
    description: string;
    orderLineId?: string;
    evidenceFile?: File;
  }): Promise<boolean> => {
    if (!selectedOrder || busy) return false;
    setBusy(true);
    setError(undefined);
    try {
      const objectPath = input.evidenceFile
        ? await uploadV1CustomerIssueEvidence(props.client, props.accountId, input.evidenceFile)
        : undefined;
      await reportV1CustomerIssue({
        ...auth,
        orderId: selectedOrder.id,
        orderLineId: input.orderLineId,
        category: input.category,
        description: input.description,
        objectPath,
        contentType: input.evidenceFile?.type,
        idempotencyKey: crypto.randomUUID(),
      });
      await refreshSelectedOrder(selectedOrder.id);
      return true;
    } catch (issueError) {
      setError(message(issueError));
      return false;
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
      restaurants={restaurants}
      categories={catalogue?.categories ?? []}
      skus={catalogue?.skus ?? []}
      selectedCategory={selectedCategory}
      onCategory={setSelectedCategory}
      onSearch={() => props.onNavigate("search")}
      onOrders={() => props.onNavigate("orders")}
      onParcel={props.onOpenParcel}
      onAdd={add}
      onRestaurant={setSelectedRestaurant}
    /> : props.section === "search" ? <SearchSection
      query={query} onQuery={setQuery} searching={searching}
      skus={query.trim() ? searchResults : catalogue?.skus ?? []} onAdd={add}
    /> : <OrdersSection orders={orders} onOpen={setSelectedOrder} />}

    {cartCount > 0 && !showingCart && <button className="v1-cart-bar" type="button" onClick={() => setShowingCart(true)}>
      <span><ShoppingBag size={18} /> {cartCount} {cartCount === 1 ? "item" : "items"}</span>
      <strong>{formatV1Price(cartSubtotal)}</strong><span>Review <ArrowRight size={17} /></span>
    </button>}
    {showingCart && <CartSheet
      lines={cartLines} foodLines={foodCart} subtotal={cartSubtotal} address={defaultAddress} busy={busy}
      onDismiss={() => setShowingCart(false)} onAdd={add} onDecrement={decrement}
      onAddFood={incrementFood} onDecrementFood={decrementFood}
      onAddress={() => addresses.length ? setShowingAddressBook(true) : setEditingAddress(null)} onSubmit={submit}
    />}
    {selectedRestaurant && <RestaurantMenuSheet
      menu={selectedRestaurant}
      onDismiss={() => setSelectedRestaurant(undefined)}
      onAdd={(item, optionIds) => addFood(selectedRestaurant, item, optionIds)}
    />}
    {selectedOrder && <MatchingSheet
      order={selectedOrder} busy={busy} error={error} paymentMessage={paymentMessage}
      onDismiss={() => { setSelectedOrder(undefined); setPaymentMessage(undefined); }}
      onCancel={cancelOrder} onPay={payOrder}
      onReportIssue={reportIssue}
    />}
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

function HomeSection({ restaurants, categories, skus, selectedCategory, onCategory, onSearch, onOrders, onParcel, onAdd, onRestaurant }: {
  restaurants: V1RestaurantMenu[];
  categories: V1CatalogueCategory[]; skus: V1CatalogueSku[]; selectedCategory?: string;
  onCategory: (id?: string) => void; onSearch: () => void; onOrders: () => void; onParcel: () => void;
  onAdd: (sku: V1CatalogueSku) => void; onRestaurant: (restaurant: V1RestaurantMenu) => void;
}) {
  const visible = selectedCategory ? skus.filter((sku) => sku.categoryId === selectedCategory) : skus;
  return <>
    <section className="v1-hero"><p>YOUR EVERYDAY, DELIVERED</p><h1>One basket.<br />Dastak finds every item.</h1><span><ShieldCheck size={18} /> You pay only after your full basket is secured</span></section>
    <button className="v1-search-launch" type="button" onClick={onSearch}><Search size={19} /><span>Search products and essentials</span><ChevronRight size={18} /></button>
    {restaurants.length ? <section className="v1-section"><header><div><p>RESTAURANTS &amp; CAFES</p><h2>Food, in the same Dastak</h2></div><span>Choose one</span></header>
      <div className="v1-restaurant-rail">{restaurants.map((restaurant) => <button type="button" key={restaurant.restaurant.branchId} onClick={() => onRestaurant(restaurant)}>
        <span className="v1-restaurant-art"><ShoppingBag size={28} /></span>
        <span><strong>{restaurant.restaurant.name}</strong><small>{restaurant.restaurant.branchName}</small><b>{restaurant.categories.reduce((total, category) => total + category.items.length, 0)} items</b></span>
        <ChevronRight size={18} />
      </button>)}</div>
    </section> : null}
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

function CartSheet({ lines, foodLines, subtotal, address, busy, onDismiss, onAdd, onDecrement, onAddFood, onDecrementFood, onAddress, onSubmit }: {
  lines: Array<{ sku: V1CatalogueSku; quantity: number }>; subtotal: number; address?: CustomerDeliveryAddress; busy: boolean;
  foodLines: FoodCartLine[]; onDismiss: () => void; onAdd: (sku: V1CatalogueSku) => void;
  onDecrement: (id: string) => void; onAddFood: (key: string) => void; onDecrementFood: (key: string) => void;
  onAddress: () => void; onSubmit: () => void;
}) {
  return <div className="v1-overlay" role="presentation"><section className="v1-sheet v1-cart-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-cart-title">
    <header><div><p>DASTAK V1</p><h2 id="v1-cart-title">Your basket</h2></div><button type="button" onClick={onDismiss} aria-label="Close basket"><X size={19} /></button></header>
    <div className="v1-security-note"><ShieldCheck size={20} /><span><strong>Matched before payment</strong><small>Dastak secures the complete basket first. Submission does not charge you.</small></span></div>
    <div className="v1-cart-lines">
      {foodLines.length ? <p className="v1-cart-group">{foodLines[0].restaurantName}</p> : null}
      {foodLines.map((line) => <article key={line.key}><div><strong>{line.item.name}</strong><small>{line.optionNames.join(" · ") || "Restaurant item"}</small><b>{formatV1Price(line.unitPricePaise * line.quantity)}</b></div><div className="v1-quantity"><button type="button" onClick={() => onDecrementFood(line.key)} aria-label={`Remove one ${line.item.name}`}><Minus size={16} /></button><span>{line.quantity}</span><button type="button" onClick={() => onAddFood(line.key)} disabled={line.quantity >= 99} aria-label={`Add one ${line.item.name}`}><Plus size={16} /></button></div></article>)}
      {lines.length && foodLines.length ? <p className="v1-cart-group">Retail essentials</p> : null}
      {lines.map(({ sku, quantity }) => <article key={sku.id}><div><strong>{sku.name}</strong><small>{sku.packSize}</small><b>{formatV1Price(sku.sellingPricePaise * quantity)}</b></div><div className="v1-quantity"><button type="button" onClick={() => onDecrement(sku.id)} aria-label={`Remove one ${sku.name}`}><Minus size={16} /></button><span>{quantity}</span><button type="button" onClick={() => onAdd(sku)} disabled={quantity >= 99} aria-label={`Add one ${sku.name}`}><Plus size={16} /></button></div></article>)}
    </div>
    <div className="v1-cart-total"><span>Basket subtotal</span><strong>{formatV1Price(subtotal)}</strong><small>Delivery, platform fees and final total appear after the complete Food + Retail basket is secured.</small></div>
    <button className="v1-address-button" type="button" onClick={onAddress}><MapPin size={19} /><span><strong>{address ? `Deliver to ${address.label}` : "Add delivery address"}</strong><small>{address?.displayAddress ?? "Add a precise pin and doorstep details."}</small></span><ChevronRight size={18} /></button>
    <button className="primary-button v1-submit" type="button" disabled={busy || (!lines.length && !foodLines.length)} onClick={onSubmit}>{busy ? "Placing order…" : address ? "Place order" : "Add address to continue"}<ArrowRight size={18} /></button>
  </section></div>;
}

function RestaurantMenuSheet({ menu, onDismiss, onAdd }: {
  menu: V1RestaurantMenu; onDismiss: () => void;
  onAdd: (item: V1RestaurantMenuItem, optionIds: string[]) => void;
}) {
  return <div className="v1-overlay" role="presentation"><section className="v1-sheet v1-menu-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-menu-title">
    <header><div><p>RESTAURANT / CAFE</p><h2 id="v1-menu-title">{menu.restaurant.name}</h2><small>{menu.restaurant.branchName}</small></div><button type="button" onClick={onDismiss} aria-label="Close restaurant menu"><X size={19} /></button></header>
    <div className="v1-security-note"><ShieldCheck size={20} /><span><strong>This restaurant confirms your exact food request</strong><small>Dastak never silently reroutes food to another restaurant. Payment starts only after the whole basket is secured.</small></span></div>
    {menu.categories.map((category) => <section className="v1-menu-category" key={category.id}><h3>{category.name}</h3>{category.description ? <p>{category.description}</p> : null}<div>{category.items.map((item) => <RestaurantItemCard key={item.id} item={item} onAdd={onAdd} />)}</div></section>)}
  </section></div>;
}

function RestaurantItemCard({ item, onAdd }: {
  item: V1RestaurantMenuItem; onAdd: (item: V1RestaurantMenuItem, optionIds: string[]) => void;
}) {
  const [selection, setSelection] = useState<Record<string, string[]>>(() => Object.fromEntries(
    item.optionGroups.map((group) => [group.id, group.options.slice(0, group.minimumSelections).map((option) => option.id)]),
  ));
  const valid = item.optionGroups.every((group) => {
    const count = selection[group.id]?.length ?? 0;
    return count >= group.minimumSelections && count <= group.maximumSelections;
  });
  const optionIds = item.optionGroups.flatMap((group) => selection[group.id] ?? []);
  const total = item.basePricePaise + item.optionGroups.flatMap((group) => group.options)
    .filter((option) => optionIds.includes(option.id))
    .reduce((sum, option) => sum + option.priceDeltaPaise, 0);
  const toggle = (groupId: string, optionId: string, single: boolean, maximum: number) => setSelection((current) => {
    const selected = current[groupId] ?? [];
    if (single) return { ...current, [groupId]: selected.includes(optionId) ? [] : [optionId] };
    if (selected.includes(optionId)) return { ...current, [groupId]: selected.filter((id) => id !== optionId) };
    if (selected.length >= maximum) return current;
    return { ...current, [groupId]: [...selected, optionId] };
  });
  return <article className="v1-menu-item"><div className="v1-menu-item-copy"><strong>{item.name}</strong>{item.description ? <p>{item.description}</p> : null}<b>{formatV1Price(item.basePricePaise)}</b></div>
    {item.optionGroups.map((group) => <fieldset key={group.id}><legend>{group.name} <small>{group.minimumSelections ? "Required" : "Optional"} · up to {group.maximumSelections}</small></legend>{group.options.map((option) => <label key={option.id}><input type={group.selectionType === "SINGLE" ? "radio" : "checkbox"} name={`${item.id}-${group.id}`} checked={(selection[group.id] ?? []).includes(option.id)} onChange={() => toggle(group.id, option.id, group.selectionType === "SINGLE", group.maximumSelections)} /><span>{option.name}</span><b>{option.priceDeltaPaise ? `+${formatV1Price(option.priceDeltaPaise)}` : "Included"}</b></label>)}</fieldset>)}
    <button className="primary-button" type="button" disabled={!valid} onClick={() => onAdd(item, optionIds)}>Add · {formatV1Price(total)}</button>
  </article>;
}

function OrdersSection({ orders, onOpen }: { orders: V1Order[]; onOpen: (order: V1Order) => void }) {
  return <section className="v1-orders-page"><header><p>YOUR ORDERS</p><h1>Dastak activity</h1><span>Canonical retail orders and live matching status.</span></header>
    {orders.length ? <div className="v1-order-list">{orders.map((order) => <button type="button" key={order.id} onClick={() => onOpen(order)}><span className="v1-order-icon"><PackageCheck size={21} /></span><span><strong>{statusTitle(order.status)}</strong><small>{order.displayOrderNumber} · {order.lines.length} products</small></span><b>{formatV1Price(order.price.totalPaise)}</b><ChevronRight size={18} /></button>)}</div> : <EmptyState title="No Dastak orders yet" copy="Submitted baskets and matching progress will appear here." />}
  </section>;
}

function MatchingSheet({
  order, busy, error, paymentMessage, onDismiss, onCancel, onPay, onReportIssue,
}: {
  order: V1Order;
  busy: boolean;
  error?: string;
  paymentMessage?: string;
  onDismiss: () => void;
  onCancel: () => void;
  onPay: () => void;
  onReportIssue: (input: {
    category: string; description: string; orderLineId?: string; evidenceFile?: File;
  }) => Promise<boolean>;
}) {
  const matching = matchingStatuses.has(order.status);
  const preparing = order.status === "PAID" || order.status === "PREPARING" ||
    order.status === "PICKUP_IN_PROGRESS";
  const fulfilmentActive = preparing || order.status === "OUT_FOR_DELIVERY";
  const [now, setNow] = useState(() => Date.now());
  const [reportingIssue, setReportingIssue] = useState(false);
  const [issueCategory, setIssueCategory] = useState("WRONG_SKU");
  const [issueLineId, setIssueLineId] = useState("");
  const [issueDescription, setIssueDescription] = useState("");
  const [issueEvidence, setIssueEvidence] = useState<File>();
  useEffect(() => {
    if (order.status !== "AWAITING_PAYMENT") return;
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, [order.status]);
  const paymentSeconds = order.payment
    ? Math.max(0, Math.ceil((Date.parse(order.payment.expiresAt) - now) / 1_000))
    : 0;
  const paymentReady = order.status === "AWAITING_PAYMENT" && order.payment?.canAttempt && paymentSeconds > 0;
  return <div className="v1-overlay" role="presentation"><section className="v1-sheet v1-matching-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-order-status-title">
    <header><div><p>{order.displayOrderNumber}</p><h2 id="v1-order-status-title">Order status</h2></div><button type="button" onClick={onDismiss} aria-label="Close order status"><X size={19} /></button></header>
    <div className="v1-status-hero"><span className={matching ? "matching" : ""}>{matching ? <i /> : fulfilmentActive ? <PackageCheck size={34} /> : <Check size={34} />}</span><h3>{statusTitle(order.status)}</h3><p>{statusMessage(order.status)}</p>{fulfilmentActive || order.status === "DELIVERED" ? <small><ShieldCheck size={16} /> Secure package custody is tracked by Dastak</small> : <small><ShieldCheck size={16} /> No charge until the complete basket is secured</small>}</div>
    <div className="v1-matching-lines">{order.lines.map((line) => <div key={line.id}><span>{line.quantity}× {line.name}</span><strong>{formatV1Price(line.lineTotalPaise)}</strong></div>)}<div className="total"><span>Current total</span><strong>{formatV1Price(order.price.totalPaise)}</strong></div></div>
    {order.status === "AWAITING_PAYMENT" && order.payment ? <div className="v1-payment-window">
      <span><strong>Reserved for payment</strong><small>{paymentSeconds > 0 ? `${formatDuration(paymentSeconds)} remaining` : "Reservation ending"}</small></span>
      <strong>{formatV1Price(order.payment.amountPaise)}</strong>
    </div> : null}
    {order.payment?.latestAttempt?.status === "FAILED" ? <p className="v1-payment-retry" role="status">Your previous attempt failed. No rematching occurred.</p> : null}
    {order.status === "OUT_FOR_DELIVERY" && order.delivery?.deliveryCode ? <div className="v1-delivery-code" role="status">
      <span><small>DELIVERY CODE</small><strong>{order.delivery.deliveryCode}</strong></span>
      <p>Share this in-app code only when every package is with you. A trusted recipient may use it without a Dastak account.</p>
    </div> : null}
    {order.status === "OUT_FOR_DELIVERY" && order.delivery?.verificationStatus === "BLOCKED" ? <p className="v1-payment-retry" role="status">Delivery verification needs Operations support. Your rider must keep every package secure.</p> : null}
    {order.support?.recovery.map((recovery) => <p className="v1-payment-retry" role="status" key={recovery.id}>{recovery.customerMessage}</p>)}
    {order.support?.issues.length ? <div className="v1-matching-lines" aria-label="Reported issues">
      {order.support.issues.map((issue) => <div key={issue.id}><span>{issue.category.replaceAll("_", " ")} · {issue.status.replaceAll("_", " ")}</span><strong>{issue.resolution ?? "Operations reviewing"}</strong></div>)}
    </div> : null}
    {order.support?.returns.map((customerReturn) => <div className="v1-delivery-code" role="status" key={customerReturn.id}>
      <span><small>RETURN {customerReturn.status.replaceAll("_", " ")}</small><strong>{customerReturn.mission?.pickupCode ?? `${customerReturn.packageCount} pkg`}</strong></span>
      <p>{customerReturn.mission?.pickupCode ? "Share this in-app code only after the assigned rider photographs and accounts for every return package." : "Operations will arrange secure reverse custody when required."}</p>
    </div>)}
    {order.support?.refunds.map((refund) => <p className="v1-payment-message" role="status" key={refund.id}>Refund {refund.status.replaceAll("_", " ").toLowerCase()} · {formatV1Price(refund.amountPaise)} to original payment method</p>)}
    {reportingIssue ? <form className="v1-problem-form" onSubmit={(event) => {
      event.preventDefault();
      void onReportIssue({
        category: issueCategory,
        description: issueDescription,
        orderLineId: issueLineId || undefined,
        evidenceFile: issueEvidence,
      }).then((success) => {
        if (!success) return;
        setReportingIssue(false);
        setIssueDescription("");
        setIssueEvidence(undefined);
      });
    }}>
      <label><span>What went wrong?</span><select value={issueCategory} onChange={(event) => setIssueCategory(event.target.value)}><option value="WRONG_SKU">Wrong product</option><option value="WRONG_QUANTITY">Wrong quantity</option><option value="DAMAGED">Damaged</option><option value="DEFECTIVE">Defective</option><option value="EXPIRED">Expired</option><option value="TAMPERED_OR_BROKEN_SEAL">Seal or tampering</option><option value="INCORRECT_PACKAGE">Incorrect package</option><option value="DELIVERY_PROBLEM">Delivery problem</option><option value="OTHER">Other</option></select></label>
      <label><span>Product (optional)</span><select value={issueLineId} onChange={(event) => setIssueLineId(event.target.value)}><option value="">Whole order</option>{order.lines.map((line) => <option key={line.id} value={line.id}>{line.quantity}× {line.name}</option>)}</select></label>
      <label><span>Details</span><textarea rows={3} minLength={3} maxLength={1000} required value={issueDescription} onChange={(event) => setIssueDescription(event.target.value)} /></label>
      <label className="v1-photo-field"><span>Photo (optional)</span><input type="file" accept="image/jpeg,image/png,image/heic" capture="environment" onChange={(event) => setIssueEvidence(event.target.files?.[0])} /><small>{issueEvidence?.name ?? "JPG, PNG or HEIC up to 10 MB"}</small></label>
      <div><button className="secondary-button" type="button" disabled={busy} onClick={() => setReportingIssue(false)}>Back</button><button className="primary-button" type="submit" disabled={busy || issueDescription.trim().length < 3}>{busy ? "Sending…" : "Send to support"}</button></div>
    </form> : order.support?.canReportIssue ? <button className="secondary-button v1-secondary-action" type="button" disabled={busy} onClick={() => setReportingIssue(true)}><CircleAlert size={17} /> Get help with this order</button> : null}
    {paymentMessage ? <p className="v1-payment-message" role="status">{paymentMessage}</p> : null}
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {paymentReady ? <button className="primary-button v1-pay" type="button" disabled={busy} onClick={onPay}>{busy ? "Opening secure payment…" : `Pay ${formatV1Price(order.payment?.amountPaise ?? order.price.totalPaise)}`}<ArrowRight size={18} /></button> : null}
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
    case "PICKUP_IN_PROGRESS": return "Picking up your order";
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
  if (status === "PAID" || status === "PREPARING") return "Payment is confirmed and your secured items are being prepared.";
  if (status === "PICKUP_IN_PROGRESS") return "Your delivery partner is collecting the complete order for you.";
  if (status === "OUT_FOR_DELIVERY") return "Every package has been collected and your delivery partner is heading to you.";
  if (status === "DELIVERED") return "Every package was securely handed over. Your order is complete.";
  if (status === "UNAVAILABLE") return "Dastak could not secure the complete basket. You were not charged.";
  if (status === "CANCELLED_PREPAYMENT") return "This order was cancelled before payment.";
  if (status === "PAYMENT_EXPIRED") return "The reservation expired without payment.";
  return "The latest verified order state is shown below.";
}

function formatDuration(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
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
