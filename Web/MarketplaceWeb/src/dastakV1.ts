import type { SupabaseClient } from "@supabase/supabase-js";

export type DastakV1Auth = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

export type V1OperationalPauseScope =
  | "ZONE_RETAIL"
  | "ZONE_FOOD"
  | "ZONE_MIXED"
  | "MERCHANT_BRANCH"
  | "RIDER_ASSIGNMENTS";

export type V1OperationalSafety = {
  permissions: {
    canManageRiderEscalations: boolean;
    canManageOperationalPauses: boolean;
  };
  pauses: Array<{
    id: string;
    scope: V1OperationalPauseScope;
    targetId: string;
    active: boolean;
    reason: string;
    activatedAt: string | null;
    clearedAt: string | null;
    version: number;
  }>;
  riderEscalations: Array<{
    missionId: string;
    orderId: string;
    displayOrderNumber: string;
    status: string;
    riderId: string | null;
    transportType: string | null;
    lastContactAt: string | null;
    lastProgressAt: string | null;
    stallDetectedAt: string | null;
    unresponsiveDetectedAt: string | null;
    escalationState: string;
    escalatedAt: string | null;
    escalationReason: string | null;
    custodyStarted: boolean;
    version: number;
  }>;
};

export type V1CatalogueCategory = {
  id: string;
  name: string;
  slug: string;
  imageKey?: string;
  sortOrder: number;
};

export type V1CatalogueSubcategory = V1CatalogueCategory & { categoryId: string };
export type V1CatalogueBrand = { id: string; name: string; slug: string };
export type V1CatalogueSku = {
  id: string;
  categoryId: string;
  subcategoryId: string;
  brand?: V1CatalogueBrand;
  name: string;
  slug: string;
  variant?: string;
  packSize: string;
  description?: string;
  imageKey?: string;
  barcode?: string;
  listPricePaise: number;
  sellingPricePaise: number;
  currencyCode: "INR";
  logisticsAttributes: Record<string, unknown>;
};

export type V1CatalogueSnapshot = {
  catalogueVersion?: string;
  categories: V1CatalogueCategory[];
  subcategories: V1CatalogueSubcategory[];
  skus: V1CatalogueSku[];
  nextCursor?: { name: string; skuId: string };
};

export type V1RestaurantMenuOption = {
  id: string; name: string; priceDeltaPaise: number; sortOrder: number;
  status: string; version: number;
};
export type V1RestaurantMenuOptionGroup = {
  id: string; name: string; selectionType: "SINGLE" | "MULTIPLE";
  minimumSelections: number; maximumSelections: number; sortOrder: number;
  status: string; version: number; options: V1RestaurantMenuOption[];
};
export type V1RestaurantMenuItem = {
  id: string; name: string; description?: string; imageKey?: string;
  basePricePaise: number; currencyCode: "INR"; taxRateBps: number;
  logisticsAttributes: Record<string, unknown>; status: string; version: number;
  optionGroups: V1RestaurantMenuOptionGroup[];
};
export type V1RestaurantMenuCategory = {
  id: string; name: string; description?: string; sortOrder: number;
  status: string; version: number; items: V1RestaurantMenuItem[];
};
export type V1RestaurantMenu = {
  restaurant: {
    organizationId: string; branchId: string; name: string; branchName: string;
    imageKey?: string; description?: string; serviceZoneId?: string;
    acceptingOrders: boolean; isOpen: boolean; branchStatus: string; merchantType: string;
    operationalVersion: number;
    softActiveOrderThreshold: number; activeOrderCount: number;
  };
  categories: V1RestaurantMenuCategory[];
};

export type V1OrderStatus =
  | "CREATED" | "MATCHING" | "FULLY_SECURED" | "AWAITING_PAYMENT"
  | "PAID" | "PREPARING" | "PICKUP_IN_PROGRESS" | "OUT_FOR_DELIVERY"
  | "DELIVERED" | "UNAVAILABLE" | "PAYMENT_EXPIRED" | "CANCELLED_PREPAYMENT"
  | "DASTAK_FULFILMENT_FAILURE";

export type V1OrderLine = {
  id: string;
  lineType: string;
  skuId?: string;
  menuItemId?: string;
  name: string;
  variant?: string;
  packSize?: string;
  quantity: number;
  unitPricePaise: number;
  lineTotalPaise: number;
  status: string;
  foodSelection?: Record<string, unknown>;
};

export type V1Order = {
  id: string;
  displayOrderNumber: string;
  orderType: string;
  status: V1OrderStatus;
  version: number;
  customerState?: string;
  fulfilmentProgress?: { state: string; title?: string };
  payment?: {
    status: string;
    amountPaise: number;
    currencyCode: "INR";
    reservedAt: string;
    expiresAt: string;
    secondsRemaining: number;
    canAttempt: boolean;
    canRetry: boolean;
    latestAttempt?: {
      id: string;
      status: string;
      failureCode?: string;
      createdAt: string;
      failedAt?: string;
      succeededAt?: string;
    };
  };
  delivery?: {
    state: "ON_THE_WAY" | "DELIVERED";
    verificationStatus: "ACTIVE" | "BLOCKED" | "CONSUMED" | "OVERRIDDEN";
    deliveryCode?: string;
    riderArrivedAt?: string;
    deliveredAt?: string;
    recipientAccountRequired: false;
  };
  support?: {
    canReportIssue: boolean;
    recovery: Array<{
      id: string; type: string; status: string; orderLineId?: string;
      openedAt: string; resolvedAt?: string; customerMessage: string;
    }>;
    issues: Array<{
      id: string; orderLineId?: string; category: string; status: string;
      description: string; reportedAt: string; resolution?: string;
      resolvedAt?: string; version: number;
      evidence: Array<{ id: string; objectPath: string; contentType: string; capturedAt: string }>;
    }>;
    returns: Array<{
      id: string; source: string; status: string; physicalReturnRequired: boolean;
      reason: string; requestedAt: string; completedAt?: string; packageCount: number;
      mission?: {
        id: string; status: string; assignedAt?: string; arrivedCustomerAt?: string;
        pickupCompletedAt?: string; completedAt?: string;
        pickupVerificationStatus: string; pickupCode?: string;
      };
    }>;
    refunds: Array<{
      id: string; orderLineId?: string; status: string; destination: string;
      amountPaise: number; currency: "INR"; reason: string;
      createdAt: string; completedAt?: string;
    }>;
  };
  price: {
    snapshotKind: string;
    subtotalPaise: number;
    deliveryFeePaise: number;
    platformFeePaise: number;
    discountPaise: number;
    taxPaise: number;
    totalPaise: number;
    currencyCode: "INR";
  };
  lines: V1OrderLine[];
  restaurant?: {
    organizationId: string; branchId: string; name: string;
    branchName: string; imageKey?: string;
  };
  submittedAt?: string;
  fullySecuredAt?: string;
  paymentExpiresAt?: string;
  paidAt?: string;
  deliveredAt?: string;
  createdAt: string;
  updatedAt: string;
};

export type V1MerchantOpportunity = {
  id: string;
  displayOrderNumber: string;
  requestScope: "FULL_BASKET" | "REQUESTED_SUBSET";
  status: string;
  reservationState: string;
  version: number;
  branch: { id: string; displayName: string };
  startedAt: string;
  expiresAt: string;
  secondsRemaining: number;
  provisionalHoldExpiresAt?: string;
  promisedPrepMinutes?: number;
  prepTimeOptionsMinutes: number[];
  physicalConfirmationRequired: boolean;
  capacityConsumed: boolean;
  orderPaymentState?: string;
  lines: Array<{
    orderLineId: string;
    skuId?: string;
    menuItemId?: string;
    name: string;
    variant?: string;
    packSize?: string;
    quantity: number;
    selection?: Record<string, unknown>;
  }>;
};

export type V1MerchantCanonicalCatalogue = {
  branch: {
    branchId: string;
    branchName: string;
    branchStatus: string;
    branchVersion: number;
    organizationId: string;
    organizationName: string;
    merchantType: string;
    operationalState: {
      isOpen: boolean;
      acceptingOrders: boolean;
      version: number;
      updatedAt?: string;
    };
    capacity: { limit: number; held: number; available: number };
  };
  categories: Array<{ categoryId: string; name: string; slug: string; sortOrder: number }>;
  subcategories: Array<{
    subcategoryId: string; categoryId: string; name: string; slug: string; sortOrder: number;
  }>;
  skus: Array<{
    skuId: string; categoryId: string; subcategoryId: string; brandName?: string;
    name: string; variant?: string; packSize: string; description?: string; imageKey?: string;
    listPricePaise: number; sellingPricePaise: number; currencyCode: "INR";
    catalogueStatus: string; selected: boolean; selectionState?: string;
    selectionVersion: number; selectionUpdatedAt?: string;
  }>;
  truncated: boolean;
};

export type V1MerchantFulfilment = {
  id: string;
  orderId: string;
  displayOrderNumber: string;
  orderStatus: string;
  status: "RESERVED_PREPAYMENT" | "PREPARING" | "READY" | "PICKED_UP" | "RELEASED";
  fulfilmentType?: string;
  version: number;
  branch: { id: string; displayName: string };
  promisedPrepMinutes: number;
  prepStartedAt?: string;
  estimatedReadyAt?: string;
  actualReadyAt?: string;
  secondsRemaining: number;
  runningLate: boolean;
  lateSeconds: number;
  packageCount?: number;
  packages: Array<{
    id: string;
    packageNumber: number;
    status: string;
    custodyOwnerType: string;
    declaredAt: string;
    readyAt?: string;
    version: number;
  }>;
  evidence: Array<{
    id: string;
    packageId?: string;
    type: string;
    objectPath: string;
    contentType: string;
    capturedAt: string;
  }>;
  problemReports: Array<{
    id: string;
    statusAtReport: string;
    reason: string;
    reportedAt: string;
  }>;
  capacity?: { status: string; heldAt: string; releasedAt?: string; releaseReason?: string };
  riderMatchEligibility: {
    eligible: boolean;
    evaluatedAt: string;
    thresholdSeconds: number;
    requiredFulfilmentCount: number;
    satisfiedFulfilmentCount: number;
    nextEligibleAt?: string;
  };
  delivery?: {
    missionId: string;
    missionStatus: string;
    riderAssigned: boolean;
    rider?: { id: string; displayName: string };
    transportType?: string;
    stopId: string;
    stopStatus: "PENDING" | "ARRIVED" | "COMPLETED";
    riderArrivedAt?: string;
    waitingSeconds: number;
    verificationStatus: "INACTIVE" | "ACTIVE" | "CONSUMED" | "BLOCKED" | "OVERRIDDEN";
    pickupCode?: string;
    pickedUpAt?: string;
  };
  canDeclarePackages: boolean;
  canAddEvidence: boolean;
  canMarkReady: boolean;
  readyIsIrreversible: boolean;
  canReportExactSkuFailure?: boolean;
  recoveryCases?: Array<{
    id: string; orderLineId: string; status: string; reason: string;
    openedAt: string; resolvedAt?: string;
  }>;
  lines: V1MerchantOpportunity["lines"];
};

export type V1RecoveryOpportunity = {
  id: string;
  recoveryCaseId: string;
  orderId: string;
  orderLineId: string;
  status: string;
  requestedQuantity: number;
  startedAt: string;
  expiresAt: string;
  promisedPrepMinutes?: number;
  version: number;
  branch: { id: string; displayName: string };
  sku: { id: string; name: string; variantName?: string; packSize: string; imageKey?: string };
};

export type V1MerchantOperations = {
  fulfilments: V1MerchantFulfilment[];
  recoveryOpportunities: V1RecoveryOpportunity[];
  returnReceipts: Record<string, unknown>[];
  settlements: Record<string, unknown>[];
};

export type V1AdminExecutionOrder = {
  id: string;
  displayOrderNumber: string;
  orderType: string;
  status: string;
  version: number;
  submittedAt?: string;
  fullySecuredAt?: string;
  paymentExpiresAt?: string;
  paidAt?: string;
  updatedAt: string;
  deliveredAt?: string;
};

export type V1AdminExecutionTrace = {
  order: V1AdminExecutionOrder;
  matchingAttempts: Record<string, unknown>[];
  provisionalHolds: Record<string, unknown>[];
  plans: Record<string, unknown>[];
  capacity: Record<string, unknown>[];
  payment?: Record<string, unknown>;
  reconciliationCases: Record<string, unknown>[];
  preparation?: {
    riderMatchEligibility: Record<string, unknown>;
    fulfilments: Record<string, unknown>[];
    packages: Record<string, unknown>[];
    evidence: Record<string, unknown>[];
    problems: Record<string, unknown>[];
    history: Record<string, unknown>[];
  };
  delivery?: {
    mission?: Record<string, unknown>;
    offers: Record<string, unknown>[];
    pickupStops: Record<string, unknown>[];
    verification: Record<string, unknown>[];
    custody: Record<string, unknown>[];
    problems: Record<string, unknown>[];
    deliveryEvidence: Record<string, unknown>[];
    exceptionalHandoffs: Record<string, unknown>[];
    canAuthorizeExceptionalHandoff: boolean;
  };
  failureAndFinance?: {
    recoveryCases: Record<string, unknown>[];
    customerIssues: Record<string, unknown>[];
    returns: Record<string, unknown>[];
    refunds: Record<string, unknown>[];
    settlements: Record<string, unknown>[];
    permissions: Record<string, unknown>;
  };
  restaurant?: {
    request?: Record<string, unknown>;
    commitment?: Record<string, unknown>;
    foodLines: Record<string, unknown>[];
    preparedFoodPhysicallyReturnable: false;
  };
};

export type V1SystemHealth = {
  healthy: boolean;
  workerConfigured: boolean;
  openCriticalIncidentCount: number;
  incidents: Array<{
    id: string;
    invariantKey: string;
    entityType: string;
    entityId: string;
    details: Record<string, unknown>;
    firstDetectedAt: string;
    lastDetectedAt: string;
    occurrenceCount: number;
  }>;
  lastMonitorRun?: {
    id: string;
    findingCount: number;
    startedAt: string;
    completedAt: string;
  };
  outbox: {
    pending: number;
    deadLetter: number;
    oldestPendingSeconds: number;
    staleThresholdSeconds: number;
  };
  notifications: { pending: number; inFlight: number; deadLetter: number };
  paymentReconciliationOpen: number;
  observedAt: string;
};

export type V1OrderSubmission = {
  deliveryAddress: {
    label?: string;
    line1: string;
    line2?: string;
    landmark?: string;
    city?: string;
    state?: string;
    postalCode?: string;
    countryCode: "IN";
    latitude: number;
    longitude: number;
    instructions?: string;
  };
  recipient: { name: string; phoneNumber: string };
  restaurantBranchId?: string;
  lines: Array<
    | { lineType: "RETAIL_SKU"; skuId: string; quantity: number }
    | { lineType: "FOOD_MENU_ITEM"; menuItemId: string; optionIds: string[]; quantity: number }
  >;
};

export type V1RestaurantRequest = {
  id: string; orderId: string; displayOrderNumber: string;
  status: "OFFERED" | "CONFIRMED" | "DECLINED" | "RELEASED";
  version: number; offeredAt: string; respondedAt?: string;
  promisedPrepMinutes?: number; responseReason?: string;
  softActiveOrderThreshold: number; activeOrderCount: number;
  softThresholdWarning: boolean; softThresholdIsBlocking: false;
  branch: {
    id: string; displayName: string; isOpen: boolean; acceptingOrders: boolean;
    operationalVersion: number;
  };
  lines: Array<{
    orderLineId: string; menuItemId: string; name: string; variant?: string;
    quantity: number; unitPricePaise: number; selection: Record<string, unknown>;
  }>;
  fulfilmentId?: string;
};

export type V1AdminSku = V1CatalogueSku & {
  brandId?: string;
  taxRateBps: number;
  status: "DRAFT" | "ACTIVE" | "INACTIVE";
  selectionCount: number;
  version: number;
  updatedAt: string;
};

export type V1AdminSnapshot = {
  categories: Array<V1CatalogueCategory & { status: string; version: number; updatedAt: string }>;
  subcategories: Array<V1CatalogueSubcategory & { status: string; version: number; updatedAt: string }>;
  brands: Array<V1CatalogueBrand & { imageKey?: string; status: string; version: number; updatedAt: string }>;
  skus: V1AdminSku[];
  skuCount: number;
  truncated: boolean;
  configuration: Array<{ key: string; value: unknown; explicit: boolean; valid: boolean; required: boolean }>;
  branches: Array<{
    id: string; name: string; organizationName: string; merchantType: string; status: string;
    isOpen: boolean; acceptingOrders: boolean; capacityLimit: number; selectedSkuCount: number;
  }>;
};

export class DastakV1RequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "DastakV1RequestError";
  }
}

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export async function getV1Catalogue(
  input: DastakV1Auth & { query?: string; categoryId?: string; subcategoryId?: string; limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  return parseV1Catalogue(await invoke(input, "dastak-v1-catalogue", {
    operation: "customerCatalogue",
    query: input.query?.trim() || null,
    categoryId: input.categoryId ?? null,
    subcategoryId: input.subcategoryId ?? null,
    limit: input.limit ?? 250,
    cursor: null,
  }, undefined, fetcher));
}

export async function getV1Restaurants(
  input: DastakV1Auth & { query?: string; limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1RestaurantMenu[]> {
  const source = requiredRecord(await invoke(input, "dastak-v1-catalogue", {
    operation: "customerRestaurants",
    query: input.query?.trim() || null,
    limit: input.limit ?? 50,
  }, undefined, fetcher));
  return requiredArray(source.restaurants).map(parseRestaurantMenu);
}

export async function getV1Orders(input: DastakV1Auth & { limit?: number; signal?: AbortSignal }, fetcher: Fetcher = fetch) {
  const source = record(await invoke(input, "dastak-v1-orders", {
    operation: "list", limit: input.limit ?? 50, cursor: null,
  }, undefined, fetcher));
  if (!source || !Array.isArray(source.orders)) invalid("order collection");
  return { orders: source.orders.map(parseV1Order) };
}

export async function getV1Order(input: DastakV1Auth & { orderId: string; signal?: AbortSignal }, fetcher: Fetcher = fetch) {
  return parseV1Order(await invoke(input, "dastak-v1-orders", {
    operation: "get", orderId: requiredUuid(input.orderId),
  }, undefined, fetcher));
}

export async function submitV1Order(
  input: DastakV1Auth & { order: V1OrderSubmission; idempotencyKey: string; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  return parseV1Order(await invoke(input, "dastak-v1-orders", {
    operation: "submit", expectedVersion: 0, order: input.order,
  }, input.idempotencyKey, fetcher));
}

export async function cancelV1Order(
  input: DastakV1Auth & { orderId: string; expectedVersion: number; idempotencyKey: string; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  return parseV1Order(await invoke(input, "dastak-v1-orders", {
    operation: "cancel", orderId: requiredUuid(input.orderId), expectedVersion: input.expectedVersion,
  }, input.idempotencyKey, fetcher));
}

export async function getV1AdminCatalogue(input: DastakV1Auth & { signal?: AbortSignal }, fetcher: Fetcher = fetch) {
  return parseV1AdminSnapshot(await invoke(input, "dastak-v1-catalogue", {
    operation: "adminSnapshot", skuLimit: 1000,
  }, undefined, fetcher));
}

export async function importV1AdminCatalogue(
  input: DastakV1Auth & { catalogue: Record<string, unknown>; idempotencyKey: string; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  const source = record(await invoke(input, "dastak-v1-catalogue", {
    operation: "importCatalogue", catalogue: input.catalogue,
  }, input.idempotencyKey, fetcher));
  if (!source) invalid("catalogue import response");
  return source;
}

export async function updateV1AdminSku(
  input: DastakV1Auth & {
    skuId: string; expectedVersion: number; patch: Record<string, unknown>; idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  const source = record(await invoke(input, "dastak-v1-catalogue", {
    operation: "updateSku", skuId: requiredUuid(input.skuId), expectedVersion: input.expectedVersion, patch: input.patch,
  }, input.idempotencyKey, fetcher));
  if (!source) invalid("SKU update response");
  return source;
}

export async function getV1MerchantCanonicalCatalogue(
  input: DastakV1Auth & { branchId?: string; limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1MerchantCanonicalCatalogue> {
  return parseMerchantCanonicalCatalogue(await invoke(input, "dastak-v1-catalogue", {
    operation: "merchantSnapshot",
    branchId: input.branchId ?? null,
    limit: input.limit ?? 1000,
  }, undefined, fetcher));
}

export async function getV1MerchantRestaurantMenu(
  input: DastakV1Auth & { branchId?: string; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1RestaurantMenu> {
  return parseRestaurantMenu(await invoke(input, "dastak-v1-catalogue", {
    operation: "merchantRestaurantMenu",
    branchId: input.branchId ?? null,
  }, undefined, fetcher));
}

export async function upsertV1RestaurantMenuEntity(
  input: DastakV1Auth & {
    branchId: string;
    entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION";
    entityId?: string;
    expectedVersion: number;
    payload: Record<string, unknown>;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  const source = requiredRecord(await invoke(input, "dastak-v1-catalogue", {
    operation: "upsertRestaurantMenuEntity",
    branchId: requiredUuid(input.branchId),
    entityType: input.entityType,
    entityId: input.entityId ? requiredUuid(input.entityId) : null,
    expectedVersion: requiredInteger(input.expectedVersion, 0),
    payload: input.payload,
  }, input.idempotencyKey, fetcher));
  return {
    entityId: requiredUuid(source.entityId),
    entityType: requiredText(source.entityType, 40),
    menu: parseRestaurantMenu(source.menu),
  };
}

export async function updateV1MerchantSkuSelection(
  input: DastakV1Auth & {
    branchId: string; skuId: string; selected: boolean; expectedVersion: number;
    idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-catalogue", {
    operation: "updateMerchantSelection",
    branchId: requiredUuid(input.branchId),
    skuId: requiredUuid(input.skuId),
    selected: input.selected,
    expectedVersion: requiredInteger(input.expectedVersion, 0),
  }, input.idempotencyKey, fetcher));
}

export async function updateV1MerchantBranchState(
  input: DastakV1Auth & {
    branchId: string; isOpen: boolean; acceptingOrders: boolean; expectedVersion: number;
    idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-catalogue", {
    operation: "updateBranchOperationalState",
    branchId: requiredUuid(input.branchId),
    isOpen: input.isOpen,
    acceptingOrders: input.acceptingOrders,
    expectedVersion: requiredInteger(input.expectedVersion, 0),
  }, input.idempotencyKey, fetcher));
}

export async function getV1MerchantOpportunities(
  input: DastakV1Auth & { limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  const source = record(await invoke(input, "dastak-v1-orders", {
    operation: "merchantOpportunities",
    limit: input.limit ?? 50,
  }, undefined, fetcher));
  if (!source || !Array.isArray(source.opportunities)) invalid("merchant opportunity collection");
  return source.opportunities.map(parseMerchantOpportunity);
}

export async function getV1RestaurantRequests(
  input: DastakV1Auth & { limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1RestaurantRequest[]> {
  const source = requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "restaurantRequests",
    limit: input.limit ?? 50,
  }, undefined, fetcher));
  return requiredArray(source.requests).map(parseRestaurantRequest);
}

export async function respondV1RestaurantRequest(
  input: DastakV1Auth & {
    requestId: string; response: "CONFIRM" | "DECLINE";
    promisedPrepMinutes?: number; reason?: string; expectedVersion: number;
    idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
): Promise<V1RestaurantRequest> {
  return parseRestaurantRequest(await invoke(input, "dastak-v1-orders", {
    operation: "respondRestaurantRequest",
    requestId: requiredUuid(input.requestId), response: input.response,
    promisedPrepMinutes: input.response === "CONFIRM"
      ? requiredInteger(input.promisedPrepMinutes, 1) : null,
    reason: input.response === "DECLINE" ? requiredText(input.reason?.trim(), 500) : null,
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function respondToV1MerchantOpportunity(
  input: DastakV1Auth & {
    opportunityId: string;
    requestScope: V1MerchantOpportunity["requestScope"];
    expectedVersion: number;
    action: "accept" | "unavailable";
    promisedPrepMinutes?: number;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  const accepting = input.action === "accept";
  return parseMerchantOpportunity(await invoke(input, "dastak-v1-orders", {
    operation: accepting ? "acceptMerchantOpportunity" : "declineMerchantOpportunity",
    opportunityId: requiredUuid(input.opportunityId),
    requestScope: input.requestScope,
    expectedVersion: input.expectedVersion,
    ...(accepting ? { promisedPrepMinutes: input.promisedPrepMinutes } : {}),
  }, input.idempotencyKey, fetcher));
}

export async function getV1MerchantFulfilments(
  input: DastakV1Auth & { limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  const source = record(await invoke(input, "dastak-v1-orders", {
    operation: "merchantFulfilments",
    limit: input.limit ?? 50,
  }, undefined, fetcher));
  if (!source || !Array.isArray(source.fulfilments)) invalid("merchant fulfilment collection");
  return source.fulfilments.map(parseMerchantFulfilment);
}

export async function getV1MerchantOperations(
  input: DastakV1Auth & { limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1MerchantOperations> {
  const source = record(await invoke(input, "dastak-v1-orders", {
    operation: "merchantFulfilments",
    limit: input.limit ?? 50,
  }, undefined, fetcher));
  if (!source || !Array.isArray(source.fulfilments) ||
    !Array.isArray(source.recoveryOpportunities) ||
    !Array.isArray(source.returnReceipts) || !Array.isArray(source.settlements)) {
    invalid("merchant operations");
  }
  return {
    fulfilments: source.fulfilments.map(parseMerchantFulfilment),
    recoveryOpportunities: source.recoveryOpportunities.map(parseRecoveryOpportunity),
    returnReceipts: source.returnReceipts.map(requiredRecord),
    settlements: source.settlements.map(requiredRecord),
  };
}

export async function reportV1ExactSkuFailure(
  input: DastakV1Auth & {
    fulfilmentId: string; orderLineId: string; reason: string;
    expectedVersion: number; idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "reportExactSkuFailure",
    fulfilmentId: requiredUuid(input.fulfilmentId),
    orderLineId: requiredUuid(input.orderLineId),
    reason: requiredText(input.reason.trim(), 500),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function createV1ExactSkuRecoveryOffer(
  input: DastakV1Auth & {
    recoveryCaseId: string; branchId: string; expectedVersion: number;
    idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "createExactSkuRecoveryOffer",
    recoveryCaseId: requiredUuid(input.recoveryCaseId),
    branchId: requiredUuid(input.branchId),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function failV1ExactSkuRecovery(
  input: DastakV1Auth & {
    recoveryCaseId: string; reason: string; expectedVersion: number;
    idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "failExactSkuRecovery",
    recoveryCaseId: requiredUuid(input.recoveryCaseId),
    reason: requiredText(input.reason.trim(), 500),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function respondV1ExactSkuRecoveryOffer(
  input: DastakV1Auth & {
    recoveryOpportunityId: string; response: "ACCEPT" | "UNAVAILABLE";
    promisedPrepMinutes?: number; expectedVersion: number;
    idempotencyKey: string; signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "respondExactSkuRecoveryOffer",
    recoveryOpportunityId: requiredUuid(input.recoveryOpportunityId),
    response: input.response,
    promisedPrepMinutes: input.response === "ACCEPT"
      ? requiredInteger(input.promisedPrepMinutes, 1)
      : null,
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function reportV1CustomerIssue(
  input: DastakV1Auth & {
    orderId: string; orderLineId?: string; category: string; description: string;
    objectPath?: string; contentType?: string; idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "reportCustomerIssue",
    orderId: requiredUuid(input.orderId),
    orderLineId: input.orderLineId ? requiredUuid(input.orderLineId) : null,
    category: requiredText(input.category, 80),
    description: requiredText(input.description.trim(), 1000),
    objectPath: input.objectPath ? requiredText(input.objectPath, 500) : null,
    contentType: input.contentType ? requiredText(input.contentType, 100) : null,
  }, input.idempotencyKey, fetcher));
}

const customerIssueEvidenceExtensions = new Map([
  ["image/jpeg", "jpg"], ["image/png", "png"], ["image/heic", "heic"],
]);

export async function uploadV1CustomerIssueEvidence(
  client: SupabaseClient,
  accountId: string,
  file: File,
) {
  const extension = customerIssueEvidenceExtensions.get(file.type);
  if (!extension || file.size < 1 || file.size > 10 * 1024 * 1024) {
    invalidInput("Choose a JPG, PNG or HEIC photo up to 10 MB.");
  }
  const objectPath = `customer-issue/${requiredUuid(accountId)}/${crypto.randomUUID()}.${extension}`;
  const { error } = await client.storage.from("dastak-evidence").upload(objectPath, file, {
    cacheControl: "3600", contentType: file.type, upsert: false,
  });
  if (error) throw new DastakV1RequestError(
    "evidence_upload_failed", "The issue photo could not be uploaded. Try again.", 0,
  );
  return objectPath;
}

export async function declareV1FulfilmentPackages(
  input: DastakV1Auth & {
    fulfilmentId: string;
    packageCount: number;
    expectedVersion: number;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantFulfilment(await invoke(input, "dastak-v1-orders", {
    operation: "declareFulfilmentPackages",
    fulfilmentId: requiredUuid(input.fulfilmentId),
    packageCount: requiredInteger(input.packageCount, 1),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function addV1FulfilmentReadyEvidence(
  input: DastakV1Auth & {
    fulfilmentId: string;
    packageId?: string;
    objectPath: string;
    expectedVersion: number;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantFulfilment(await invoke(input, "dastak-v1-orders", {
    operation: "addFulfilmentReadyEvidence",
    fulfilmentId: requiredUuid(input.fulfilmentId),
    packageId: input.packageId ? requiredUuid(input.packageId) : null,
    objectPath: requiredText(input.objectPath, 500),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function markV1FulfilmentReady(
  input: DastakV1Auth & {
    fulfilmentId: string;
    expectedVersion: number;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantFulfilment(await invoke(input, "dastak-v1-orders", {
    operation: "markFulfilmentReady",
    fulfilmentId: requiredUuid(input.fulfilmentId),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function reportV1FulfilmentProblem(
  input: DastakV1Auth & {
    fulfilmentId: string;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  return parseMerchantFulfilment(await invoke(input, "dastak-v1-orders", {
    operation: "reportFulfilmentProblem",
    fulfilmentId: requiredUuid(input.fulfilmentId),
    reason: requiredText(input.reason, 500),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

const merchantReadyEvidenceExtensions = new Map([
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
  ["image/heic", "heic"],
]);
const maximumMerchantReadyEvidenceBytes = 10 * 1024 * 1024;

export function merchantReadyEvidenceObjectPath(
  accountId: string,
  contentType: string,
  uniqueId: string,
) {
  const extension = merchantReadyEvidenceExtensions.get(contentType);
  if (!extension) invalidInput("Choose a JPG, PNG or HEIC photo.");
  return `merchant-ready/${requiredUuid(accountId)}/${requiredUuid(uniqueId)}.${extension}`;
}

export async function uploadV1MerchantReadyEvidence(
  client: SupabaseClient,
  accountId: string,
  file: File,
) {
  if (
    !merchantReadyEvidenceExtensions.has(file.type) || file.size < 1 ||
    file.size > maximumMerchantReadyEvidenceBytes
  ) invalidInput("Choose a JPG, PNG or HEIC photo up to 10 MB.");
  const objectPath = merchantReadyEvidenceObjectPath(accountId, file.type, crypto.randomUUID());
  const { error } = await client.storage.from("dastak-evidence").upload(objectPath, file, {
    cacheControl: "3600",
    contentType: file.type,
    upsert: false,
  });
  if (error) {
    throw new DastakV1RequestError(
      "evidence_upload_failed",
      "The Ready photo could not be uploaded. Try again.",
      0,
    );
  }
  return objectPath;
}

export async function getV1AdminExecutionOrders(
  input: DastakV1Auth & { limit?: number; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
) {
  const source = record(await invoke(input, "dastak-v1-orders", {
    operation: "adminExecutionOrders",
    limit: input.limit ?? 50,
  }, undefined, fetcher));
  if (!source || !Array.isArray(source.orders)) invalid("execution order collection");
  return source.orders.map(parseAdminExecutionOrder);
}

export async function getV1AdminExecutionTrace(
  input: DastakV1Auth & { orderId: string; signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1AdminExecutionTrace> {
  const source = record(await invoke(input, "dastak-v1-orders", {
    operation: "adminExecutionTrace",
    orderId: requiredUuid(input.orderId),
  }, undefined, fetcher));
  if (!source) invalid("execution trace");
  const payment = source.payment === null || source.payment === undefined
    ? undefined
    : record(source.payment);
  const preparation = source.preparation === null || source.preparation === undefined
    ? undefined
    : record(source.preparation);
  const delivery = source.delivery === null || source.delivery === undefined
    ? undefined
    : record(source.delivery);
  const failureAndFinance = source.failureAndFinance === null ||
      source.failureAndFinance === undefined
    ? undefined
    : record(source.failureAndFinance);
  const restaurant = source.restaurant === null || source.restaurant === undefined
    ? undefined
    : record(source.restaurant);
  if (
    !Array.isArray(source.matchingAttempts) || !Array.isArray(source.provisionalHolds) ||
    !Array.isArray(source.plans) || !Array.isArray(source.capacity) ||
    !Array.isArray(source.reconciliationCases) ||
    (source.payment !== null && source.payment !== undefined && !payment) ||
    (source.preparation !== null && source.preparation !== undefined && !preparation) ||
    (source.delivery !== null && source.delivery !== undefined && !delivery) ||
    (source.restaurant !== null && source.restaurant !== undefined && !restaurant) ||
    (source.failureAndFinance !== null && source.failureAndFinance !== undefined &&
      !failureAndFinance) ||
    (preparation && (
      !record(preparation.riderMatchEligibility) || !Array.isArray(preparation.fulfilments) ||
      !Array.isArray(preparation.packages) || !Array.isArray(preparation.evidence) ||
      !Array.isArray(preparation.problems) || !Array.isArray(preparation.history)
    )) ||
    (delivery && (
      (delivery.mission !== null && delivery.mission !== undefined && !record(delivery.mission)) ||
      !Array.isArray(delivery.offers) || !Array.isArray(delivery.pickupStops) ||
      !Array.isArray(delivery.verification) || !Array.isArray(delivery.custody) ||
      !Array.isArray(delivery.problems) || !Array.isArray(delivery.deliveryEvidence) ||
      !Array.isArray(delivery.exceptionalHandoffs) ||
      typeof delivery.canAuthorizeExceptionalHandoff !== "boolean"
    )) || (failureAndFinance && (
      !Array.isArray(failureAndFinance.recoveryCases) ||
      !Array.isArray(failureAndFinance.customerIssues) ||
      !Array.isArray(failureAndFinance.returns) ||
      !Array.isArray(failureAndFinance.refunds) ||
      !Array.isArray(failureAndFinance.settlements) ||
      !record(failureAndFinance.permissions)
    )) || (restaurant && (
      (restaurant.request !== null && restaurant.request !== undefined && !record(restaurant.request)) ||
      (restaurant.commitment !== null && restaurant.commitment !== undefined && !record(restaurant.commitment)) ||
      !Array.isArray(restaurant.foodLines) ||
      restaurant.preparedFoodPhysicallyReturnable !== false
    ))
  ) invalid("execution trace");
  return {
    order: parseAdminExecutionOrder(source.order),
    matchingAttempts: source.matchingAttempts.map(requiredRecord),
    provisionalHolds: source.provisionalHolds.map(requiredRecord),
    plans: source.plans.map(requiredRecord),
    capacity: source.capacity.map(requiredRecord),
    payment,
    reconciliationCases: source.reconciliationCases.map(requiredRecord),
    preparation: preparation ? {
      riderMatchEligibility: requiredRecord(preparation.riderMatchEligibility),
      fulfilments: (preparation.fulfilments as unknown[]).map(requiredRecord),
      packages: (preparation.packages as unknown[]).map(requiredRecord),
      evidence: (preparation.evidence as unknown[]).map(requiredRecord),
      problems: (preparation.problems as unknown[]).map(requiredRecord),
      history: (preparation.history as unknown[]).map(requiredRecord),
    } : undefined,
    delivery: delivery ? {
      mission: delivery.mission === null || delivery.mission === undefined
        ? undefined
        : requiredRecord(delivery.mission),
      offers: (delivery.offers as unknown[]).map(requiredRecord),
      pickupStops: (delivery.pickupStops as unknown[]).map(requiredRecord),
      verification: (delivery.verification as unknown[]).map(requiredRecord),
      custody: (delivery.custody as unknown[]).map(requiredRecord),
      problems: (delivery.problems as unknown[]).map(requiredRecord),
      deliveryEvidence: (delivery.deliveryEvidence as unknown[]).map(requiredRecord),
      exceptionalHandoffs: (delivery.exceptionalHandoffs as unknown[]).map(requiredRecord),
      canAuthorizeExceptionalHandoff: requiredBoolean(
        delivery.canAuthorizeExceptionalHandoff,
      ),
    } : undefined,
    failureAndFinance: failureAndFinance ? {
      recoveryCases: (failureAndFinance.recoveryCases as unknown[]).map(requiredRecord),
      customerIssues: (failureAndFinance.customerIssues as unknown[]).map(requiredRecord),
      returns: (failureAndFinance.returns as unknown[]).map(requiredRecord),
      refunds: (failureAndFinance.refunds as unknown[]).map(requiredRecord),
      settlements: (failureAndFinance.settlements as unknown[]).map(requiredRecord),
      permissions: requiredRecord(failureAndFinance.permissions),
    } : undefined,
    restaurant: restaurant ? {
      request: restaurant.request === null || restaurant.request === undefined
        ? undefined : requiredRecord(restaurant.request),
      commitment: restaurant.commitment === null || restaurant.commitment === undefined
        ? undefined : requiredRecord(restaurant.commitment),
      foodLines: (restaurant.foodLines as unknown[]).map(requiredRecord),
      preparedFoodPhysicallyReturnable: false,
    } : undefined,
  };
}

export async function getV1AdminSystemHealth(
  input: DastakV1Auth & { signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1SystemHealth> {
  return parseV1SystemHealth(await invoke(input, "dastak-v1-orders", {
    operation: "adminSystemHealth",
  }, undefined, fetcher));
}

export async function getV1AdminOperationalSafety(
  input: DastakV1Auth & { signal?: AbortSignal },
  fetcher: Fetcher = fetch,
): Promise<V1OperationalSafety> {
  return parseV1OperationalSafety(await invoke(input, "dastak-v1-orders", {
    operation: "adminOperationalSafety",
  }, undefined, fetcher));
}

export async function manageV1RiderEscalation(
  input: DastakV1Auth & {
    missionId: string;
    action: "RELEASE_REMATCH" | "ENTER_DELIVERY_RECOVERY";
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  const reason = requiredText(input.reason.trim(), 500);
  if (reason.length < 10) invalidInput("Add a clear Operations reason.");
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "manageRiderEscalation",
    missionId: requiredUuid(input.missionId),
    action: input.action,
    reason,
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function setV1OperationalPause(
  input: DastakV1Auth & {
    scope: V1OperationalPauseScope;
    targetId: string;
    active: boolean;
    reason: string;
    expectedVersion: number;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  const reason = requiredText(input.reason.trim(), 500);
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "setOperationalPause",
    scope: input.scope,
    targetId: requiredUuid(input.targetId),
    active: input.active,
    reason,
    expectedVersion: requiredInteger(input.expectedVersion, 0),
  }, input.idempotencyKey, fetcher));
}

function parseV1OperationalSafety(value: unknown): V1OperationalSafety {
  const source = record(value);
  const permissions = record(source?.permissions);
  if (!source || !permissions || !Array.isArray(source.pauses) ||
    !Array.isArray(source.riderEscalations)) invalid("operational safety response");
  return {
    permissions: {
      canManageRiderEscalations: requiredBoolean(permissions.canManageRiderEscalations),
      canManageOperationalPauses: requiredBoolean(permissions.canManageOperationalPauses),
    },
    pauses: source.pauses.map((value) => {
      const pause = requiredRecord(value);
      const scope = String(pause.scope) as V1OperationalPauseScope;
      if (!["ZONE_RETAIL", "ZONE_FOOD", "ZONE_MIXED", "MERCHANT_BRANCH", "RIDER_ASSIGNMENTS"].includes(scope)) {
        invalid("operational pause");
      }
      return {
        id: requiredUuid(pause.id), scope,
        targetId: requiredUuid(pause.targetId), active: requiredBoolean(pause.active),
        reason: requiredText(pause.reason, 500),
        activatedAt: optionalTimestamp(pause.activatedAt) ?? null,
        clearedAt: optionalTimestamp(pause.clearedAt) ?? null,
        version: requiredInteger(pause.version, 1),
      };
    }),
    riderEscalations: source.riderEscalations.map((value) => {
      const escalation = requiredRecord(value);
      return {
        missionId: requiredUuid(escalation.missionId),
        orderId: requiredUuid(escalation.orderId),
        displayOrderNumber: requiredText(escalation.displayOrderNumber, 40),
        status: requiredText(escalation.status, 80),
        riderId: escalation.riderId === null || escalation.riderId === undefined
          ? null : requiredUuid(escalation.riderId),
        transportType: optionalText(escalation.transportType, 40) ?? null,
        lastContactAt: optionalTimestamp(escalation.lastContactAt) ?? null,
        lastProgressAt: optionalTimestamp(escalation.lastProgressAt) ?? null,
        stallDetectedAt: optionalTimestamp(escalation.stallDetectedAt) ?? null,
        unresponsiveDetectedAt: optionalTimestamp(escalation.unresponsiveDetectedAt) ?? null,
        escalationState: requiredText(escalation.escalationState, 80),
        escalatedAt: optionalTimestamp(escalation.escalatedAt) ?? null,
        escalationReason: optionalText(escalation.escalationReason, 500) ?? null,
        custodyStarted: requiredBoolean(escalation.custodyStarted),
        version: requiredInteger(escalation.version, 1),
      };
    }),
  };
}

export async function authorizeV1ExceptionalDeliveryHandoff(
  input: DastakV1Auth & {
    missionId: string;
    deliveryEvidenceId: string;
    reason: string;
    expectedMissionVersion: number;
    idempotencyKey: string;
    signal?: AbortSignal;
  },
  fetcher: Fetcher = fetch,
) {
  const reason = requiredText(input.reason.trim().replace(/\s+/g, " "), 500);
  if (reason.length < 10) invalidInput("Add a clear Operations reason.");
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "authorizeExceptionalDeliveryHandoff",
    missionId: requiredUuid(input.missionId),
    deliveryEvidenceId: requiredUuid(input.deliveryEvidenceId),
    reason,
    expectedMissionVersion: requiredInteger(input.expectedMissionVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function decideV1CustomerIssue(
  input: DastakV1Auth & {
    issueId: string; decision: "REJECT" | "RESOLVE_NO_REFUND" |
      "REFUND_WITHOUT_RETURN" | "PHYSICAL_RETURN";
    refundAmountPaise?: number; faultSource?: string; returnPackageCount?: number;
    reason: string; expectedVersion: number; idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "decideCustomerIssue",
    issueId: requiredUuid(input.issueId), decision: input.decision,
    refundAmountPaise: input.refundAmountPaise ?? null,
    faultSource: input.faultSource ?? null,
    returnPackageCount: input.returnPackageCount ?? null,
    reason: requiredText(input.reason.trim(), 1000),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function assignV1ReturnRider(
  input: DastakV1Auth & {
    returnMissionId: string; riderId: string; expectedVersion: number;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "assignReturnRider",
    returnMissionId: requiredUuid(input.returnMissionId),
    riderId: requiredUuid(input.riderId),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function manageV1DeliveryRecovery(
  input: DastakV1Auth & {
    recoveryCaseId: string; action: "RESUME_DELIVERY" | "RETURN_TO_ORIGIN";
    faultSource: string; refundAmountPaise?: number;
    correctedAddress?: Record<string, unknown>; reason: string;
    expectedVersion: number; idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "manageDeliveryRecovery",
    recoveryCaseId: requiredUuid(input.recoveryCaseId), action: input.action,
    faultSource: requiredText(input.faultSource, 40),
    refundAmountPaise: input.refundAmountPaise ?? null,
    correctedAddress: input.correctedAddress ?? null,
    reason: requiredText(input.reason.trim(), 500),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function finalizeV1SettlementCalculation(
  input: DastakV1Auth & {
    settlementEntryId: string; expectedVersion: number; idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "finalizeSettlementCalculation",
    settlementEntryId: requiredUuid(input.settlementEntryId),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export async function settleV1Entry(
  input: DastakV1Auth & {
    settlementEntryId: string; settlementReference: string;
    expectedVersion: number; idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return requiredRecord(await invoke(input, "dastak-v1-orders", {
    operation: "settleEntry", settlementEntryId: requiredUuid(input.settlementEntryId),
    settlementReference: requiredText(input.settlementReference.trim(), 200),
    expectedVersion: requiredInteger(input.expectedVersion, 1),
  }, input.idempotencyKey, fetcher));
}

export function parseV1Catalogue(value: unknown): V1CatalogueSnapshot {
  const source = record(value);
  if (!source || !Array.isArray(source.categories) || !Array.isArray(source.subcategories) || !Array.isArray(source.skus)) {
    invalid("catalogue response");
  }
  const cursor = source.nextCursor === null || source.nextCursor === undefined ? undefined : record(source.nextCursor);
  return {
    catalogueVersion: optionalTimestamp(source.catalogueVersion),
    categories: source.categories.map(parseCategory),
    subcategories: source.subcategories.map(parseSubcategory),
    skus: source.skus.map(parseSku),
    nextCursor: cursor ? { name: requiredText(cursor.name, 160), skuId: requiredUuid(cursor.skuId) } : undefined,
  };
}

function parseRestaurantMenu(value: unknown): V1RestaurantMenu {
  const source = requiredRecord(value);
  const restaurant = requiredRecord(source.restaurant);
  return {
    restaurant: {
      organizationId: requiredUuid(restaurant.organizationId),
      branchId: requiredUuid(restaurant.branchId),
      name: requiredText(restaurant.name, 160),
      branchName: requiredText(restaurant.branchName, 160),
      imageKey: optionalText(restaurant.imageKey, 500),
      description: optionalText(restaurant.description, 500),
      serviceZoneId: restaurant.serviceZoneId === null || restaurant.serviceZoneId === undefined
        ? undefined : requiredUuid(restaurant.serviceZoneId),
      acceptingOrders: requiredBoolean(restaurant.acceptingOrders),
      isOpen: requiredBoolean(restaurant.isOpen),
      operationalVersion: requiredInteger(restaurant.operationalVersion, 0),
      branchStatus: requiredText(restaurant.branchStatus, 40),
      merchantType: requiredText(restaurant.merchantType, 40),
      softActiveOrderThreshold: requiredInteger(restaurant.softActiveOrderThreshold, 1),
      activeOrderCount: requiredInteger(restaurant.activeOrderCount, 0),
    },
    categories: requiredArray(source.categories).map((categoryValue) => {
      const category = requiredRecord(categoryValue);
      return {
        id: requiredUuid(category.id), name: requiredText(category.name, 100),
        description: optionalText(category.description, 500),
        sortOrder: requiredInteger(category.sortOrder, 0),
        status: requiredText(category.status, 20), version: requiredInteger(category.version, 1),
        items: requiredArray(category.items).map((itemValue) => {
          const item = requiredRecord(itemValue);
          return {
            id: requiredUuid(item.id), name: requiredText(item.name, 160),
            description: optionalText(item.description, 1000),
            imageKey: optionalText(item.imageKey, 500),
            basePricePaise: requiredInteger(item.basePricePaise, 1),
            currencyCode: currency(item.currencyCode),
            taxRateBps: requiredInteger(item.taxRateBps, 0),
            logisticsAttributes: requiredRecord(item.logisticsAttributes),
            status: requiredText(item.status, 20), version: requiredInteger(item.version, 1),
            optionGroups: requiredArray(item.optionGroups).map((groupValue) => {
              const group = requiredRecord(groupValue);
              const selectionType = requiredText(group.selectionType, 20);
              if (!['SINGLE', 'MULTIPLE'].includes(selectionType)) invalid('option group');
              return {
                id: requiredUuid(group.id), name: requiredText(group.name, 100),
                selectionType: selectionType as 'SINGLE' | 'MULTIPLE',
                minimumSelections: requiredInteger(group.minimumSelections, 0),
                maximumSelections: requiredInteger(group.maximumSelections, 1),
                sortOrder: requiredInteger(group.sortOrder, 0),
                status: requiredText(group.status, 20), version: requiredInteger(group.version, 1),
                options: requiredArray(group.options).map((optionValue) => {
                  const option = requiredRecord(optionValue);
                  return {
                    id: requiredUuid(option.id), name: requiredText(option.name, 100),
                    priceDeltaPaise: requiredInteger(option.priceDeltaPaise, 0),
                    sortOrder: requiredInteger(option.sortOrder, 0),
                    status: requiredText(option.status, 20), version: requiredInteger(option.version, 1),
                  };
                }),
              };
            }),
          };
        }),
      };
    }),
  };
}

function parseRestaurantRequest(value: unknown): V1RestaurantRequest {
  const source = requiredRecord(value);
  const branch = requiredRecord(source.branch);
  const status = requiredText(source.status, 30);
  if (!['OFFERED', 'CONFIRMED', 'DECLINED', 'RELEASED'].includes(status)) {
    invalid('restaurant request');
  }
  return {
    id: requiredUuid(source.id), orderId: requiredUuid(source.orderId),
    displayOrderNumber: requiredText(source.displayOrderNumber, 80),
    status: status as V1RestaurantRequest['status'],
    version: requiredInteger(source.version, 1), offeredAt: requiredTimestamp(source.offeredAt),
    respondedAt: optionalTimestamp(source.respondedAt),
    promisedPrepMinutes: optionalInteger(source.promisedPrepMinutes, 1),
    responseReason: optionalText(source.responseReason, 500),
    softActiveOrderThreshold: requiredInteger(source.softActiveOrderThreshold, 1),
    activeOrderCount: requiredInteger(source.activeOrderCount, 0),
    softThresholdWarning: requiredBoolean(source.softThresholdWarning),
    softThresholdIsBlocking: source.softThresholdIsBlocking === false
      ? false : invalid('soft threshold semantics'),
    branch: {
      id: requiredUuid(branch.id), displayName: requiredText(branch.displayName, 160),
      isOpen: requiredBoolean(branch.isOpen), acceptingOrders: requiredBoolean(branch.acceptingOrders),
      operationalVersion: requiredInteger(branch.operationalVersion, 1),
    },
    lines: requiredArray(source.lines).map((lineValue) => {
      const line = requiredRecord(lineValue);
      return {
        orderLineId: requiredUuid(line.orderLineId), menuItemId: requiredUuid(line.menuItemId),
        name: requiredText(line.name, 200), variant: optionalText(line.variant, 160),
        quantity: requiredInteger(line.quantity, 1),
        unitPricePaise: requiredInteger(line.unitPricePaise, 0),
        selection: requiredRecord(line.selection),
      };
    }),
    fulfilmentId: source.fulfilmentId === null || source.fulfilmentId === undefined
      ? undefined : requiredUuid(source.fulfilmentId),
  };
}

export function parseV1Order(value: unknown): V1Order {
  const source = record(value);
  const price = record(source?.price);
  if (!source || !price || !Array.isArray(source.lines)) invalid("order response");
  const status = requiredText(source.status, 60) as V1OrderStatus;
  if (!orderStatuses.has(status)) invalid("order status");
  const progress = source.fulfilmentProgress === null || source.fulfilmentProgress === undefined
    ? undefined : record(source.fulfilmentProgress);
  const delivery = source.delivery === null || source.delivery === undefined
    ? undefined
    : record(source.delivery);
  const support = source.support === null || source.support === undefined
    ? undefined
    : record(source.support);
  const restaurant = source.restaurant === null || source.restaurant === undefined
    ? undefined : record(source.restaurant);
  if (source.delivery !== null && source.delivery !== undefined && !delivery) {
    invalid("delivery state");
  }
  if (source.support !== null && source.support !== undefined && !support) {
    invalid("support state");
  }
  if (source.restaurant !== null && source.restaurant !== undefined && !restaurant) {
    invalid("restaurant identity");
  }
  return {
    id: requiredUuid(source.id),
    displayOrderNumber: requiredText(source.displayOrderNumber, 80),
    orderType: requiredText(source.orderType, 40),
    status,
    version: requiredInteger(source.version, 1),
    customerState: optionalText(source.customerState, 80),
    fulfilmentProgress: progress
      ? { state: requiredText(progress.state, 80), title: optionalText(progress.title, 160) }
      : undefined,
    payment: source.payment === null || source.payment === undefined
      ? undefined
      : parseOrderPayment(source.payment),
    delivery: delivery ? parseOrderDelivery(delivery) : undefined,
    support: support ? parseOrderSupport(support) : undefined,
    restaurant: restaurant ? {
      organizationId: requiredUuid(restaurant.organizationId),
      branchId: requiredUuid(restaurant.branchId),
      name: requiredText(restaurant.name, 160),
      branchName: requiredText(restaurant.branchName, 160),
      imageKey: optionalText(restaurant.imageKey, 500),
    } : undefined,
    price: {
      snapshotKind: requiredText(price.snapshotKind, 40),
      subtotalPaise: requiredInteger(price.subtotalPaise, 0),
      deliveryFeePaise: requiredInteger(price.deliveryFeePaise, 0),
      platformFeePaise: requiredInteger(price.platformFeePaise, 0),
      discountPaise: requiredInteger(price.discountPaise, 0),
      taxPaise: requiredInteger(price.taxPaise, 0),
      totalPaise: requiredInteger(price.totalPaise, 0),
      currencyCode: currency(price.currencyCode),
    },
    lines: source.lines.map(parseOrderLine),
    submittedAt: optionalTimestamp(source.submittedAt),
    fullySecuredAt: optionalTimestamp(source.fullySecuredAt),
    paymentExpiresAt: optionalTimestamp(source.paymentExpiresAt),
    paidAt: optionalTimestamp(source.paidAt),
    deliveredAt: optionalTimestamp(source.deliveredAt),
    createdAt: requiredTimestamp(source.createdAt),
    updatedAt: requiredTimestamp(source.updatedAt),
  };
}

function parseOrderSupport(source: Record<string, unknown>): NonNullable<V1Order["support"]> {
  if (!Array.isArray(source.recovery) || !Array.isArray(source.issues) ||
    !Array.isArray(source.returns) || !Array.isArray(source.refunds)) invalid("support state");
  return {
    canReportIssue: requiredBoolean(source.canReportIssue),
    recovery: source.recovery.map((item) => {
      const value = requiredRecord(item);
      return {
        id: requiredUuid(value.id), type: requiredText(value.type, 40),
        status: requiredText(value.status, 60),
        orderLineId: value.orderLineId ? requiredUuid(value.orderLineId) : undefined,
        openedAt: requiredTimestamp(value.openedAt),
        resolvedAt: optionalTimestamp(value.resolvedAt),
        customerMessage: requiredText(value.customerMessage, 300),
      };
    }),
    issues: source.issues.map((item) => {
      const value = requiredRecord(item);
      const evidence = requiredArray(value.evidence);
      return {
        id: requiredUuid(value.id),
        orderLineId: value.orderLineId ? requiredUuid(value.orderLineId) : undefined,
        category: requiredText(value.category, 80), status: requiredText(value.status, 40),
        description: requiredText(value.description, 1000),
        reportedAt: requiredTimestamp(value.reportedAt),
        resolution: optionalText(value.resolution, 1000),
        resolvedAt: optionalTimestamp(value.resolvedAt),
        version: requiredInteger(value.version, 1),
        evidence: evidence.map((entry) => {
          const photo = requiredRecord(entry);
          return {
            id: requiredUuid(photo.id), objectPath: requiredText(photo.objectPath, 500),
            contentType: requiredText(photo.contentType, 100),
            capturedAt: requiredTimestamp(photo.capturedAt),
          };
        }),
      };
    }),
    returns: source.returns.map((item) => {
      const value = requiredRecord(item);
      const mission = value.mission === null || value.mission === undefined
        ? undefined : requiredRecord(value.mission);
      return {
        id: requiredUuid(value.id), source: requiredText(value.source, 40),
        status: requiredText(value.status, 60),
        physicalReturnRequired: requiredBoolean(value.physicalReturnRequired),
        reason: requiredText(value.reason, 1000), requestedAt: requiredTimestamp(value.requestedAt),
        completedAt: optionalTimestamp(value.completedAt),
        packageCount: requiredInteger(value.packageCount, 0),
        mission: mission ? {
          id: requiredUuid(mission.id), status: requiredText(mission.status, 60),
          assignedAt: optionalTimestamp(mission.assignedAt),
          arrivedCustomerAt: optionalTimestamp(mission.arrivedCustomerAt),
          pickupCompletedAt: optionalTimestamp(mission.pickupCompletedAt),
          completedAt: optionalTimestamp(mission.completedAt),
          pickupVerificationStatus: requiredText(mission.pickupVerificationStatus, 40),
          pickupCode: optionalText(mission.pickupCode, 6),
        } : undefined,
      };
    }),
    refunds: source.refunds.map((item) => {
      const value = requiredRecord(item);
      return {
        id: requiredUuid(value.id),
        orderLineId: value.orderLineId ? requiredUuid(value.orderLineId) : undefined,
        status: requiredText(value.status, 40), destination: requiredText(value.destination, 80),
        amountPaise: requiredInteger(value.amountPaise, 1), currency: currency(value.currency),
        reason: requiredText(value.reason, 500), createdAt: requiredTimestamp(value.createdAt),
        completedAt: optionalTimestamp(value.completedAt),
      };
    }),
  };
}

function parseOrderDelivery(source: Record<string, unknown>): NonNullable<V1Order["delivery"]> {
  const state = requiredText(source.state, 40);
  const verificationStatus = requiredText(source.verificationStatus, 40);
  if (
    !["ON_THE_WAY", "DELIVERED"].includes(state) ||
    !["ACTIVE", "BLOCKED", "CONSUMED", "OVERRIDDEN"].includes(verificationStatus) ||
    source.recipientAccountRequired !== false
  ) invalid("delivery state");
  const deliveryCode = optionalText(source.deliveryCode, 6);
  if (deliveryCode !== undefined && !/^\d{6}$/.test(deliveryCode)) invalid("delivery code");
  return {
    state: state as NonNullable<V1Order["delivery"]>["state"],
    verificationStatus: verificationStatus as NonNullable<V1Order["delivery"]>["verificationStatus"],
    deliveryCode,
    riderArrivedAt: optionalTimestamp(source.riderArrivedAt),
    deliveredAt: optionalTimestamp(source.deliveredAt),
    recipientAccountRequired: false,
  };
}

function parseOrderPayment(value: unknown): NonNullable<V1Order["payment"]> {
  const source = record(value);
  if (!source) invalid("payment reservation");
  const latest = source.latestAttempt === null || source.latestAttempt === undefined
    ? undefined
    : record(source.latestAttempt);
  if (source.latestAttempt !== null && source.latestAttempt !== undefined && !latest) {
    invalid("payment attempt");
  }
  return {
    status: requiredText(source.status, 40),
    amountPaise: requiredInteger(source.amountPaise, 1),
    currencyCode: currency(source.currencyCode),
    reservedAt: requiredTimestamp(source.reservedAt),
    expiresAt: requiredTimestamp(source.expiresAt),
    secondsRemaining: requiredInteger(source.secondsRemaining, 0),
    canAttempt: requiredBoolean(source.canAttempt),
    canRetry: requiredBoolean(source.canRetry),
    latestAttempt: latest
      ? {
        id: requiredUuid(latest.id),
        status: requiredText(latest.status, 40),
        failureCode: optionalText(latest.failureCode, 80),
        createdAt: requiredTimestamp(latest.createdAt),
        failedAt: optionalTimestamp(latest.failedAt),
        succeededAt: optionalTimestamp(latest.succeededAt),
      }
      : undefined,
  };
}

function parseMerchantOpportunity(value: unknown): V1MerchantOpportunity {
  const source = record(value);
  const branch = record(source?.branch);
  if (!source || !branch || !Array.isArray(source.lines) || !Array.isArray(source.prepTimeOptionsMinutes)) {
    invalid("merchant opportunity");
  }
  const requestScope = requiredText(source.requestScope, 40);
  if (requestScope !== "FULL_BASKET" && requestScope !== "REQUESTED_SUBSET") {
    invalid("merchant opportunity scope");
  }
  return {
    id: requiredUuid(source.id),
    displayOrderNumber: requiredText(source.displayOrderNumber, 80),
    requestScope,
    status: requiredText(source.status, 40),
    reservationState: requiredText(source.reservationState, 80),
    version: requiredInteger(source.version, 1),
    branch: { id: requiredUuid(branch.id), displayName: requiredText(branch.displayName, 100) },
    startedAt: requiredTimestamp(source.startedAt),
    expiresAt: requiredTimestamp(source.expiresAt),
    secondsRemaining: requiredInteger(source.secondsRemaining, 0),
    provisionalHoldExpiresAt: optionalTimestamp(source.provisionalHoldExpiresAt),
    promisedPrepMinutes: optionalInteger(source.promisedPrepMinutes, 1),
    prepTimeOptionsMinutes: source.prepTimeOptionsMinutes.map((item) => requiredInteger(item, 1)),
    physicalConfirmationRequired: requiredBoolean(source.physicalConfirmationRequired),
    capacityConsumed: requiredBoolean(source.capacityConsumed),
    orderPaymentState: optionalText(source.orderPaymentState, 60),
    lines: source.lines.map((item) => {
      const line = requiredRecord(item);
      const skuId = line.skuId === null || line.skuId === undefined
        ? undefined : requiredUuid(line.skuId);
      const menuItemId = line.menuItemId === null || line.menuItemId === undefined
        ? undefined : requiredUuid(line.menuItemId);
      if ((skuId ? 1 : 0) + (menuItemId ? 1 : 0) !== 1) invalid("merchant fulfilment line");
      return {
        orderLineId: requiredUuid(line.orderLineId),
        skuId,
        menuItemId,
        name: requiredText(line.name, 200),
        variant: optionalText(line.variant, 160),
        packSize: optionalText(line.packSize, 80),
        quantity: requiredInteger(line.quantity, 1),
        selection: line.selection === null || line.selection === undefined
          ? undefined : requiredRecord(line.selection),
      };
    }),
  };
}

function parseMerchantCanonicalCatalogue(value: unknown): V1MerchantCanonicalCatalogue {
  const source = requiredRecord(value);
  const branch = requiredRecord(source.branch);
  const operationalState = requiredRecord(branch.operationalState);
  const capacity = requiredRecord(branch.capacity);
  const categories = requiredArray(source.categories);
  const subcategories = requiredArray(source.subcategories);
  const skus = requiredArray(source.skus);
  return {
    branch: {
      branchId: requiredUuid(branch.branchId),
      branchName: requiredText(branch.branchName, 100),
      branchStatus: requiredText(branch.branchStatus, 40),
      branchVersion: requiredInteger(branch.branchVersion, 1),
      organizationId: requiredUuid(branch.organizationId),
      organizationName: requiredText(branch.organizationName, 100),
      merchantType: requiredText(branch.merchantType, 40),
      operationalState: {
        isOpen: requiredBoolean(operationalState.isOpen),
        acceptingOrders: requiredBoolean(operationalState.acceptingOrders),
        version: requiredInteger(operationalState.version, 0),
        updatedAt: optionalTimestamp(operationalState.updatedAt),
      },
      capacity: {
        limit: requiredInteger(capacity.limit, 1),
        held: requiredInteger(capacity.held, 0),
        available: requiredInteger(capacity.available, 0),
      },
    },
    categories: categories.map((item) => {
      const category = requiredRecord(item);
      return {
        categoryId: requiredUuid(category.categoryId),
        name: requiredText(category.name, 100),
        slug: requiredText(category.slug, 120),
        sortOrder: requiredInteger(category.sortOrder, 0),
      };
    }),
    subcategories: subcategories.map((item) => {
      const subcategory = requiredRecord(item);
      return {
        subcategoryId: requiredUuid(subcategory.subcategoryId),
        categoryId: requiredUuid(subcategory.categoryId),
        name: requiredText(subcategory.name, 100),
        slug: requiredText(subcategory.slug, 120),
        sortOrder: requiredInteger(subcategory.sortOrder, 0),
      };
    }),
    skus: skus.map((item) => {
      const sku = requiredRecord(item);
      return {
        skuId: requiredUuid(sku.skuId),
        categoryId: requiredUuid(sku.categoryId),
        subcategoryId: requiredUuid(sku.subcategoryId),
        brandName: optionalText(sku.brandName, 100),
        name: requiredText(sku.name, 160),
        variant: optionalText(sku.variant, 160),
        packSize: requiredText(sku.packSize, 80),
        description: optionalText(sku.description, 1000),
        imageKey: optionalText(sku.imageKey, 500),
        listPricePaise: requiredInteger(sku.listPricePaise, 0),
        sellingPricePaise: requiredInteger(sku.sellingPricePaise, 0),
        currencyCode: currency(sku.currencyCode),
        catalogueStatus: requiredText(sku.catalogueStatus, 40),
        selected: requiredBoolean(sku.selected),
        selectionState: optionalText(sku.selectionState, 40),
        selectionVersion: requiredInteger(sku.selectionVersion, 0),
        selectionUpdatedAt: optionalTimestamp(sku.selectionUpdatedAt),
      };
    }),
    truncated: requiredBoolean(source.truncated),
  };
}

export function parseV1MerchantFulfilment(value: unknown): V1MerchantFulfilment {
  return parseMerchantFulfilment(value);
}

function parseMerchantFulfilment(value: unknown): V1MerchantFulfilment {
  const source = record(value);
  const branch = record(source?.branch);
  const capacity = source?.capacity === null || source?.capacity === undefined
    ? undefined
    : record(source.capacity);
  const rider = record(source?.riderMatchEligibility);
  const delivery = source?.delivery === null || source?.delivery === undefined
    ? undefined
    : record(source.delivery);
  if (
    !source || !branch || !rider || !Array.isArray(source.packages) ||
    !Array.isArray(source.evidence) || !Array.isArray(source.problemReports) ||
    !Array.isArray(source.lines) ||
    (source.capacity !== null && source.capacity !== undefined && !capacity) ||
    (source.delivery !== null && source.delivery !== undefined && !delivery)
  ) invalid("merchant fulfilment");
  const status = requiredText(source.status, 40);
  if (!["RESERVED_PREPAYMENT", "PREPARING", "READY", "PICKED_UP", "RELEASED"].includes(status)) {
    invalid("merchant fulfilment status");
  }
  return {
    id: requiredUuid(source.id),
    orderId: requiredUuid(source.orderId),
    displayOrderNumber: requiredText(source.displayOrderNumber, 80),
    orderStatus: requiredText(source.orderStatus, 60),
    status: status as V1MerchantFulfilment["status"],
    fulfilmentType: optionalText(source.fulfilmentType, 40),
    version: requiredInteger(source.version, 1),
    branch: {
      id: requiredUuid(branch.id),
      displayName: requiredText(branch.displayName, 100),
    },
    promisedPrepMinutes: requiredInteger(source.promisedPrepMinutes, 1),
    prepStartedAt: optionalTimestamp(source.prepStartedAt),
    estimatedReadyAt: optionalTimestamp(source.estimatedReadyAt),
    actualReadyAt: optionalTimestamp(source.actualReadyAt),
    secondsRemaining: requiredInteger(source.secondsRemaining, 0),
    runningLate: requiredBoolean(source.runningLate),
    lateSeconds: requiredInteger(source.lateSeconds, 0),
    packageCount: optionalInteger(source.packageCount, 1),
    packages: source.packages.map((item) => {
      const packageRecord = requiredRecord(item);
      return {
        id: requiredUuid(packageRecord.id),
        packageNumber: requiredInteger(packageRecord.packageNumber, 1),
        status: requiredText(packageRecord.status, 40),
        custodyOwnerType: requiredText(packageRecord.custodyOwnerType, 60),
        declaredAt: requiredTimestamp(packageRecord.declaredAt),
        readyAt: optionalTimestamp(packageRecord.readyAt),
        version: requiredInteger(packageRecord.version, 1),
      };
    }),
    evidence: source.evidence.map((item) => {
      const evidence = requiredRecord(item);
      return {
        id: requiredUuid(evidence.id),
        packageId: evidence.packageId === null || evidence.packageId === undefined
          ? undefined
          : requiredUuid(evidence.packageId),
        type: requiredText(evidence.type, 60),
        objectPath: requiredText(evidence.objectPath, 500),
        contentType: requiredText(evidence.contentType, 100),
        capturedAt: requiredTimestamp(evidence.capturedAt),
      };
    }),
    problemReports: source.problemReports.map((item) => {
      const problem = requiredRecord(item);
      return {
        id: requiredUuid(problem.id),
        statusAtReport: requiredText(problem.statusAtReport, 60),
        reason: requiredText(problem.reason, 500),
        reportedAt: requiredTimestamp(problem.reportedAt),
      };
    }),
    capacity: capacity ? {
      status: requiredText(capacity.status, 40),
      heldAt: requiredTimestamp(capacity.heldAt),
      releasedAt: optionalTimestamp(capacity.releasedAt),
      releaseReason: optionalText(capacity.releaseReason, 160),
    } : undefined,
    riderMatchEligibility: {
      eligible: requiredBoolean(rider.eligible),
      evaluatedAt: requiredTimestamp(rider.evaluatedAt),
      thresholdSeconds: requiredInteger(rider.thresholdSeconds, 0),
      requiredFulfilmentCount: requiredInteger(rider.requiredFulfilmentCount, 0),
      satisfiedFulfilmentCount: requiredInteger(rider.satisfiedFulfilmentCount, 0),
      nextEligibleAt: optionalTimestamp(rider.nextEligibleAt),
    },
    delivery: delivery ? parseMerchantDelivery(delivery) : undefined,
    canDeclarePackages: requiredBoolean(source.canDeclarePackages),
    canAddEvidence: requiredBoolean(source.canAddEvidence),
    canMarkReady: requiredBoolean(source.canMarkReady),
    readyIsIrreversible: requiredBoolean(source.readyIsIrreversible),
    canReportExactSkuFailure: source.canReportExactSkuFailure === undefined
      ? undefined : requiredBoolean(source.canReportExactSkuFailure),
    recoveryCases: source.recoveryCases === undefined
      ? undefined
      : requiredArray(source.recoveryCases).map((item) => {
        const recovery = requiredRecord(item);
        return {
          id: requiredUuid(recovery.id), orderLineId: requiredUuid(recovery.orderLineId),
          status: requiredText(recovery.status, 60), reason: requiredText(recovery.reason, 500),
          openedAt: requiredTimestamp(recovery.openedAt),
          resolvedAt: optionalTimestamp(recovery.resolvedAt),
        };
      }),
    lines: source.lines.map((item) => {
      const line = requiredRecord(item);
      const skuId = line.skuId === null || line.skuId === undefined
        ? undefined : requiredUuid(line.skuId);
      const menuItemId = line.menuItemId === null || line.menuItemId === undefined
        ? undefined : requiredUuid(line.menuItemId);
      if ((skuId ? 1 : 0) + (menuItemId ? 1 : 0) !== 1) invalid("merchant fulfilment line");
      return {
        orderLineId: requiredUuid(line.orderLineId),
        skuId,
        menuItemId,
        name: requiredText(line.name, 200),
        variant: optionalText(line.variant, 160),
        packSize: optionalText(line.packSize, 80),
        quantity: requiredInteger(line.quantity, 1),
        selection: line.selection === null || line.selection === undefined
          ? undefined : requiredRecord(line.selection),
      };
    }),
  };
}

function parseRecoveryOpportunity(value: unknown): V1RecoveryOpportunity {
  const source = requiredRecord(value);
  const branch = requiredRecord(source.branch);
  const sku = requiredRecord(source.sku);
  return {
    id: requiredUuid(source.id), recoveryCaseId: requiredUuid(source.recoveryCaseId),
    orderId: requiredUuid(source.orderId), orderLineId: requiredUuid(source.orderLineId),
    status: requiredText(source.status, 40),
    requestedQuantity: requiredInteger(source.requestedQuantity, 1),
    startedAt: requiredTimestamp(source.startedAt), expiresAt: requiredTimestamp(source.expiresAt),
    promisedPrepMinutes: optionalInteger(source.promisedPrepMinutes, 1),
    version: requiredInteger(source.version, 1),
    branch: { id: requiredUuid(branch.id), displayName: requiredText(branch.displayName, 100) },
    sku: {
      id: requiredUuid(sku.id), name: requiredText(sku.name, 160),
      variantName: optionalText(sku.variantName, 160), packSize: requiredText(sku.packSize, 80),
      imageKey: optionalText(sku.imageKey, 500),
    },
  };
}

function parseMerchantDelivery(source: Record<string, unknown>): NonNullable<V1MerchantFulfilment["delivery"]> {
  const rider = source.rider === null || source.rider === undefined ? undefined : record(source.rider);
  const stopStatus = requiredText(source.stopStatus, 40);
  const verificationStatus = requiredText(source.verificationStatus, 40);
  if (!["PENDING", "ARRIVED", "COMPLETED"].includes(stopStatus) ||
    !["INACTIVE", "ACTIVE", "CONSUMED", "BLOCKED", "OVERRIDDEN"].includes(verificationStatus) ||
    (source.rider !== null && source.rider !== undefined && !rider)) {
    invalid("merchant delivery state");
  }
  return {
    missionId: requiredUuid(source.missionId),
    missionStatus: requiredText(source.missionStatus, 60),
    riderAssigned: requiredBoolean(source.riderAssigned),
    rider: rider ? {
      id: requiredUuid(rider.id),
      displayName: requiredText(rider.displayName, 160),
    } : undefined,
    transportType: optionalText(source.transportType, 40),
    stopId: requiredUuid(source.stopId),
    stopStatus: stopStatus as NonNullable<V1MerchantFulfilment["delivery"]>["stopStatus"],
    riderArrivedAt: optionalTimestamp(source.riderArrivedAt),
    waitingSeconds: requiredInteger(source.waitingSeconds, 0),
    verificationStatus: verificationStatus as NonNullable<V1MerchantFulfilment["delivery"]>["verificationStatus"],
    pickupCode: optionalText(source.pickupCode, 6),
    pickedUpAt: optionalTimestamp(source.pickedUpAt),
  };
}

function parseAdminExecutionOrder(value: unknown): V1AdminExecutionOrder {
  const source = requiredRecord(value);
  return {
    id: requiredUuid(source.id),
    displayOrderNumber: requiredText(source.displayOrderNumber, 80),
    orderType: requiredText(source.orderType, 40),
    status: requiredText(source.status, 60),
    version: requiredInteger(source.version, 1),
    submittedAt: optionalTimestamp(source.submittedAt),
    fullySecuredAt: optionalTimestamp(source.fullySecuredAt),
    paymentExpiresAt: optionalTimestamp(source.paymentExpiresAt),
    paidAt: optionalTimestamp(source.paidAt),
    updatedAt: requiredTimestamp(source.updatedAt),
    deliveredAt: optionalTimestamp(source.deliveredAt),
  };
}

export function parseV1SystemHealth(value: unknown): V1SystemHealth {
  const source = requiredRecord(value);
  const outbox = requiredRecord(source.outbox);
  const notifications = requiredRecord(source.notifications);
  const monitor = source.lastMonitorRun === null || source.lastMonitorRun === undefined
    ? undefined
    : requiredRecord(source.lastMonitorRun);
  return {
    healthy: requiredBoolean(source.healthy),
    workerConfigured: requiredBoolean(source.workerConfigured),
    openCriticalIncidentCount: requiredInteger(source.openCriticalIncidentCount, 0),
    incidents: requiredArray(source.incidents).map((value) => {
      const incident = requiredRecord(value);
      return {
        id: requiredUuid(incident.id),
        invariantKey: requiredText(incident.invariantKey, 120),
        entityType: requiredText(incident.entityType, 80),
        entityId: requiredUuid(incident.entityId),
        details: requiredRecord(incident.details),
        firstDetectedAt: requiredTimestamp(incident.firstDetectedAt),
        lastDetectedAt: requiredTimestamp(incident.lastDetectedAt),
        occurrenceCount: requiredInteger(incident.occurrenceCount, 1),
      };
    }),
    lastMonitorRun: monitor ? {
      id: requiredUuid(monitor.id),
      findingCount: requiredInteger(monitor.findingCount, 0),
      startedAt: requiredTimestamp(monitor.startedAt),
      completedAt: requiredTimestamp(monitor.completedAt),
    } : undefined,
    outbox: {
      pending: requiredInteger(outbox.pending, 0),
      deadLetter: requiredInteger(outbox.deadLetter, 0),
      oldestPendingSeconds: requiredInteger(outbox.oldestPendingSeconds, 0),
      staleThresholdSeconds: requiredInteger(outbox.staleThresholdSeconds, 1),
    },
    notifications: {
      pending: requiredInteger(notifications.pending, 0),
      inFlight: requiredInteger(notifications.inFlight, 0),
      deadLetter: requiredInteger(notifications.deadLetter, 0),
    },
    paymentReconciliationOpen: requiredInteger(source.paymentReconciliationOpen, 0),
    observedAt: requiredTimestamp(source.observedAt),
  };
}

export function parseV1AdminSnapshot(value: unknown): V1AdminSnapshot {
  const source = record(value);
  if (!source || !Array.isArray(source.categories) || !Array.isArray(source.subcategories) ||
    !Array.isArray(source.brands) || !Array.isArray(source.skus) ||
    !Array.isArray(source.configuration) || !Array.isArray(source.branches)) invalid("admin catalogue response");
  return {
    categories: source.categories.map((item) => parseAdminEntity(item, parseCategory)),
    subcategories: source.subcategories.map((item) => parseAdminEntity(item, parseSubcategory)),
    brands: source.brands.map(parseAdminBrand),
    skus: source.skus.map(parseAdminSku),
    skuCount: requiredInteger(source.skuCount, 0),
    truncated: requiredBoolean(source.truncated),
    configuration: source.configuration.map(parseConfiguration),
    branches: source.branches.map(parseBranch),
  };
}

export function formatV1Price(paise: number) {
  return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(paise / 100);
}

async function invoke(
  input: DastakV1Auth & { signal?: AbortSignal },
  functionName: string,
  body: Record<string, unknown>,
  idempotencyKey: string | undefined,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/${functionName}`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
        ...(idempotencyKey ? { "x-idempotency-key": idempotencyKey } : {}),
      },
      body: JSON.stringify(body),
      signal: input.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    throw new DastakV1RequestError("network_error", "Dastak could not be reached. Check your connection.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const failure = record(record(payload)?.error);
    throw new DastakV1RequestError(
      optionalText(failure?.code, 100) ?? "request_failed",
      optionalText(failure?.message, 400) ?? "Dastak could not complete this request.",
      response.status,
    );
  }
  return payload;
}

function parseCategory(value: unknown): V1CatalogueCategory {
  const source = record(value);
  if (!source) invalid("category");
  return {
    id: requiredUuid(source.id), name: requiredText(source.name, 100), slug: requiredText(source.slug, 100),
    imageKey: optionalText(source.imageKey, 500), sortOrder: requiredInteger(source.sortOrder, 0),
  };
}

function parseSubcategory(value: unknown): V1CatalogueSubcategory {
  return { ...parseCategory(value), categoryId: requiredUuid(record(value)?.categoryId) };
}

function parseBrand(value: unknown): V1CatalogueBrand {
  const source = record(value);
  if (!source) invalid("brand");
  return { id: requiredUuid(source.id), name: requiredText(source.name, 100), slug: requiredText(source.slug, 100) };
}

function parseSku(value: unknown): V1CatalogueSku {
  const source = record(value);
  const logistics = record(source?.logisticsAttributes);
  if (!source || !logistics) invalid("SKU");
  const listPricePaise = requiredInteger(source.listPricePaise, 0);
  const sellingPricePaise = requiredInteger(source.sellingPricePaise, 0);
  if (sellingPricePaise > listPricePaise) invalid("SKU price");
  return {
    id: requiredUuid(source.id), categoryId: requiredUuid(source.categoryId), subcategoryId: requiredUuid(source.subcategoryId),
    brand: source.brand === null || source.brand === undefined ? undefined : parseBrand(source.brand),
    name: requiredText(source.name, 160), slug: requiredText(source.slug, 160),
    variant: optionalText(source.variant, 160), packSize: requiredText(source.packSize, 80),
    description: optionalText(source.description, 1000), imageKey: optionalText(source.imageKey, 500),
    barcode: optionalText(source.barcode, 64), listPricePaise,
    sellingPricePaise, currencyCode: currency(source.currencyCode),
    logisticsAttributes: logistics,
  };
}

function parseOrderLine(value: unknown): V1OrderLine {
  const source = record(value);
  if (!source) invalid("order line");
  return {
    id: requiredUuid(source.id), lineType: requiredText(source.lineType, 40),
    skuId: source.skuId === null || source.skuId === undefined ? undefined : requiredUuid(source.skuId),
    menuItemId: source.menuItemId === null || source.menuItemId === undefined
      ? undefined : requiredUuid(source.menuItemId),
    name: requiredText(source.name, 200), variant: optionalText(source.variant, 160), packSize: optionalText(source.packSize, 80),
    quantity: requiredInteger(source.quantity, 1), unitPricePaise: requiredInteger(source.unitPricePaise, 0),
    lineTotalPaise: requiredInteger(source.lineTotalPaise, 0), status: requiredText(source.status, 60),
    foodSelection: source.foodSelection === null || source.foodSelection === undefined
      ? undefined : requiredRecord(source.foodSelection),
  };
}

function parseAdminEntity<T extends object>(value: unknown, parser: (value: unknown) => T) {
  const source = record(value);
  if (!source) invalid("admin catalogue entity");
  return { ...parser(value), status: requiredText(source.status, 20), version: requiredInteger(source.version, 1), updatedAt: requiredTimestamp(source.updatedAt) };
}

function parseAdminBrand(value: unknown) {
  const source = record(value);
  if (!source) invalid("admin brand");
  return { ...parseBrand(value), imageKey: optionalText(source.imageKey, 500), status: requiredText(source.status, 20), version: requiredInteger(source.version, 1), updatedAt: requiredTimestamp(source.updatedAt) };
}

function parseAdminSku(value: unknown): V1AdminSku {
  const source = record(value);
  if (!source) invalid("admin SKU");
  const status = requiredText(source.status, 20);
  if (status !== "DRAFT" && status !== "ACTIVE" && status !== "INACTIVE") invalid("SKU status");
  return {
    ...parseSku({ ...source, brand: null }),
    brandId: source.brandId === null || source.brandId === undefined ? undefined : requiredUuid(source.brandId),
    taxRateBps: requiredInteger(source.taxRateBps, 0), status, selectionCount: requiredInteger(source.selectionCount, 0),
    version: requiredInteger(source.version, 1), updatedAt: requiredTimestamp(source.updatedAt),
  };
}

function parseConfiguration(value: unknown) {
  const source = record(value);
  if (!source) invalid("configuration");
  return { key: requiredText(source.key, 120), value: source.value, explicit: requiredBoolean(source.explicit), valid: requiredBoolean(source.valid), required: requiredBoolean(source.required) };
}

function parseBranch(value: unknown) {
  const source = record(value);
  if (!source) invalid("branch");
  return {
    id: requiredUuid(source.id), name: requiredText(source.name, 160), organizationName: requiredText(source.organizationName, 160),
    merchantType: requiredText(source.merchantType, 80), status: requiredText(source.status, 40),
    isOpen: requiredBoolean(source.isOpen), acceptingOrders: requiredBoolean(source.acceptingOrders),
    capacityLimit: requiredInteger(source.capacityLimit, 0), selectedSkuCount: requiredInteger(source.selectedSkuCount, 0),
  };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
function requiredRecord(value: unknown) { return record(value) ?? invalid("object"); }
function requiredArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : invalid("array");
}
function requiredText(value: unknown, maximum: number) { return optionalText(value, maximum) ?? invalid("text"); }
function optionalText(value: unknown, maximum: number) {
  return value === null || value === undefined ? undefined
    : typeof value === "string" && value.trim().length > 0 && value.length <= maximum ? value : invalid("text");
}
function requiredInteger(value: unknown, minimum: number) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum ? value : invalid("number");
}
function optionalInteger(value: unknown, minimum: number) {
  return value === null || value === undefined ? undefined : requiredInteger(value, minimum);
}
function requiredBoolean(value: unknown) { return typeof value === "boolean" ? value : invalid("boolean"); }
function requiredUuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : invalid("identifier");
}
function requiredTimestamp(value: unknown) {
  return typeof value === "string" && value.length <= 50 && Number.isFinite(Date.parse(value)) ? value : invalid("timestamp");
}
function optionalTimestamp(value: unknown) { return value === null || value === undefined ? undefined : requiredTimestamp(value); }
function currency(value: unknown): "INR" { return value === "INR" ? "INR" : invalid("currency"); }
function invalidInput(message: string): never {
  throw new DastakV1RequestError("validation_failed", message, 400);
}
function invalid(subject: string): never {
  throw new DastakV1RequestError("invalid_response", `Dastak received an invalid ${subject}.`, 502);
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const orderStatuses = new Set<V1OrderStatus>([
  "CREATED", "MATCHING", "FULLY_SECURED", "AWAITING_PAYMENT", "PAID", "PREPARING",
  "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY", "DELIVERED", "UNAVAILABLE", "PAYMENT_EXPIRED",
  "CANCELLED_PREPAYMENT", "DASTAK_FULFILMENT_FAILURE",
]);
