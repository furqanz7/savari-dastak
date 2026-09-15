import { ProductDetailCard, type DetailProduct } from "./ProductDetailCard";
import { ProductDetailOverlay } from "./ProductDetailOverlay";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ArrowLeft, ArrowRight, Ban, Check, ChevronRight, CircleAlert, ClockAlert, Copy, Download,
  Heart, Leaf, LockKeyhole, MapPin, Minus, PackageCheck, PackageX, Plus, Printer,
  ReceiptText, RefreshCw, RotateCcw, Search, ShieldCheck, ShoppingBag,
  UserRound, UtensilsCrossed, X,
} from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import {
  foodCartKey, loadCustomerCart, persistedFoodCart, resolveFoodCart, saveCustomerCart,
  validateRetailCart, type PersistedFoodCartLine, type ResolvedFoodCartLine, type RetailCart,
} from "./customerCartPersistence";
import { customerDataIssue, type CustomerDataIssue } from "./customerDataState";
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
  type DastakV1Auth, type V1CatalogueCategory, type V1CatalogueCategoryType,
  type V1CatalogueSku, type V1CatalogueSubcategory, type V1Order,
  type V1OrderCursor, type V1RestaurantMenu, type V1RestaurantMenuItem,
} from "./dastakV1";
import { CustomerTimeline } from "./CustomerDeliveryDetails";
import { CustomerLiveDelivery } from "./CustomerLiveDelivery";
import { customerRiderArrived } from "./customerDeliveryPresentation";
import { useModalDialog } from "./useModalDialog";
import { RefreshQueue, type OrderRealtimeHealth } from "./orderRealtime";
import { CustomerEmptyState, CustomerNotice, CustomerPageHeading, CustomerSkeleton, CustomerSyncStatus } from "./CustomerUI";
import { userFacingError } from "./userFacingError";
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
  realtimeHealth?: OrderRealtimeHealth;
  initialOrderId?: string;
  section: Extract<CustomerSection, "home" | "search" | "orders" | "wishlist" | "payments">;
  onNavigate: (section: CustomerSection) => void;
  onOpenParcel: () => void;
  onOpenOrder: (orderId: string) => void;
  onCloseOrder: () => void;
  onSessionExpired: () => void;
};

type Cart = RetailCart;
type FoodCartLine = ResolvedFoodCartLine;
export type CustomerHomeMode = "food" | "grocery" | "parcel" | "print";
const matchingStatuses = new Set(["CREATED", "MATCHING"]);
const liveStatuses = new Set([
  "CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT", "PAID", "PREPARING",
  "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY",
]);
const cancellableStatuses = new Set(["CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT"]);

async function loadCompleteV1Category(
  auth: DastakV1Auth,
  categoryId: string,
  signal: AbortSignal,
) {
  const skus = new Map<string, V1CatalogueSku>();
  let cursor: { name: string; skuId: string } | undefined;
  for (let page = 0; page < 20; page += 1) {
    const result = await getV1Catalogue({ ...auth, categoryId, limit: 250, cursor, signal });
    result.skus.forEach((sku) => skus.set(sku.id, sku));
    if (!result.nextCursor || (cursor?.name === result.nextCursor.name && cursor.skuId === result.nextCursor.skuId)) break;
    cursor = result.nextCursor;
  }
  return [...skus.values()];
}

export function DastakV1CustomerExperience(props: Props) {
  const auth = useMemo<DastakV1Auth>(() => ({
    accessToken: props.accessToken,
    publishableKey: props.publishableKey,
    supabaseUrl: props.supabaseUrl,
  }), [props.accessToken, props.publishableKey, props.supabaseUrl]);
  const [catalogue, setCatalogue] = useState<Awaited<ReturnType<typeof getV1Catalogue>>>();
  const [categorySkus, setCategorySkus] = useState<Record<string, V1CatalogueSku[]>>({});
  const [loadingCategoryId, setLoadingCategoryId] = useState<string>();
  const [restaurants, setRestaurants] = useState<V1RestaurantMenu[]>([]);
  const [selectedRestaurant, setSelectedRestaurant] = useState<V1RestaurantMenu>();
  const [searchResults, setSearchResults] = useState<V1CatalogueSku[]>([]);
  const [orders, setOrders] = useState<V1Order[]>([]);
  const [wishlistItems, setWishlistItems] = useState<CustomerWishlistItem[]>([]);
  const [ordersNextCursor, setOrdersNextCursor] = useState<V1OrderCursor>();
  const [addresses, setAddresses] = useState<CustomerDeliveryAddress[]>([]);
  const [query, setQuery] = useState("");
  const [selectedCategoryType, setSelectedCategoryType] = useState<string>();
  const [selectedCategory, setSelectedCategory] = useState<string>();
  const [selectedSubcategory, setSelectedSubcategory] = useState<string>();
  const [homeMode, setHomeMode] = useState<CustomerHomeMode>("grocery");
  const [initialCart] = useState(() => loadCustomerCart(props.accountId));
  const [cart, setCart] = useState<Cart>(() => initialCart.retail);
  const [foodCartEntries, setFoodCartEntries] = useState<PersistedFoodCartLine[]>(() => initialCart.food);
  const [loadingCatalogue, setLoadingCatalogue] = useState(true);
  const [loadingOrders, setLoadingOrders] = useState(true);
  const [loadingMoreOrders, setLoadingMoreOrders] = useState(false);
  const [loadingWishlist, setLoadingWishlist] = useState(true);
  const [wishlistUpdatingIds, setWishlistUpdatingIds] = useState<Set<string>>(new Set());
  const [searching, setSearching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [storefrontIssues, setStorefrontIssues] = useState<Partial<Record<"catalogue" | "restaurants" | "addresses", string>>>({});
  const [orderActionError, setOrderActionError] = useState<string>();
  const [paymentMessage, setPaymentMessage] = useState<string>();
  const [showingLaunchPayment, setShowingLaunchPayment] = useState(false);
  const [ordersError, setOrdersError] = useState<CustomerDataIssue>();
  const [liveOrderError, setLiveOrderError] = useState<string>();
  const [showingCart, setShowingCart] = useState(false);
  const [showingAddressBook, setShowingAddressBook] = useState(false);
  const [editingAddress, setEditingAddress] = useState<CustomerDeliveryAddress | null>();
  const [selectedOrder, setSelectedOrder] = useState<V1Order>();
  const [pendingReorder, setPendingReorder] = useState<V1Order>();
  const submissionKeys = useRef(new Map<string, string>());
  const ordersRequestVersion = useRef(0);
  const ordersPaginationAdvanced = useRef(false);
  const catalogueRefreshQueue = useRef(new RefreshQueue());
  const restaurantRefreshQueue = useRef(new RefreshQueue());
  const addressRefreshQueue = useRef(new RefreshQueue());
  const ordersRefreshQueue = useRef(new RefreshQueue());
  const catalogueController = useRef<AbortController | undefined>(undefined);
  const restaurantController = useRef<AbortController | undefined>(undefined);
  const addressController = useRef<AbortController | undefined>(undefined);
  const ordersController = useRef<AbortController | undefined>(undefined);
  const selectedOrderId = selectedOrder?.id;
  const selectedOrderStatus = selectedOrder?.status;
  const onCloseOrder = props.onCloseOrder;
  const onSessionExpired = props.onSessionExpired;
  const presentRequestFailure = useCallback((requestError: unknown, setter = setError) => {
    const issue = customerDataIssue(requestError);
    if (issue.action === "sign_in") {
      onSessionExpired();
      return;
    }
    setter(message(requestError));
  }, [onSessionExpired]);

  const recordStorefrontFailure = useCallback((source: "catalogue" | "restaurants" | "addresses", requestError: unknown) => {
    const issue = customerDataIssue(requestError);
    if (issue.action === "sign_in") {
      onSessionExpired();
      return;
    }
    setStorefrontIssues((current) => ({ ...current, [source]: message(requestError) }));
  }, [onSessionExpired]);
  const clearStorefrontFailure = useCallback((source: "catalogue" | "restaurants" | "addresses") => {
    setStorefrontIssues((current) => {
      if (!current[source]) return current;
      const next = { ...current };
      delete next[source];
      return next;
    });
  }, []);

  const refreshCatalogue = useCallback(async () => {
    await catalogueRefreshQueue.current.request(false, async () => {
      const controller = new AbortController();
      catalogueController.current = controller;
      setLoadingCatalogue(true);
      try {
        const next = await getV1Catalogue({ ...auth, limit: 250, signal: controller.signal });
        if (controller.signal.aborted) return;
        setCatalogue(next);
        setCategorySkus({});
        setCart((current) => validateRetailCart(current, next.skus, !next.nextCursor));
        clearStorefrontFailure("catalogue");
      } catch (requestError) {
        if (!controller.signal.aborted) recordStorefrontFailure("catalogue", requestError);
      } finally {
        if (!controller.signal.aborted) setLoadingCatalogue(false);
        if (catalogueController.current === controller) catalogueController.current = undefined;
      }
    });
  }, [auth, clearStorefrontFailure, recordStorefrontFailure]);

  const refreshRestaurants = useCallback(async () => {
    await restaurantRefreshQueue.current.request(false, async () => {
      const controller = new AbortController();
      restaurantController.current = controller;
      try {
        const next = await getV1Restaurants({ ...auth, limit: 50, signal: controller.signal });
        if (controller.signal.aborted) return;
        setRestaurants(next);
        setFoodCartEntries((current) => persistedFoodCart(resolveFoodCart(current, next)));
        clearStorefrontFailure("restaurants");
      } catch (requestError) {
        if (!controller.signal.aborted) recordStorefrontFailure("restaurants", requestError);
      } finally {
        if (restaurantController.current === controller) restaurantController.current = undefined;
      }
    });
  }, [auth, clearStorefrontFailure, recordStorefrontFailure]);

  const refreshAddresses = useCallback(async () => {
    await addressRefreshQueue.current.request(false, async () => {
      const controller = new AbortController();
      addressController.current = controller;
      try {
        const next = await getCustomerAddresses({ ...auth, signal: controller.signal });
        if (controller.signal.aborted) return;
        setAddresses(next.addresses);
        clearStorefrontFailure("addresses");
      } catch (requestError) {
        if (!controller.signal.aborted) recordStorefrontFailure("addresses", requestError);
      } finally {
        if (addressController.current === controller) addressController.current = undefined;
      }
    });
  }, [auth, clearStorefrontFailure, recordStorefrontFailure]);

  const refreshOrders = useCallback(async () => {
    await ordersRefreshQueue.current.request(false, async () => {
      const controller = new AbortController();
      ordersController.current = controller;
      const requestVersion = ++ordersRequestVersion.current;
      setLoadingOrders(true);
      setOrdersError(undefined);
      try {
        const result = await getV1Orders({ ...auth, limit: 50, signal: controller.signal });
        if (requestVersion !== ordersRequestVersion.current || controller.signal.aborted) return;
        setOrders((current) => mergeV1Orders(result.orders, current));
        if (!ordersPaginationAdvanced.current) setOrdersNextCursor(result.nextCursor);
        setOrdersError(undefined);
      } catch (requestError) {
        if (!controller.signal.aborted && requestVersion === ordersRequestVersion.current) {
          setOrdersError(customerDataIssue(requestError));
        }
      } finally {
        if (requestVersion === ordersRequestVersion.current && !controller.signal.aborted) setLoadingOrders(false);
        if (ordersController.current === controller) ordersController.current = undefined;
      }
    });
  }, [auth]);

  const refreshWishlist = useCallback(async (signal?: AbortSignal) => {
    setLoadingWishlist(true);
    try {
      const result = await getCustomerWishlist({ ...auth, signal });
      setWishlistItems(result.items);
    } catch (wishlistError) {
      if (!signal?.aborted) presentRequestFailure(wishlistError);
    } finally {
      if (!signal?.aborted) setLoadingWishlist(false);
    }
  }, [auth, presentRequestFailure]);

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
      setOrdersError(customerDataIssue(requestError));
    } finally {
      setLoadingMoreOrders(false);
    }
  }, [auth, loadingMoreOrders, ordersNextCursor]);

  useEffect(() => {
    const refreshStorefront = () => {
      void refreshCatalogue();
      void refreshRestaurants();
      void refreshAddresses();
    };
    const onVisible = () => {
      if (document.visibilityState === "visible") refreshStorefront();
    };
    refreshStorefront();
    const interval = window.setInterval(() => {
      if (document.visibilityState === "visible" && navigator.onLine !== false) refreshStorefront();
    }, 300_000);
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", refreshStorefront);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", refreshStorefront);
      catalogueController.current?.abort();
      restaurantController.current?.abort();
      addressController.current?.abort();
    };
  }, [refreshAddresses, refreshCatalogue, refreshRestaurants]);
  useEffect(() => {
    if (!selectedCategory || Object.prototype.hasOwnProperty.call(categorySkus, selectedCategory)) {
      setLoadingCategoryId(undefined);
      return;
    }
    const categoryId = selectedCategory;
    const controller = new AbortController();
    setLoadingCategoryId(categoryId);
    void loadCompleteV1Category(auth, categoryId, controller.signal)
      .then((skus) => {
        if (!controller.signal.aborted) {
          setCategorySkus((current) => ({ ...current, [categoryId]: skus }));
          setError(undefined);
        }
      })
      .catch((categoryError) => {
        if (!controller.signal.aborted) presentRequestFailure(categoryError);
      })
      .finally(() => {
        if (!controller.signal.aborted) {
          setLoadingCategoryId((current) => current === categoryId ? undefined : current);
        }
      });
    return () => controller.abort();
  }, [auth, categorySkus, presentRequestFailure, selectedCategory]);
  useEffect(() => {
    const controller = new AbortController();
    void refreshWishlist(controller.signal);
    return () => controller.abort();
  }, [refreshWishlist]);
  useEffect(() => {
    void refreshOrders();
    return () => ordersController.current?.abort();
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
        if (!controller.signal.aborted) presentRequestFailure(requestError, setLiveOrderError);
      });
    return () => controller.abort();
  }, [auth, presentRequestFailure, props.initialOrderId]);
  useEffect(() => {
    if (props.orderRefreshToken === 0) return;
    void refreshOrders();
  }, [props.orderRefreshToken, refreshOrders]);
  useEffect(() => {
    saveCustomerCart(props.accountId, { retail: cart, food: foodCartEntries });
  }, [cart, foodCartEntries, props.accountId]);

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
          if (!(searchError instanceof DOMException && searchError.name === "AbortError")) presentRequestFailure(searchError);
        })
        .finally(() => { if (!controller.signal.aborted) setSearching(false); });
    }, 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [auth, presentRequestFailure, query]);

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
        presentRequestFailure(requestError, setLiveOrderError);
        timer = window.setTimeout(poll, 5_000);
      }
    };
    timer = window.setTimeout(poll, 3_000);
    return () => {
      stopped = true;
      if (timer !== undefined) window.clearTimeout(timer);
      controller.abort();
    };
  }, [auth, presentRequestFailure, selectedOrderId, selectedOrderStatus]);

  const skuById = useMemo(() => {
    const result = new Map<string, V1CatalogueSku>();
    catalogue?.skus.forEach((sku) => result.set(sku.id, sku));
    Object.values(categorySkus).forEach((items) => items.forEach((sku) => result.set(sku.id, sku)));
    searchResults.forEach((sku) => result.set(sku.id, sku));
    return result;
  }, [catalogue, categorySkus, searchResults]);
  const menuItemById = useMemo(() => {
    const result = new Map<string, { restaurant: V1RestaurantMenu; item: V1RestaurantMenuItem }>();
    restaurants.forEach((restaurant) => restaurant.categories.forEach((category) =>
      category.items.forEach((item) => result.set(item.id, { restaurant, item }))
    ));
    return result;
  }, [restaurants]);
  const foodCart = useMemo(
    () => resolveFoodCart(foodCartEntries, restaurants),
    [foodCartEntries, restaurants],
  );
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
      presentRequestFailure(wishlistError);
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
      return false;
    }
    const options = item.optionGroups.flatMap((group) => group.options)
      .filter((option) => optionIds.includes(option.id));
    const normalizedIds = options.map((option) => option.id).sort();
    const key = foodCartKey(item.id, normalizedIds);
    setFoodCartEntries((current) => {
      const found = current.find((line) => foodCartKey(line.itemId, line.optionIds) === key);
      if (found) {
        return current.map((line) => foodCartKey(line.itemId, line.optionIds) === key
          ? { ...line, quantity: Math.min(line.quantity + 1, 99) }
          : line);
      }
      return [...current, {
        branchId: restaurant.restaurant.branchId,
        itemId: item.id,
        optionIds: normalizedIds,
        quantity: 1,
      }];
    });
    setError(undefined);
    return true;
  };
  const decrementFood = (key: string) => setFoodCartEntries((current) => current.flatMap((line) =>
    foodCartKey(line.itemId, line.optionIds) !== key
      ? [line]
      : line.quantity > 1
        ? [{ ...line, quantity: line.quantity - 1 }]
        : []
  ));
  const incrementFood = (key: string) => setFoodCartEntries((current) => current.map((line) =>
    foodCartKey(line.itemId, line.optionIds) === key
      ? { ...line, quantity: Math.min(line.quantity + 1, 99) }
      : line
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
              key: foodCartKey(current.item.id, normalizedIds),
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
    setFoodCartEntries(persistedFoodCart(nextFoodCart));
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
      setFoodCartEntries([]);
      setShowingCart(false);
      setSelectedOrder(order);
      props.onOpenOrder(order.id);
    } catch (submitError) {
      presentRequestFailure(submitError);
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
      presentRequestFailure(cancelError, setOrderActionError);
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
      presentRequestFailure(issueError, setOrderActionError);
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
      presentRequestFailure(addressError);
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
    } catch (addressError) { presentRequestFailure(addressError); }
    finally { setBusy(false); }
  };

  const deleteAddress = async (address: CustomerDeliveryAddress) => {
    setBusy(true);
    try {
      const result = await deleteCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: crypto.randomUUID() });
      setAddresses(result.addresses);
    } catch (addressError) { presentRequestFailure(addressError); }
    finally { setBusy(false); }
  };

  if (showingLaunchPayment && selectedOrder) {
    return <LaunchPaymentScreen
      auth={auth}
      order={selectedOrder}
      onSessionExpired={props.onSessionExpired}
      onDismiss={() => {
        setShowingLaunchPayment(false);
        void refreshSelectedOrder(selectedOrder.id).catch((requestError) => presentRequestFailure(requestError, setOrderActionError));
      }}
      onCommitted={(order) => {
        setSelectedOrder(order);
        setOrders((current) => mergeV1Orders([order], current));
        setShowingLaunchPayment(false);
        setPaymentMessage("Order confirmed. Your basket is now being prepared; pay your delivery partner at the doorstep.");
      }}
    />;
  }

  return <div className="v1-customer-shell">
    <CustomerHeader address={defaultAddress} count={cartCount} onAddress={() => addresses.length ? setShowingAddressBook(true) : setEditingAddress(null)} onSearch={() => props.onNavigate("search")} onCart={() => setShowingCart(true)} />
    {props.section === "search" || props.section === "wishlist" || props.section === "payments" ? <button className="customer-back-link" type="button" onClick={() => props.onNavigate(props.section === "search" ? "home" : "account")}><ArrowLeft size={17} />{props.section === "search" ? "Home" : "Account"}</button> : null}
    {error && !showingCart && editingAddress === undefined && !showingAddressBook ? <CustomerNotice title="We couldn’t complete that action" onDismiss={() => setError(undefined)}>{error}</CustomerNotice> : null}
    {storefrontIssues.addresses && (props.section === "home" || showingCart) ? <CustomerNotice title="Saved places couldn’t update" onRetry={() => void refreshAddresses()}>{addresses.length ? "Your saved address is still shown. Reconnect before changing it." : storefrontIssues.addresses}</CustomerNotice> : null}
    {props.section === "home" ? <HomeSection
      mode={homeMode}
      onMode={(mode) => {
        setHomeMode(mode);
        setSelectedCategoryType(undefined);
        setSelectedCategory(undefined);
        setSelectedSubcategory(undefined);
      }}
      supabaseUrl={props.supabaseUrl}
      restaurants={restaurants}
      categoryTypes={catalogue?.categoryTypes ?? []}
      categories={catalogue?.categories ?? []}
      subcategories={catalogue?.subcategories ?? []}
      skus={selectedCategory ? categorySkus[selectedCategory] ?? [] : catalogue?.skus ?? []}
      loadingProducts={Boolean(selectedCategory && loadingCategoryId === selectedCategory)}
      loadingCatalogue={loadingCatalogue && !catalogue}
      catalogueIssue={storefrontIssues.catalogue}
      restaurantIssue={storefrontIssues.restaurants}
      onRetryCatalogue={() => void refreshCatalogue()}
      onRetryRestaurants={() => void refreshRestaurants()}
      onSearch={() => props.onNavigate("search")}
      selectedCategoryType={selectedCategoryType}
      selectedCategory={selectedCategory}
      selectedSubcategory={selectedSubcategory}
      onCategoryType={(id) => {
        const children = id ? catalogue?.categories.filter((item) => item.categoryTypeId === id) ?? [] : [];
        setSelectedCategoryType(id);
        setSelectedCategory((children.find((item) => item.status === "ACTIVE") ?? children[0])?.id);
        setSelectedSubcategory(undefined);
      }}
      onCategory={(id) => {
        setSelectedCategory(id);
        setSelectedSubcategory(undefined);
        if (id) setSelectedCategoryType(catalogue?.categories.find((item) => item.id === id)?.categoryTypeId);
      }}
      onSubcategory={setSelectedSubcategory}
      onOrders={() => props.onNavigate("orders")}
      onAdd={add}
      onRestaurant={setSelectedRestaurant}
      wishlistIds={wishlistIds}
      wishlistUpdatingIds={wishlistUpdatingIds}
      onWishlist={toggleWishlist}
    /> : props.section === "search" ? <SearchSection
      supabaseUrl={props.supabaseUrl}
      query={query} onQuery={setQuery} searching={searching}
      skus={query.trim() ? searchResults : []} onAdd={add}
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
      onSessionExpired={props.onSessionExpired}
      realtimeHealth={props.realtimeHealth}
      onShop={() => props.onNavigate("home")}
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
    {showingCart && !showingAddressBook && editingAddress === undefined && <CartSheet
      lines={cartLines} foodLines={foodCart} subtotal={cartSubtotal} address={defaultAddress} busy={busy} supabaseUrl={props.supabaseUrl} error={error}
      onDismiss={() => setShowingCart(false)} onAdd={add} onDecrement={decrement}
      onAddFood={incrementFood} onDecrementFood={decrementFood}
      onAddress={() => addresses.length ? setShowingAddressBook(true) : setEditingAddress(null)} onSubmit={submit}
    />}
    {selectedRestaurant && <RestaurantMenuSheet
      menu={selectedRestaurant} supabaseUrl={props.supabaseUrl} error={error}
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
        presentRequestFailure(requestError, setLiveOrderError);
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
  </div>;
}

export function CustomerHeader({ address, count, onAddress, onSearch, onCart }: { address?: CustomerDeliveryAddress; count: number; onAddress: () => void; onSearch: () => void; onCart: () => void }) {
  return <header className="v1-customer-header">
    <button type="button" className="v1-deliver-to" onClick={onAddress}><MapPin size={21} /><span><small>Deliver to</small><strong>{address?.label ?? "Set your location"}<ChevronRight size={15} /></strong>{address ? <em>{address.displayAddress}</em> : null}</span></button>
    <div className="v1-header-actions"><button className="customer-header-search-icon" type="button" onClick={onSearch} aria-label="Search Dastak" title="Search"><Search size={21} /></button><button className="customer-basket-button" type="button" onClick={onCart} aria-label={`Basket, ${count} items`}><ShoppingBag size={21} /><span>Basket</span>{count > 0 ? <b>{count}</b> : null}</button></div>
  </header>;
}

export function HomeSection({ mode = "grocery", onMode = () => undefined, supabaseUrl, restaurants, categoryTypes, categories, subcategories, skus, loadingProducts, loadingCatalogue = false, catalogueIssue, restaurantIssue, onRetryCatalogue, onRetryRestaurants, onSearch, selectedCategoryType, selectedCategory, selectedSubcategory, onCategoryType, onCategory, onSubcategory, onOrders, onAdd, onRestaurant, wishlistIds, wishlistUpdatingIds, onWishlist }: {
  mode?: CustomerHomeMode; onMode?: (mode: CustomerHomeMode) => void;
  supabaseUrl: string;
  restaurants: V1RestaurantMenu[];
  categoryTypes: V1CatalogueCategoryType[]; categories: V1CatalogueCategory[];
  subcategories: V1CatalogueSubcategory[]; skus: V1CatalogueSku[];
  loadingProducts: boolean;
  loadingCatalogue?: boolean; catalogueIssue?: string; restaurantIssue?: string;
  onRetryCatalogue?: () => void; onRetryRestaurants?: () => void; onSearch?: () => void;
  selectedCategoryType?: string; selectedCategory?: string; selectedSubcategory?: string;
  onCategoryType: (id?: string) => void;
  onCategory: (id?: string) => void; onSubcategory: (id?: string) => void;
  onOrders: () => void;
  onAdd: (sku: V1CatalogueSku) => void; onRestaurant: (restaurant: V1RestaurantMenu) => void;
  wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>;
  onWishlist: (kind: CustomerWishlistItemKind, itemId: string) => void;
}) {
  const directoryRef = useRef<HTMLElement>(null);
  useEffect(() => {
    if (selectedCategoryType) directoryRef.current?.scrollIntoView({ block: "start" });
  }, [selectedCategoryType]);
  const visible = skus.filter((sku) =>
    (!selectedCategory || sku.categoryId === selectedCategory) &&
    (!selectedSubcategory || sku.subcategoryId === selectedSubcategory));
  const categorySubcategories = subcategories.filter((item) => item.categoryId === selectedCategory);
  const selectedType = categoryTypes.find((item) => item.id === selectedCategoryType);
  const selectedTypeCategories = categories.filter((item) => item.categoryTypeId === selectedCategoryType);
  const navigationGroups = catalogueNavigationGroups(categoryTypes);
  const selectedName = subcategories.find((item) => item.id === selectedSubcategory)?.name
    ?? categories.find((item) => item.id === selectedCategory)?.name;
  return <>
    {!selectedType ? <CustomerCommerceNavigation mode={mode} onMode={onMode} /> : null}
    {!selectedType && mode === "grocery" ? <section className="customer-home-hero"><div><p className="customer-eyebrow">YOUR EVERYDAY, DELIVERED</p><h1>A little more ease.<br /><em>Every day.</em></h1><p>Groceries and everyday essentials, selected carefully and brought to your doorstep.</p><button className="customer-button" type="button" onClick={() => directoryRef.current?.scrollIntoView({ block: "start", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" })}>Shop grocery<ArrowRight size={19} /></button><span className="customer-hero-assurance"><ShieldCheck size={17} /> Pay via UPI or cash at your doorstep</span></div><div className="customer-hero-display" aria-hidden="true"><span className="customer-hero-orbit" />{skus.filter((sku) => sku.imageKey).slice(0, 3).map((sku) => <div key={sku.id}><ProductImage src={catalogueImageUrl(supabaseUrl, sku.imageKey ?? null)} alt="" /></div>)}<span className="customer-hero-seal">The everyday<br /><b>made easy.</b></span></div></section> : null}
    {!selectedType && mode === "grocery" ? <div className="customer-discovery-shortcuts"><button type="button" onClick={() => directoryRef.current?.scrollIntoView({ block: "start" })}><ShoppingBag size={20} /><span>Shop essentials</span><ArrowRight size={16} /></button><button type="button" onClick={onSearch}><Search size={20} /><span>Find your favourites</span><ArrowRight size={16} /></button><button type="button" onClick={() => onMode("food")}><UtensilsCrossed size={20} /><span>Order food</span><ArrowRight size={16} /></button></div> : null}
    {!selectedType && mode === "food" ? <section className="customer-food-hero"><div><p className="customer-eyebrow">FOOD, MADE NEARBY</p><h1>Your table is closer<br /><em>than you think.</em></h1><p>Choose a restaurant or café, build your order, and let the kitchen confirm every detail.</p></div><UtensilsCrossed size={46} aria-hidden="true" /></section> : null}
    {!selectedType && mode === "food" && (restaurants.length || restaurantIssue) ? <section className="v1-section" id="customer-restaurants"><header><div><p>RESTAURANTS &amp; CAFES</p><h2>Something delicious, nearby.</h2></div><span>{restaurants.length ? `${restaurants.length} ${restaurants.length === 1 ? "kitchen" : "kitchens"}` : ""}</span></header>
      {restaurantIssue ? <CustomerNotice title="Restaurant menus couldn’t update" onRetry={onRetryRestaurants}>{restaurantIssue}</CustomerNotice> : null}
      <div className="v1-restaurant-rail">{restaurants.map((restaurant) => <button type="button" key={restaurant.restaurant.branchId} onClick={() => onRestaurant(restaurant)}>
        <span className="v1-restaurant-art">{restaurant.restaurant.imageKey ? <ProductImage src={catalogueImageUrl(supabaseUrl, restaurant.restaurant.imageKey)} alt="" /> : <UtensilsCrossed size={28} />}</span>
        <span className="v1-restaurant-copy"><small>RESTAURANT / CAFE</small><strong>{restaurant.restaurant.name}</strong><span>{restaurant.restaurant.branchName}</span><b>{restaurant.categories.reduce((total, category) => total + category.items.length, 0)} items · View menu</b></span>
        <ChevronRight size={18} />
      </button>)}</div>
    </section> : null}
    {!selectedType && mode === "food" && !restaurants.length && !restaurantIssue ? <CustomerEmptyState title="Kitchens are opening soon" copy="Restaurants and cafés available for your area will appear here." icon={<UtensilsCrossed size={30} />} /> : null}
    {!selectedType && (mode === "parcel" || mode === "print") ? <CustomerComingSoon mode={mode} onGrocery={() => onMode("grocery")} /> : null}
    {mode === "grocery" || selectedType ? <section ref={directoryRef} className="v1-section v1-catalogue-directory"><header><div><p>SHOP DASTAK</p><h2>{selectedType?.name ?? "What does your day need?"}</h2></div>{selectedType ? <button type="button" className="v1-text-action" onClick={() => onCategoryType(undefined)}><ArrowLeft size={16} />All categories</button> : null}</header>
      {catalogueIssue ? <CustomerNotice title="Products couldn’t update" onRetry={onRetryCatalogue}>{catalogueIssue}</CustomerNotice> : null}
      {loadingCatalogue ? <CustomerSkeleton label="Opening Dastak catalogue" /> : !selectedType ? <div className="v1-category-groups">{navigationGroups.map((group) => <section key={group.key}><header><h3>{group.name}</h3></header><div className="v1-category-grid">{group.types.map((type) => <button type="button" key={type.id} onClick={() => onCategoryType(type.id)}><CategoryArtwork supabaseUrl={supabaseUrl} item={type} /><strong>{type.name}</strong>{type.status && type.status !== "ACTIVE" ? <small>Coming soon</small> : null}</button>)}</div></section>)}</div> : <div className="v1-category-browser">
        <div className="v1-subcategory-rail" role="group" aria-label="Subcategories">
          {selectedTypeCategories.map((category) => <button className={selectedCategory === category.id ? "selected" : ""} aria-pressed={selectedCategory === category.id} type="button" key={category.id} onClick={() => onCategory(category.id)}><CategoryArtwork supabaseUrl={supabaseUrl} item={category} /><strong>{category.name}</strong></button>)}
        </div>
        <div className="v1-category-results" key={selectedCategory}><header><h3>{selectedName ?? "Products"}</h3><span>{loadingProducts ? "Loading…" : `${visible.length} products`}</span></header>
          {categorySubcategories.length ? <label className="v1-catalogue-type-filter">Type<select aria-label="Product type" value={selectedSubcategory ?? ""} onChange={(event) => onSubcategory(event.target.value || undefined)}><option value="">All types</option>{categorySubcategories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label> : null}
          {loadingProducts ? <CustomerSkeleton label="Loading this category" /> : selectedCategory ? <ProductGrid supabaseUrl={supabaseUrl} skus={visible} onAdd={onAdd} wishlistIds={wishlistIds} wishlistUpdatingIds={wishlistUpdatingIds} onWishlist={onWishlist} /> : <p>Products coming soon.</p>}</div>
      </div>}
    </section> : null}
    {mode === "grocery" && !loadingCatalogue && !selectedCategory && !selectedCategoryType && visible.length ? <section className="v1-section"><header><div><p>FOR YOUR EVERYDAY</p><h2>Everyday essentials</h2></div><span>{visible.length} products</span></header>
      <ProductGrid supabaseUrl={supabaseUrl} skus={visible} onAdd={onAdd} wishlistIds={wishlistIds} wishlistUpdatingIds={wishlistUpdatingIds} onWishlist={onWishlist} />
    </section> : null}
    {!selectedType ? <button className="v1-order-link" type="button" onClick={onOrders}>View your Dastak orders <ArrowRight size={17} /></button> : null}
  </>;
}

function CustomerCommerceNavigation({ mode, onMode }: { mode: CustomerHomeMode; onMode: (mode: CustomerHomeMode) => void }) {
  const items: Array<{ mode: CustomerHomeMode; label: string; icon: React.ReactNode; soon?: boolean }> = [
    { mode: "food", label: "Food", icon: <UtensilsCrossed /> },
    { mode: "grocery", label: "Grocery", icon: <ShoppingBag /> },
    { mode: "parcel", label: "Parcel", icon: <PackageCheck />, soon: true },
    { mode: "print", label: "Print", icon: <Printer />, soon: true },
  ];
  return <nav className="customer-commerce-nav" aria-label="Shop by service">{items.map((item) => <button key={item.mode} type="button" className={mode === item.mode ? "selected" : ""} aria-current={mode === item.mode ? "page" : undefined} onClick={() => onMode(item.mode)}>{item.icon}<span>{item.label}</span>{item.soon ? <small>Soon</small> : null}</button>)}</nav>;
}

function CustomerComingSoon({ mode, onGrocery }: { mode: "parcel" | "print"; onGrocery: () => void }) {
  const print = mode === "print";
  return <section className="customer-coming-soon"><span>{print ? <Printer size={34} /> : <PackageCheck size={34} />}</span><p className="customer-eyebrow">COMING SOON</p><h1>{print ? "Print, without the errand." : "Send it with Dastak."}</h1><p>{print ? "Documents and everyday print jobs, prepared carefully and delivered to your doorstep." : "A simple, secure way to send parcels across your city is on its way."}</p><button className="customer-button" type="button" onClick={onGrocery}>Shop grocery for now<ArrowRight size={18} /></button></section>;
}

export function SearchSection({ supabaseUrl, query, onQuery, searching, skus, onAdd, wishlistIds, wishlistUpdatingIds, onWishlist }: { supabaseUrl: string; query: string; onQuery: (value: string) => void; searching: boolean; skus: V1CatalogueSku[]; onAdd: (sku: V1CatalogueSku) => void; wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>; onWishlist: (kind: CustomerWishlistItemKind, itemId: string) => void }) {
  const submit = (event: FormEvent) => event.preventDefault();
  return <section className="v1-search-page"><CustomerPageHeading eyebrow="FIND YOUR EVERYDAY" title="What’s on your list?" description="Find a favourite, discover something new, or search for exactly what you need." />
    <form className="v1-search-field" role="search" onSubmit={submit}><Search size={20} /><input autoFocus value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Products, brands and categories" aria-label="Search Dastak products" />{query ? <button type="button" onClick={() => onQuery("")} aria-label="Clear search"><X size={17} /></button> : null}</form>
    {!query.trim() ? <><div className="customer-search-ideas"><p>Need a little inspiration?</p><div>{["Milk", "Fresh fruit", "Coffee", "Rice", "Snacks"].map((term) => <button type="button" key={term} onClick={() => onQuery(term)}><Search size={15} />{term}</button>)}</div></div><CustomerEmptyState title="Your next favourite is a search away" copy="Start typing to find a product, brand or category." icon={<Search size={30} />} /></> : searching ? <CustomerSkeleton label="Searching Dastak" /> : skus.length ? <><p className="customer-result-count" role="status">{skus.length} {skus.length === 1 ? "result" : "results"} for “{query.trim()}”</p><ProductGrid supabaseUrl={supabaseUrl} skus={skus} onAdd={onAdd} wishlistIds={wishlistIds} wishlistUpdatingIds={wishlistUpdatingIds} onWishlist={onWishlist} /></> : <CustomerEmptyState title="No exact matches" copy="Try a shorter name, another brand, or a category like milk or snacks." icon={<Search size={30} />} action="Clear search" onAction={() => onQuery("")} />}
  </section>;
}

function CategoryArtwork({ supabaseUrl, item }: { supabaseUrl: string; item: V1CatalogueCategory }) {
  const categoryArtwork = {
    "fresh-produce": "canonical/taxonomy/fresh-produce-provided-v2.png",
    "personal-care": "canonical/taxonomy/personal-care-v2.png",
    "beauty-grooming": "canonical/taxonomy/beauty-grooming-skin-face-reference.png",
    "health-hygiene": "canonical/taxonomy/pharma-wellness-v2.png",
    pharmacy: "canonical/taxonomy/pharmacy-wellness-reference.png",
    "toys-games-kids": "canonical/taxonomy/toys-games-kids-v2.png",
    "automotive-travel-utility": "canonical/taxonomy/automotive-travel-utility-v2.png",
    "home-improvement-hardware": "canonical/taxonomy/home-improvement-hardware-v2.png",
  } as Record<string, string>;
  const subcategoryArtwork = {
    "fresh-produce-all": "canonical/taxonomy/subcategories/fresh-produce-all.png",
    "fresh-fruits": "canonical/taxonomy/subcategories/fresh-fruits-provided.png",
    "fresh-vegetables": "canonical/taxonomy/subcategories/fresh-vegetables-provided.png",
    "leafy-greens-herbs": "canonical/taxonomy/subcategories/leafy-greens-herbs-provided.png",
    "seasonal-fruits": "canonical/taxonomy/subcategories/seasonal-fruits-provided.png",
    "fresh-cuts-sprouts": "canonical/taxonomy/subcategories/fresh-cuts-sprouts-provided.png",
    "exotic-premium-produce": "canonical/taxonomy/subcategories/exotic-premium-produce-provided.png",
    "flowers-leaves": "canonical/taxonomy/subcategories/flowers-leaves-provided.png",
    "trusted-organics": "canonical/taxonomy/subcategories/trusted-organics-web.png",
    "frozen-vegetables": "canonical/taxonomy/subcategories/frozen-veg-v3.png",
    milk: "canonical/taxonomy/subcategories/milk-provided.png",
    "curd-and-yogurt": "canonical/taxonomy/subcategories/curd-yogurt-provided.png",
    "paneer-and-cream": "canonical/taxonomy/subcategories/paneer-cream-provided.png",
    "butter-and-margarine": "canonical/taxonomy/subcategories/butter-margarine-provided.png",
    "curd-yogurt": "canonical/taxonomy/subcategories/curd-yogurt-provided.png",
    "paneer-cream": "canonical/taxonomy/subcategories/paneer-cream-provided.png",
    "butter-margarine": "canonical/taxonomy/subcategories/butter-margarine-provided.png",
    cheese: "canonical/taxonomy/subcategories/cheese-provided.png",
    eggs: "canonical/taxonomy/subcategories/eggs-provided.png",
    "bread-buns": "canonical/taxonomy/subcategories/bread-buns-provided.png",
    "bakery-essentials": "canonical/taxonomy/subcategories/bakery-essentials-provided.png",
    "dairy-alternatives": "canonical/taxonomy/subcategories/dairy-alternatives-provided.png",
    "milk-powders-creamers": "canonical/taxonomy/subcategories/milk-powders-creamers-provided.png",
  } as Record<string, string>;
  // Subcategory rows may be normalized without categoryId by the catalogue API;
  // resolve their permanent artwork by slug before falling back to row data.
  const normalizedName = item.name.toLowerCase().replace(/&/g, "and").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  const permanentArtworkKey = subcategoryArtwork[item.slug] ?? subcategoryArtwork[normalizedName] ?? categoryArtwork[item.slug] ?? item.imageKey;
  return <span className={`v1-category-art count-${permanentArtworkKey ? 1 : 0}`} aria-hidden="true">{permanentArtworkKey
    ? <ProductImage src={catalogueImageUrl(supabaseUrl, permanentArtworkKey)} alt="" />
    : item.slug.includes("paan") || item.slug.includes("produce") ? <Leaf size={29} />
      : item.slug.includes("pharmacy") || item.slug.includes("medicine") || item.slug.includes("health") ? <ShieldCheck size={29} />
      : <PackageCheck size={28} />}</span>;
}

function catalogueNavigationGroups(categoryTypes: V1CatalogueCategoryType[]) {
  const groups = new Map<string, {
    key: string;
    name: string;
    sortOrder: number;
    types: V1CatalogueCategoryType[];
  }>();
  for (const type of categoryTypes) {
    const section = type.navigationSection ?? { key: "more", name: "More to explore", sortOrder: 999 };
    const group = groups.get(section.key) ?? { ...section, types: [] };
    group.types.push(type);
    groups.set(section.key, group);
  }
  return [...groups.values()]
    .map((group) => ({ ...group, types: [...group.types].sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name)) }))
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

export function ProductGrid({ supabaseUrl, skus, onAdd, wishlistIds, wishlistUpdatingIds, onWishlist }: { supabaseUrl: string; skus: V1CatalogueSku[]; onAdd: (sku: V1CatalogueSku) => void; wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>; onWishlist: (kind: CustomerWishlistItemKind, itemId: string) => void }) {
  const [selectedId, setSelectedId] = useState<string>();
  const selected = skus.find((sku) => sku.id === selectedId);
  const [addedId, setAddedId] = useState<string>();
  useEffect(() => {
    if (!addedId) return;
    const timer = window.setTimeout(() => setAddedId(undefined), 1800);
    return () => window.clearTimeout(timer);
  }, [addedId]);
  const addProduct = (sku: V1CatalogueSku) => { onAdd(sku); setAddedId(sku.id); };
  if (!skus.length) return <EmptyState title="No products here yet" copy="Choose another category." />;
  return <><div className="v1-product-grid">{skus.map((sku) => <article className="v1-product-card" key={sku.id}>
    <button type="button" className="product-open-button" onClick={() => setSelectedId(sku.id)} aria-label={`View ${sku.name} details`}><ProductImage className="v1-product-art" src={catalogueImageUrl(supabaseUrl, sku.imageKey ?? null)} alt="" /></button>
    <button className="v1-wishlist-button" type="button" aria-pressed={wishlistIds.has(`RETAIL_SKU:${sku.id}`)} disabled={wishlistUpdatingIds.has(sku.id)} onClick={() => onWishlist("RETAIL_SKU", sku.id)} aria-label={wishlistIds.has(`RETAIL_SKU:${sku.id}`) ? `Remove ${sku.name} from Wishlist` : `Save ${sku.name} to Wishlist`}>
      <Heart size={18} fill={wishlistIds.has(`RETAIL_SKU:${sku.id}`) ? "currentColor" : "none"} />
    </button>
    {sku.listPricePaise > sku.sellingPricePaise ? <span className="customer-product-saving">{Math.round((1 - sku.sellingPricePaise / sku.listPricePaise) * 100)}% off</span> : null}
    <div className="v1-product-copy"><small>{sku.brand?.name ?? "Dastak selection"}</small><h3><button type="button" className="customer-product-title" onClick={() => setSelectedId(sku.id)} title={sku.name}>{sku.name}</button></h3><p>{[sku.variant, sku.packSize].filter(Boolean).join(" · ")}</p>
      <div className="customer-product-price"><span><strong>{formatV1Price(sku.sellingPricePaise)}</strong>{sku.listPricePaise > sku.sellingPricePaise ? <del>{formatV1Price(sku.listPricePaise)}</del> : null}</span><button className="customer-add-product" type="button" onClick={() => addProduct(sku)} aria-label={`Add ${sku.name}`}>{addedId === sku.id ? <Check size={17} /> : <Plus size={17} />}<span>{addedId === sku.id ? "Added" : "Add"}</span></button></div>
    </div>
  </article>)}</div>{selected ? <ProductDetailOverlay
    selectedId={selected.id} products={skus.filter((item) => item.categoryId === selected.categoryId).map(customerDetail)}
    supabaseUrl={supabaseUrl} onSelect={setSelectedId} onClose={() => setSelectedId(undefined)} showPagingControls
    renderProduct={(product, select) => {
      const sku = skus.find((item) => item.id === product.id);
      return sku ? <ProductDetailCard product={product} products={skus.filter((item) => item.categoryId === sku.categoryId).map(customerDetail)}
        supabaseUrl={supabaseUrl} onSelect={select} onClose={() => setSelectedId(undefined)}
        saved={wishlistIds.has(`RETAIL_SKU:${sku.id}`)} savingWishlist={wishlistUpdatingIds.has(sku.id)}
        onWishlist={() => onWishlist("RETAIL_SKU", sku.id)}
        action={<button type="button" onClick={() => addProduct(sku)}>{addedId === sku.id ? <><Check size={18} />Added</> : <><Plus size={18} />Add to basket</>}</button>}>
        {addedId === sku.id ? <p className="product-share-status" role="status">Added to your basket</p> : null}
      </ProductDetailCard> : null;
    }} /> : null}<span className="customer-sr-only" role="status">{addedId ? "Item added to your basket" : ""}</span></>;
}

function customerDetail(sku: V1CatalogueSku): DetailProduct {
  return { ...sku, brand: sku.brand?.name, price: sku.sellingPricePaise, listPrice: sku.listPricePaise,
    facts: [["Manufacturer", sku.manufacturerName], ["Country of origin", sku.countryOfOriginCode], ["Diet", sku.dietType], ["Shelf life", sku.shelfLifeDays ? `${sku.shelfLifeDays} days` : undefined], ["Barcode", sku.barcode]] };
}

export function CartSheet({ lines, foodLines, subtotal, address, busy, supabaseUrl, error, onDismiss, onAdd, onDecrement, onAddFood, onDecrementFood, onAddress, onSubmit }: {
  lines: Array<{ sku: V1CatalogueSku; quantity: number }>; subtotal: number; address?: CustomerDeliveryAddress; busy: boolean;
  foodLines: FoodCartLine[]; onDismiss: () => void; onAdd: (sku: V1CatalogueSku) => void;
  onDecrement: (id: string) => void; onAddFood: (key: string) => void; onDecrementFood: (key: string) => void;
  onAddress: () => void; onSubmit: () => void;
  supabaseUrl: string; error?: string;
}) {
  const dialog = useModalDialog<HTMLElement>({ busy, onDismiss });
  const empty = !lines.length && !foodLines.length;
  return <div className="v1-overlay" role="presentation"><section ref={dialog} tabIndex={-1} className="v1-sheet v1-cart-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-cart-title">
    <header><div><p>GOOD THINGS, TOGETHER</p><h2 id="v1-cart-title">Your basket</h2></div><button type="button" disabled={busy} onClick={onDismiss} aria-label="Close basket"><X size={19} /></button></header>
    {empty ? <CustomerEmptyState title="A little empty in here" copy="Add everyday essentials or something delicious. We’ll bring it all together." action="Explore Dastak" onAction={onDismiss} icon={<ShoppingBag size={30} />} /> : <>
    <div className="v1-security-note"><ShieldCheck size={20} /><span><strong>Your full basket, confirmed first</strong><small>We’ll secure your items before you confirm. Pay by UPI or cash at your doorstep.</small></span></div>
    <div className="v1-cart-lines">
      {foodLines.length ? <p className="v1-cart-group">{foodLines[0].restaurantName}</p> : null}
      {foodLines.map((line) => <article key={line.key}><div><strong>{line.item.name}</strong><small>{line.optionNames.join(" · ") || "Restaurant item"}</small><b>{formatV1Price(line.unitPricePaise * line.quantity)}</b></div><div className="v1-quantity"><button type="button" onClick={() => onDecrementFood(line.key)} aria-label={`Remove one ${line.item.name}`}><Minus size={16} /></button><span>{line.quantity}</span><button type="button" onClick={() => onAddFood(line.key)} disabled={line.quantity >= 99} aria-label={`Add one ${line.item.name}`}><Plus size={16} /></button></div></article>)}
      {lines.length && foodLines.length ? <p className="v1-cart-group">Retail essentials</p> : null}
      {lines.map(({ sku, quantity }) => <article className="customer-cart-retail-line" key={sku.id}><ProductImage src={catalogueImageUrl(supabaseUrl, sku.imageKey ?? null)} alt="" /><div className="customer-cart-line-copy"><strong>{sku.name}</strong><small>{sku.packSize}</small><b>{formatV1Price(sku.sellingPricePaise * quantity)}</b></div><div className="v1-quantity"><button type="button" onClick={() => onDecrement(sku.id)} aria-label={`Remove one ${sku.name}`}><Minus size={16} /></button><span>{quantity}</span><button type="button" onClick={() => onAdd(sku)} disabled={quantity >= 99} aria-label={`Add one ${sku.name}`}><Plus size={16} /></button></div></article>)}
    </div>
    <div className="v1-cart-total"><span>Basket subtotal</span><strong>{formatV1Price(subtotal)}</strong><small>Delivery, platform fees and final total appear after the complete Food + Retail basket is secured.</small></div>
    <button className="v1-address-button" type="button" onClick={onAddress}><MapPin size={19} /><span><strong>{address ? `Deliver to ${address.label}` : "Add delivery address"}</strong><small>{address?.displayAddress ?? "Add a precise pin and doorstep details."}</small></span><ChevronRight size={18} /></button>
    {error ? <CustomerNotice title="Your basket needs attention">{error}</CustomerNotice> : null}
    <footer className="customer-cart-footer"><span><LockKeyhole size={15} />No charge now</span><button className="primary-button v1-submit" type="button" disabled={busy} onClick={onSubmit}>{busy ? "Placing order…" : address ? "Place order" : "Add address to continue"}<ArrowRight size={18} /></button></footer></>}
  </section></div>;
}

function RestaurantMenuSheet({ menu, supabaseUrl, error, onDismiss, onAdd, wishlistIds, wishlistUpdatingIds, onWishlist }: {
  menu: V1RestaurantMenu; onDismiss: () => void;
  supabaseUrl: string; error?: string;
  onAdd: (item: V1RestaurantMenuItem, optionIds: string[]) => boolean;
  wishlistIds: Set<string>; wishlistUpdatingIds: Set<string>; onWishlist: (itemId: string) => void;
}) {
  const dialog = useModalDialog<HTMLElement>({ onDismiss });
  return <div className="v1-overlay" role="presentation"><section ref={dialog} tabIndex={-1} className="v1-sheet v1-menu-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-menu-title">
    <header><div><p>RESTAURANT / CAFE</p><h2 id="v1-menu-title">{menu.restaurant.name}</h2><small>{menu.restaurant.branchName}</small></div><button type="button" onClick={onDismiss} aria-label="Close restaurant menu"><X size={19} /></button></header>
    <div className="customer-menu-banner" aria-hidden="true">{menu.restaurant.imageKey ? <ProductImage src={catalogueImageUrl(supabaseUrl, menu.restaurant.imageKey)} alt="" /> : <UtensilsCrossed size={42} />}</div>
    <div className="v1-security-note"><UtensilsCrossed size={20} /><span><strong>Prepared by {menu.restaurant.name}</strong><small>Your chosen kitchen confirms each item. You pay at your doorstep.</small></span></div>
    {error ? <CustomerNotice title="Your basket needs attention">{error}</CustomerNotice> : null}
    <nav className="customer-menu-nav" aria-label="Menu categories">{menu.categories.map((category) => <a href={`#menu-${category.id}`} key={category.id} onClick={(event) => { event.preventDefault(); document.getElementById(`menu-${category.id}`)?.scrollIntoView({ block: "start" }); }}>{category.name}</a>)}</nav>
    {menu.categories.map((category) => <section className="v1-menu-category" id={`menu-${category.id}`} key={category.id}><h3>{category.name}</h3>{category.description ? <p>{category.description}</p> : null}<div>{category.items.map((item) => <RestaurantItemCard key={item.id} item={item} supabaseUrl={supabaseUrl} onAdd={onAdd} wished={wishlistIds.has(`MENU_ITEM:${item.id}`)} updatingWishlist={wishlistUpdatingIds.has(item.id)} onWishlist={() => onWishlist(item.id)} />)}</div></section>)}
  </section></div>;
}

function RestaurantItemCard({ item, supabaseUrl, onAdd, wished, updatingWishlist, onWishlist }: {
  item: V1RestaurantMenuItem; supabaseUrl: string; onAdd: (item: V1RestaurantMenuItem, optionIds: string[]) => boolean;
  wished: boolean; updatingWishlist: boolean; onWishlist: () => void;
}) {
  const [added, setAdded] = useState(false);
  useEffect(() => {
    if (!added) return;
    const timer = window.setTimeout(() => setAdded(false), 1800);
    return () => window.clearTimeout(timer);
  }, [added]);
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
    {item.imageKey ? <ProductImage className="customer-menu-photo" src={catalogueImageUrl(supabaseUrl, item.imageKey)} alt={item.name} /> : null}
    <button className="primary-button" type="button" disabled={!valid} onClick={() => setAdded(onAdd(item, optionIds))}>{added ? <><Check size={18} /> Added</> : `Add · ${formatV1Price(total)}`}</button><span className="customer-sr-only" role="status">{added ? `${item.name} added to your basket` : ""}</span>
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

function LaunchPaymentScreen({ auth, order, onDismiss, onCommitted, onSessionExpired }: {
  auth: DastakV1Auth;
  order: V1Order;
  onDismiss: () => void;
  onCommitted: (order: V1Order) => void;
  onSessionExpired: () => void;
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
      const issue = customerDataIssue(requestError);
      if (issue.action === "sign_in") {
        onSessionExpired();
        return;
      }
      setState("failure");
      setError(message(requestError));
    }
  };

  return <div className="v1-launch-payment-page">
    <section className="v1-launch-payment-card" aria-labelledby="launch-payment-title">
      <header><button type="button" onClick={onDismiss} disabled={state === "confirming"} aria-label="Back to order"><X size={19} /></button><div><p>SECURED CHECKOUT</p><h1 id="launch-payment-title">Confirm your order</h1></div></header>
      <div className="v1-launch-payment-total"><span><small>YOUR ORDER TOTAL</small><strong>{formatV1Price(order.launchPayment?.amountPaise ?? order.price.totalPaise)}</strong></span><ShieldCheck size={27} /></div>
      <section className="v1-launch-payment-reservation"><PackageCheck size={21} /><span><strong>{expired ? "Reservation expired" : "Your full basket is secured"}</strong><small>{expired ? "Return to your order to see the latest status." : `${formatDuration(secondsRemaining)} remaining to confirm`}</small></span></section>
      <section className="v1-launch-payment-address"><MapPin size={20} /><span><small>DELIVER TO</small><strong>{orderAddress(order)}</strong></span></section>
      <section className="v1-launch-payment-option" aria-label="Selected payment option"><span aria-hidden="true"><Check size={18} /></span><div><strong>Pay via UPI/Cash on Delivery</strong><small>Pay the delivery partner at your doorstep by UPI or cash. No charge now.</small></div></section>
      <div className="v1-launch-payment-assurance"><LockKeyhole size={18} /><span>Dastak will confirm the full secured basket and begin preparation immediately.</span></div>
      {state === "committed" ? <p className="v1-launch-payment-success" role="status"><Check size={18} /> Order confirmed. Opening your Preparing journey…</p> : null}
      {error ? <div className="v1-launch-payment-error" role="alert"><CircleAlert size={18} /><span>{error}</span></div> : null}
      {expired ? <button className="secondary-button" type="button" onClick={onDismiss}>Back to order</button> : <button className="primary-button" type="button" disabled={state === "confirming" || state === "committed"} onClick={() => void confirm()}>{state === "confirming" ? "Confirming order…" : state === "failure" ? "Try confirming again" : "Confirm order"}<ArrowRight size={18} /></button>}
    </section>
  </div>;
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
  onRefresh, onLoadMore, onOpen, onReorder, onSessionExpired, realtimeHealth, onShop,
}: {
  orders: V1Order[];
  loading: boolean;
  loadingMore: boolean;
  canLoadMore: boolean;
  error?: CustomerDataIssue;
  imageUrlForLine: (line: V1Order["lines"][number]) => string | null;
  onRefresh: () => void;
  onLoadMore: () => void;
  onOpen: (order: V1Order) => void;
  onReorder: (order: V1Order) => void;
  onSessionExpired: () => void;
  realtimeHealth?: OrderRealtimeHealth;
  onShop?: () => void;
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
    <CustomerPageHeading eyebrow="YOUR DASTAK" title="Orders" description="From your first pick to your doorstep. Follow it all here."><CustomerSyncStatus health={realtimeHealth} refreshing={loading} failed={Boolean(error)} /></CustomerPageHeading>
    <div className="v1-order-scopes" role="group" aria-label="Filter orders">
      {(["active", "past"] as const).map((value) => <button type="button" key={value} aria-pressed={scope === value} onClick={() => { scopeWasChosen.current = true; setScope(value); }}><span>{value[0].toUpperCase() + value.slice(1)}</span><small>{value === "active" ? activeCount : orders.length - activeCount}</small></button>)}
    </div>
    {error && orders.length > 0 ? <div className="v1-orders-error" role="status"><CircleAlert size={18} /><span><strong>{error.title}</strong>{error.message}</span><button type="button" onClick={error.action === "sign_in" ? onSessionExpired : onRefresh}>{error.action === "sign_in" ? "Sign in again" : "Try again"}</button></div> : null}
    {error && orders.length === 0 ? <div className="v1-orders-error" role="alert"><CircleAlert size={18} /><span><strong>{error.title}</strong>{error.message}</span><button type="button" onClick={error.action === "sign_in" ? onSessionExpired : onRefresh}>{error.action === "sign_in" ? "Sign in again" : "Try again"}</button></div>
      : loading && orders.length === 0 ? <CustomerSkeleton kind="orders" label="Loading your orders" />
        : visible.length ? <div className="v1-order-list">{visible.map((order) => {
      const active = isV1OrderActive(order.status);
      const duration = deliveredDurationLabel(order);
      const itemCount = orderItemCount(order);
      const productNames = order.lines.slice(0, 2).map((line) => line.name).join(" · ");
      return <article className={`v1-commerce-order-card ${active ? "active" : ""}`} key={order.id}>
        <button className="v1-order-card-main" type="button" onClick={() => onOpen(order)} aria-label={`Open ${order.displayOrderNumber}, ${customerRiderArrived(order) ? "Your rider has arrived" : statusTitle(order.status)}`}>
          <span className={`v1-order-icon ${active ? "active" : "terminal"}`}><OrderStatusIcon status={order.status} size={21} /></span>
          <span className="v1-order-card-copy"><strong>{duration ?? (customerRiderArrived(order) ? "Your rider has arrived" : statusTitle(order.status))}</strong><small>{order.restaurant?.name ?? orderKindLabel(order.orderType)}</small></span>
          <span className="v1-order-card-trailing"><b>{formatV1Price(order.price.totalPaise)}</b></span>
          <span className="v1-order-thumbnails">{order.lines.slice(0, 4).map((line) => <ProductImage key={line.id} src={imageUrlForLine(line)} alt="" />)}{order.lines.length > 4 ? <i>+{order.lines.length - 4}</i> : null}</span>
          <span className="v1-order-products"><b>{productNames}{order.lines.length > 2 ? ` + ${order.lines.length - 2} more` : ""}</b><small>{itemCount} {itemCount === 1 ? "item" : "items"} · {order.displayOrderNumber}</small><time dateTime={order.submittedAt ?? order.createdAt}>{formatOrderDate(order.submittedAt ?? order.createdAt)}</time></span>
          {active ? <OrderJourneyProgress status={order.status} arrived={customerRiderArrived(order)} compact /> : null}
        </button>
        <footer>{canReorderV1Order(order.status) ? <button type="button" onClick={() => onReorder(order)}><RotateCcw size={16} /> Order again</button> : null}<button type="button" onClick={() => onOpen(order)}>{active ? "Track order" : "Details"}</button></footer>
      </article>;
        })}</div>
          : error ? null : <CustomerEmptyState title={scope === "active" ? "No active orders" : "No past orders"} copy={scope === "active" ? "Everything’s taken care of. Your next delivery will appear here as soon as you order." : "Completed and cancelled orders will appear here."} icon={<ReceiptText size={30} />} action="Explore Dastak" onAction={onShop} />}
    {!error && scope === "past" && canLoadMore ? <button className="secondary-button v1-load-more" type="button" disabled={loadingMore} onClick={onLoadMore}>{loadingMore ? "Loading earlier orders…" : "Load earlier orders"}</button> : null}
  </section>;
}

function OrderJourneyProgress({ status, arrived = false, compact = false }: {
  status: V1Order["status"];
  arrived?: boolean;
  compact?: boolean;
}) {
  const current = orderJourneyStep(status);
  if (current === undefined) return null;
  const label = arrived ? "Your rider has arrived" : orderJourneyLabel(status);
  return <div className={`v1-order-progress ${compact ? "compact" : ""}`} role="img" aria-label={label}>
    <div aria-hidden="true">{orderJourneySteps.map((step, index) => <i className={index <= current ? "complete" : undefined} key={step} />)}</div>
    <small>{label}</small>
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
  const arrived = customerRiderArrived(order);

  return <div className="v1-overlay" role="presentation"><section ref={dialog} tabIndex={-1} className="v1-sheet v1-matching-sheet" role="dialog" aria-modal="true" aria-labelledby="v1-order-status-title">
    <header><div><p>{order.displayOrderNumber}</p><h2 id="v1-order-status-title">Order status</h2><small>{order.restaurant?.name ?? orderKindLabel(order.orderType)} · {formatOrderDate(order.submittedAt ?? order.createdAt)}</small></div><button type="button" onClick={onDismiss} aria-label="Close order status"><X size={19} /></button></header>
    <div className={`v1-status-hero ${isFailureStatus(order.status) ? "failure" : ""}`}><span className={matching ? "matching" : ""}>{matching ? <i /> : <OrderStatusIcon status={order.status} size={25} />}</span><div><header><h3>{deliveredDurationLabel(order) ?? (arrived ? "Your rider has arrived" : statusTitle(order.status))}</h3><strong>{formatV1Price(order.price.totalPaise)}</strong></header><p>{arrived ? "Your delivery partner is at the destination. Check every package before sharing your delivery PIN." : statusMessage(order.status)}</p></div>{isV1OrderActive(order.status) ? <OrderJourneyProgress status={order.status} arrived={arrived} /> : null}<small className="v1-order-assurance"><ShieldCheck size={16} /> {statusAssurance(order.status)}</small></div>

    {(order.status === "PAID" || order.status === "PREPARING") && readyAt ? <section className={`v1-order-eta ${runningLate ? "late" : ""}`} aria-label="Preparation estimate"><ClockAlert size={21} /><span><strong>{runningLate ? "Taking a little longer" : "Preparation estimate"}</strong><small>{runningLate ? "Your order stays in preparation until it is genuinely ready." : `Expected around ${formatOrderTime(readyAt)}`}</small></span><b>{runningLate ? "We’re watching" : relativeTime(readyAt, now)}</b></section> : null}

    {order.status === "OUT_FOR_DELIVERY" && order.delivery?.deliveryCode && !order.delivery.pinVerified ? <div className="v1-delivery-code" role="status">
      <header><ShieldCheck size={20} /><span><small>DELIVERY CODE</small><b>Share only after every package arrives</b></span></header>
      <strong>{order.delivery.deliveryCode}</strong>
      <p>Share this PIN once your rider and every package arrive. The rider then takes the package photo, collects payment and completes delivery. A trusted recipient can use this PIN without an account.</p>
    </div> : null}

    {order.tracking || order.status === "OUT_FOR_DELIVERY" ? <CustomerLiveDelivery order={order} delayed={Boolean(liveError)} /> : null}

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
      { label: "Rider arrived", value: order.delivery?.riderArrivedAt },
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
  return <CustomerEmptyState title={title} copy={copy} />;
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
  if (status === "CANCELLED_PREPAYMENT" || status === "CANCELLED") return <Ban size={size} />;
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
  return ["UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT", "CANCELLED",
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

function formatDuration(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
}

function message(error: unknown) { return userFacingError(error, "Dastak could not complete this request."); }
