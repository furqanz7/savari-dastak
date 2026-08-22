import type { SupabaseClient } from "@supabase/supabase-js";

export type DastakV1Auth = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
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

export type V1OrderStatus =
  | "CREATED" | "MATCHING" | "FULLY_SECURED" | "AWAITING_PAYMENT"
  | "PAID" | "PREPARING" | "PICKUP_IN_PROGRESS" | "OUT_FOR_DELIVERY"
  | "DELIVERED" | "UNAVAILABLE" | "PAYMENT_EXPIRED" | "CANCELLED_PREPAYMENT"
  | "DASTAK_FULFILMENT_FAILURE";

export type V1OrderLine = {
  id: string;
  lineType: string;
  skuId?: string;
  name: string;
  variant?: string;
  packSize?: string;
  quantity: number;
  unitPricePaise: number;
  lineTotalPaise: number;
  status: string;
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
    skuId: string;
    name: string;
    variant?: string;
    packSize?: string;
    quantity: number;
  }>;
};

export type V1MerchantFulfilment = {
  id: string;
  orderId: string;
  displayOrderNumber: string;
  orderStatus: string;
  status: "RESERVED_PREPAYMENT" | "PREPARING" | "READY" | "PICKED_UP";
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
  lines: V1MerchantOpportunity["lines"];
};

export type V1AdminExecutionOrder = {
  id: string;
  displayOrderNumber: string;
  status: string;
  version: number;
  submittedAt?: string;
  fullySecuredAt?: string;
  paymentExpiresAt?: string;
  paidAt?: string;
  updatedAt: string;
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
  };
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
  lines: Array<{ lineType: "RETAIL_SKU"; skuId: string; quantity: number }>;
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
  if (
    !Array.isArray(source.matchingAttempts) || !Array.isArray(source.provisionalHolds) ||
    !Array.isArray(source.plans) || !Array.isArray(source.capacity) ||
    !Array.isArray(source.reconciliationCases) ||
    (source.payment !== null && source.payment !== undefined && !payment) ||
    (source.preparation !== null && source.preparation !== undefined && !preparation) ||
    (source.delivery !== null && source.delivery !== undefined && !delivery) ||
    (preparation && (
      !record(preparation.riderMatchEligibility) || !Array.isArray(preparation.fulfilments) ||
      !Array.isArray(preparation.packages) || !Array.isArray(preparation.evidence) ||
      !Array.isArray(preparation.problems) || !Array.isArray(preparation.history)
    )) ||
    (delivery && (
      (delivery.mission !== null && delivery.mission !== undefined && !record(delivery.mission)) ||
      !Array.isArray(delivery.offers) || !Array.isArray(delivery.pickupStops) ||
      !Array.isArray(delivery.verification) || !Array.isArray(delivery.custody) ||
      !Array.isArray(delivery.problems)
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
    } : undefined,
  };
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

export function parseV1Order(value: unknown): V1Order {
  const source = record(value);
  const price = record(source?.price);
  if (!source || !price || !Array.isArray(source.lines)) invalid("order response");
  const status = requiredText(source.status, 60) as V1OrderStatus;
  if (!orderStatuses.has(status)) invalid("order status");
  const progress = source.fulfilmentProgress === null || source.fulfilmentProgress === undefined
    ? undefined : record(source.fulfilmentProgress);
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
      return {
        orderLineId: requiredUuid(line.orderLineId),
        skuId: requiredUuid(line.skuId),
        name: requiredText(line.name, 200),
        variant: optionalText(line.variant, 160),
        packSize: optionalText(line.packSize, 80),
        quantity: requiredInteger(line.quantity, 1),
      };
    }),
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
  if (!["RESERVED_PREPAYMENT", "PREPARING", "READY", "PICKED_UP"].includes(status)) {
    invalid("merchant fulfilment status");
  }
  return {
    id: requiredUuid(source.id),
    orderId: requiredUuid(source.orderId),
    displayOrderNumber: requiredText(source.displayOrderNumber, 80),
    orderStatus: requiredText(source.orderStatus, 60),
    status: status as V1MerchantFulfilment["status"],
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
    lines: source.lines.map((item) => {
      const line = requiredRecord(item);
      return {
        orderLineId: requiredUuid(line.orderLineId),
        skuId: requiredUuid(line.skuId),
        name: requiredText(line.name, 200),
        variant: optionalText(line.variant, 160),
        packSize: optionalText(line.packSize, 80),
        quantity: requiredInteger(line.quantity, 1),
      };
    }),
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
    status: requiredText(source.status, 60),
    version: requiredInteger(source.version, 1),
    submittedAt: optionalTimestamp(source.submittedAt),
    fullySecuredAt: optionalTimestamp(source.fullySecuredAt),
    paymentExpiresAt: optionalTimestamp(source.paymentExpiresAt),
    paidAt: optionalTimestamp(source.paidAt),
    updatedAt: requiredTimestamp(source.updatedAt),
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
    name: requiredText(source.name, 200), variant: optionalText(source.variant, 160), packSize: optionalText(source.packSize, 80),
    quantity: requiredInteger(source.quantity, 1), unitPricePaise: requiredInteger(source.unitPricePaise, 0),
    lineTotalPaise: requiredInteger(source.lineTotalPaise, 0), status: requiredText(source.status, 60),
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
