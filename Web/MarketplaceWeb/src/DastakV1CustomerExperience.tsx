import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ArrowRight, Ban, Check, ChevronRight, CircleAlert, ClockAlert, Copy, Download,
  Heart, LockKeyhole, MapPin, Minus, PackageCheck, PackageX, Plus,
  ReceiptText, RefreshCw, RotateCcw, Search, ShieldCheck, ShoppingBag, Sparkles,
  UserRound, X,
} from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import { CustomerAddressBookSheet } from "./CustomerAddressBookSheet";
import { CustomerAddressSheet, type CustomerAddressDraft } from "./CustomerAddressSheet";
import {
  deleteCustomerAddress, getCustomerAddresses, saveCustomerAddress, setDefaultCustomerAddress,
  type CustomerDeliveryAddress,
} from "./customerAddresses";
import type { CustomerSection } from "./customerNavigation";
import {
  getCustomerWishlist,
  setCustomerWishlistItem,
  type CustomerWishlistItem,
  type CustomerWishlistItemKind,
} from "./customerWishlist";
import {
  cancelV1Order, commitV1LaunchPayment, formatV1Price, getV1Catalogue, getV1Order, getV1Orders,
  getV1Restaurants, reportV1CustomerIssue, submitV1Order, uploadV1CustomerIssueEvidence,
  type DastakV1Auth, type V1CatalogueCategory, type V1CatalogueSku, type V1Order,
  type V1OrderCursor, type V1RestaurantMenu, type V1RestaurantMenuItem,
} from "./dastakV1";
import {
  CustomerRouteMap, CustomerTimeline, type CustomerMapPoint,
} from "./CustomerDeliveryDetails";
import { useModalDialog } from "./useModalDialog";
import {
  canReorderV1Order,
  customerPhoneNumber,
  deliveryAddressLine,
  deliveredDurationLabel,
  humanizeV1State,
  isIssueEvidenceRequired,
  isV1OrderActive,
  orderJourneyLabel,
  orderJourneyStep,
  orderJourneySteps,
  orderKindLabel,
  orderItemCount,
  orderLineDetail,
  statusAssurance,
  statusMessage,
  statusTitle,
} from "./v1OrderPresentation";

type Props = DastakV1Auth & {
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  orderRefreshToken: number;
  initialOrderId?: string;
  section: Extract<CustomerSection, "home" | "search" | "orders" | "wishlist" | "payments">;
  onNavigate: (section: CustomerSection) => void;
  onOpenParcel: () => void;
  onOpenOrder: (orderId: string) => void;
  onCloseOrder: () => void;
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
  const [wishlistItems, setWishlistItems] = useState<CustomerWishlistItem[]>([]);
  const [ordersNextCursor, setOrdersNextCursor] = useState<V1OrderCursor>();
  const [addresses, setAddresses] = useState<CustomerDeliveryAddress[]>([]);
  const [query, setQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState<string>();
  const [cart, setCart] = useState<Cart>(() => loadCart(props.accountId));
  const [foodCart, setFoodCart] = useState<FoodCartLine[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingOrders, setLoadingOrders] = useState(true);
  const [loadingMoreOrders, setLoadingMoreOrders] = useState(false);
  const [loadingWishlist, setLoadingWishlist] = useState(true);
  const [wishlistUpdatingIds, setWishlistUpdatingIds] = useState<Set<string>>(new Set());
  const [searching, setSearching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [orderActionError, setOrderActionError] = useState<string>();
  const [paymentMessage, setPaymentMessage] = useState<string>();
  const [showingLaunchPayment, setShowingLaunchPayment] = useState(false);
  const [ordersError, setOrdersError] = useState<string>();
  const [liveOrderError, setLiveOrderError] = useState<string>();
  const [showingCart, setShowingCart] = useState(false);
  const [showingAddressBook, setShowingAddressBook] = useState(false);
  const [editingAddress, setEditingAddress] = useState<CustomerDeliveryAddress | null>();
  const [selectedOrder, setSelectedOrder] = useState<V1Order>();
  const [pendingReorder, setPendingReorder] = useState<V1Order>();
  const submissionKeys = useRef(new Map<string, string>());
  const ordersRequestVersion = useRef(0);
  const ordersPaginationAdvanced = useRef(false);
  const selectedOrderId = selectedOrder?.id;
  const selectedOrderStatus = selectedOrder?.status;
  const onCloseOrder = props.onCloseOrder;

  const refreshStorefront = useCallback(async () => {
    const [nextCatalogue, nextRestaurants, nextAddresses] = await Promise.allSettled([
      getV1Catalogue({ ...auth, limit: 250 }),
      getV1Restaurants({ ...auth, limit: 50 }),
      getCustomerAddresses(auth),
    ]);
    if (nextCatalogue.status === "fulfilled") setCatalogue(nextCatalogue.value);
    if (nextRestaurants.status === "fulfilled") setRestaurants(nextRestaurants.value);
    if (nextAddresses.status === "fulfilled") setAddresses(nextAddresses.value.addresses);
    const firstFailure = [nextCatalogue, nextRestaurants, nextAddresses]
      .find((result) => result.status === "rejected");
    if (firstFailure?.status === "rejected") setError(message(firstFailure.reason));
    else setError(undefined);
    setLoading(false);
  }, [auth]);

  const refreshOrders = useCallback(async (signal?: AbortSignal) => {
    const requestVersion = ++ordersRequestVersion.current;
    setLoadingOrders(true);
    try {
      const result = await getV1Orders({ ...auth, limit: 50, signal });
      if (requestVersion !== ordersRequestVersion.current || signal?.aborted) return;
      setOrders((current) => mergeV1Orders(result.orders, current));
      if (!ordersPaginationAdvanced.current) setOrdersNextCursor(result.nextCursor);
      setOrdersError(undefined);
    } catch (requestError) {
      if (signal?.aborted || requestVersion !== ordersRequestVersion.current) return;
      setOrdersError(message(requestError));
    } finally {
      if (requestVersion === ordersRequestVersion.current && !signal?.aborted) {
        setLoadingOrders(false);
      }
    }
  }, [auth]);

  const refreshWishlist = useCallback(async () => {
    setLoadingWishlist(true);
    try {
      const result = await getCustomerWishlist(auth);
      setWishlistItems(result.items);
    } catch (wishlistError) {
      setError(message(wishlistError));
    } finally {
      setLoadingWishlist(false);
    }
  }, [auth]);

  const loadMoreOrders = useCallback(async () => {
    if (!ordersNextCursor || loadingMoreOrders) return;
    setLoadingMoreOrders(true);
    try {
      const result = await getV1Orders({ ...auth, limit: 50, cursor: ordersNextCursor });
      ordersPaginationAdvanced.current = true;
      setOrders((current) => mergeV1Orders(result.orders, current));
      setOrdersNextCursor(result.nextCursor);
      setOrdersError(undefined);
    } catch (requestError) {
      setOrdersError(message(requestError));
    } finally {
      setLoadingMoreOrders(false);
    }
  }, [auth, loadingMoreOrders, ordersNextCursor]);

  useEffect(() => { void refreshStorefront(); }, [refreshStorefront]);
  useEffect(() => { void refreshWishlist(); }, [refreshWishlist]);
  useEffect(() => {
    const controller = new AbortController();
    void refreshOrders(controller.signal);
    return () => controller.abort();
  }, [refreshOrders]);
  useEffect(() => {
    if (!props.initialOrderId) {
      setSelectedOrder(undefined);
      setOrderActionError(undefined);
      setLiveOrderError(undefined);
      return;
    }
    const controller = new AbortController();
    void getV1Order({ ...auth, orderId: props.initialOrderId, signal: controller.signal })
      .then((order) => {
        setSelectedOrder((current) => newerOrder(current, order));
        setOrders((current) => mergeV1Orders([order], current));
        setOrderActionError(undefined);
        setLiveOrderError(undefined);
      })
      .catch((requestError) => {
        if (!controller.signal.aborted) setLiveOrderError(message(requestError));
      });
    return () => controller.abort();
  }, [auth, props.initialOrderId]);
  useEffect(() => {
    if (props.orderRefreshToken === 0) return;
    void refreshOrders();
  }, [props.orderRefreshToken, refreshOrders]);
  useEffect(() => { saveCart(props.accountId, cart); }, [cart, props.accountId]);

  useEffect(() => {
    const dismiss = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || busy) return;
      if (showingCart) setShowingCart(false);
    };
    window.addEventListener("keydown", dismiss);
    return () => window.removeEventListener("keydown", dismiss);
  }, [busy, showingCart]);

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
    let timer: number | undefined;
    let stopped = false;
    const poll = async () => {
      try {
        const order = await getV1Order({ ...auth, orderId: selectedOrderId, signal: controller.signal });
        if (stopped) return;
        setSelectedOrder((current) => newerOrder(current, order));
        setOrders((current) => mergeV1Orders([order], current));
        setLiveOrderError(undefined);
        if (liveStatuses.has(order.status)) timer = window.setTimeout(poll, 3_000);
      } catch (requestError) {
        if (stopped || controller.signal.aborted) return;
        setLiveOrderError(message(requestError));
        timer = window.setTimeout(poll, 5_000);
      }
    };
    timer = window.setTimeout(poll, 3_000);
    return () => {
      stopped = true;
      if (timer !== undefined) window.clearTimeout(timer);
      controller.abort();
    };
  }, [auth, selectedOrderId, selectedOrderStatus]);

  const skuById = useMemo(() => {
    const result = new Map<string, V1CatalogueSku>();
    catalogue?.skus.forEach((sku) => result.set(sku.id, sku));
    searchResults.forEach((sku) => result.set(sku.id, sku));
    return result;
  }, [catalogue, searchResults]);
  const menuItemById = useMemo(() => {
    const result = new Map<string, { restaurant: V1RestaurantMenu; item: V1RestaurantMenuItem }>();
    restaurants.forEach((restaurant) => restaurant.categories.forEach((category) =>
      category.items.forEach((item) => result.set(item.id, { restaurant, item }))
    ));
    return result;
  }, [restaurants]);
  const wishlistIds = useMemo(
    () => new Set(wishlistItems.map((item) => `${item.kind}:${item.itemId}`)),
    [wishlistItems],
  );
  const cartLines = useMemo(() => Object.entries(cart).flatMap(([skuId, quantity]) => {
    const sku = skuById.get(skuId);
    return sku && quantity > 0 ? [{ sku, quantity }] : [];
  }), [cart, skuById]);
  const cartCount = cartLines.reduce((total, line) => total + line.quantity, 0) +
    foodCart.reduce((total, line) => total + line.quantity, 0);
  const cartSubtotal = cartLines.reduce((total, line) => total + line.sku.sellingPricePaise * line.quantity, 0) +
    foodCart.reduce((total, line) => total + line.unitPricePaise * line.quantity, 0);
  const defaultAddress = addresses.find((address) => address.isDefault) ?? addresses[0];

  const toggleWishlist = async (itemKind: CustomerWishlistItemKind, itemId: string) => {
    if (wishlistUpdatingIds.has(itemId)) return;
    setWishlistUpdatingIds((current) => new Set(current).add(itemId));
    try {
      const result = await setCustomerWishlistItem({
        ...auth,
        itemKind,
        itemId,
        wished: !wishlistIds.has(`${itemKind}:${itemId}`),
        idempotencyKey: crypto.randomUUID(),
      });
      setWishlistItems(result.items);
      setError(undefined);
    } catch (wishlistError) {
      setError(message(wishlistError));
    } finally {
      setWishlistUpdatingIds((current) => {
        const next = new Set(current);
        next.delete(itemId);
        return next;
      });
    }
  };

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

  const imageUrlForLine = useCallback((line: V1Order["lines"][number]) => {
    const imageKey = line.skuId
      ? skuById.get(line.skuId)?.imageKey
      : line.menuItemId ? menuItemById.get(line.menuItemId)?.item.imageKey : undefined;
    return catalogueImageUrl(props.supabaseUrl, imageKey ?? null);
  }, [menuItemById, props.supabaseUrl, skuById]);

  const reorderOrder = useCallback((order: V1Order) => {
    const nextCart: Cart = {};
    const nextFoodCart: FoodCartLine[] = [];
    let addedUnits = 0;
    let skippedLines = 0;

    order.lines.forEach((line) => {
      const quantity = Math.min(Math.max(line.quantity, 1), 99);
      if (line.skuId && skuById.has(line.skuId)) {
        nextCart[line.skuId] = quantity;
        addedUnits += quantity;
        return;
      }
      if (line.menuItemId) {
        const current = menuItemById.get(line.menuItemId);
        if (current && current.restaurant.restaurant.branchId === order.restaurant?.branchId) {
          const availableOptions = new Set(current.item.optionGroups.flatMap((group) =>
            group.options.map((option) => option.id)
          ));
          const optionIds = line.foodSelection?.options.map((option) => option.id) ?? [];
          if (optionIds.every((id) => availableOptions.has(id))) {
            const options = current.item.optionGroups.flatMap((group) => group.options)
              .filter((option) => optionIds.includes(option.id));
            const normalizedIds = options.map((option) => option.id).sort();
            nextFoodCart.push({
              key: `${current.item.id}:${normalizedIds.join(",")}`,
              branchId: current.restaurant.restaurant.branchId,
              restaurantName: current.restaurant.restaurant.name,
              item: current.item,
              optionIds: normalizedIds,
              optionNames: options.map((option) => option.name),
              unitPricePaise: current.item.basePricePaise +
                options.reduce((total, option) => total + option.priceDeltaPaise, 0),
              quantity,
            });
            addedUnits += quantity;
            return;
          }
        }
      }
      skippedLines += 1;
    });

    setPendingReorder(undefined);
    if (!addedUnits) {
      setError("These items are not currently available to reorder.");
      return;
    }
    setCart(nextCart);
    setFoodCart(nextFoodCart);
    if (selectedOrderId === order.id) {
      setSelectedOrder(undefined);
      setOrderActionError(undefined);
      setLiveOrderError(undefined);
      onCloseOrder();
    }
    setError(skippedLines
      ? `Added ${addedUnits} available item${addedUnits === 1 ? "" : "s"}; ${skippedLines} unavailable line${skippedLines === 1 ? " was" : "s were"} skipped.`
      : undefined);
    setShowingCart(true);
  }, [menuItemById, onCloseOrder, selectedOrderId, skuById]);

  const requestReorder = useCallback((order: V1Order) => {
    if (cartCount > 0) setPendingReorder(order);
    else reorderOrder(order);
  }, [cartCount, reorderOrder]);

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
      setOrders((current) => mergeV1Orders([order], current));
      setCart({});
      setFoodCart([]);
      setShowingCart(false);
      setSelectedOrder(order);
      props.onOpenOrder(order.id);
    } catch (submitError) {
      setError(message(submitError));
    } finally {
      setBusy(false);
    }
  };

  const cancelOrder = async () => {
    if (!selectedOrder || busy) return false;
    setBusy(true);
    setOrderActionError(undefined);
    try {
      const order = await cancelV1Order({
        ...auth, orderId: selectedOrder.id, expectedVersion: selectedOrder.version, idempotencyKey: crypto.randomUUID(),
      });
      setSelectedOrder((current) => newerOrder(current, order));
      setOrders((current) => mergeV1Orders([order], current));
    } catch (cancelError) {
      setOrderActionError(message(cancelError));
    } finally {
      setBusy(false);
    }
  };

  const refreshSelectedOrder = useCallback(async (orderId: string) => {
    const order = await getV1Order({ ...auth, orderId });
    setSelectedOrder((current) => newerOrder(current, order));
    setOrders((current) => mergeV1Orders([order], current));
    setLiveOrderError(undefined);
    return order;
  }, [auth]);

  const payOrder = () => {
    if (selectedOrder?.status === "AWAITING_PAYMENT" && selectedOrder.launchPayment?.canCommit) {
      setOrderActionError(undefined);
      setPaymentMessage(undefined);
      setShowingLaunchPayment(true);
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
    setOrderActionError(undefined);
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
      setOrderActionError(message(issueError));
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

  if (loading && props.section !== "orders") {
    return <div className="v1-loading" role="status"><span /> Opening Dastak catalogue</div>;
  }

  if (showingLaunchPayment && selectedOrder) {
    return <LaunchPaymentScreen
      auth={auth}
      order={selectedOrder}
      onDismiss={() => {
        setShowingLaunchPayment(false);
        void refreshSelectedOrder(selectedOrder.id).catch((requestError) => setOrderActionError(message(requestError)));
      }}
      onCommitted={(order) => {
        setSelectedOrder(order);
        setOrders((current) => mergeV1Orders([order], current));
        setShowingLaunchPayment(false);
        setPaymentMessage("Order confirmed. Your basket is now being prepared; pay your delivery partner at the doorstep.");
      }}
    />;
  }

  return <main className="v1-customer-shell">
    <CustomerHeader address={defaultAddress} count={cartCount} onCart={() => setShowingCart(true)} />
    {error && <div className="v1-alert" role="alert"><CircleAlert size={18} /><span>{error}</span><button type="button" onClick={() => setError(undefined)} aria-label="Dismiss error"><X size={16} /></button></div>}
    {props.section === "home" ? <HomeSection
      supabaseUrl={props.supabaseUrl}
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
      wishlistIds={wishlistIds}
      wishlistUpdatingIds={wishlistUpdatingIds}
      onWishlist={toggleWishlist}
    /> : props.section === "search" ? <SearchSection
      supabaseUrl={props.supabaseUrl}
      query={query} onQuery={setQuery} searching={searching}
      skus={query.trim() ? searchResults : catalogue?.skus ?? []} onAdd={add}
      wishlistIds={wishlistIds} wishlistUpdatingIds={wishlistUpdatingIds} onWishlist={toggleWishlist}
    /> : props.section === "wishlist" ? <WishlistSection
      supabaseUrl={props.supabaseUrl}
      items={wishlistItems}
      loading={loadingWishlist}
      skuById={skuById}
      menuItemById={menuItemById}
      updatingIds={wishlistUpdatingIds}
      onRefresh={() => void refreshWishlist()}
      onAdd={add}
      onAddFood={addFood}
      onChooseFood={(restaurant) => setSelectedRestaurant(restaurant)}
      onRemove={(kind, itemId) => void toggleWishlist(kind, itemId)}
    /> : props.section === "payments" ? <PaymentsSection
      orders={orders}
      loading={loadingOrders}
      onRefresh={() => void refreshOrders()}
      onOpen={(order) => {
        setSelectedOrder(order);
        props.onOpenOrder(order.id);
      }}
    /> : <OrdersSection
      imageUrlForLine={imageUrlForLine}
      orders={orders}
      loading={loadingOrders}
      loadingMore={loadingMoreOrders}
      canLoadMore={Boolean(ordersNextCursor)}
      error={ordersError}
      onRefresh={() => void refreshOrders()}
      onLoadMore={() => void loadMoreOrders()}
      onReorder={requestReorder}
      onOpen={(order) => {
        setSelectedOrder(order);
        setOrderActionError(undefined);
        setLiveOrderError(undefined);
        props.onOpenOrder(order.id);
      }}
    />}

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
      wishlistIds={wishlistIds}
      wishlistUpdatingIds={wishlistUpdatingIds}
      onWishlist={(itemId) => void toggleWishlist("MENU_ITEM", itemId)}
    />}
    {selectedOrder && <MatchingSheet
      order={selectedOrder} busy={busy} error={orderActionError} liveError={liveOrderError}
      paymentMessage={paymentMessage}
      imageUrlForLine={imageUrlForLine}
      onDismiss={() => {
        setSelectedOrder(undefined);
        setOrderActionError(undefined);
        setPaymentMessage(undefined);
        setLiveOrderError(undefined);
        props.onCloseOrder();
      }}
      onCancel={cancelOrder} onPay={payOrder}
      onRefresh={() => void refreshSelectedOrder(selectedOrder.id).catch((requestError) => {
        setLiveOrderError(message(requestError));
      })}
      onReportIssue={reportIssue}
      onReorder={() => requestReorder(selectedOrder)}
    />}
    {pendingReorder && <BasketReplacementDialog
      busy={busy}
      onDismiss={() => setPendingReorder(undefined)}
      onConfirm={() => reorderOrder(pendingReorder)}
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

function HomeSection({ supabaseUrl, restaurants, categories, skus, selectedCategory, onCategory, onSearch, onOrders, onParcel, onAdd, onRestaurant, wishlistIds, wishlistUpdatingIds, onWishlist }: {
  supabaseUrl: string;
  restaurants: V1RestaurantMenu[];
  categories: V1CatalogueCategory[]; skus: V1CatalogueSku[]; selectedCategory?: string;
  onCategory: (id?: string) => void; onSearch: () => void; onOrders: () => void; onParcel: () => void;
  onAdd: (sku: V1CatalogueSku) => void; onRestaurant: (restaurant: V1RestaurantMenu) => void;
  wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>;
  onWishlist: (kind: CustomerWishlistItemKind, itemId: string) => void;
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
      <ProductGrid supabaseUrl={supabaseUrl} skus={visible} onAdd={onAdd} wishlistIds={wishlistIds} wishlistUpdatingIds={wishlistUpdatingIds} onWishlist={onWishlist} />
    </section>
    <section className="v1-service-band"><PackageCheck size={24} /><div><strong>Send a parcel</strong><span>Door-to-door delivery across your city</span></div><button type="button" onClick={onParcel}>Open <ChevronRight size={17} /></button></section>
    <button className="v1-order-link" type="button" onClick={onOrders}>View your Dastak orders <ArrowRight size={17} /></button>
  </>;
}

function SearchSection({ supabaseUrl, query, onQuery, searching, skus, onAdd, wishlistIds, wishlistUpdatingIds, onWishlist }: { supabaseUrl: string; query: string; onQuery: (value: string) => void; searching: boolean; skus: V1CatalogueSku[]; onAdd: (sku: V1CatalogueSku) => void; wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>; onWishlist: (kind: CustomerWishlistItemKind, itemId: string) => void }) {
  const submit = (event: FormEvent) => event.preventDefault();
  return <section className="v1-search-page"><header><p>CANONICAL CATALOGUE</p><h1>Find an exact product</h1><span>Search by product, brand or category. Retail merchant identity stays private.</span></header>
    <form className="v1-search-field" role="search" onSubmit={submit}><Search size={20} /><input autoFocus value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Products, brands and categories" aria-label="Search Dastak products" />{query ? <button type="button" onClick={() => onQuery("")} aria-label="Clear search"><X size={17} /></button> : null}</form>
    {searching ? <div className="v1-inline-loading" role="status"><span /> Searching Dastak</div> : skus.length ? <ProductGrid supabaseUrl={supabaseUrl} skus={skus} onAdd={onAdd} wishlistIds={wishlistIds} wishlistUpdatingIds={wishlistUpdatingIds} onWishlist={onWishlist} /> : <EmptyState title={query ? "No exact matches" : "Catalogue is empty"} copy={query ? "Try another product, brand or category." : "Dastak is preparing launch products."} />}
  </section>;
}

function ProductGrid({ supabaseUrl, skus, onAdd, wishlistIds, wishlistUpdatingIds, onWishlist }: { supabaseUrl: string; skus: V1CatalogueSku[]; onAdd: (sku: V1CatalogueSku) => void; wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>; onWishlist: (kind: CustomerWishlistItemKind, itemId: string) => void }) {
  if (!skus.length) return <EmptyState title="No products here yet" copy="Choose another category." />;
  return <div className="v1-product-grid">{skus.map((sku) => <article className="v1-product-card" key={sku.id}>
    <ProductImage className="v1-product-art" src={catalogueImageUrl(supabaseUrl, sku.imageKey ?? null)} alt="" />
    <button className="v1-wishlist-button" type="button" disabled={wishlistUpdatingIds.has(sku.id)} onClick={() => onWishlist("RETAIL_SKU", sku.id)} aria-label={wishlistIds.has(`RETAIL_SKU:${sku.id}`) ? `Remove ${sku.name} from Wishlist` : `Save ${sku.name} to Wishlist`}>
      <Heart size={18} fill={wishlistIds.has(`RETAIL_SKU:${sku.id}`) ? "currentColor" : "none"} />
    </button>
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
    <div className="v1-security-note"><ShieldCheck size={20} /><span><strong>Matched before confirmation</strong><small>Dastak secures the complete basket first. You pay the delivery partner later by UPI or cash.</small></span></div>
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

function RestaurantMenuSheet({ menu, onDismiss, onAdd, wishlistIds, wishlistUpdatingIds, onWishlist }: {
  menu: V1RestaurantMenu; onDismiss: () => void;
  onAdd: (item: V1RestaurantMenuItem, optionIds: string[]) => void;
  wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>; onWishlist: (itemId: string) => void;
}) {
  return <div className="v1-overlay" role="presentation"><section className="v1-sheet v1-menu-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-menu-title">
    <header><div><p>RESTAURANT / CAFE</p><h2 id="v1-menu-title">{menu.restaurant.name}</h2><small>{menu.restaurant.branchName}</small></div><button type="button" onClick={onDismiss} aria-label="Close restaurant menu"><X size={19} /></button></header>
    <div className="v1-security-note"><ShieldCheck size={20} /><span><strong>This restaurant confirms your exact food request</strong><small>Dastak never silently reroutes food to another restaurant. Payment starts only after the whole basket is secured.</small></span></div>
    {menu.categories.map((category) => <section className="v1-menu-category" key={category.id}><h3>{category.name}</h3>{category.description ? <p>{category.description}</p> : null}<div>{category.items.map((item) => <RestaurantItemCard key={item.id} item={item} onAdd={onAdd} wished={wishlistIds.has(`MENU_ITEM:${item.id}`)} updatingWishlist={wishlistUpdatingIds.has(item.id)} onWishlist={() => onWishlist(item.id)} />)}</div></section>)}
  </section></div>;
}

function RestaurantItemCard({ item, onAdd, wished, updatingWishlist, onWishlist }: {
  item: V1RestaurantMenuItem; onAdd: (item: V1RestaurantMenuItem, optionIds: string[]) => void;
  wished: boolean; updatingWishlist: boolean; onWishlist: () => void;
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
  return <article className="v1-menu-item"><div className="v1-menu-item-copy"><strong>{item.name}</strong>{item.description ? <p>{item.description}</p> : null}<b>{formatV1Price(item.basePricePaise)}</b></div><button className="v1-menu-wishlist" type="button" disabled={updatingWishlist} onClick={onWishlist} aria-label={wished ? `Remove ${item.name} from Wishlist` : `Save ${item.name} to Wishlist`}><Heart size={18} fill={wished ? "currentColor" : "none"} /></button>
    {item.optionGroups.map((group) => <fieldset key={group.id}><legend>{group.name} <small>{group.minimumSelections ? "Required" : "Optional"} · up to {group.maximumSelections}</small></legend>{group.options.map((option) => <label key={option.id}><input type={group.selectionType === "SINGLE" ? "radio" : "checkbox"} name={`${item.id}-${group.id}`} checked={(selection[group.id] ?? []).includes(option.id)} onChange={() => toggle(group.id, option.id, group.selectionType === "SINGLE", group.maximumSelections)} /><span>{option.name}</span><b>{option.priceDeltaPaise ? `+${formatV1Price(option.priceDeltaPaise)}` : "Included"}</b></label>)}</fieldset>)}
    <button className="primary-button" type="button" disabled={!valid} onClick={() => onAdd(item, optionIds)}>Add · {formatV1Price(total)}</button>
  </article>;
}

function WishlistSection({
  supabaseUrl, items, loading, skuById, menuItemById, updatingIds,
  onRefresh, onAdd, onAddFood, onChooseFood, onRemove,
}: {
  supabaseUrl: string;
  items: CustomerWishlistItem[];
  loading: boolean;
  skuById: Map<string, V1CatalogueSku>;
  menuItemById: Map<string, { restaurant: V1RestaurantMenu; item: V1RestaurantMenuItem }>;
  updatingIds: Set<string>;
  onRefresh: () => void;
  onAdd: (sku: V1CatalogueSku) => void;
  onAddFood: (restaurant: V1RestaurantMenu, item: V1RestaurantMenuItem, optionIds: string[]) => void;
  onChooseFood: (restaurant: V1RestaurantMenu) => void;
  onRemove: (kind: CustomerWishlistItemKind, itemId: string) => void;
}) {
  const retail = items.flatMap((saved) => {
    if (saved.kind !== "RETAIL_SKU") return [];
    const sku = skuById.get(saved.itemId);
    return sku ? [{ saved, sku }] : [];
  });
  const food = items.flatMap((saved) => {
    if (saved.kind !== "MENU_ITEM") return [];
    const selection = menuItemById.get(saved.itemId);
    return selection ? [{ saved, ...selection }] : [];
  });
  const unresolved = items.length - retail.length - food.length;

  return <section className="v1-wishlist-page">
    <header className="v1-feature-header">
      <div><p>SAVED FOR LATER</p><h1>Things worth remembering</h1><span>Prices and availability refresh from Dastak's current catalogue before anything reaches your basket.</span></div>
      <button type="button" onClick={onRefresh} disabled={loading}><RefreshCw size={17} className={loading ? "spinning" : ""} /> Refresh</button>
    </header>
    {loading && !items.length ? <div className="v1-inline-loading" role="status"><span /> Opening your Wishlist</div>
      : !items.length ? <EmptyState title="Your Wishlist is ready" copy="Tap the heart on a product or Restaurant/Cafe item to save it here." />
        : <>
          {retail.length ? <section className="v1-saved-group"><header><h2>Retail essentials</h2><span>{retail.length}</span></header><div className="v1-saved-list">
            {retail.map(({ saved, sku }) => <article key={saved.itemId}>
              <ProductImage src={catalogueImageUrl(supabaseUrl, sku.imageKey ?? null)} alt="" />
              <div><small>{sku.brand?.name?.toUpperCase() ?? "DASTAK CATALOGUE"}</small><strong>{sku.name}</strong><span>{[sku.variant, sku.packSize].filter(Boolean).join(" · ")}</span><b>{formatV1Price(sku.sellingPricePaise)}</b></div>
              <div className="v1-saved-actions"><button type="button" disabled={updatingIds.has(sku.id)} onClick={() => onRemove("RETAIL_SKU", sku.id)} aria-label={`Remove ${sku.name} from Wishlist`}><Heart size={18} fill="currentColor" /></button><button type="button" onClick={() => onAdd(sku)}><Plus size={17} /> Add</button></div>
            </article>)}
          </div></section> : null}
          {food.length ? <section className="v1-saved-group"><header><h2>Restaurant &amp; Cafe</h2><span>{food.length}</span></header><div className="v1-saved-list">
            {food.map(({ saved, restaurant, item }) => <article key={saved.itemId}>
              <ProductImage src={catalogueImageUrl(supabaseUrl, item.imageKey ?? null)} alt="" />
              <div><small>{restaurant.restaurant.name.toUpperCase()}</small><strong>{item.name}</strong><span>{restaurant.restaurant.branchName}</span><b>{formatV1Price(item.basePricePaise)}</b></div>
              <div className="v1-saved-actions"><button type="button" disabled={updatingIds.has(item.id)} onClick={() => onRemove("MENU_ITEM", item.id)} aria-label={`Remove ${item.name} from Wishlist`}><Heart size={18} fill="currentColor" /></button><button type="button" onClick={() => item.optionGroups.length ? onChooseFood(restaurant) : onAddFood(restaurant, item, [])}>{item.optionGroups.length ? "Choose" : <><Plus size={17} /> Add</>}</button></div>
            </article>)}
          </div></section> : null}
          {unresolved > 0 ? <div className="v1-unavailable-note"><PackageX size={18} /><span>{unresolved} saved {unresolved === 1 ? "item is" : "items are"} not available in your current area.</span></div> : null}
        </>}
  </section>;
}

function LaunchPaymentScreen({ auth, order, onDismiss, onCommitted }: {
  auth: DastakV1Auth;
  order: V1Order;
  onDismiss: () => void;
  onCommitted: (order: V1Order) => void;
}) {
  const [now, setNow] = useState(() => Date.now());
  const [state, setState] = useState<"ready" | "confirming" | "committed" | "failure">("ready");
  const [error, setError] = useState<string>();
  const key = useRef(crypto.randomUUID());
  const expiry = order.launchPayment?.reservationExpiresAt ?? order.payment?.expiresAt;
  const secondsRemaining = expiry ? Math.max(0, Math.ceil((Date.parse(expiry) - now) / 1_000)) : 0;
  const expired = order.launchPayment?.reservationState === "EXPIRED" || secondsRemaining === 0;

  useEffect(() => {
    if (!expiry || expired) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, [expired, expiry]);

  const confirm = async () => {
    if (expired || state === "confirming") return;
    setState("confirming");
    setError(undefined);
    try {
      const committed = await commitV1LaunchPayment({
        ...auth,
        orderId: order.id,
        expectedVersion: order.version,
        idempotencyKey: key.current,
      });
      setState("committed");
      window.setTimeout(() => onCommitted(committed), 450);
    } catch (requestError) {
      key.current = crypto.randomUUID();
      setState("failure");
      setError(message(requestError));
    }
  };

  return <main className="v1-launch-payment-page">
    <section className="v1-launch-payment-card" aria-labelledby="launch-payment-title">
      <header><button type="button" onClick={onDismiss} disabled={state === "confirming"} aria-label="Back to order"><X size={19} /></button><div><p>SECURED CHECKOUT</p><h1 id="launch-payment-title">Confirm your order</h1></div></header>
      <div className="v1-launch-payment-total"><span><small>AUTHORITATIVE TOTAL</small><strong>{formatV1Price(order.launchPayment?.amountPaise ?? order.price.totalPaise)}</strong></span><ShieldCheck size={27} /></div>
      <section className="v1-launch-payment-reservation" aria-live="polite"><PackageCheck size={21} /><span><strong>{expired ? "Reservation expired" : "Your full basket is secured"}</strong><small>{expired ? "Return to the order to refresh its current state." : `${formatDuration(secondsRemaining)} remaining to confirm`}</small></span></section>
      <section className="v1-launch-payment-address"><MapPin size={20} /><span><small>DELIVER TO</small><strong>{orderAddress(order)}</strong></span></section>
      <section className="v1-launch-payment-option" aria-label="Selected payment option"><span aria-hidden="true"><Check size={18} /></span><div><strong>Pay via UPI/Cash on Delivery</strong><small>Pay the delivery partner at your doorstep by UPI or cash. No charge now.</small></div></section>
      <div className="v1-launch-payment-assurance"><LockKeyhole size={18} /><span>Dastak will confirm the full secured basket and begin preparation immediately.</span></div>
      {state === "committed" ? <p className="v1-launch-payment-success" role="status"><Check size={18} /> Order confirmed. Opening your Preparing journey…</p> : null}
      {error ? <div className="v1-launch-payment-error" role="alert"><CircleAlert size={18} /><span>{error}</span></div> : null}
      {expired ? <button className="secondary-button" type="button" onClick={onDismiss}>Refresh order</button> : <button className="primary-button" type="button" disabled={state === "confirming" || state === "committed"} onClick={() => void confirm()}>{state === "confirming" ? "Confirming order…" : state === "failure" ? "Try confirming again" : "Confirm order"}<ArrowRight size={18} /></button>}
    </section>
  </main>;
}

function PaymentsSection({ orders, loading, onRefresh, onOpen }: {
  orders: V1Order[];
  loading: boolean;
  onRefresh: () => void;
  onOpen: (order: V1Order) => void;
}) {
  const paid = orders.filter((order) => order.launchPayment?.state === "PAYMENT_COLLECTED" || Boolean(order.paidAt));
  return <section className="v1-payments-page">
    <header className="v1-feature-header">
      <div><p>PAYMENTS</p><h1>Pay at your doorstep</h1><span>Confirm after Dastak secures your full basket. Pay the delivery partner by UPI or cash—there is no charge now.</span></div>
      <button type="button" onClick={onRefresh} disabled={loading}><RefreshCw size={17} className={loading ? "spinning" : ""} /> Refresh</button>
    </header>
    <section className="v1-payment-security"><LockKeyhole size={26} /><div><strong>Pay via UPI/Cash on Delivery</strong><span>Your delivery partner records the exact amount as collected before delivery is completed.</span></div></section>
    <section className="v1-payment-activity"><header><h2>Recent payment activity</h2><span>{paid.length}</span></header>
      {loading && !paid.length ? <div className="v1-inline-loading" role="status"><span /> Loading payments</div>
        : !paid.length ? <EmptyState title="No collected payments yet" copy="Completed doorstep collections will appear here with their confirmed total." />
          : <div>{paid.slice(0, 20).map((order) => <button type="button" key={order.id} onClick={() => onOpen(order)}><span className="v1-payment-status"><ShieldCheck size={18} /></span><span><strong>{order.displayOrderNumber}</strong><small>{order.launchPayment?.collectedAt ? `Collected ${formatOrderDate(order.launchPayment.collectedAt)}` : order.paidAt ? formatOrderDate(order.paidAt) : "Collected"}</small></span><b>{formatV1Price(order.price.totalPaise)}</b><ChevronRight size={17} /></button>)}</div>}
    </section>
  </section>;
}

type OrderScope = "active" | "past";

export function OrdersSection({
  orders, loading, loadingMore, canLoadMore, error, imageUrlForLine,
  onRefresh, onLoadMore, onOpen, onReorder,
}: {
  orders: V1Order[];
  loading: boolean;
  loadingMore: boolean;
  canLoadMore: boolean;
  error?: string;
  imageUrlForLine: (line: V1Order["lines"][number]) => string | null;
  onRefresh: () => void;
  onLoadMore: () => void;
  onOpen: (order: V1Order) => void;
  onReorder: (order: V1Order) => void;
}) {
  const [scope, setScope] = useState<OrderScope>("active");
  const scopeWasChosen = useRef(false);
  const visible = useMemo(() => orders.filter((order) =>
    (scope === "active") === isV1OrderActive(order.status)
  ), [orders, scope]);
  const activeCount = useMemo(
    () => orders.reduce((count, order) => count + Number(isV1OrderActive(order.status)), 0),
    [orders],
  );
  useEffect(() => {
    if (!scopeWasChosen.current && orders.length > 0) {
      setScope(activeCount > 0 ? "active" : "past");
    }
  }, [activeCount, orders.length]);

  return <section className="v1-orders-page">
    <header className="v1-orders-header"><div><p>YOUR ORDERS</p><h1>Orders</h1><span>Track an active delivery or revisit a past order.</span></div><button className="v1-orders-refresh" type="button" onClick={onRefresh} disabled={loading}><RefreshCw size={17} className={loading ? "spinning" : ""} /> Refresh</button></header>
    <div className="v1-order-scopes" role="group" aria-label="Filter orders">
      {(["active", "past"] as const).map((value) => <button type="button" key={value} aria-pressed={scope === value} onClick={() => { scopeWasChosen.current = true; setScope(value); }}><span>{value[0].toUpperCase() + value.slice(1)}</span></button>)}
    </div>
    {error ? <div className="v1-orders-error" role="alert"><CircleAlert size={18} /><span>{error}</span><button type="button" onClick={onRefresh}>Try again</button></div> : null}
    {loading && orders.length === 0 ? <div className="v1-orders-loading" role="status"><span /> Loading your orders</div> : visible.length ? <div className="v1-order-list">{visible.map((order) => {
      const active = isV1OrderActive(order.status);
      const duration = deliveredDurationLabel(order);
      const itemCount = orderItemCount(order);
      const productNames = order.lines.slice(0, 2).map((line) => line.name).join(" · ");
      return <article className={`v1-commerce-order-card ${active ? "active" : ""}`} key={order.id}>
        <button className="v1-order-card-main" type="button" onClick={() => onOpen(order)} aria-label={`Open ${order.displayOrderNumber}, ${statusTitle(order.status)}`}>
          <span className={`v1-order-icon ${active ? "active" : "terminal"}`}><OrderStatusIcon status={order.status} size={21} /></span>
          <span className="v1-order-card-copy"><strong>{duration ?? statusTitle(order.status)}</strong><small>{order.restaurant?.name ?? orderKindLabel(order.orderType)}</small></span>
          <span className="v1-order-card-trailing"><b>{formatV1Price(order.price.totalPaise)}</b></span>
          <span className="v1-order-thumbnails">{order.lines.slice(0, 4).map((line) => <ProductImage key={line.id} src={imageUrlForLine(line)} alt="" />)}{order.lines.length > 4 ? <i>+{order.lines.length - 4}</i> : null}</span>
          <span className="v1-order-products"><b>{productNames}{order.lines.length > 2 ? ` + ${order.lines.length - 2} more` : ""}</b><small>{itemCount} {itemCount === 1 ? "item" : "items"} · {order.displayOrderNumber}</small><time dateTime={order.submittedAt ?? order.createdAt}>{formatOrderDate(order.submittedAt ?? order.createdAt)}</time></span>
          {active ? <OrderJourneyProgress status={order.status} compact /> : null}
        </button>
        <footer>{canReorderV1Order(order.status) ? <button type="button" onClick={() => onReorder(order)}><RotateCcw size={16} /> Order again</button> : null}<button type="button" onClick={() => onOpen(order)}>{active ? "Track order" : "Details"}</button></footer>
      </article>;
    })}</div> : <EmptyState title={scope === "active" ? "No active orders" : "No past orders"} copy={scope === "active" ? "When an order is in progress, you can track it here." : "Completed and cancelled orders will appear here."} />}
    {scope === "past" && canLoadMore ? <button className="secondary-button v1-load-more" type="button" disabled={loadingMore} onClick={onLoadMore}>{loadingMore ? "Loading earlier orders…" : "Load earlier orders"}</button> : null}
  </section>;
}

function OrderJourneyProgress({ status, compact = false }: {
  status: V1Order["status"];
  compact?: boolean;
}) {
  const current = orderJourneyStep(status);
  if (current === undefined) return null;
  return <div className={`v1-order-progress ${compact ? "compact" : ""}`} role="img" aria-label={orderJourneyLabel(status)}>
    <div aria-hidden="true">{orderJourneySteps.map((step, index) => <i className={index <= current ? "complete" : undefined} key={step} />)}</div>
    <small>{orderJourneyLabel(status)}</small>
  </div>;
}

export function MatchingSheet({
  order, busy, error, liveError, paymentMessage, onDismiss, onCancel, onPay,
  imageUrlForLine, onRefresh, onReportIssue, onReorder,
}: {
  order: V1Order;
  busy: boolean;
  error?: string;
  liveError?: string;
  paymentMessage?: string;
  imageUrlForLine: (line: V1Order["lines"][number]) => string | null;
  onDismiss: () => void;
  onCancel: () => void;
  onPay: () => void;
  onReorder: () => void;
  onRefresh: () => void;
  onReportIssue: (input: {
    category: string; description: string; orderLineId?: string; evidenceFile?: File;
  }) => Promise<boolean>;
}) {
  const dialog = useModalDialog<HTMLElement>({ busy, onDismiss });
  const matching = matchingStatuses.has(order.status);
  const paid = Boolean(order.paidAt);
  const launchPayment = order.launchPayment;
  const launchCollectionSatisfied = !launchPayment || launchPayment.state === "NOT_APPLICABLE" ||
    launchPayment.state === "PAYMENT_COLLECTED";
  const currentTimelineItem = activeTimelineItem(order.status);
  const [now, setNow] = useState(() => Date.now());
  const [reportingIssue, setReportingIssue] = useState(false);
  const [confirmingCancellation, setConfirmingCancellation] = useState(false);
  const [issueCategory, setIssueCategory] = useState("WRONG_SKU");
  const [issueLineId, setIssueLineId] = useState("");
  const [issueDescription, setIssueDescription] = useState("");
  const [issueEvidence, setIssueEvidence] = useState<File>();
  useEffect(() => {
    const cadence = order.status === "AWAITING_PAYMENT"
      ? 1_000
      : ["PAID", "PREPARING", "OUT_FOR_DELIVERY"].includes(order.status) ? 30_000 : undefined;
    if (!cadence) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), cadence);
    return () => window.clearInterval(timer);
  }, [order.status]);
  useEffect(() => { setConfirmingCancellation(false); }, [order.id, order.status]);
  const paymentExpiry = launchPayment?.reservationExpiresAt ?? order.payment?.expiresAt;
  const paymentSeconds = paymentExpiry
    ? Math.max(0, Math.ceil((Date.parse(paymentExpiry) - now) / 1_000))
    : 0;
  const paymentReady = order.status === "AWAITING_PAYMENT" && launchPayment?.canCommit && paymentSeconds > 0;
  const evidenceRequired = isIssueEvidenceRequired(issueCategory);
  const readyAt = order.fulfilmentProgress?.estimatedReadyAt;
  const runningLate = Boolean(order.fulfilmentProgress?.runningLate ||
    (readyAt && Date.parse(readyAt) < now));
  const mapPoints: CustomerMapPoint[] = order.status === "OUT_FOR_DELIVERY" && order.deliveryAddress
    ? [
      {
        label: order.deliveryAddress.label ?? "Delivery address",
        address: orderAddress(order),
        latitude: order.deliveryAddress.latitude,
        longitude: order.deliveryAddress.longitude,
        kind: "dropoff",
      },
      ...(order.delivery?.riderLocation ? [{
        label: "Your delivery partner",
        address: order.delivery.distanceToDestinationMeters === undefined
          ? "Live location" : `${formatDistance(order.delivery.distanceToDestinationMeters)} away`,
        latitude: order.delivery.riderLocation.latitude,
        longitude: order.delivery.riderLocation.longitude,
        kind: "courier" as const,
      }] : []),
    ] : [];

  return <div className="v1-overlay" role="presentation"><section ref={dialog} tabIndex={-1} className="v1-sheet v1-matching-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-order-status-title">
    <header><div><p>{order.displayOrderNumber}</p><h2 id="v1-order-status-title">Order status</h2><small>{order.restaurant?.name ?? orderKindLabel(order.orderType)} · {formatOrderDate(order.submittedAt ?? order.createdAt)}</small></div><button type="button" onClick={onDismiss} aria-label="Close order status"><X size={19} /></button></header>
    <div className={`v1-status-hero ${isFailureStatus(order.status) ? "failure" : ""}`}><span className={matching ? "matching" : ""}>{matching ? <i /> : <OrderStatusIcon status={order.status} size={25} />}</span><div><header><h3>{deliveredDurationLabel(order) ?? statusTitle(order.status)}</h3><strong>{formatV1Price(order.price.totalPaise)}</strong></header><p>{statusMessage(order.status)}</p></div>{isV1OrderActive(order.status) ? <OrderJourneyProgress status={order.status} /> : null}<small className="v1-order-assurance"><ShieldCheck size={16} /> {statusAssurance(order.status)}</small></div>

    {(order.status === "PAID" || order.status === "PREPARING") && readyAt ? <section className={`v1-order-eta ${runningLate ? "late" : ""}`} aria-label="Preparation estimate"><ClockAlert size={21} /><span><strong>{runningLate ? "Taking a little longer" : "Preparation estimate"}</strong><small>{runningLate ? "Your order stays in preparation until it is genuinely ready." : `Expected around ${formatOrderTime(readyAt)}`}</small></span><b>{runningLate ? "We’re watching" : relativeTime(readyAt, now)}</b></section> : null}

    {mapPoints.length ? <section className="v1-live-delivery"><header><div><p><i /> LIVE DELIVERY</p><h3>{order.delivery?.riderLocation ? "Your rider is on the way" : "Waiting for a fresh rider location"}</h3></div>{order.delivery?.distanceToDestinationMeters !== undefined ? <strong>{formatDistance(order.delivery.distanceToDestinationMeters)} away</strong> : null}</header><CustomerRouteMap points={mapPoints} />{order.delivery?.riderLocationUpdatedAt ? <small aria-live="polite">Location updated {relativeTime(order.delivery.riderLocationUpdatedAt, now)}</small> : null}</section> : null}

    <section className="v1-order-contents" aria-label="Order items"><header><div><p>ITEMS IN THIS ORDER</p><h3>{orderItemCount(order)} {orderItemCount(order) === 1 ? "item" : "items"}</h3>{order.restaurant ? <small>{order.restaurant.name} · {order.restaurant.branchName}</small> : null}</div></header><div className="v1-matching-lines">{order.lines.map((line) => <div key={line.id}><ProductImage src={imageUrlForLine(line)} alt="" /><span><b>{line.name}</b>{orderLineDetail(line) ? <small>{orderLineDetail(line)}</small> : null}<small>{line.quantity} × {formatV1Price(line.unitPricePaise)}</small></span><strong>{formatV1Price(line.lineTotalPaise)}</strong></div>)}</div></section>

    {order.deliveryAddress ? <section className="v1-order-destination"><div><MapPin size={20} /><span><small>{order.deliveryAddress.label ?? "DELIVERY ADDRESS"}</small><strong>{orderAddress(order)}</strong></span></div>{order.recipient ? <div><UserRound size={20} /><span><small>RECIPIENT</small><strong>{order.recipient.name} · {customerPhoneNumber(order.recipient.phoneNumber)}</strong></span></div> : null}{order.deliveryAddress.instructions ? <p><strong>Delivery note</strong>{order.deliveryAddress.instructions}</p> : null}</section> : null}

    <section className="v1-order-receipt" aria-label={paid ? "Bill summary" : "Order summary"}><header><h3><ReceiptText size={19} /> {paid ? "Bill summary" : "Order summary"}</h3>{paid ? <button type="button" onClick={() => downloadReceipt(order)}><Download size={16} /> Download receipt</button> : null}</header><ReceiptRow label="Items" amount={order.price.subtotalPaise} />{order.price.deliveryFeePaise ? <ReceiptRow label="Delivery" amount={order.price.deliveryFeePaise} /> : null}{order.price.platformFeePaise ? <ReceiptRow label="Dastak platform fee" amount={order.price.platformFeePaise} /> : null}{order.price.taxPaise ? <ReceiptRow label="Taxes" amount={order.price.taxPaise} /> : null}{order.price.discountPaise ? <ReceiptRow label="Discount" amount={-order.price.discountPaise} /> : null}<ReceiptRow label={orderTotalLabel(order)} amount={order.price.totalPaise} total /></section>

    <section className="v1-order-facts" aria-label="Order details"><h3>Order details</h3><div><span><small>ORDER NUMBER</small><strong>{order.displayOrderNumber}</strong></span><button type="button" onClick={() => void copyText(order.displayOrderNumber)} aria-label={`Copy order number ${order.displayOrderNumber}`}><Copy size={16} /> Copy</button></div><div><span><small>PAYMENT</small><strong>{customerPaymentLabel(order)}</strong></span></div><div><span><small>ORDER PLACED</small><strong>{formatOrderDate(order.submittedAt ?? order.createdAt)}</strong></span></div>{launchPayment?.committedAt ? <div><span><small>ORDER CONFIRMED</small><strong>{formatOrderDate(launchPayment.committedAt)}</strong></span></div> : null}{launchPayment?.collectedAt ? <div><span><small>PAYMENT COLLECTED</small><strong>{formatOrderDate(launchPayment.collectedAt)}</strong></span></div> : !launchPayment && order.paidAt ? <div><span><small>PAYMENT CONFIRMED</small><strong>{formatOrderDate(order.paidAt)}</strong></span></div> : null}{order.deliveredAt ?? order.delivery?.deliveredAt ? <div><span><small>DELIVERED</small><strong>{formatOrderDate(order.deliveredAt ?? order.delivery!.deliveredAt!)}</strong></span></div> : null}</section>

    <CustomerTimeline items={[
      { label: "Order placed", value: order.submittedAt ?? order.createdAt },
      { label: "Basket secured", value: order.fullySecuredAt },
      { label: "Order confirmed", value: launchPayment?.committedAt },
      { label: "Payment collected", value: launchPayment?.collectedAt ?? (!launchPayment ? order.paidAt : undefined) },
      { label: "Out for delivery", value: order.delivery?.outForDeliveryAt },
      { label: "Delivered", value: order.deliveredAt ?? order.delivery?.deliveredAt },
      ...(currentTimelineItem ? [currentTimelineItem] : []),
    ]} />

    {order.status === "AWAITING_PAYMENT" && launchPayment ? <div className="v1-payment-window">
      <span><strong>Full basket secured</strong><small>{paymentSeconds > 0 ? `${formatDuration(paymentSeconds)} to confirm · no charge now` : "Reservation ending"}</small></span>
      <strong>{formatV1Price(launchPayment.amountPaise ?? order.price.totalPaise)}</strong>
    </div> : null}
    {order.status === "OUT_FOR_DELIVERY" && launchPayment?.state === "PAYMENT_DUE_AT_DELIVERY" ? <p className="v1-payment-message" role="status"><strong>Payment due at delivery.</strong> Pay your delivery partner {formatV1Price(launchPayment.amountPaise ?? order.price.totalPaise)} by UPI or cash.</p> : null}
    {order.status === "OUT_FOR_DELIVERY" && launchPayment?.state === "COLLECTION_RETRY_NEEDED" ? <p className="v1-payment-retry" role="status">Payment was not confirmed. Your delivery partner can safely retry the doorstep collection before delivery.</p> : null}
    {launchPayment?.state === "PAYMENT_COLLECTED" ? <p className="v1-payment-message" role="status"><strong>Payment collected.</strong> {launchPayment.collectionMethod ? `${launchPayment.collectionMethod === "CASH" ? "Cash" : "UPI"} recorded` : "Collection recorded"} at the doorstep.</p> : null}
    {order.status === "OUT_FOR_DELIVERY" && order.delivery?.deliveryCode && launchCollectionSatisfied ? <div className="v1-delivery-code" role="status">
      <header><ShieldCheck size={20} /><span><small>DELIVERY CODE</small><b>Share only after every package arrives</b></span></header>
      <strong>{order.delivery.deliveryCode}</strong>
      <p>A trusted recipient may use this in-app code without a Dastak account. No SMS code is used.</p>
    </div> : null}
    {order.status === "OUT_FOR_DELIVERY" && order.delivery?.verificationStatus === "BLOCKED" ? <p className="v1-payment-retry" role="status">Delivery verification needs Operations support. Your rider must keep every package secure.</p> : null}
    {order.support?.recovery.map((recovery) => <p className="v1-payment-retry" role="status" key={recovery.id}>{recovery.customerMessage}</p>)}
    {order.support?.issues.length ? <section className="v1-order-support-history" aria-label="Reported issues"><h3>Support updates</h3>{order.support.issues.map((issue) => <div key={issue.id}><span><strong>{humanizeV1State(issue.category)}</strong><small>{humanizeV1State(issue.status)}</small></span><p>{issue.resolution ?? "Operations is reviewing your report."}</p></div>)}</section> : null}
    {order.support?.returns.map((customerReturn) => <div className="v1-delivery-code" role="status" key={customerReturn.id}>
      <span><small>RETURN · {humanizeV1State(customerReturn.status)}</small><strong>{customerReturn.mission?.pickupCode ?? `${customerReturn.packageCount} pkg`}</strong></span>
      <p>{customerReturn.mission?.pickupCode ? "Share this in-app code only after the assigned rider photographs and accounts for every return package." : "Operations will arrange secure reverse custody when required."}</p>
    </div>)}
    {order.support?.refunds.map((refund) => <p className="v1-payment-message" role="status" key={refund.id}>Refund {humanizeV1State(refund.status).toLowerCase()} · {formatV1Price(refund.amountPaise)} to original payment method</p>)}
    {reportingIssue ? <form className="v1-problem-form" onSubmit={(event) => {
      event.preventDefault();
      if (evidenceRequired && !issueEvidence) return;
      void onReportIssue({
        category: issueCategory,
        description: issueDescription,
        orderLineId: issueLineId || undefined,
        evidenceFile: issueEvidence,
      }).then((success) => {
        if (!success) return;
        setReportingIssue(false);
        setIssueDescription("");
        setIssueLineId("");
        setIssueEvidence(undefined);
      });
    }}>
      <label><span>What went wrong?</span><select value={issueCategory} onChange={(event) => setIssueCategory(event.target.value)}><option value="WRONG_SKU">Wrong product</option><option value="WRONG_QUANTITY">Wrong quantity</option><option value="DAMAGED">Damaged</option><option value="DEFECTIVE">Defective</option><option value="EXPIRED">Expired</option><option value="TAMPERED_OR_BROKEN_SEAL">Seal or tampering</option><option value="INCORRECT_PACKAGE">Incorrect package</option><option value="SUSPECTED_MERCHANT_MISFULFILMENT">Merchant fulfilment concern</option><option value="DELIVERY_PROBLEM">Delivery problem</option><option value="OTHER">Other</option></select></label>
      <label><span>Product (optional)</span><select value={issueLineId} onChange={(event) => setIssueLineId(event.target.value)}><option value="">Whole order</option>{order.lines.map((line) => <option key={line.id} value={line.id}>{line.quantity}× {line.name}</option>)}</select></label>
      <label><span>Details</span><textarea rows={3} minLength={3} maxLength={1000} required value={issueDescription} onChange={(event) => setIssueDescription(event.target.value)} /></label>
      <label className="v1-photo-field"><span>Evidence photo {evidenceRequired ? "(required)" : "(optional)"}</span><input type="file" required={evidenceRequired} accept="image/jpeg,image/png,image/heic" capture="environment" onChange={(event) => setIssueEvidence(event.target.files?.[0])} /><small>{issueEvidence?.name ?? "JPG, PNG or HEIC up to 10 MB"}</small></label>
      <div><button className="secondary-button" type="button" disabled={busy} onClick={() => setReportingIssue(false)}>Back</button><button className="primary-button" type="submit" disabled={busy || issueDescription.trim().length < 3 || (evidenceRequired && !issueEvidence)}>{busy ? "Sending…" : "Send to support"}</button></div>
    </form> : order.support?.canReportIssue ? <button className="secondary-button v1-secondary-action" type="button" disabled={busy} onClick={() => setReportingIssue(true)}><CircleAlert size={17} /> Get help with this order</button> : null}
    <a className="v1-support-link" href="/support"><span><strong>Contact Dastak support</strong><small>Account, payment or delivery help</small></span><ChevronRight size={17} /></a>
    {paymentMessage ? <p className="v1-payment-message" role="status">{paymentMessage}</p> : null}
    {liveError ? <div className="v1-live-error" role="status"><CircleAlert size={17} /><span>Live updates paused: {liveError}</span><button type="button" onClick={onRefresh}>Refresh now</button></div> : null}
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {paymentReady ? <button className="primary-button v1-pay" type="button" disabled={busy} onClick={onPay}>Confirm Pay via UPI/Cash on Delivery<ArrowRight size={18} /></button> : null}
    {cancellableStatuses.has(order.status) ? confirmingCancellation ? <div className="v1-cancel-confirm" role="alert"><strong>Cancel this order?</strong><p>Reserved items will be released. Cancellation is available only before you confirm the order.</p><div><button className="secondary-button" type="button" disabled={busy} onClick={() => setConfirmingCancellation(false)}>Keep order</button><button className="danger-button" type="button" disabled={busy} onClick={onCancel}>{busy ? "Cancelling…" : "Cancel order"}</button></div></div> : <button className="v1-cancel" type="button" disabled={busy} onClick={() => setConfirmingCancellation(true)}><Ban size={17} /> Cancel order</button> : null}
    {canReorderV1Order(order.status) ? <button className="primary-button v1-reorder" type="button" disabled={busy} onClick={onReorder}><RotateCcw size={17} /> Order again</button> : null}
  </section></div>;
}

function EmptyState({ title, copy }: { title: string; copy: string }) {
  return <div className="v1-empty"><ShoppingBag size={30} /><strong>{title}</strong><span>{copy}</span></div>;
}

function ProductImage({ src, alt, className }: {
  src: string | null;
  alt: string;
  className?: string;
}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => { setFailed(false); }, [src]);
  return <span className={`v1-catalogue-image ${className ?? ""}`}>
    {src && !failed
      ? <img src={src} alt={alt} loading="lazy" decoding="async" onError={() => setFailed(true)} />
      : <ShoppingBag size={24} aria-hidden="true" />}
  </span>;
}

function BasketReplacementDialog({ busy, onDismiss, onConfirm }: {
  busy: boolean;
  onDismiss: () => void;
  onConfirm: () => void;
}) {
  const dialog = useModalDialog<HTMLElement>({ busy, onDismiss });
  return <div className="v1-overlay v1-confirm-overlay" role="presentation"><section ref={dialog} tabIndex={-1} className="v1-sheet v1-confirm-sheet" role="dialog" aria-modal="true" aria-labelledby="replace-basket-title">
    <header><div><p>ORDER AGAIN</p><h2 id="replace-basket-title">Replace your current basket?</h2></div><button type="button" onClick={onDismiss} aria-label="Keep current basket"><X size={19} /></button></header>
    <p>Items already in your basket will be replaced. You can review current availability and prices before submitting.</p>
    <div><button className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>Keep current basket</button><button className="primary-button" type="button" disabled={busy} onClick={onConfirm}>Replace and reorder</button></div>
  </section></div>;
}

function OrderStatusIcon({ status, size }: { status: V1Order["status"]; size: number }) {
  if (status === "UNAVAILABLE") return <PackageX size={size} />;
  if (status === "PAYMENT_EXPIRED") return <ClockAlert size={size} />;
  if (status === "CANCELLED_PREPAYMENT") return <Ban size={size} />;
  if (status === "DASTAK_FULFILMENT_FAILURE") return <CircleAlert size={size} />;
  if (status === "DELIVERED") return <Check size={size} />;
  return <PackageCheck size={size} />;
}

function ReceiptRow({ label, amount, total = false }: {
  label: string; amount: number; total?: boolean;
}) {
  return <div className={total ? "total" : ""}><span>{label}</span><strong>{formatV1Price(amount)}</strong></div>;
}

function receiptText(order: V1Order) {
  const lines = [
    "Dastak receipt",
    `Order ${order.displayOrderNumber}`,
    "",
    ...order.lines.map((line) => `${line.quantity} × ${line.name} — ${formatV1Price(line.lineTotalPaise)}`),
    "",
    `Items: ${formatV1Price(order.price.subtotalPaise)}`,
    `Delivery: ${formatV1Price(order.price.deliveryFeePaise)}`,
    `Dastak platform fee: ${formatV1Price(order.price.platformFeePaise)}`,
    `Taxes: ${formatV1Price(order.price.taxPaise)}`,
  ];
  if (order.price.discountPaise) lines.push(`Discount: −${formatV1Price(order.price.discountPaise)}`);
  lines.push(`Total: ${formatV1Price(order.price.totalPaise)}`);
  if (order.launchPayment?.collectedAt) {
    lines.push(`Payment collected at delivery${order.launchPayment.collectionMethod ? ` by ${order.launchPayment.collectionMethod}` : ""}: ${formatOrderDate(order.launchPayment.collectedAt)}`);
  } else if (order.paidAt) {
    lines.push(`Payment confirmed: ${formatOrderDate(order.paidAt)}`);
  }
  if (order.deliveryAddress) lines.push(`Delivered to: ${orderAddress(order)}`);
  return lines.join("\n");
}

function downloadReceipt(order: V1Order) {
  const url = URL.createObjectURL(new Blob([receiptText(order)], { type: "text/plain;charset=utf-8" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `Dastak-${order.displayOrderNumber}-receipt.txt`;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

async function copyText(value: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }
  const field = document.createElement("textarea");
  field.value = value;
  field.style.position = "fixed";
  field.style.opacity = "0";
  document.body.append(field);
  field.select();
  document.execCommand("copy");
  field.remove();
}

function isFailureStatus(status: V1Order["status"]) {
  return ["UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT",
    "DASTAK_FULFILMENT_FAILURE"].includes(status);
}

function newerOrder(current: V1Order | undefined, incoming: V1Order) {
  if (!current || current.id !== incoming.id || incoming.version >= current.version) return incoming;
  return current;
}

function mergeV1Orders(incoming: V1Order[], current: V1Order[]) {
  const currentById = new Map(current.map((order) => [order.id, order]));
  const merged = new Map<string, V1Order>(currentById);
  incoming.forEach((order) => {
    const existing = currentById.get(order.id) ?? merged.get(order.id);
    merged.set(order.id, existing && existing.version > order.version ? existing : order);
  });
  return [...merged.values()].sort((left, right) => {
    const date = Date.parse(right.createdAt) - Date.parse(left.createdAt);
    return date || right.id.localeCompare(left.id);
  });
}

function orderAddress(order: V1Order) {
  const address = order.deliveryAddress;
  if (!address) return "Delivery address";
  return deliveryAddressLine(address);
}

function orderTotalLabel(order: V1Order) {
  if (order.paidAt) return "Total paid";
  if (order.launchPayment?.committedAt) return "Due at delivery";
  if (["FULLY_SECURED", "AWAITING_PAYMENT"].includes(order.status)) return "Order total";
  return "Current basket total";
}

function customerPaymentLabel(order: V1Order) {
  const launch = order.launchPayment;
  if (!launch) return order.paidAt ? "Payment confirmed" : "Not yet confirmed";
  if (launch.state === "PAYMENT_COLLECTED") {
    return `Collected at delivery${launch.collectionMethod ? ` · ${launch.collectionMethod === "CASH" ? "Cash" : "UPI"}` : ""}`;
  }
  if (launch.state === "COLLECTION_RETRY_NEEDED") return "Collection needs a safe retry";
  if (launch.state === "PAYMENT_DUE_AT_DELIVERY") return "Due at delivery · UPI or cash";
  if (launch.state === "READY_TO_CONFIRM") return "Confirm now · no charge now";
  if (launch.state === "RESERVATION_EXPIRED") return "Reservation expired";
  return order.paidAt ? "Payment confirmed" : "Not applicable";
}

function activeTimelineItem(status: V1Order["status"]) {
  if (status === "CREATED" || status === "MATCHING") {
    return { label: "Finding every item", statusText: "In progress" };
  }
  if (status === "FULLY_SECURED" || status === "AWAITING_PAYMENT") {
    return { label: "Ready to confirm", statusText: "Action needed" };
  }
  if (status === "PAID" || status === "PREPARING") {
    return { label: "Preparing your order", statusText: "In progress" };
  }
  if (status === "PICKUP_IN_PROGRESS") {
    return { label: "Picking up your order", statusText: "In progress" };
  }
  if (status === "DASTAK_FULFILMENT_FAILURE") {
    return { label: "Recovery in progress", statusText: "Operations is helping" };
  }
  return undefined;
}

function formatOrderDate(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium", timeStyle: "short",
  }).format(new Date(value));
}

function formatOrderTime(value: string) {
  return new Intl.DateTimeFormat(undefined, { timeStyle: "short" }).format(new Date(value));
}

function relativeTime(value: string, now: number) {
  const seconds = Math.round((Date.parse(value) - now) / 1_000);
  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  if (Math.abs(seconds) < 90) return formatter.format(seconds, "second");
  const minutes = Math.round(seconds / 60);
  if (Math.abs(minutes) < 90) return formatter.format(minutes, "minute");
  return formatter.format(Math.round(minutes / 60), "hour");
}

function formatDistance(meters: number) {
  return meters < 1_000 ? `${meters} m` : `${(meters / 1_000).toFixed(1)} km`;
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
